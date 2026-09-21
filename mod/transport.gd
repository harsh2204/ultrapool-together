extends Node

signal connected
signal disconnected(reason: String)
signal received(message: Dictionary)
signal status_changed(text: String)
signal room_ready

const PROTOCOL := 2
const GAME_VERSION := "0.15.7"
const MOD_ID := "ultrapool-together"
const MAX_PACKET_BYTES := 262144
const STEAM_CHANNEL := 47
const LOBBY_FRIENDS_ONLY := 1
const LOBBY_MEMBER_GONE := 2 | 4 | 8 | 16
const HANDSHAKE_TIMEOUT_MS := 15000
const PEER_TIMEOUT_MS := 20000
const HEARTBEAT_MS := 2000

var is_host := false
var connected_peer := false
var room_code := ""

var _mode := ""
var _token := ""
var _peer_id := 0
var _enet: ENetMultiplayerPeer
var _steam: Object
var _hello_sent := false
var _deadline := 0
var _last_received := 0
var _last_heartbeat := 0
var _lobby_id := 0
var _create_pending := false
var _join_pending_id := 0
var _lobby_deadline := 0
var _command_line_checked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func host_lan(port: int, token: String) -> Error:
	close()
	if port < 1024 or port > 65535 or token.length() > 128:
		return ERR_INVALID_PARAMETER
	_token = token if not token.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()
	_enet = ENetMultiplayerPeer.new()
	var error := _enet.create_server(port, 1, 1)
	if error != OK:
		close()
		return error
	_enet.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_enet.peer_connected.connect(_on_enet_connected)
	_enet.peer_disconnected.connect(_on_enet_disconnected)
	_mode = "lan"
	is_host = true
	room_code = _token
	status_changed.emit("Waiting for a guest on UDP port %d." % port)
	return OK


func join_lan(host: String, port: int, token: String) -> Error:
	close()
	if (
		host.strip_edges().is_empty()
		or port < 1024
		or port > 65535
		or token.is_empty()
		or token.length() > 128
	):
		return ERR_INVALID_PARAMETER
	_token = token
	_enet = ENetMultiplayerPeer.new()
	var error := _enet.create_client(host.strip_edges(), port, 1)
	if error != OK:
		close()
		return error
	_enet.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_mode = "lan"
	_peer_id = 1
	_deadline = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS
	status_changed.emit("Connecting to host...")
	return OK


func host_steam() -> Error:
	if _create_pending or _join_pending_id != 0:
		return ERR_BUSY
	close()
	if not _prepare_steam():
		return ERR_UNAVAILABLE
	_mode = "steam"
	is_host = true
	_token = Crypto.new().generate_random_bytes(16).hex_encode()
	_create_pending = true
	_lobby_deadline = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS
	status_changed.emit("Creating Steam room...")
	_steam.call("createLobby", LOBBY_FRIENDS_ONLY, 2)
	return OK


func join_steam(code: String) -> Error:
	var parts := code.strip_edges().split("-")
	if parts.size() != 2 or parts[0] != "UP2" or not parts[1].is_valid_int():
		return ERR_INVALID_PARAMETER
	return _join_lobby(int(parts[1]))


func listen_for_invites() -> bool:
	if not _prepare_steam():
		return false
	if not _command_line_checked:
		_command_line_checked = true
		var args := OS.get_cmdline_args()
		for index in range(args.size() - 1):
			if args[index] == "+connect_lobby" and args[index + 1].is_valid_int():
				_join_lobby(int(args[index + 1]))
				break
	return true


func invite_ready() -> bool:
	return _mode == "steam" and is_host and _lobby_id != 0 and _peer_id == 0


func session_open() -> bool:
	return not _mode.is_empty() or _create_pending or _join_pending_id != 0


func invite_friend() -> Error:
	if not invite_ready():
		return ERR_UNAVAILABLE
	if not bool(_steam.call("isOverlayEnabled")):
		status_changed.emit("Enable the Steam overlay to invite a friend.")
		return ERR_UNAVAILABLE
	_steam.call("activateGameOverlayInviteDialog", _lobby_id)
	return OK


func _join_lobby(lobby_id: int) -> Error:
	if lobby_id <= 0:
		return ERR_INVALID_PARAMETER
	if lobby_id == _lobby_id:
		return OK
	if connected_peer:
		return ERR_ALREADY_IN_USE
	if _create_pending or _join_pending_id != 0:
		return ERR_BUSY
	close()
	if not _prepare_steam():
		return ERR_UNAVAILABLE
	_mode = "steam"
	_join_pending_id = lobby_id
	_lobby_deadline = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS
	status_changed.emit("Joining Steam room...")
	_steam.call("joinLobby", lobby_id)
	return OK


func send(message: Dictionary) -> void:
	if connected_peer:
		_send_wire({"kind": "data", "data": message})


func close() -> void:
	if connected_peer:
		_send_wire({"kind": "bye"})
	if _enet != null:
		_enet.close()
		_enet = null
	if _steam != null:
		if _peer_id != 0 and _mode == "steam":
			_steam.call("closeChannelWithUser", _peer_id, STEAM_CHANNEL)
		if _lobby_id != 0:
			_steam.call("leaveLobby", _lobby_id)
	_lobby_id = 0
	_lobby_deadline = 0
	# Pending request IDs remain until their callbacks can leave cancelled lobbies.
	_mode = ""
	_token = ""
	_peer_id = 0
	_deadline = 0
	_hello_sent = false
	connected_peer = false
	is_host = false
	room_code = ""


func _exit_tree() -> void:
	close()
	if _steam != null:
		for binding in _steam_bindings():
			if _steam.is_connected(binding[0], binding[1]):
				_steam.disconnect(binding[0], binding[1])
		_steam = null


func _steam_bindings() -> Array:
	return [
		["network_messages_session_request", _on_steam_request],
		["network_messages_session_failed", _on_steam_failed],
		["join_requested", _on_join_requested],
		["lobby_created", _on_lobby_created],
		["lobby_joined", _on_lobby_joined],
		["lobby_chat_update", _on_lobby_chat_update],
	]


func _prepare_steam() -> bool:
	if _steam != null:
		return true
	if not Engine.has_singleton("Steam"):
		return false
	_steam = Engine.get_singleton("Steam")
	for method in [
		"sendMessageToUser",
		"receiveMessagesOnChannel",
		"acceptSessionWithUser",
		"closeChannelWithUser",
		"loggedOn",
		"getSteamID",
		"run_callbacks",
		"createLobby",
		"joinLobby",
		"leaveLobby",
		"getLobbyOwner",
		"getLobbyData",
		"setLobbyData",
		"setLobbyJoinable",
		"getNumLobbyMembers",
		"getLobbyMemberByIndex",
		"activateGameOverlayInviteDialog",
		"isOverlayEnabled",
	]:
		if not _steam.has_method(method):
			_steam = null
			return false
	for binding in _steam_bindings():
		if not _steam.has_signal(binding[0]):
			_steam = null
			return false
	if not bool(_steam.call("loggedOn")) and _steam.has_method("steamInitEx"):
		var initialization: Dictionary = _steam.call("steamInitEx")
		if initialization.get("status", 1) != 0:
			status_changed.emit(
				"Steam initialization failed. Start Steam and launch ULTRAPOOL once, then retry."
			)
			_steam = null
			return false
	if not bool(_steam.call("loggedOn")) or int(_steam.call("getSteamID")) == 0:
		_steam = null
		return false
	for binding in _steam_bindings():
		_steam.connect(binding[0], binding[1])
	if _steam.has_method("initRelayNetworkAccess"):
		_steam.call("initRelayNetworkAccess")
	return true


func _process(_delta: float) -> void:
	if _steam != null:
		_steam.call("run_callbacks")
	if _lobby_deadline != 0 and Time.get_ticks_msec() >= _lobby_deadline:
		_fail_room("Steam room request timed out. Try again shortly.")
	if _mode == "lan":
		_enet.poll()
		if _enet == null:
			return
		if (
			not is_host
			and not _hello_sent
			and _enet.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		):
			_send_hello()
		var packet_count := 0
		while _enet != null and _enet.get_available_packet_count() > 0 and packet_count < 64:
			var sender := _enet.get_packet_peer()
			var packet := _enet.get_packet()
			_receive_wire(sender, packet)
			packet_count += 1
		if (
			_enet != null
			and not is_host
			and _enet.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED
		):
			_drop_peer("Host disconnected. You can join again.")
	elif _mode == "steam":
		var packets: Array = _steam.call("receiveMessagesOnChannel", STEAM_CHANNEL, 64)
		for packet in packets:
			if _mode != "steam":
				break
			_receive_wire(int(packet.get("identity", 0)), packet.get("payload", PackedByteArray()))
	if _mode.is_empty() or _peer_id == 0:
		return
	var now := Time.get_ticks_msec()
	if not connected_peer:
		if now >= _deadline:
			_drop_peer("Connection timed out. Try joining again.")
		return
	if now - _last_received > PEER_TIMEOUT_MS:
		_drop_peer("Connection lost. You can join again.")
	elif now - _last_heartbeat >= HEARTBEAT_MS:
		_last_heartbeat = now
		_send_wire({"kind": "ping"})


func _on_enet_connected(id: int) -> void:
	if not is_host:
		return
	if _peer_id != 0:
		_enet.disconnect_peer(id)
		return
	_peer_id = id
	_deadline = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS


func _on_enet_disconnected(id: int) -> void:
	if id == _peer_id:
		_peer_id = 0
		_drop_peer(
			(
				"Guest disconnected. Waiting for a guest."
				if is_host
				else "Host disconnected. You can join again."
			)
		)


func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	var error := _join_lobby(lobby_id)
	if error == ERR_ALREADY_IN_USE:
		status_changed.emit("Leave the current game before joining another.")
	elif error == ERR_BUSY:
		status_changed.emit(
			"Steam is finishing the previous request. Accept the invite again shortly."
		)
	elif error != OK:
		status_changed.emit("Could not join the Steam room. Check that Steam is online.")


func _on_lobby_created(result: int, lobby_id: int) -> void:
	if not _create_pending:
		return
	_create_pending = false
	if _mode != "steam" or not is_host:
		if result == 1:
			_steam.call("leaveLobby", lobby_id)
		return
	_lobby_deadline = 0
	if result != 1 or lobby_id == 0:
		_fail_room("Steam could not create the room (%d)." % result)
		return
	_lobby_id = lobby_id
	var metadata := {
		"mod": MOD_ID,
		"protocol": str(PROTOCOL),
		"game_version": GAME_VERSION,
		"host": str(_steam.call("getSteamID")),
		"token": _token,
	}
	for key in metadata:
		if not bool(_steam.call("setLobbyData", _lobby_id, key, metadata[key])):
			_fail_room("Steam could not prepare the room. Try again.")
			return
	room_code = "UP2-%d" % _lobby_id
	status_changed.emit("Invite a friend to play.")
	room_ready.emit()


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if lobby_id != _join_pending_id:
		return
	_join_pending_id = 0
	if _mode != "steam" or is_host:
		if response == 1:
			_steam.call("leaveLobby", lobby_id)
		return
	_lobby_deadline = 0
	if response != 1:
		_fail_room("Steam room unavailable. Ask your friend for a new invite.")
		return
	_lobby_id = lobby_id
	var owner := int(_steam.call("getLobbyOwner", lobby_id))
	var metadata_host := str(_steam.call("getLobbyData", lobby_id, "host"))
	_token = str(_steam.call("getLobbyData", lobby_id, "token"))
	var matches_version := (
		str(_steam.call("getLobbyData", lobby_id, "mod")) == MOD_ID
		and str(_steam.call("getLobbyData", lobby_id, "protocol")) == str(PROTOCOL)
		and str(_steam.call("getLobbyData", lobby_id, "game_version")) == GAME_VERSION
	)
	if not matches_version:
		_fail_room("Both players need the same game and mod version.")
		return
	if (
		owner == 0
		or owner == int(_steam.call("getSteamID"))
		or metadata_host != str(owner)
		or _token.length() != 32
		or not _token.is_valid_hex_number()
	):
		_fail_room("This Steam room is no longer available.")
		return
	_peer_id = owner
	room_code = "UP2-%d" % _lobby_id
	_deadline = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS
	status_changed.emit("Connecting to your friend...")
	_send_hello()


func _on_lobby_chat_update(
	lobby_id: int, changed_id: int, _making_change_id: int, state: int
) -> void:
	if lobby_id != _lobby_id or _mode != "steam":
		return
	if not is_host and int(_steam.call("getLobbyOwner", lobby_id)) != _peer_id:
		_drop_peer("Host left the room.")
	elif changed_id == _peer_id and (state & LOBBY_MEMBER_GONE) != 0:
		_drop_peer("Guest left. Waiting for a friend." if is_host else "Host left the room.")


func _lobby_has_member(id: int) -> bool:
	for index in range(int(_steam.call("getNumLobbyMembers", _lobby_id))):
		if int(_steam.call("getLobbyMemberByIndex", _lobby_id, index)) == id:
			return true
	return false


func _on_steam_request(id: int) -> void:
	if _mode != "steam" or (id != _peer_id and (not is_host or _peer_id != 0)):
		return
	if _lobby_id == 0 or not _lobby_has_member(id):
		return
	if _peer_id == 0:
		_peer_id = id
		_deadline = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS
	_steam.call("acceptSessionWithUser", id)


func _on_steam_failed(_reason: int, id: int, _state: int, _debug: String) -> void:
	if _mode == "steam" and id == _peer_id:
		_drop_peer("Steam could not connect. Check that both players are online and try again.")


func _send_hello() -> void:
	_hello_sent = true
	_send_wire(
		{"kind": "hello", "protocol": PROTOCOL, "game_version": GAME_VERSION, "token": _token}
	)


func _send_wire(message: Dictionary) -> void:
	if _peer_id == 0:
		return
	var packet := var_to_bytes(message)
	if packet.size() > MAX_PACKET_BYTES:
		_drop_peer("Multiplayer update exceeded the packet limit.")
		return
	if _mode == "lan" and _enet != null:
		_enet.set_target_peer(_peer_id)
		if _enet.put_packet(packet) != OK:
			_drop_peer("Network send failed. You can join again.")
	elif _mode == "steam" and _steam != null:
		# k_nSteamNetworkingSend_Reliable; Steam handles encryption and relaying.
		var result: int = _steam.call("sendMessageToUser", _peer_id, packet, 8, STEAM_CHANNEL)
		if result != 1:
			_drop_peer("Steam send failed (%d). You can join again." % result)


func _receive_wire(sender: int, packet: PackedByteArray) -> void:
	if sender != _peer_id or sender == 0:
		return
	if packet.is_empty() or packet.size() > MAX_PACKET_BYTES:
		_drop_peer("Invalid network packet.")
		return
	# bytes_to_var never instantiates objects (unlike bytes_to_var_with_objects).
	var message: Variant = bytes_to_var(packet)
	if not message is Dictionary or not message.get("kind") is String:
		_drop_peer("Invalid network message.")
		return
	var kind: String = message["kind"]
	if not connected_peer:
		if kind == "reject" and not is_host:
			_drop_peer("Room code or game/mod version did not match.")
			return
		var expected := "hello" if is_host else "welcome"
		if (
			kind != expected
			or message.get("protocol") != PROTOCOL
			or message.get("game_version") != GAME_VERSION
			or message.get("token") != _token
		):
			_send_wire({"kind": "reject"})
			_drop_peer("Room code or game/mod version did not match.")
			return
		if is_host:
			_send_wire(
				{
					"kind": "welcome",
					"protocol": PROTOCOL,
					"game_version": GAME_VERSION,
					"token": _token
				}
			)
			if _peer_id == 0:
				return
		connected_peer = true
		if is_host and _mode == "steam":
			_steam.call("setLobbyJoinable", _lobby_id, false)
		_last_received = Time.get_ticks_msec()
		_last_heartbeat = _last_received
		status_changed.emit("Guest connected." if is_host else "Connected to host.")
		connected.emit()
		return
	_last_received = Time.get_ticks_msec()
	match kind:
		"data":
			if message.get("data") is Dictionary:
				received.emit(message["data"])
		"ping":
			_send_wire({"kind": "pong"})
		"bye":
			_drop_peer("Guest left. Waiting for a guest." if is_host else "Host closed the room.")


func _drop_peer(reason: String) -> void:
	var former_peer := _peer_id
	_peer_id = 0
	connected_peer = false
	_deadline = 0
	_hello_sent = false
	if is_host:
		if _mode == "lan" and _enet != null and former_peer != 0:
			_enet.disconnect_peer(former_peer)
		elif _mode == "steam" and _steam != null and former_peer != 0:
			_steam.call("closeChannelWithUser", former_peer, STEAM_CHANNEL)
		if _mode == "steam" and _lobby_id != 0:
			_steam.call("setLobbyJoinable", _lobby_id, true)
	else:
		_peer_id = former_peer
		close()
	status_changed.emit(reason)
	disconnected.emit(reason)


func _fail_room(reason: String) -> void:
	close()
	status_changed.emit(reason)
	disconnected.emit(reason)

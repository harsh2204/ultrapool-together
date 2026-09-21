extends Node

signal connected
signal peer_joined(id: int)
signal peer_left(id: int, reason: String)
signal disconnected(reason: String)
signal received(sender: int, message: Dictionary)
signal status_changed(text: String)
signal room_ready

const PROTOCOL := 5
const MAX_PLAYERS := 8
const GAME_VERSION := "0.15.7"
const MOD_ID := "ultrapool-together"
const MAX_PACKET_BYTES := 262144
const STEAM_CHANNEL := 47
const STEAM_TRANSIENT_CHANNEL := 48
const LOBBY_FRIENDS_ONLY := 1
const FRIEND_FLAG_IMMEDIATE := 4
const LOBBY_MEMBER_GONE := 2 | 4 | 8 | 16
const HANDSHAKE_TIMEOUT_MS := 15000
const PEER_TIMEOUT_MS := 20000
const HEARTBEAT_MS := 2000

var is_host := false
var connected_peer: bool:
	get:
		return _peers.values().any(func(peer): return peer.ready)
var room_code := ""

var _mode := ""
var _token := ""
var _host_id := 0
var _peers: Dictionary = {}
var _members: Dictionary = {}
var _seen_nonces: Dictionary = {}
var _joinable := true
var _closing := false
var _enet: ENetMultiplayerPeer
var _steam: Object
var _lobby_id := 0
var _create_pending := false
var _join_pending_id := 0
var _lobby_deadline := 0
var _command_line_checked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func local_id() -> int:
	if _mode == "steam" and _steam != null:
		return int(_steam.call("getSteamID"))
	if _mode == "lan" and _enet != null:
		return _enet.get_unique_id()
	return 0


func host_id() -> int:
	return local_id() if is_host else _host_id


func host_lan(port: int, token: String) -> Error:
	close()
	if port < 1024 or port > 65535 or token.length() > 128:
		return ERR_INVALID_PARAMETER
	_token = token if not token.is_empty() else _new_token()
	_enet = ENetMultiplayerPeer.new()
	var error := _enet.create_server(port, MAX_PLAYERS - 1, 2)
	if error != OK:
		close()
		return error
	_enet.peer_connected.connect(_on_enet_connected)
	_enet.peer_disconnected.connect(_on_enet_disconnected)
	_mode = "lan"
	is_host = true
	room_code = _token
	status_changed.emit("Waiting for players on UDP port %d." % port)
	room_ready.emit()
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
	var error := _enet.create_client(host.strip_edges(), port, 2)
	if error != OK:
		close()
		return error
	_mode = "lan"
	_host_id = 1
	_add_peer(_host_id)
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
	_token = _new_token()
	_create_pending = true
	_lobby_deadline = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS
	status_changed.emit("Creating Steam room...")
	_steam.call("createLobby", LOBBY_FRIENDS_ONLY, MAX_PLAYERS)
	return OK


func join_steam(code: String) -> Error:
	var parts := code.strip_edges().split("-")
	if parts.size() != 2 or parts[0] != "UP5" or not parts[1].is_valid_int():
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


func set_joinable(value: bool) -> void:
	_joinable = value
	_update_joinable()


func _update_joinable() -> void:
	if _mode == "steam" and is_host and _lobby_id != 0:
		_steam.call("setLobbyJoinable", _lobby_id, _joinable and _has_room())


func _has_room() -> bool:
	if _peers.size() >= MAX_PLAYERS - 1:
		return false
	return (
		_mode != "steam"
		or _lobby_id == 0
		or int(_steam.call("getNumLobbyMembers", _lobby_id)) < MAX_PLAYERS
	)


func invite_ready() -> bool:
	return _mode == "steam" and is_host and _lobby_id != 0 and _joinable and _has_room()


func session_open() -> bool:
	return not _mode.is_empty() or _create_pending or _join_pending_id != 0


func online_friends() -> Array:
	var friends: Array = []
	if not invite_ready():
		return friends
	for index in range(int(_steam.call("getFriendCount", FRIEND_FLAG_IMMEDIATE))):
		var id := int(_steam.call("getFriendByIndex", index, FRIEND_FLAG_IMMEDIATE))
		if int(_steam.call("getFriendPersonaState", id)) == 0 or _lobby_has_member(id):
			continue
		friends.append({"id": id, "name": _player_name(id)})
	friends.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	return friends


func _player_name(id: int) -> String:
	if _mode == "steam":
		var name := str(_steam.call("getFriendPersonaName", id))
		name = name.replace("\n", " ").replace("\r", " ").strip_edges().left(48)
		return name if not name.is_empty() else "Steam player"
	return "Host" if id == host_id() else "LAN player %d" % id


func participants() -> Array:
	var people: Array = []
	if _mode.is_empty():
		return people
	var ids: Array = []
	if is_host:
		ids.append(local_id())
		ids.append_array(_peers.keys())
	else:
		ids = _members.keys()
		for id in [local_id(), _host_id]:
			if id != 0 and not ids.has(id):
				ids.append(id)
	for id in ids:
		var ready: bool = id == local_id() or _members.has(id)
		if is_host or id == _host_id:
			ready = id == local_id() or (_peers.has(id) and _peers[id].ready)
		people.append(
			{
				"id": id,
				"name": _members[id] if _members.has(id) else _player_name(id),
				"host": id == host_id(),
				"you": id == local_id(),
				"connected": ready
			}
		)
	people.sort_custom(func(a, b): return a.host if a.host != b.host else a.id < b.id)
	return people


func invite_friend(friend_id: int) -> Error:
	if not invite_ready():
		return ERR_UNAVAILABLE
	if not bool(_steam.call("inviteUserToLobby", _lobby_id, friend_id)):
		status_changed.emit("Steam couldn't send the invitation. Share your room code instead.")
		return FAILED
	status_changed.emit("Invitation sent through Steam.")
	return OK


func _join_lobby(lobby_id: int) -> Error:
	if lobby_id <= 0:
		return ERR_INVALID_PARAMETER
	if lobby_id == _lobby_id:
		return OK
	if connected_peer or is_host:
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
	broadcast_except(message, 0)


func connected_peers() -> Array:
	return _peers.keys().filter(func(id): return _peers[id].ready)


func send_to(id: int, message: Dictionary, unreliable := false) -> void:
	if _peers.has(id) and _peers[id].ready:
		_send_wire(id, {"kind": "data", "data": message}, unreliable)


func send_unreliable(message: Dictionary) -> void:
	broadcast_except(message, 0, true)


func broadcast_except(message: Dictionary, exclude_id: int, unreliable := false) -> void:
	for id in _peers.keys():
		if id != exclude_id and _peers.has(id) and _peers[id].ready:
			_send_wire(id, {"kind": "data", "data": message}, unreliable)


func disconnect_peer(id: int, reason: String) -> void:
	if not is_host or not _peers.has(id):
		return
	_send_wire(id, {"kind": "bye", "reason": reason.left(256)})
	_drop_peer(id, reason)


func close() -> void:
	_closing = true
	for id in _peers.keys():
		if _peers[id].ready:
			_send_wire(id, {"kind": "bye"})
		_close_channels(id)
	_peers.clear()
	_members.clear()
	_seen_nonces.clear()
	if _enet != null:
		_enet.close()
		_enet = null
	if _steam != null and _lobby_id != 0:
		_steam.call("leaveLobby", _lobby_id)
	_lobby_id = 0
	_lobby_deadline = 0
	# Pending request IDs remain until their callbacks can leave cancelled lobbies.
	_mode = ""
	_token = ""
	_host_id = 0
	_joinable = true
	is_host = false
	room_code = ""
	_closing = false


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
		"getFriendCount",
		"getFriendByIndex",
		"getFriendPersonaState",
		"getFriendPersonaName",
		"inviteUserToLobby",
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
			and _peers.has(_host_id)
			and not _peers[_host_id].hello_sent
			and _enet.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		):
			_send_hello()
		var packet_count := 0
		while _enet != null and _enet.get_available_packet_count() > 0 and packet_count < 128:
			var sender := _enet.get_packet_peer()
			var transient := _enet.get_packet_channel() == 1
			var packet := _enet.get_packet()
			_receive_wire(sender, packet, transient)
			packet_count += 1
		if (
			_enet != null
			and not is_host
			and _enet.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED
		):
			_drop_peer(_host_id, "Host disconnected. You can join again.")
	elif _mode == "steam":
		for channel in [STEAM_CHANNEL, STEAM_TRANSIENT_CHANNEL]:
			if _mode != "steam":
				break
			var packets: Array = _steam.call("receiveMessagesOnChannel", channel, 128)
			for packet in packets:
				if _mode != "steam":
					break
				_receive_wire(
					int(packet.get("identity", 0)),
					packet.get("payload", PackedByteArray()),
					channel == STEAM_TRANSIENT_CHANNEL
				)
	var now := Time.get_ticks_msec()
	for id in _peers.keys():
		if not _peers.has(id):
			continue
		var peer: Dictionary = _peers[id]
		if not peer.ready:
			if now >= peer.deadline:
				_drop_peer(id, "Connection timed out. Try joining again.")
		elif now - peer.last_received > PEER_TIMEOUT_MS:
			_drop_peer(id, "Connection lost. You can join again.")
		elif now - peer.last_heartbeat >= HEARTBEAT_MS:
			peer.last_heartbeat = now
			_send_wire(id, {"kind": "ping"})


func _new_token() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func _add_peer(id: int) -> void:
	_peers[id] = {
		"ready": false,
		"hello_sent": false,
		"deadline": Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS,
		"last_received": 0,
		"last_heartbeat": 0,
		"nonce": "" if is_host else _new_token(),
		"session": ""
	}


func _on_enet_connected(id: int) -> void:
	if not is_host:
		return
	if not _joinable or _peers.size() >= MAX_PLAYERS - 1:
		_enet.disconnect_peer(id)
		return
	_add_peer(id)


func _on_enet_disconnected(id: int) -> void:
	if _peers.has(id):
		_drop_peer(id, "Player disconnected.")


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
		"host": str(local_id()),
		"token": _token,
	}
	for key in metadata:
		if not bool(_steam.call("setLobbyData", _lobby_id, key, metadata[key])):
			_fail_room("Steam could not prepare the room. Try again.")
			return
	room_code = "UP5-%d" % _lobby_id
	_update_joinable()
	status_changed.emit("Invite friends or share your room code.")
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
		_fail_room("Steam room unavailable. Ask the host for a new invite.")
		return
	_lobby_id = lobby_id
	var owner := int(_steam.call("getLobbyOwner", lobby_id))
	var metadata_host := str(_steam.call("getLobbyData", lobby_id, "host"))
	_token = str(_steam.call("getLobbyData", lobby_id, "token"))
	if (
		str(_steam.call("getLobbyData", lobby_id, "mod")) != MOD_ID
		or str(_steam.call("getLobbyData", lobby_id, "protocol")) != str(PROTOCOL)
		or str(_steam.call("getLobbyData", lobby_id, "game_version")) != GAME_VERSION
	):
		_fail_room("All players need the same game and mod version.")
		return
	if owner == 0 or owner == local_id() or metadata_host != str(owner) or not _valid_token(_token):
		_fail_room("This Steam room is no longer available.")
		return
	_host_id = owner
	_add_peer(owner)
	room_code = "UP5-%d" % _lobby_id
	status_changed.emit("Connecting to the host...")
	_send_hello()


func _on_lobby_chat_update(
	lobby_id: int, changed_id: int, _making_change_id: int, state: int
) -> void:
	if lobby_id != _lobby_id or _mode != "steam":
		return
	if not is_host and int(_steam.call("getLobbyOwner", lobby_id)) != _host_id:
		_drop_peer(_host_id, "Host left the room.")
	elif _peers.has(changed_id) and (state & LOBBY_MEMBER_GONE) != 0:
		_drop_peer(changed_id, "Player left the room." if is_host else "Host left the room.")
	_update_joinable()


func _lobby_has_member(id: int) -> bool:
	for index in range(int(_steam.call("getNumLobbyMembers", _lobby_id))):
		if int(_steam.call("getLobbyMemberByIndex", _lobby_id, index)) == id:
			return true
	return false


func _on_steam_request(id: int) -> void:
	if _mode != "steam" or _lobby_id == 0 or id == local_id() or not _lobby_has_member(id):
		return
	if not _peers.has(id):
		if not is_host or not _joinable or _peers.size() >= MAX_PLAYERS - 1:
			return
		_add_peer(id)
	_steam.call("acceptSessionWithUser", id)
	_update_joinable()


func _on_steam_failed(_reason: int, id: int, _state: int, _debug: String) -> void:
	if _mode == "steam" and _peers.has(id):
		_drop_peer(id, "Steam could not connect. Check that all players are online and try again.")


func _send_hello() -> void:
	_peers[_host_id].hello_sent = true
	_send_wire(
		_host_id,
		{
			"kind": "hello",
			"protocol": PROTOCOL,
			"game_version": GAME_VERSION,
			"token": _token,
			"nonce": _peers[_host_id].nonce
		}
	)


func _send_wire(id: int, message: Dictionary, transient := false) -> void:
	if not _peers.has(id):
		return
	var envelope := message.duplicate()
	envelope["session"] = _peers[id].session
	var packet := var_to_bytes(envelope)
	if packet.size() > MAX_PACKET_BYTES:
		if not transient and not _closing:
			_drop_peer(id, "Multiplayer update exceeded the packet limit.")
		return
	if _mode == "lan" and _enet != null:
		_enet.set_target_peer(id)
		_enet.transfer_channel = 1 if transient else 0
		_enet.transfer_mode = (
			MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
			if transient
			else MultiplayerPeer.TRANSFER_MODE_RELIABLE
		)
		if _enet.put_packet(packet) != OK and not transient and not _closing:
			_drop_peer(id, "Network send failed. You can join again.")
	elif _mode == "steam" and _steam != null:
		# UnreliableNoDelay drops stale updates; ReliableNoNagle sends actions promptly.
		var flags := 5 if transient else 9
		var channel := STEAM_TRANSIENT_CHANNEL if transient else STEAM_CHANNEL
		var result: int = _steam.call("sendMessageToUser", id, packet, flags, channel)
		if result != 1 and not transient and not _closing:
			_drop_peer(id, "Steam send failed (%d). You can join again." % result)


func _receive_wire(sender: int, packet: PackedByteArray, transient := false) -> void:
	if not _peers.has(sender):
		return
	var peer: Dictionary = _peers[sender]
	if transient and not peer.ready:
		return
	if packet.is_empty() or packet.size() > MAX_PACKET_BYTES:
		if not transient:
			_drop_peer(sender, "Invalid network packet.")
		return
	# bytes_to_var never instantiates objects (unlike bytes_to_var_with_objects).
	var message: Variant = bytes_to_var(packet)
	if not message is Dictionary or not message.get("kind") is String:
		if not transient:
			_drop_peer(sender, "Invalid network message.")
		return
	var kind: String = message.kind
	if (
		is_host
		and not transient
		and kind == "hello"
		and not peer.nonce.is_empty()
		and message.get("nonce") != peer.nonce
		and _valid_token(message.get("nonce"))
		and message.get("token") == _token
		and message.get("protocol") == PROTOCOL
		and message.get("game_version") == GAME_VERSION
	):
		if _seen_nonces.get(sender, []).has(message.nonce):
			return
		var was_ready: bool = peer.ready
		_add_peer(sender)
		if was_ready:
			_publish_members()
			peer_left.emit(sender, "Player is reconnecting.")
		if not _peers.has(sender):
			return
		peer = _peers[sender]
	if transient and kind != "data":
		return
	if not peer.ready:
		_handshake(sender, message)
		return
	if message.get("session") != peer.session:
		return
	peer.last_received = Time.get_ticks_msec()
	match kind:
		"data":
			if message.get("data") is Dictionary:
				received.emit(sender, message.data)
		"members":
			if not is_host:
				_receive_members(message.get("players"))
		"ping":
			_send_wire(sender, {"kind": "pong"})
		"bye":
			var reason := "Player left the room." if is_host else "Host closed the room."
			if not is_host and message.get("reason") is String:
				reason = message.reason.left(256)
			_drop_peer(sender, reason)


func _valid_token(value) -> bool:
	return value is String and value.length() == 32 and value.is_valid_hex_number()


func _handshake(id: int, message: Dictionary) -> void:
	var peer: Dictionary = _peers[id]
	if message.kind == "reject" and not is_host:
		if message.get("nonce") == peer.nonce:
			_drop_peer(id, "Room unavailable, or game/mod version did not match.")
		return
	if is_host and message.kind == "ready":
		if not peer.session.is_empty() and message.get("session") == peer.session:
			_mark_ready(id)
		return
	var expected := "hello" if is_host else "welcome"
	if message.kind != expected:
		return
	if not is_host and message.get("nonce") != peer.nonce:
		return
	if (
		message.get("protocol") != PROTOCOL
		or message.get("game_version") != GAME_VERSION
		or message.get("token") != _token
		or not _valid_token(message.get("nonce"))
		or (is_host and not _joinable)
	):
		_send_wire(id, {"kind": "reject", "nonce": message.get("nonce", "")})
		_drop_peer(id, "Room unavailable, or game/mod version did not match.")
		return
	if is_host:
		if not peer.nonce.is_empty() and peer.nonce != message.nonce:
			return
		if peer.nonce.is_empty():
			var previous: Array = _seen_nonces.get(id, [])
			if previous.has(message.nonce):
				return
			previous.append(message.nonce)
			if previous.size() > 32:
				previous.pop_front()
			_seen_nonces[id] = previous
		peer.nonce = message.nonce
		if peer.session.is_empty():
			peer.session = _new_token()
		_send_wire(
			id,
			{
				"kind": "welcome",
				"protocol": PROTOCOL,
				"game_version": GAME_VERSION,
				"token": _token,
				"nonce": peer.nonce
			}
		)
	else:
		if not _valid_token(message.get("session")):
			return
		peer.session = message.session
		_send_wire(id, {"kind": "ready"})
		if _peers.has(id):
			_mark_ready(id)


func _mark_ready(id: int) -> void:
	_peers[id].ready = true
	_peers[id].last_received = Time.get_ticks_msec()
	_peers[id].last_heartbeat = Time.get_ticks_msec()
	_update_joinable()
	if is_host:
		_publish_members()
	else:
		connected.emit()
	if not _peers.has(id):
		return
	status_changed.emit("Player connected." if is_host else "Connected to host.")
	peer_joined.emit(id)


func _publish_members() -> void:
	var players: Array = []
	for person in participants():
		if person.connected:
			players.append({"id": person.id, "name": person.name})
	for id in _peers.keys():
		if _peers.has(id) and _peers[id].ready:
			_send_wire(id, {"kind": "members", "players": players})


func _receive_members(players) -> void:
	if not players is Array or players.size() > MAX_PLAYERS:
		return
	var members: Dictionary = {}
	for person in players:
		if (
			not person is Dictionary
			or not person.get("id") is int
			or person.id <= 0
			or members.has(person.id)
			or not person.get("name") is String
			or person.name.length() > 48
		):
			return
		members[person.id] = person.name
	if members.has(local_id()) and members.has(_host_id):
		_members = members


func _close_channels(id: int) -> void:
	if _mode == "steam" and _steam != null:
		_steam.call("closeChannelWithUser", id, STEAM_CHANNEL)
		_steam.call("closeChannelWithUser", id, STEAM_TRANSIENT_CHANNEL)


func _drop_peer(id: int, reason: String) -> void:
	if not _peers.has(id):
		return
	var was_ready: bool = _peers[id].ready
	_peers.erase(id)
	_close_channels(id)
	if is_host:
		if _mode == "lan" and _enet != null:
			_enet.disconnect_peer(id)
		_update_joinable()
		_publish_members()
		if was_ready:
			peer_left.emit(id, reason)
		status_changed.emit(reason)
	else:
		close()
		if was_ready:
			peer_left.emit(id, reason)
		status_changed.emit(reason)
		disconnected.emit(reason)


func _fail_room(reason: String) -> void:
	close()
	status_changed.emit(reason)
	disconnected.emit(reason)

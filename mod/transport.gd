extends Node

signal connected
signal disconnected(reason: String)
signal received(message: Dictionary)
signal status_changed(text: String)

const PROTOCOL := 1
const GAME_VERSION := "0.15.7"
const MAX_PACKET_BYTES := 1048576
const STEAM_MAX_PACKET_BYTES := 524288
const STEAM_CHANNEL := 47
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
	if host.strip_edges().is_empty() or port < 1024 or port > 65535 or token.is_empty() or token.length() > 128:
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
	close()
	if not _prepare_steam():
		return ERR_UNAVAILABLE
	_mode = "steam"
	is_host = true
	_token = Crypto.new().generate_random_bytes(16).hex_encode()
	room_code = "UP1-%d-%s" % [int(_steam.call("getSteamID")), _token]
	status_changed.emit("Steam room ready. Share the room code with your guest.")
	return OK


func join_steam(code: String) -> Error:
	close()
	var parts := code.strip_edges().split("-")
	if parts.size() != 3 or parts[0] != "UP1" or not parts[1].is_valid_int() or parts[2].length() != 32 or not parts[2].is_valid_hex_number():
		return ERR_INVALID_PARAMETER
	var host_id := int(parts[1])
	if host_id <= 0:
		return ERR_INVALID_PARAMETER
	if not _prepare_steam():
		return ERR_UNAVAILABLE
	if host_id == int(_steam.call("getSteamID")):
		close()
		return ERR_INVALID_PARAMETER
	_mode = "steam"
	_token = parts[2]
	room_code = code.strip_edges()
	_peer_id = host_id
	_deadline = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS
	status_changed.emit("Connecting through Steam...")
	_send_hello()
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
		for binding in [["network_messages_session_request", _on_steam_request], ["network_messages_session_failed", _on_steam_failed]]:
			if _steam.is_connected(binding[0], binding[1]):
				_steam.disconnect(binding[0], binding[1])
		_steam = null
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


func _prepare_steam() -> bool:
	if not Engine.has_singleton("Steam"):
		return false
	_steam = Engine.get_singleton("Steam")
	for method in ["sendMessageToUser", "receiveMessagesOnChannel", "acceptSessionWithUser", "closeChannelWithUser", "loggedOn", "getSteamID"]:
		if not _steam.has_method(method):
			_steam = null
			return false
	if not bool(_steam.call("loggedOn")) and _steam.has_method("steamInitEx"):
		var initialization: Dictionary = _steam.call("steamInitEx")
		if initialization.get("status", 1) != 0:
			status_changed.emit("Steam initialization failed. Start Steam and launch ULTRAPOOL once, then retry.")
			_steam = null
			return false
	if not bool(_steam.call("loggedOn")) or int(_steam.call("getSteamID")) == 0:
		_steam = null
		return false
	_steam.connect("network_messages_session_request", _on_steam_request)
	_steam.connect("network_messages_session_failed", _on_steam_failed)
	if _steam.has_method("initRelayNetworkAccess"):
		_steam.call("initRelayNetworkAccess")
	return true


func _process(_delta: float) -> void:
	if _mode == "lan":
		_enet.poll()
		if _enet == null:
			return
		if not is_host and not _hello_sent and _enet.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_send_hello()
		var packet_count := 0
		while _enet != null and _enet.get_available_packet_count() > 0 and packet_count < 64:
			var sender := _enet.get_packet_peer()
			var packet := _enet.get_packet()
			_receive_wire(sender, packet)
			packet_count += 1
		if _enet != null and not is_host and _enet.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_drop_peer("Host disconnected. You can join again.")
	elif _mode == "steam":
		_steam.call("run_callbacks")
		if _steam == null or _mode != "steam":
			return
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
			_drop_peer("Connection timed out. Check the room code or host address and try again.")
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
		_drop_peer("Guest disconnected. Waiting for a guest." if is_host else "Host disconnected. You can join again.")


func _on_steam_request(id: int) -> void:
	if _mode != "steam" or (id != _peer_id and (not is_host or _peer_id != 0)):
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
	_send_wire({"kind": "hello", "protocol": PROTOCOL, "game_version": GAME_VERSION, "token": _token})


func _send_wire(message: Dictionary) -> void:
	if _peer_id == 0:
		return
	var packet := var_to_bytes(message)
	var limit := STEAM_MAX_PACKET_BYTES if _mode == "steam" else MAX_PACKET_BYTES
	if packet.size() > limit:
		status_changed.emit("Packet too large; lower the stream resolution.")
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
		if kind != expected or message.get("protocol") != PROTOCOL or message.get("game_version") != GAME_VERSION or message.get("token") != _token:
			_send_wire({"kind": "reject"})
			_drop_peer("Room code or game/mod version did not match.")
			return
		if is_host:
			_send_wire({"kind": "welcome", "protocol": PROTOCOL, "game_version": GAME_VERSION, "token": _token})
			if _peer_id == 0:
				return
		connected_peer = true
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
	else:
		_peer_id = former_peer
		close()
	status_changed.emit(reason)
	disconnected.emit(reason)

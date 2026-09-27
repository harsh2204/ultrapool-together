extends SceneTree

const Transport = preload("../mod/transport.gd")


class SteamStub:
	extends RefCounted
	var owner = 10
	var local = 20
	var sent: Array = []
	var left: Array = []
	var data: Dictionary = {}

	# Match GodotSteam's API spelling.
	# gdlint: disable=function-name
	func run_callbacks() -> void:
		pass

	func receiveMessagesOnChannel(_channel: int, _maximum: int) -> Array:
		return []

	func getLobbyOwner(_lobby: int) -> int:
		return owner

	func getSteamID() -> int:
		return local

	func sendMessageToUser(id: int, packet: PackedByteArray, _flags: int, _channel: int) -> int:
		sent.append({"id": id, "message": bytes_to_var(packet)})
		return 1

	func closeChannelWithUser(_id: int, _channel: int) -> void:
		pass

	func leaveLobby(lobby: int) -> void:
		left.append(lobby)

	func setLobbyJoinable(_lobby: int, _joinable: bool) -> bool:
		return true

	func setLobbyData(_lobby: int, key: String, value: String) -> bool:
		data[key] = value
		return true

	func getNumLobbyMembers(_lobby: int) -> int:
		return 2

	func getFriendPersonaName(_id: int) -> String:
		return "Player"


class Events:
	extends RefCounted
	var lost: Array = []
	var reconnected = 0
	var connected = 0
	var disconnected: Array = []

	func watch(transport: Node) -> void:
		transport.host_lost.connect(func(reason): lost.append(reason))
		transport.reconnected.connect(func(): reconnected += 1)
		transport.connected.connect(func(): connected += 1)
		transport.disconnected.connect(func(reason): disconnected.append(reason))


var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_lost_host_reconnects()
	_reconnect_window_expires()
	_owner_change_migrates()
	_room_closure_is_final()
	_host_and_lan_keep_existing_behavior()
	for failure in failures:
		print("TRANSPORT_RECONNECT_PROBE FAIL ", failure)
	print("TRANSPORT_RECONNECT_PROBE ", "PASS" if failures.is_empty() else "FAIL", " ", checks)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _guest() -> Node:
	var transport = Transport.new()
	transport._steam = SteamStub.new()
	transport._mode = "steam"
	transport._lobby_id = 77
	transport._host_id = 10
	transport._token = "0123456789abcdef0123456789abcdef"
	transport._add_peer(10)
	transport._mark_ready(10)
	return transport


func _dispose(transport: Node) -> void:
	transport.close()
	transport._steam = null
	transport.free()


func _time_out(transport: Node) -> void:
	transport._peers[10].last_received = Time.get_ticks_msec() - transport.PEER_TIMEOUT_MS - 1
	transport._process(0.016)


func _welcome(transport: Node) -> void:
	var peer: Dictionary = transport._peers[10]
	transport._handshake(
		10,
		{
			"kind": "welcome",
			"protocol": transport.PROTOCOL,
			"game_version": transport.GAME_VERSION,
			"token": transport._token,
			"nonce": peer.nonce,
			"session": "fedcba9876543210fedcba9876543210"
		}
	)


func _lost_host_reconnects() -> void:
	var transport = _guest()
	var steam: SteamStub = transport._steam
	var events = Events.new()
	events.watch(transport)
	_time_out(transport)
	_check(events.lost.size() == 1, "timed-out host link reports host_lost once")
	_check(events.disconnected.is_empty(), "timed-out host link does not end the session")
	_check(steam.left.is_empty(), "guest stays in the Steam room while reconnecting")
	_check(transport.session_open() and transport._lobby_id == 77, "room membership is kept")
	transport._process(0.016)
	_check(not transport._peers.has(10), "reconnect waits for its retry interval")
	var old_nonce = ""
	transport._reconnect_at = 0
	steam.sent.clear()
	transport._process(0.016)
	var hellos = steam.sent.filter(func(entry): return entry.message.kind == "hello")
	_check(hellos.size() == 1 and hellos[0].id == 10, "retry sends a fresh hello to the host")
	old_nonce = transport._peers[10].nonce
	transport._peers[10].deadline = 0
	transport._process(0.016)
	_check(
		events.lost.size() == 1 and events.disconnected.is_empty(), "failed attempt keeps retrying"
	)
	transport._reconnect_at = 0
	transport._process(0.016)
	_check(transport._peers[10].nonce != old_nonce, "each attempt uses a new nonce")
	_welcome(transport)
	_check(events.reconnected == 1 and events.connected == 0, "handshake reports a reconnection")
	_check(transport._reconnect_deadline == 0, "successful reconnection clears the retry window")
	_time_out(transport)
	_check(events.lost.size() == 2, "a later loss starts a new reconnect window")
	_dispose(transport)


func _reconnect_window_expires() -> void:
	var transport = _guest()
	var events = Events.new()
	events.watch(transport)
	_time_out(transport)
	transport._reconnect_deadline = Time.get_ticks_msec() - 1
	transport._process(0.016)
	_check(events.disconnected.size() == 1, "expired reconnect window ends the session")
	_check((transport._steam as SteamStub).left == [77], "expired window leaves the Steam room")
	_dispose(transport)


func _owner_change_migrates() -> void:
	var transport = _guest()
	var steam: SteamStub = transport._steam
	var events = Events.new()
	events.watch(transport)
	var changes: Array = []
	transport.host_changed.connect(func(host, previous): changes.append([host, previous]))
	_time_out(transport)
	steam.owner = 30
	transport._reconnect_at = 0
	transport._process(0.016)
	_check(changes == [[30, 10]], "pending reconnection follows Steam's new room owner")
	_check(events.disconnected.is_empty() and steam.left.is_empty(), "migration keeps the session")
	_check(
		transport._host_id == 30 and not transport._peers.has(30),
		"new host gets time to restore the room before the first hello"
	)
	transport._reconnect_at = 0
	steam.sent.clear()
	transport._process(0.016)
	_check(
		steam.sent.any(func(entry): return entry.id == 30 and entry.message.kind == "hello"),
		"guest greets the new room host"
	)
	_dispose(transport)
	transport = _guest()
	steam = transport._steam
	events = Events.new()
	events.watch(transport)
	changes.clear()
	transport.host_changed.connect(func(host, previous): changes.append([host, previous]))
	steam.owner = 30
	transport._on_lobby_chat_update(77, 10, 10, 2)
	_check(changes == [[30, 10]], "room update announcing a new owner starts migration")
	_check(events.lost.is_empty() and events.disconnected.is_empty(), "migration is not a failure")
	_dispose(transport)
	transport = _guest()
	steam = transport._steam
	var promotions: Array = []
	transport.host_promoted.connect(func(previous): promotions.append(previous))
	steam.owner = 20
	transport._on_lobby_chat_update(77, 10, 10, 2)
	_check(promotions == [10] and transport.is_host, "new Steam owner becomes the room host")
	_check(steam.data.get("host") == "20", "promoted host advertises itself in the room data")
	_check(
		transport._peers.is_empty() and transport.host_id() == 20, "promotion starts a new peer set"
	)
	_dispose(transport)
	transport = _guest()
	events = Events.new()
	events.watch(transport)
	(transport._steam as SteamStub).owner = 0
	transport._on_lobby_chat_update(77, 10, 10, 2)
	_check(events.disconnected.size() == 1, "a room without an owner has closed")
	_dispose(transport)


func _room_closure_is_final() -> void:
	var transport = _guest()
	var events = Events.new()
	events.watch(transport)
	transport._drop_peer(10, "Host closed the room.")
	_check(
		events.lost.is_empty() and events.disconnected.size() == 1,
		"closing the room is not retried"
	)
	_dispose(transport)


func _host_and_lan_keep_existing_behavior() -> void:
	var host = Transport.new()
	host._steam = SteamStub.new()
	host._mode = "steam"
	host.is_host = true
	host._lobby_id = 77
	host._add_peer(30)
	host._mark_ready(30)
	var departures: Array = []
	host.peer_left.connect(func(id, _reason): departures.append(id))
	host._drop_peer(30, "Connection lost.", true)
	_check(departures == [30] and host._reconnect_deadline == 0, "room host drops lost guests")
	_dispose(host)
	var lan = _guest()
	lan._mode = "lan"
	var events = Events.new()
	events.watch(lan)
	lan._drop_peer(10, "Host disconnected.", true)
	_check(
		events.lost.is_empty() and events.disconnected.size() == 1, "LAN sessions do not reconnect"
	)
	lan._steam = null
	lan.free()

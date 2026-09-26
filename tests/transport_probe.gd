extends Node

var host_node: Node
var guests: Array = []
var inbox: Array = []
var joined: Array = []
var departed: Array = []
var host_connected_events = 0
var host_disconnect_events = 0
var failed := false
var _transport_script: Script


func check(condition: bool, label: String) -> void:
	print("TRANSPORT TEST ", "PASS " if condition else "FAIL ", label)
	failed = failed or not condition


func pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _record(sender: int, message: Dictionary, receiver: String) -> void:
	inbox.append({"sender": sender, "message": message, "receiver": receiver})


func _new_guest() -> Node:
	var guest = _transport_script.new()
	add_child(guest)
	guest.received.connect(_record.bind("guest%d" % guests.size()))
	guests.append(guest)
	return guest


func _count(kind: String, receiver = "") -> int:
	return (
		inbox
		. filter(
			func(entry):
				return (
					entry.message.get("kind") == kind
					and (receiver == "" or entry.receiver == receiver)
				)
		)
		. size()
	)


func _run() -> void:
	if not OS.get_user_data_dir().contains("UltrapoolTogetherTransportTest"):
		print("TRANSPORT TEST FAIL isolated save directory required")
		get_tree().quit(2)
		return
	get_node("/root/SettingsManager").set("use_analytics", false)
	get_node("/root/AnalyticsManager").set("state", 0)
	get_node("/root/PlatformManager").set("_steam", null)
	get_node("/root/CloudSaveManager").set("backend", null)
	var path = get_script().resource_path.get_base_dir().get_base_dir().path_join(
		"mod/transport.gd"
	)
	_transport_script = load(path)
	if _transport_script == null or not _transport_script.can_instantiate():
		print("TRANSPORT TEST FAIL script did not compile")
		get_tree().quit(1)
		return
	host_node = _transport_script.new()
	add_child(host_node)
	host_node.received.connect(_record.bind("host"))
	host_node.peer_joined.connect(func(id): joined.append(id))
	host_node.peer_left.connect(func(id, _reason): departed.append(id))
	host_node.connected.connect(func(): host_connected_events += 1)
	host_node.disconnected.connect(func(_reason): host_disconnect_events += 1)
	check(host_node.host_lan(47657, "") == OK, "host opens port")
	check(host_node.room_code.length() == 32, "random room token")
	for _index in range(3):
		check(_new_guest().join_lan("127.0.0.1", 47657, host_node.room_code) == OK, "guest starts")
	await pause(2.0)
	check(host_node.connected_peers().size() == 3, "three independently verified guests")
	check(
		joined.size() == 3 and host_connected_events == 0, "peer joins do not restart host session"
	)
	check(guests.all(func(guest): return guest.connected_peer), "all guests finish handshake")
	check(
		guests.all(func(guest): return guest.participants().size() == 4),
		"host membership reaches all guests"
	)
	if host_node.connected_peers().size() != 3:
		_finish()
		return
	var first_id: int = guests[0].local_id()
	check(host_node.host_id() == host_node.local_id(), "host identity is separate from guest slots")
	check(guests[0].host_id() == host_node.local_id(), "guest knows coordinator identity")
	check(
		guests[0].join_steam("UP8-123") == ERR_ALREADY_IN_USE, "invite preserves active connection"
	)
	for guest in guests:
		guest.send({"kind": "input", "claimed_actor": first_id, "actual": guest.local_id()})
	host_node.send_to(first_id, {"kind": "private_reply"})
	host_node.send({"kind": "broadcast"})
	host_node.broadcast_except({"kind": "relay"}, first_id, true)
	await pause(0.5)
	check(_count("input", "host") == 3, "all guests can send to coordinator")
	check(
		(
			inbox
			. filter(func(entry): return entry.message.get("kind") == "input")
			. all(func(entry): return entry.sender == entry.message.actual)
		),
		"payload claims cannot change authenticated sender"
	)
	check(
		_count("private_reply") == 1 and _count("private_reply", "guest0") == 1, "addressed reply"
	)
	check(_count("broadcast") == 3, "broadcast reaches every guest")
	check(
		_count("relay") == 2 and _count("relay", "guest0") == 0, "transient relay excludes sender"
	)
	var replaced_session: String = host_node._peers[first_id].session
	var replaced_nonce: String = host_node._peers[first_id].nonce
	guests[0]._add_peer(guests[0].host_id())
	guests[0]._send_hello()
	await pause(0.5)
	check(
		(
			host_node.connected_peers().size() == 3
			and host_node._peers[first_id].session != replaced_session
		),
		"fresh hello replaces the same identity before old connection timeout"
	)
	var old_session: String = host_node._peers[first_id].session
	host_node._receive_wire(
		first_id,
		var_to_bytes(
			{
				"kind": "hello",
				"protocol": host_node.PROTOCOL,
				"game_version": "0.15.7",
				"token": host_node.room_code,
				"nonce": replaced_nonce
			}
		)
	)
	check(
		host_node._peers[first_id].ready and host_node._peers[first_id].session == old_session,
		"delayed retired hello cannot replace the new session"
	)
	guests[0].close()
	await pause(0.5)
	check(host_node.connected_peers().size() == 2, "one departure leaves other guests connected")
	check(departed.has(first_id) and host_disconnect_events == 0, "departure is peer-specific")
	check(host_node.is_host and host_node.session_open(), "host room survives departure")
	guests[0].join_lan("127.0.0.1", 47657, host_node.room_code)
	await pause(0.5)
	first_id = guests[0].local_id()
	check(host_node.connected_peers().size() == 3, "guest reconnects without resetting others")
	if not host_node._peers.has(first_id):
		_finish()
		return
	check(
		host_node._peers[first_id].session != old_session, "reconnect gets fresh session identity"
	)
	host_node._receive_wire(
		first_id, var_to_bytes({"kind": "data", "session": old_session, "data": {"kind": "stale"}})
	)
	host_node._receive_wire(0, var_to_bytes({"kind": "data", "data": {"kind": "unknown_sender"}}))
	check(
		_count("stale") == 0 and _count("unknown_sender") == 0, "stale and unknown packets ignored"
	)
	var rejected = _transport_script.new()
	add_child(rejected)
	rejected.join_lan("127.0.0.1", 47657, "wrong-token")
	await pause(0.5)
	check(
		not rejected.connected_peer and host_node.connected_peers().size() == 3,
		"bad token isolated"
	)
	rejected.close()
	host_node.set_joinable(false)
	rejected.join_lan("127.0.0.1", 47657, host_node.room_code)
	await pause(0.5)
	check(
		not rejected.connected_peer and host_node.connected_peers().size() == 3,
		"closed room rejects join"
	)
	rejected.close()
	host_node.set_joinable(true)
	for _index in range(3, host_node.MAX_PLAYERS - 1):
		_new_guest().join_lan("127.0.0.1", 47657, host_node.room_code)
	await pause(2.0)
	check(host_node.connected_peers().size() == 7, "eight-player room capacity")
	check(
		guests.all(func(guest): return guest.participants().size() == 8),
		"complete eight-player roster"
	)
	rejected.join_lan("127.0.0.1", 47657, host_node.room_code)
	await pause(0.5)
	check(
		not rejected.connected_peer and host_node.connected_peers().size() == 7,
		"ninth player refused"
	)
	rejected.close()
	var snapshot := PackedByteArray()
	snapshot.resize(200000)
	snapshot.fill(42)
	host_node.send_to(first_id, {"kind": "large", "data": snapshot})
	guests[1].send_unreliable({"kind": "presence", "seq": 17})
	host_node.send_to(first_id, {"kind": "shot_start"})
	await pause(1.0)
	check(
		_count("large", "guest0") == 1 and _count("large") == 1, "large message remains addressed"
	)
	check(
		_count("presence", "host") == 1 and _count("shot_start", "guest0") == 1,
		"reliable and transient coexist"
	)
	snapshot.resize(262144)
	host_node.send_unreliable({"kind": "too_large", "data": snapshot})
	check(host_node.connected_peers().size() == 7, "oversized transient does not remove peers")
	host_node.send_to(first_id, {"kind": "too_large", "data": snapshot})
	check(host_node.connected_peers().size() == 6, "reliable packet limit isolates affected peer")
	host_node._receive_wire(guests[1].local_id(), var_to_bytes("malformed"))
	check(host_node.connected_peers().size() == 5, "malformed packet isolates one peer")
	check(host_disconnect_events == 0, "peer faults never end coordinator session")
	for code in ["invalid", "UP1-123-token", "UP2-123", "UP3-123", "UP4-123", "UP7-123", "UP8-0"]:
		check(
			rejected.join_steam(code) == ERR_INVALID_PARAMETER, "reject old or malformed room code"
		)
	host_node.close()
	for guest in guests:
		guest.close()
	check(not host_node.session_open(), "closed host exposes idle state")
	if "--steam" in OS.get_cmdline_user_args():
		await _steam_room_check()
	_finish()


func _steam_room_check() -> void:
	check(host_node.host_steam() == OK, "actual Steam room request starts")
	for _attempt in range(100):
		if host_node.invite_ready() or not host_node.is_host:
			break
		await pause(0.2)
	check(host_node.invite_ready() and host_node.room_code.begins_with("UP8-"), "Steam room ready")
	if host_node._lobby_id != 0:
		check(
			(
				host_node._steam.call("getLobbyData", host_node._lobby_id, "protocol")
				== str(host_node.PROTOCOL)
			),
			"lobby publishes the current protocol"
		)
	host_node.close()
	check(
		not host_node.invite_ready() and host_node._steam != null, "invite listener survives close"
	)


func _finish() -> void:
	host_node.close()
	for guest in guests:
		guest.close()
	print("TRANSPORT TEST COMPLETE ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)

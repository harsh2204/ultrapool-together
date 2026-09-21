extends Node

var host_node: Node
var guest_node: Node
var inbox: Array = []
var failed := false


func check(condition: bool, label: String) -> void:
	print("TRANSPORT TEST ", "PASS " if condition else "FAIL ", label)
	failed = failed or not condition


func pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	if not OS.get_user_data_dir().contains("UltrapoolTogetherTransportTest"):
		print("TRANSPORT TEST FAIL isolated save directory required")
		get_tree().quit(2)
		return
	get_node("/root/SettingsManager").set("use_analytics", false)
	get_node("/root/AnalyticsManager").set("state", 0)
	get_node("/root/PlatformManager").set("_steam", null)
	get_node("/root/CloudSaveManager").set("backend", null)
	var transport_path: String = get_script().resource_path.get_base_dir().get_base_dir().path_join(
		"mod/transport.gd"
	)
	var transport_script = load(transport_path)
	if transport_script == null or not transport_script.can_instantiate():
		print("TRANSPORT TEST FAIL script did not compile")
		get_tree().quit(1)
		return
	host_node = transport_script.new()
	guest_node = transport_script.new()
	add_child(host_node)
	add_child(guest_node)
	host_node.received.connect(func(message): inbox.append(message))
	guest_node.received.connect(func(message): inbox.append(message))
	check(host_node.host_lan(47657, "") == OK, "host opens port")
	check(host_node.room_code.length() == 32, "random 128 bit token")
	check(guest_node.join_lan("127.0.0.1", 47657, host_node.room_code) == OK, "guest starts")
	await pause(2.0)
	check(host_node.connected_peer and guest_node.connected_peer, "two-way handshake")
	check(
		guest_node.join_steam("UP3-123") == ERR_ALREADY_IN_USE,
		"another invite cannot replace an active session"
	)
	check(
		guest_node.connected_peer and guest_node.session_open(),
		"rejected invite preserves current connection"
	)
	guest_node.send({"type": "input", "position": Vector2(120, 240), "pressed": true})
	var snapshot := PackedByteArray()
	snapshot.resize(200000)
	snapshot.fill(42)
	host_node.send({"type": "snapshot", "state": snapshot})
	await pause(5.0)
	check(inbox.size() == 2, "bidirectional data and 200KB snapshot")
	if inbox.size() == 2:
		check(
			(
				inbox[0].get("position") == Vector2(120, 240)
				or inbox[1].get("position") == Vector2(120, 240)
			),
			"input content intact"
		)
	guest_node.close()
	await pause(0.5)
	check(not host_node.connected_peer and host_node.is_host, "disconnect keeps host open")
	guest_node.join_lan("127.0.0.1", 47657, "wrong-token")
	await pause(0.5)
	check(not host_node.connected_peer and not guest_node.connected_peer, "invalid token rejected")
	guest_node.close()
	guest_node.join_lan("127.0.0.1", 47657, host_node.room_code)
	await pause(0.5)
	check(host_node.connected_peer and guest_node.connected_peer, "guest can reconnect")
	guest_node._enet.set_target_peer(1)
	guest_node._enet.put_packet(var_to_bytes({"kind": "data", "data": "not a dictionary"}))
	await pause(0.2)
	check(inbox.size() == 2, "malformed data not emitted")
	guest_node._enet.put_packet(var_to_bytes("not a dictionary"))
	await pause(0.3)
	check(not host_node.connected_peer, "malformed packet disconnects")
	check(guest_node.join_steam("invalid") == ERR_INVALID_PARAMETER, "bad Steam code rejected")
	check(
		guest_node.join_steam("UP1-123-token") == ERR_INVALID_PARAMETER,
		"old protocol room rejected"
	)
	check(guest_node.join_steam("UP2-123") == ERR_INVALID_PARAMETER, "old v0.2 room rejected")
	check(guest_node.join_steam("UP3-0") == ERR_INVALID_PARAMETER, "zero lobby rejected")
	guest_node.join_lan("127.0.0.1", 47657, host_node.room_code)
	await pause(0.5)
	check(
		host_node.connected_peer and guest_node.connected_peer, "reconnect after malformed packet"
	)
	guest_node.send_unreliable({"kind": "presence", "seq": 17})
	host_node.send({"kind": "shot_start", "turn": 3})
	await pause(0.5)
	check(
		inbox.any(func(message): return message.get("seq") == 17),
		"transient channel delivers cursor updates"
	)
	check(
		inbox.any(func(message): return message.get("kind") == "shot_start"),
		"reliable actions still arrive after transient sends"
	)
	snapshot.resize(262144)
	host_node.send_unreliable({"kind": "snapshot", "state": snapshot})
	check(host_node.connected_peer, "oversized transient update does not end session")
	host_node.send({"type": "snapshot", "state": snapshot})
	check(not host_node.connected_peer, "packet limit includes wire overhead")
	host_node.close()
	guest_node.close()
	check(
		not host_node.session_open() and not guest_node.session_open(),
		"closed sessions expose idle state"
	)
	if "--steam" in OS.get_cmdline_user_args():
		var steam_error: int = host_node.host_steam()
		check(steam_error == OK, "actual Steam room request starts")
		for _attempt in range(100):
			if host_node.invite_ready() or not host_node.is_host:
				break
			await pause(0.2)
		check(
			host_node.invite_ready() and host_node.room_code.begins_with("UP3-"),
			"friends lobby becomes ready asynchronously"
		)
		var steam: Object = host_node._steam
		var lobby_id: int = host_node._lobby_id
		if lobby_id != 0:
			check(
				steam.call("getLobbyData", lobby_id, "protocol") == "3", "lobby publishes protocol"
			)
			check(
				int(steam.call("getLobbyOwner", lobby_id)) == int(steam.call("getSteamID")),
				"host owns lobby"
			)
		host_node.close()
		check(
			not host_node.invite_ready() and host_node._steam != null,
			"closing room keeps Steam invite listener"
		)
	print("TRANSPORT TEST COMPLETE ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)

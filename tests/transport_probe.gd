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
	var transport_path: String = get_script().resource_path.get_base_dir().get_base_dir().path_join("mod/transport.gd")
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
	guest_node.send({"type": "input", "position": Vector2(120, 240), "pressed": true})
	var frame := PackedByteArray()
	frame.resize(300000)
	frame.fill(42)
	host_node.send({"type": "frame", "jpg": frame})
	await pause(5.0)
	check(inbox.size() == 2, "bidirectional data and 300KB frame")
	if inbox.size() == 2:
		check(inbox[0].get("position") == Vector2(120, 240) or inbox[1].get("position") == Vector2(120, 240), "input content intact")
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
	host_node.close()
	guest_node.close()
	if "--steam" in OS.get_cmdline_user_args():
		var steam_error: int = host_node.host_steam()
		check(steam_error == OK and host_node.room_code.begins_with("UP1-"), "actual Steam host room initializes")
		host_node.close()
	print("TRANSPORT TEST COMPLETE ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)

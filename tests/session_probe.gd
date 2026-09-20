extends Node

var mod: Node
var role = "host"
var failures: Array[String] = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg == "--guest":
			role = "guest"
	_run.call_deferred()

func _run():
	if not OS.get_user_data_dir().contains("UltrapoolTogetherSessionTest"):
		get_tree().quit(2)
		return
	mod = get_node("/root/UltrapoolTogether")
	get_node("/root/SettingsManager").set("use_analytics", false)
	get_node("/root/AnalyticsManager").set("state", 0)
	get_node("/root/PlatformManager").set("_steam", null)
	get_node("/root/CloudSaveManager").set("backend", null)
	get_node("/root/TutorialManager").set("ENABLED", false)
	await get_tree().create_timer(2).timeout
	if role == "host":
		await _host()
	else:
		await _guest()
	print("SESSION_PROBE_", "PASS " if failures.is_empty() else "FAIL ", role, " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _host():
	_check(mod.transport.host_lan(24817, "session-test-password") == OK, "host starts")
	if not await _wait(func(): return mod.active, 30):
		_check(false, "guest connects")
		return
	_check(true, "guest connects")
	var global_node = get_node("/root/Global")
	var database = get_node("/root/BallDatabase")
	global_node.set("chosen_deck", database.get("id_to_deck")["1_CLASSIC"])
	global_node.set("chosen_difficulty", database.get("id_to_difficulty")["diff_1"])
	global_node.set("chosen_run_state", null)
	global_node.go_to_game()
	if not await _wait(func(): return mod.adapter.can_shoot(), 35):
		_check(false, "host table becomes ready")
		return
	_check(true, "host table becomes ready")
	mod._pass(0, mod.shot_number)
	_check(mod.turn_owner == 1, "co-op pass changes turn")
	mod._pass(1, mod.shot_number)
	_check(mod.turn_owner == 0, "co-op pass returns turn")
	mod.pvp = true
	mod._start_match()
	mod.shots = [4, 4]
	mod.scores = [10.0, 20.0]
	mod._publish_state()
	var before = mod.adapter.game_data().shots_left
	mod._take_shot(1, Vector2(200, 0), mod.shot_number)
	_check(mod.adapter.game_data().shots_left == before, "wrong player cannot shoot")
	mod._take_shot(0, Vector2(200, 0), mod.shot_number - 1)
	_check(mod.adapter.game_data().shots_left == before, "stale turn cannot shoot")
	mod._take_shot(0, Vector2(200, 0), mod.shot_number)
	_check(mod.shot_pending, "host real shot starts")
	mod._take_shot(0, Vector2(200, 0), mod.shot_number)
	_check(mod.adapter.game_data().shots_left == before - 1, "duplicate host shot rejected")
	if not await _wait(func(): return mod.finished, 90):
		_check(false, "both real shots resolve and match finishes")
		return
	_check(mod.shots == [5, 5], "PvP counts one real shot per player")
	_check(mod.adapter.game_data().shots_left == before - 2, "guest duplicate consumed no extra shot")
	_check(not mod._winner().is_empty(), "PvP publishes result")
	await _screenshot("host")
	if not await _wait(func(): return not mod.active, 15):
		_check(false, "guest disconnect reaches host")
		return
	_check(not InputMap.action_get_events(&"click").is_empty(), "disconnect restores native controls")

func _guest():
	_check(mod.transport.join_lan("127.0.0.1", 24817, "session-test-password") == OK, "guest connects to loopback")
	if not await _wait(func(): return mod.active, 30):
		_check(false, "guest handshake")
		return
	_check(get_tree().paused, "guest local simulation is paused")
	if not await _wait(func(): return mod.pvp and mod.turn_owner == 1 and not mod.shot_pending and mod.latest_state.get("can_shoot", false), 80):
		_check(false, "host shot hands turn to guest")
		return
	_check(true, "host shot hands turn to guest")
	mod.angle.value = 150
	mod.power.value = 85
	mod._request_shot()
	mod._request_shot()
	if not await _wait(func(): return mod.finished, 60):
		_check(false, "guest shot resolves to match result")
		return
	_check(mod.shots == [5, 5], "guest receives final scoreboard")
	if DisplayServer.get_name() != "headless":
		_check(mod.last_guest_frame >= 2 and mod.remote_view.texture != null, "host video decoded and acknowledged")
	await _screenshot("guest")
	await get_tree().create_timer(2).timeout
	mod.transport.close()
	mod._disconnected("Integration test disconnect")
	_check(not get_tree().paused, "disconnect resumes guest local game")

func _wait(condition: Callable, seconds: float) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		if role == "host":
			var ui = get_node("/root/UIManager")
			ui.get("popup_queue").clear()
			for popup in ui.get("active_popups").duplicate():
				popup.close_menu()
			var tutorial = get_node("/root/TutorialManager")
			if tutorial.get("active_popup") != null:
				tutorial.close_popup()
			get_tree().paused = false
		await get_tree().process_frame
	return condition.call()

func _screenshot(label: String):
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path = get_script().resource_path.get_base_dir().get_base_dir().path_join(".local/" + label + "-session.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("SESSION_SCREENSHOT ", path)

func _check(condition: bool, description: String):
	print("SESSION_CHECK ", "PASS " if condition else "FAIL ", role, " ", description)
	if not condition:
		failures.append(description)

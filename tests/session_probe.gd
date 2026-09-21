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
	mod.ui_root.hide()
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
	var player = global_node.gameManager.player_ball
	var native_script = load("res://player_ball.gd")
	var bindings_before = _bindings()
	var before: int = mod.adapter.game_data().shots_left
	_check(player.has_method("together_play_shot"), "host cue uses native turn hook")
	_check(mod.can_control(), "host can aim on own turn")
	mod.panel.show()
	player.shoot(Vector2(200, 0))
	_check(
		not mod.shot_pending and mod.adapter.game_data().shots_left == before,
		"multiplayer panel blocks native shooting"
	)
	mod.panel.hide()
	mod._request_pass()
	_check(mod.turn_owner == 1, "co-op pass changes turn")
	_check(not mod.can_control(), "host cannot aim on partner turn")
	player.shoot(Vector2(200, 0))
	_check(
		not mod.shot_pending and mod.adapter.game_data().shots_left == before,
		"off-turn native host shot is rejected"
	)
	mod._pass(1, mod.shot_number)
	_check(mod.turn_owner == 0, "co-op pass returns turn")
	_check(mod.can_control(), "native host controls resume on own turn")
	mod.pvp = true
	mod._start_match()
	mod.shots = [4, 4]
	mod.scores = [10.0, 20.0]
	mod._publish_state()
	mod._take_shot(1, Vector2(200, 0), mod.shot_number)
	_check(mod.adapter.game_data().shots_left == before, "wrong player cannot shoot")
	mod._take_shot(0, Vector2(200, 0), mod.shot_number - 1)
	_check(mod.adapter.game_data().shots_left == before, "stale turn cannot shoot")
	player.shoot(Vector2(200, 0))
	_check(mod.shot_pending, "native host shot starts authoritative physics")
	_check(not mod.can_control(), "in-flight shot disables native aiming")
	player.shoot(Vector2(200, 0))
	mod._take_shot(0, Vector2(200, 0), mod.shot_number)
	_check(mod.adapter.game_data().shots_left == before - 1, "duplicate host shot rejected")
	if not await _wait(func(): return mod.finished, 90):
		_check(false, "both real shots resolve and match finishes")
		return
	_check(mod.shots == [5, 5], "PvP counts one real shot per player")
	_check(
		mod.adapter.game_data().shots_left == before - 2, "guest duplicate consumed no extra shot"
	)
	_check(not mod._winner().is_empty(), "PvP publishes result")
	_check(not mod.can_control(), "match result disables native aiming")
	if not await _wait(func(): return not mod.active, 15):
		_check(false, "guest disconnect reaches host")
		return
	_check(player.get_script() == native_script, "disconnect restores original player script")
	_check(
		_bindings() == bindings_before, "native input bindings stay unchanged throughout session"
	)


func _guest():
	var original_scene = get_tree().current_scene
	var original_mode = original_scene.process_mode
	var original_visibility = original_scene.visible
	var global_node = get_node("/root/Global")
	var original_game = global_node.gameManager
	var original_camera = global_node.camera
	var bindings_before = _bindings()
	_check(
		mod.transport.join_lan("127.0.0.1", 24817, "session-test-password") == OK,
		"guest connects to loopback"
	)
	if not await _wait(func(): return mod.active, 30):
		_check(false, "guest handshake")
		return
	_check(
		get_tree().current_scene == original_scene and original_scene.is_inside_tree(),
		"guest preserves original menu instance"
	)
	_check(
		original_scene.process_mode == Node.PROCESS_MODE_DISABLED and not original_scene.visible,
		"guest suspends original menu while connected"
	)
	if not await _wait(func(): return mod.pvp and mod.turn_owner == 1 and mod.can_control(), 80):
		_check(false, "host shot hands turn to guest")
		return
	_check(true, "host shot hands turn to guest")
	_check(mod.table_sync.ready_for_input(), "guest replica is ready for native aiming")
	var replica = global_node.gameManager
	var player = replica.player_ball
	_check(player.has_method("together_play_shot"), "guest cue uses native turn hook")
	var frozen = true
	for body in replica.replicas.values():
		frozen = (
			frozen
			and body.freeze
			and not body.is_physics_processing()
			and body.collision_layer == 0
			and body.collision_mask == 0
		)
	_check(frozen, "replicated balls cannot run local authoritative physics")
	var shots_before: int = replica.get_shots_left()
	var velocity_before: Vector2 = player.linear_velocity
	var turn_before: int = mod.shot_number
	player.shoot(Vector2(-150, 85))
	_check(
		mod.awaiting_shot_turn == turn_before, "native guest shot waits for host acknowledgement"
	)
	_check(not mod.can_control(), "guest cannot aim while submission is pending")
	player.shoot(Vector2(-150, 85))
	_check(
		mod.awaiting_shot_turn == turn_before and replica.get_shots_left() == shots_before,
		"duplicate native guest input does not spend a local shot"
	)
	_check(player.linear_velocity == velocity_before, "guest shot intent applies no local impulse")
	if not await _wait(func(): return mod.finished, 60):
		_check(false, "guest shot resolves to match result")
		return
	_check(mod.shots == [5, 5], "guest receives final scoreboard")
	_check(mod.last_guest_snapshot > 1, "guest applies and acknowledges successive table snapshots")
	_check(not mod.can_control(), "guest cannot shoot after match result")
	await get_tree().create_timer(2).timeout
	mod.transport.close()
	mod._disconnected("Integration test disconnect")
	_check(
		get_tree().current_scene == original_scene and original_scene.is_inside_tree(),
		"disconnect retains original menu instance"
	)
	_check(
		(
			original_scene.process_mode == original_mode
			and original_scene.visible == original_visibility
		),
		"disconnect restores original menu processing and visibility"
	)
	_check(
		global_node.gameManager == original_game and global_node.camera == original_camera,
		"disconnect restores original game and camera references"
	)
	_check(not is_instance_valid(replica), "disconnect removes replica")
	_check(_bindings() == bindings_before, "guest native input bindings stay unchanged")


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


func _bindings() -> Dictionary:
	var result = {}
	for action in [&"click", &"shoot", &"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		var events: Array[String] = []
		for event in InputMap.action_get_events(action):
			events.append(event.as_text())
		result[String(action)] = events
	return result


func _check(condition: bool, description: String):
	print("SESSION_CHECK ", "PASS " if condition else "FAIL ", role, " ", description)
	if not condition:
		failures.append(description)

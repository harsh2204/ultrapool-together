extends Node

var mod: Node
var role = "host"
var failures: Array[String] = []
var reports: Dictionary = {}


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
	get_node("/root/SettingsManager").use_analytics = false
	get_node("/root/AnalyticsManager").state = 0
	get_node("/root/PlatformManager")._steam = null
	get_node("/root/CloudSaveManager").backend = null
	get_node("/root/TutorialManager").ENABLED = false
	mod.transport.received.connect(_received)
	await get_tree().create_timer(2).timeout
	var menu = get_node("/root/UIManager").decks_menu
	var database = get_node("/root/BallDatabase")
	menu.index_deck = menu.decks.find(database.id_to_deck["1_CLASSIC"])
	menu.index_diff = menu.difficulties.find(database.id_to_difficulty["diff_1"])
	_check(menu.index_deck >= 0 and menu.index_diff >= 0, "classic test run is available")
	if not failures.is_empty():
		_finish()
		return
	var bindings_before = _bindings()
	if role == "host":
		await _host()
	else:
		await _guest()
	_check(_bindings() == bindings_before, "native mouse and controller bindings stay unchanged")
	_finish()


func _host():
	_check(mod.transport.host_lan(24817, "session-test-password") == OK, "host opens a lobby")
	if not await _wait(func(): return _room().get("players", []).size() == 2, 30):
		_check(false, "guest appears in the lobby")
		return
	_check(not mod.active, "joining does not start a match")
	_check(mod.panel.get_node("%Start").disabled, "start is disabled before everyone readies")
	mod.panel.start_requested.emit()
	_check(not mod.active, "premature start request is rejected")
	if not await _wait(func(): return _other_player().get("ready", false), 15):
		_check(false, "guest chooses a seat and readies up")
		return
	mod.panel.ready_requested.emit(true)
	if not await _wait(func(): return _room().get("can_start", false), 10):
		_check(false, "both seated players unlock start")
		return
	mod.panel.start_requested.emit()
	if not await _wait(func(): return mod.active and mod.can_control(), 40):
		_check(false, "co-op starts the host's native table")
		return
	_check(mod.is_table_host(), "room host leads the co-op table")
	var game = get_node("/root/Global").gameManager
	var player = game.player_ball
	var before: int = game.get_shots_left()
	_check(player.has_method("together_play_shot"), "native cue uses the multiplayer turn hook")
	mod._set_panel(true)
	player.shoot(Vector2(200, 0))
	_check(not mod.shot_pending and game.get_shots_left() == before, "lobby screen blocks aiming")
	mod._set_panel(false)
	player.shoot(Vector2(200, 0))
	_check(mod.shot_pending, "host native shot starts local physics")
	player.shoot(Vector2(200, 0))
	_check(game.get_shots_left() == before - 1, "duplicate host input cannot spend another shot")
	if not await _wait(func(): return mod.shot_number >= 2 and not mod.shot_pending, 100):
		_check(false, "both co-op shots resolve")
		return
	_check(game.get_shots_left() == before - 2, "both players consume exactly one native shot")
	_check(not mod.finished, "co-op is not limited by the competitive shot budget")
	mod.panel.return_requested.emit()
	_check(
		mod.active and _room().return_vote.active,
		"host must wait for teammate consent before ending co-op"
	)
	if not await _wait(func(): return not mod.active and _at_menu(), 20):
		_check(false, "return to lobby ends the first run")
		return
	mod.panel.table_count_requested.emit(2)
	mod.panel.run_vote_requested.emit("match_mode", "score", _room().run_vote.catalog_revision)
	mod.panel.shot_budget_requested.emit(1)
	if not await _wait(
		func():
			return _other_player().get("table", -1) == 1 and _other_player().get("ready", false),
		20
	):
		_check(false, "guest chooses a separate table")
		return
	mod.panel.ready_requested.emit(true)
	if not await _wait(func(): return _room().get("can_start", false), 10):
		_check(false, "separate-table lobby is ready")
		return
	mod.panel.start_requested.emit()
	if not await _competition():
		return
	mod.panel.return_requested.emit()
	if not await _wait(func(): return not mod.active and _at_menu(), 20):
		_check(false, "competition returns to lobby")
		return
	if not await _wait(func(): return _room().get("players", []).size() == 1, 20):
		_check(false, "guest leaves without closing the room")
		return
	_check(mod.transport.session_open(), "host room remains available after a guest leaves")
	mod.panel.leave_requested.emit()


func _guest():
	var original_scene = get_tree().current_scene
	var original_mode = original_scene.process_mode
	var original_visibility = original_scene.visible
	_check(
		mod.transport.join_lan("127.0.0.1", 24817, "session-test-password") == OK,
		"guest joins loopback"
	)
	if not await _wait(func(): return not _local_player().is_empty(), 30):
		_check(false, "guest receives the lobby roster")
		return
	_check(
		not mod.active and get_tree().current_scene == original_scene,
		"joining preserves the main menu"
	)
	_check(_local_player().table == -1, "joining starts on the unassigned bench")
	mod.panel.ready_requested.emit(true)
	await get_tree().create_timer(0.3).timeout
	_check(not _local_player().ready, "unseated player cannot ready up")
	mod.panel.slot_requested.emit(0, 1)
	mod.panel.ready_requested.emit(true)
	if not await _wait(func(): return mod.active and mod.can_control(), 90):
		_check(false, "host shot hands the co-op turn to the guest")
		return
	_check(not mod.is_table_host(), "same-table guest uses a replica")
	_check(
		original_scene.process_mode == Node.PROCESS_MODE_DISABLED and not original_scene.visible,
		"started match suspends the guest menu"
	)
	var replica = get_node("/root/Global").gameManager
	var player = replica.player_ball
	_check(mod.table_sync.ready_for_input(), "guest table is ready for native aiming")
	for body in replica.replicas.values():
		_check(
			body.get_meta("together_replica", false),
			"replica suppresses authoritative collision effects"
		)
		_check(
			body.ball.material.get_shader_parameter("tex") == body.ball_item.data.texture,
			"guest sees the native ball type texture"
		)
	var inspection = get_node("/root/UIManager").info_display
	_check(
		inspection.can_process() and inspection.is_visible_in_tree(),
		"guest native ball inspection is enabled"
	)
	var before: int = replica.get_shots_left()
	var velocity: Vector2 = player.linear_velocity
	var turn: int = mod.shot_number
	player.shoot(Vector2(-150, 85))
	_check(mod.awaiting_shot_turn == turn, "guest shot waits for host acceptance")
	player.shoot(Vector2(-150, 85))
	_check(
		replica.get_shots_left() == before and player.linear_velocity == velocity,
		"duplicate pending input does not launch a local shot"
	)
	if not await _wait(func(): return mod.last_started_turn == turn, 10):
		_check(false, "confirmed shot starts guest simulation")
		return
	var position: Vector2 = player.global_position
	mod.transport.set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	mod.transport.set_process(true)
	_check(
		player.global_position.distance_to(position) > 0.1,
		"guest ball moves between network updates"
	)
	if not await _wait(func(): return _room().get("return_vote", {}).get("active", false), 90):
		_check(false, "host proposes returning from co-op")
		return
	_check(mod.active, "return proposal keeps the guest run active until consent")
	mod.panel.return_vote_requested.emit(true)
	if not await _wait(func(): return not mod.active and _at_menu(), 90):
		_check(false, "guest returns from co-op to the lobby")
		return
	mod._set_panel(false)
	_check(
		(
			is_instance_valid(original_scene)
			and original_scene.process_mode == original_mode
			and original_scene.visible == original_visibility
		),
		"closing the returned lobby restores the guest's original menu"
	)
	mod._set_panel(true)
	if not await _wait(
		func():
			return (
				_room().get("table_count", 0) == 2
				and _room().get("match_mode") == "score"
				and _room().get("shot_budget", 0) == 1
			),
		20
	):
		_check(false, "guest receives competitive table settings")
		return
	mod.panel.slot_requested.emit(1, 0)
	mod.panel.ready_requested.emit(true)
	if not await _competition():
		return
	if not await _wait(func(): return not mod.active and _at_menu(), 30):
		_check(false, "separate table returns to the main menu")
		return
	mod.panel.leave_requested.emit()
	_check(not mod.transport.session_open(), "guest leaves the local test room")


func _competition() -> bool:
	if not await _wait(func(): return mod.active and mod.can_control(), 45):
		_check(false, "competitive native table becomes ready")
		return false
	var global_node = get_node("/root/Global")
	var game = global_node.gameManager
	_check(
		mod.is_table_host() and not game.has_method("apply_table"),
		"each separate table runs native gameplay"
	)
	game.player_info.money += 17 if role == "host" else 29
	var own_money = game.player_info.money
	var report = {
		"kind": "session_probe",
		"phase": "competition_started",
		"seed": global_node.seed,
		"deck": str(global_node.chosen_deck.id),
		"difficulty": str(global_node.chosen_difficulty.id),
		"cue": game.player_ball.global_position
	}
	mod.transport.send(report)
	if not await _wait(func(): return reports.has("competition_started"), 15):
		_check(false, "both native tables start")
		return false
	var other: Dictionary = reports.competition_started
	_check(
		(
			other.seed == report.seed
			and other.deck == report.deck
			and other.difficulty == report.difficulty
		),
		"tables receive the same seed, deck, and difficulty"
	)
	_check(other.cue.distance_to(report.cue) < 0.01, "native cue placement matches across tables")
	await get_tree().create_timer(0.3).timeout
	_check(game.player_info.money == own_money, "other table cannot overwrite this table's wallet")
	var before: int = game.get_shots_left()
	game.player_ball.shoot(Vector2(200, 0))
	_check(
		mod.shot_pending and game.get_shots_left() == before - 1,
		"table host consumes one native shot"
	)
	if not await _wait(func(): return mod.finished, 75):
		_check(false, "one-shot table reaches its competitive result")
		return false
	_check(not mod.can_control(), "finished table disables aiming")
	game.player_ball.shoot(Vector2(200, 0))
	_check(game.get_shots_left() == before - 1, "finished table cannot spend another shot")
	mod.transport.send({"kind": "session_probe", "phase": "competition_finished"})
	if not await _wait(func(): return reports.has("competition_finished"), 90):
		_check(false, "other table finishes independently")
		return false
	if not await _wait(_scoreboard_complete, 15):
		_check(false, "room scoreboard includes both finished tables")
		return false
	mod.transport.send({"kind": "session_probe", "phase": "scoreboard_seen"})
	if not await _wait(func(): return reports.has("scoreboard_seen"), 15):
		_check(false, "both players receive the final table scoreboard")
		return false
	return true


func _scoreboard_complete() -> bool:
	var summaries: Array = _room().get("table_summaries", [])
	return (
		summaries.size() == 2
		and summaries.all(func(summary): return summary.finished and summary.shots_used == 1)
	)


func _received(_sender: int, message: Dictionary):
	if message.get("kind") == "session_probe" and message.get("phase") is String:
		reports[message.phase] = message


func _room() -> Dictionary:
	return mod.panel._state


func _local_player() -> Dictionary:
	for player in _room().get("players", []):
		if player.id == mod.transport.local_id():
			return player
	return {}


func _other_player() -> Dictionary:
	for player in _room().get("players", []):
		if player.id != mod.transport.local_id():
			return player
	return {}


func _at_menu() -> bool:
	var global_node = get_node("/root/Global")
	var scene = get_tree().current_scene
	return (
		not global_node.transitioning
		and not global_node.in_run
		and scene != null
		and scene.scene_file_path == global_node.SCENE_MENU.resource_path
	)


func _wait(condition: Callable, seconds: float) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		var ui = get_node("/root/UIManager")
		ui.popup_queue.clear()
		for popup in ui.active_popups.duplicate():
			popup.close_menu()
		var tutorial = get_node("/root/TutorialManager")
		if tutorial.active_popup != null:
			tutorial.cancel()
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


func _finish():
	print("SESSION_PROBE_", "PASS " if failures.is_empty() else "FAIL ", role, " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

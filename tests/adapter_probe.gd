extends Node

var _failures: Array[String] = []
var _adapter: Node
var _allow_control = false
var _submitted_shots: Array[Vector2] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("ADAPTER_PROBE_START save_dir=", OS.get_user_data_dir())
	if not _check(
		OS.get_user_data_dir().contains("UltrapoolTogetherAdapterTest"), "isolated save directory"
	):
		_finish()
		return
	var global_node = get_node("/root/Global")
	var tutorial = get_node("/root/TutorialManager")
	var ui = get_node("/root/UIManager")
	var database = get_node("/root/BallDatabase")
	get_node("/root/SettingsManager").set("use_analytics", false)
	get_node("/root/AnalyticsManager").set("state", 0)
	get_node("/root/PlatformManager").set("_steam", null)
	get_node("/root/CloudSaveManager").set("backend", null)
	tutorial.set("ENABLED", false)
	await get_tree().process_frame
	_close_popups(ui, tutorial)
	var adapter_path: String = get_script().resource_path.get_base_dir().get_base_dir().path_join(
		"mod/game_adapter.gd"
	)
	var adapter_script = load(adapter_path)
	if not _check(adapter_script != null, "adapter script loads"):
		_finish()
		return
	var adapter = adapter_script.new()
	_adapter = adapter
	add_child(adapter)
	_check(not adapter.shoot(Vector2(200, 0)), "shot rejected without session")
	var bindings_before = _bindings()
	var difficulties: Dictionary = database.get("id_to_difficulty")
	print("ADAPTER_DIFFICULTIES ", difficulties.keys())
	var difficulty = null
	for candidate in difficulties.values():
		if not candidate.get("can_be_chosen"):
			continue
		if (
			difficulty == null
			or (
				int(candidate.get("scoreRequirementModifier"))
				< int(difficulty.get("scoreRequirementModifier"))
			)
		):
			difficulty = candidate
	if not _check(difficulty != null, "playable difficulty available"):
		_finish()
		return
	print("ADAPTER_DIFFICULTY_SELECTED ", difficulty.get("id"))
	global_node.set("chosen_deck", database.get("id_to_deck")["1_CLASSIC"])
	global_node.set("chosen_difficulty", difficulty)
	global_node.set("chosen_run_state", null)
	global_node.go_to_game()
	adapter.begin_session(self)
	var ready_deadline = Time.get_ticks_msec() + 30000
	while not adapter.can_shoot() and Time.get_ticks_msec() < ready_deadline:
		_close_popups(ui, tutorial)
		await get_tree().process_frame
	print("ADAPTER_READY_STATE ", JSON.stringify(adapter.game_data()))
	if not _check(adapter.can_shoot(), "table reaches ready state within 30 seconds"):
		adapter.end_session()
		_finish()
		return
	_check(_bindings() == bindings_before, "native mouse and controller bindings remain intact")
	var player = global_node.get("gameManager").get("player_ball")
	_check(player.has_method("together_play_shot"), "new cue ball receives native input hook")
	adapter.end_session()
	var original_script = player.get_script()
	var prediction = player.get("prediction")
	var shoot_ui = player.get("shoot_ui")
	var ball_item = player.get("ball_item")
	adapter.begin_session(self)
	_check(player is PlayerBall, "native hook preserves player type")
	_check(
		player.get("prediction") == prediction and player.get("shoot_ui") == shoot_ui,
		"native aiming onready references survive hook"
	)
	_check(player.get("ball_item") == ball_item, "inherited ball state survives hook")
	player.set("holding_shot", true)
	player.set("preparing_shot", true)
	await get_tree().create_timer(0.05, true).timeout
	_check(
		not player.get("holding_shot") and not player.get("preparing_shot"),
		"off-turn frame cancels native aiming"
	)
	player.set("holding_shot", true)
	player.set("preparing_shot", true)
	get_tree().paused = true
	await get_tree().create_timer(0.05, true).timeout
	_check(
		not player.get("holding_shot") and not player.get("preparing_shot"),
		"paused table cancels native aiming"
	)
	get_tree().paused = false
	var native_shots_before: int = adapter.game_data().shots_left
	player.shoot(Vector2(200, 0))
	player.set("precise_mode", true)
	player.set("shot", Vector2(200, 0))
	player._on_shoot_button_pressed()
	_check(_submitted_shots.is_empty(), "off-turn drag and precise confirmation cannot submit")
	_check(
		adapter.game_data().shots_left == native_shots_before, "off-turn attempts spend no shots"
	)
	await get_tree().create_timer(0.7, true).timeout
	_allow_control = true
	player.shoot(Vector2(180, 0))
	_check(_submitted_shots == [Vector2(180, 0)], "native shot routes to session controller")
	_check(
		adapter.game_data().shots_left == native_shots_before,
		"submitted intent does not run local physics"
	)
	_allow_control = false
	_check(not adapter.shoot(Vector2.ZERO), "zero shot rejected")
	_check(not adapter.shoot(Vector2(50, 0)), "minimum threshold rejected")
	_check(not adapter.shoot(Vector2(NAN, 0)), "NaN shot rejected")
	_check(not adapter.shoot(Vector2(INF, 0)), "infinite shot rejected")
	var shots_before: int = adapter.game_data().shots_left
	_check(adapter.shoot(Vector2(200, 0)), "real shot accepted")
	_check(
		adapter.game_data().shots_left == shots_before - 1, "real shot consumes exactly one shot"
	)
	_check(not adapter.can_shoot(), "shot blocks further shots while moving")
	_check(not adapter.shoot(Vector2(200, 0)), "duplicate in-flight shot rejected")
	var settled_deadline = Time.get_ticks_msec() + 60000
	while not adapter.is_settled() and Time.get_ticks_msec() < settled_deadline:
		_close_popups(ui, tutorial)
		await get_tree().process_frame
	print("ADAPTER_SETTLED_STATE ", JSON.stringify(adapter.game_data()))
	_check(adapter.is_settled(), "real shot settles within 60 seconds")
	_check(adapter.can_shoot(), "next shot becomes available after settling")
	_check(adapter.shot_score() == adapter.score(), "active shot score uses live score")
	var game = global_node.get("gameManager")
	var completed_score: int = game.get_required_score() + 10
	game.set_score(completed_score)
	game.force_round_end()
	_check(game.get("round_end_stuff_happened"), "round completion snapshots score before flag")
	_check(adapter.score() < completed_score, "round cash-out reduces live score")
	_check(adapter.shot_score() == completed_score, "round cash-out preserves shot credit")
	var popup_deadline = Time.get_ticks_msec() + 15000
	while not get_tree().paused and Time.get_ticks_msec() < popup_deadline:
		await get_tree().process_frame
	_check(get_tree().paused and ui.is_popup_open(), "real round-over popup pauses game")
	adapter.begin_session(self)
	await get_tree().create_timer(0.9, true).timeout
	_check(adapter.is_settled(), "completed shot settles while round popup is paused")
	_check(adapter.shot_score() == completed_score, "completed shot credit survives paused popup")
	_check(not adapter.can_shoot(), "round popup keeps shooting disabled")
	adapter.end_session()
	_check(player.get_script() == original_script, "original player script restored")
	_check(
		player.get("prediction") == prediction and player.get("shoot_ui") == shoot_ui,
		"native aiming references survive restoration"
	)
	_check(_bindings() == bindings_before, "all native shot bindings remain unchanged")
	_check(not adapter.can_shoot(), "session end disables mod shooting")
	_check(not adapter.shoot(Vector2(200, 0)), "shot rejected after session end")
	_finish()


func can_control() -> bool:
	return _allow_control and _adapter.can_shoot()


func submit_shot(vector: Vector2) -> bool:
	_submitted_shots.append(vector)
	return true


func _close_popups(ui, tutorial) -> void:
	ui.get("popup_queue").clear()
	for popup in ui.get("active_popups").duplicate():
		popup.close_menu()
	if tutorial.get("active_popup") != null:
		tutorial.close_popup()
	get_tree().paused = false


func _bindings() -> Dictionary:
	var result = {}
	for action in [&"click", &"shoot", &"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		var events: Array[String] = []
		for event in InputMap.action_get_events(action):
			events.append(event.as_text())
		result[String(action)] = events
	return result


func _check(condition: bool, label: String) -> bool:
	print("ADAPTER_CHECK ", "PASS " if condition else "FAIL ", label)
	if not condition:
		_failures.append(label)
	return condition


func _finish() -> void:
	if _failures.is_empty():
		print("ADAPTER_PROBE_PASS")
	else:
		print("ADAPTER_PROBE_FAIL ", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)

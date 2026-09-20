extends Node

const SHOT_ACTIONS = [&"click", &"shoot", &"aim_left", &"aim_right", &"aim_up", &"aim_down"]
const SETTLE_TIME = 0.6
const MIN_SHOT_LENGTH = 50.0
const MAX_SHOT_LENGTH = 200.0

var _session_active = false
var _saved_bindings: Dictionary = {}
var _input_blocked = false
var _settled_seconds = 0.0
var _last_game_id = 0
var _last_player_id = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000


func begin_session() -> void:
	_session_active = true
	_settled_seconds = 0.0
	_update_input_gate()


func end_session() -> void:
	_session_active = false
	_restore_bindings()
	_settled_seconds = 0.0


func _exit_tree() -> void:
	_restore_bindings()


func _process(delta: float) -> void:
	_update_input_gate()
	var game = _game()
	var game_id: int = game.get_instance_id() if game != null else 0
	if game_id != _last_game_id:
		_last_game_id = game_id
		_settled_seconds = 0.0
	if _raw_settled(game):
		_settled_seconds += delta
	else:
		_settled_seconds = 0.0


func can_shoot() -> bool:
	var game = _game()
	if not _session_active or not _table_active(game) or not is_settled():
		return false
	var player = game.get("player_ball")
	return is_instance_valid(player) and bool(player.get("spawned")) \
		and not bool(player.get("falling")) and game.has_shots() and game.can_shoot()


func shoot(vector: Vector2) -> bool:
	if not vector.is_finite() or vector.length() <= MIN_SHOT_LENGTH or not can_shoot():
		return false
	var player = _game().get("player_ball")
	player.pause_cancel_shot()
	_settled_seconds = 0.0
	player.shoot(vector.limit_length(MAX_SHOT_LENGTH))
	return true


func is_settled() -> bool:
	return _settled_seconds >= SETTLE_TIME and _raw_settled(_game())


func score() -> float:
	var game = _game()
	return float(game.get("score")) if game != null else 0.0


func shot_score() -> float:
	var game = _game()
	if game == null:
		return 0.0
	if game.get("round_ended") and game.get("round_end_stuff_happened"):
		return float(game.get("score_this_round"))
	return float(game.get("score"))


func game_data() -> Dictionary:
	var viewport_size = get_viewport().get_visible_rect().size
	var data = {
		"available": false,
		"table_active": false,
		"can_shoot": false,
		"settled": is_settled(),
		"in_shop": false,
		"in_menu": true,
		"game_over": false,
		"round_ended": false,
		"round_finalized": false,
		"round": 0,
		"rounds_played": 0,
		"shots_left": 0,
		"score": 0.0,
		"cue_screen": [0.0, 0.0],
		"viewport_size": [viewport_size.x, viewport_size.y],
		"aim_scale": [1.0, 1.0],
	}
	var game = _game()
	if game == null:
		return data
	data.available = true
	data.table_active = _table_active(game)
	data.can_shoot = can_shoot()
	data.in_shop = bool(game.get("in_shop"))
	data.in_menu = bool(game.get("in_menu"))
	data.game_over = bool(game.get("game_ended"))
	data.round_ended = bool(game.get("round_ended"))
	data.round_finalized = data.round_ended and bool(game.get("round_end_stuff_happened"))
	data.round = int(game.get("level_number")) + 1
	data.rounds_played = int(game.get("rounds_played"))
	data.shots_left = game.get_shots_left()
	data.score = score()
	var player = game.get("player_ball")
	if is_instance_valid(player):
		var screen_position: Vector2 = player.get_global_transform_with_canvas().origin
		data.cue_screen = [screen_position.x, screen_position.y]
		var inverse_canvas: Transform2D = player.get_canvas_transform().affine_inverse()
		data.aim_scale = [inverse_canvas.x.length(), inverse_canvas.y.length()]
	return data


func _game():
	var global_node = get_node_or_null("/root/Global")
	if global_node == null:
		return null
	var game = global_node.get("gameManager")
	if not is_instance_valid(game) or not game.is_inside_tree():
		return null
	return game


func _table_active(game) -> bool:
	if game == null or get_tree().paused:
		return false
	if game.get("in_shop") or game.get("in_menu") or game.get("game_ended") \
		or game.get("round_ended") or not game.get("balls_spawned"):
		return false
	var global_node = get_node("/root/Global")
	if global_node.get("transitioning"):
		return false
	var tutorial = get_node_or_null("/root/TutorialManager")
	if tutorial != null and not tutorial.is_free():
		return false
	var ui = get_node_or_null("/root/UIManager")
	return ui == null or not ui.is_popup_open()


func _raw_settled(game) -> bool:
	if game == null:
		return false
	if game.get("round_ended") and game.get("round_end_stuff_happened"):
		return true
	if get_tree().paused:
		return false
	if game.get("in_shop") or game.get("game_ended"):
		return true
	if not game.get("balls_spawned") or game.get("balls_moving"):
		return false
	var player = game.get("player_ball")
	if is_instance_valid(player) and player.is_moving():
		return false
	var global_node = get_node("/root/Global")
	if global_node.has_active_wisp():
		return false
	var events = global_node.get("eventManager")
	return not is_instance_valid(events) or not bool(events.get("_queue_busy"))


func _update_input_gate() -> void:
	var game = _game()
	if not _session_active or not _table_active(game):
		_restore_bindings()
		return
	var player = game.get("player_ball")
	var player_id: int = player.get_instance_id() if is_instance_valid(player) else 0
	if not _input_blocked or player_id != _last_player_id:
		if is_instance_valid(player):
			player.pause_cancel_shot()
		_last_player_id = player_id
	if _input_blocked:
		return
	for action in SHOT_ACTIONS:
		if InputMap.has_action(action):
			_saved_bindings[action] = InputMap.action_get_events(action)
			Input.action_release(action)
			InputMap.action_erase_events(action)
	_input_blocked = true


func _restore_bindings() -> void:
	if not _input_blocked:
		return
	for action in _saved_bindings:
		Input.action_release(action)
		InputMap.action_erase_events(action)
		for event in _saved_bindings[action]:
			InputMap.action_add_event(action, event)
	_saved_bindings.clear()
	_input_blocked = false
	_last_player_id = 0

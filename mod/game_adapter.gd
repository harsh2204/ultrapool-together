extends Node

const SETTLE_TIME = 0.6
const MIN_SHOT_LENGTH = 50.0
const MAX_SHOT_LENGTH = 200.0

var _session_active = false
var _controller: Node
var _native_player_script: Script
var _hooked_player: Node
var _original_player_script: Script
var _settled_seconds = 0.0
var _last_game_id = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	get_tree().node_added.connect(_node_added)


func begin_session(controller: Node) -> void:
	_controller = controller
	if _native_player_script == null:
		_native_player_script = load(
			get_script().resource_path.get_base_dir().path_join("native_player.gd")
		)
	_session_active = true
	_settled_seconds = 0.0
	_update_player_hook()


func end_session() -> void:
	_session_active = false
	_restore_player()
	_controller = null
	_settled_seconds = 0.0


func _exit_tree() -> void:
	_restore_player()


func _process(delta: float) -> void:
	_update_player_hook()
	if is_instance_valid(_hooked_player) and not _controller.can_control():
		_hooked_player.pause_cancel_shot()
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
	return (
		is_instance_valid(player)
		and bool(player.get("spawned"))
		and not bool(player.get("falling"))
		and game.has_shots()
		and game.can_shoot()
	)


func shoot(vector: Vector2) -> bool:
	if not vector.is_finite() or vector.length() <= MIN_SHOT_LENGTH or not can_shoot():
		return false
	var player = _game().get("player_ball")
	_update_player_hook()
	player.pause_cancel_shot()
	_settled_seconds = 0.0
	player.together_play_shot(vector.limit_length(MAX_SHOT_LENGTH))
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
	var data = {
		"available": false,
		"table_active": false,
		"can_shoot": false,
		"settled": is_settled(),
		"in_shop": false,
		"in_menu": true,
		"game_over": false,
		"round_result_open": false,
		"run_won": false,
		"run_goal_rounds": 0,
		"round_ended": false,
		"round_finalized": false,
		"round": 0,
		"rounds_played": 0,
		"shots_left": 0,
		"score": 0.0,
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
	data.round_result_open = get_node("/root/UIManager").round_over_menu.is_open
	data.run_won = is_run_won(game)
	data.run_goal_rounds = int(game.get_target_round())
	data.round_ended = bool(game.get("round_ended"))
	data.round_finalized = data.round_ended and bool(game.get("round_end_stuff_happened"))
	data.round = int(game.get("level_number")) + 1
	data.rounds_played = int(game.get("rounds_played"))
	data.shots_left = game.get_shots_left()
	data.score = score()
	return data


static func is_run_won(game) -> bool:
	return (
		bool(game.get("game_ended"))
		and bool(game.get("round_won"))
		and not bool(game.get("round_game_over"))
		and int(game.get("level_number")) == int(game.get_target_round()) - 1
	)


func _game():
	var global_node = get_node_or_null("/root/Global")
	if global_node == null:
		return null
	var game = global_node.get("gameManager")
	if not is_instance_valid(game) or not game.is_inside_tree() or not game.is_node_ready():
		return null
	return game


func _table_active(game) -> bool:
	if game == null or get_tree().paused:
		return false
	if (
		game.get("in_shop")
		or game.get("in_menu")
		or game.get("game_ended")
		or game.get("round_ended")
		or not game.get("balls_spawned")
	):
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


func _update_player_hook() -> void:
	if not _session_active:
		return
	var game = _game()
	var player = game.get("player_ball") if game != null else null
	if is_instance_valid(_hooked_player) and _hooked_player == player:
		_hooked_player.set("together_controller", _controller)
		return
	_restore_player()
	if not is_instance_valid(player):
		return
	player.pause_cancel_shot()
	_original_player_script = player.get_script()
	_replace_script(player, _native_player_script)
	player.set("together_controller", _controller)
	_hooked_player = player


func _node_added(node: Node) -> void:
	if _session_active and node is PlayerBall:
		node.ready.connect(_update_player_hook, CONNECT_ONE_SHOT)


func _restore_player() -> void:
	if is_instance_valid(_hooked_player):
		_hooked_player.pause_cancel_shot()
		_replace_script(_hooked_player, _original_player_script)
	_hooked_player = null
	_original_player_script = null


func _replace_script(player: Node, script: Script) -> void:
	var values = {}
	for property in player.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = player.get(property.name)
	player.set_script(script)
	for property in player.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and values.has(property.name):
			player.set(property.name, values[property.name])

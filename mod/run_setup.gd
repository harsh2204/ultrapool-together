extends Node

var _starting = false
var _original_deck: Resource


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -2000
	set_process(false)


func at_main_menu() -> bool:
	var global_node = get_node("/root/Global")
	var scene = get_tree().current_scene
	return (
		not global_node.transitioning
		and not global_node.in_run
		and scene != null
		and scene.scene_file_path == global_node.SCENE_MENU.resource_path
	)


func capture_config() -> Dictionary:
	var menu = get_node("/root/UIManager").decks_menu
	var generator = RandomNumberGenerator.new()
	generator.randomize()
	return {
		"deck": str(menu.decks[menu.index_deck].id),
		"difficulty": str(menu.difficulties[menu.index_diff].id),
		"seed": generator.randi_range(1, 2147483647)
	}


func validate_config(config: Dictionary) -> bool:
	if (
		not config.get("deck") is String
		or not config.get("difficulty") is String
		or not config.get("seed") is int
		or config.seed < 1
		or config.seed > 2147483647
	):
		return false
	var database = get_node("/root/BallDatabase")
	if (
		not database.id_to_deck.has(config.deck)
		or not database.id_to_difficulty.has(config.difficulty)
	):
		return false
	return (
		config.deck != "DAILY"
		and database.id_to_deck[config.deck].can_be_chosen
		and database.id_to_difficulty[config.difficulty].can_be_chosen
	)


func start(config: Dictionary, catalog: Node = null) -> Error:
	if not validate_config(config):
		return ERR_INVALID_DATA
	if not at_main_menu():
		return ERR_BUSY
	var global_node = get_node("/root/Global")
	var database = get_node("/root/BallDatabase")
	global_node.chosen_run_state = null
	global_node.chosen_deck = database.id_to_deck[config.deck]
	if catalog != null:
		_original_deck = global_node.chosen_deck
		global_node.chosen_deck = catalog.prepare_deck(_original_deck)
	global_node.chosen_difficulty = database.id_to_difficulty[config.difficulty]
	global_node.run_mode = global_node.RunMode.NORMAL
	global_node.seed_text = str(config.seed)
	global_node.set_seeded(true)
	global_node.set_seed(config.seed)
	_starting = true
	set_process(true)
	global_node.go_to_game()
	return OK


func ready_for_input() -> bool:
	return not _starting


func _process(_delta: float) -> void:
	var game = get_node("/root/Global").gameManager
	if (
		not is_instance_valid(game)
		or not game.balls_spawned
		or not is_instance_valid(game.player_ball)
	):
		return
	var cue = game.player_ball
	# Native spawning jitters the cue with the shared visual RNG across awaited frames.
	cue.global_position = game.player_ball_position.global_position
	cue.start_pos = cue.global_position
	cue.prev_pos = cue.global_position
	_starting = false
	set_process(false)


func cancel() -> void:
	_starting = false
	set_process(false)
	if _original_deck != null:
		get_node("/root/Global").chosen_deck = _original_deck
		_original_deck = null


func return_menu() -> Error:
	cancel()
	var global_node = get_node("/root/Global")
	if global_node.transitioning:
		return ERR_BUSY
	var ui = get_node("/root/UIManager")
	for popup in ui.active_popups.duplicate():
		popup.just_opened_or_closed = false
		popup.instant_close_menu()
	ui.popup_queue.clear()
	ui.update_pause()
	if at_main_menu():
		return OK
	get_node("/root/EffectManager").clear_effects()
	global_node.go_to_main_menu()
	return OK

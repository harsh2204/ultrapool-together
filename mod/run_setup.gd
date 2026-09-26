extends Node

var _starting = false


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


# Publish the host's native unlocks once when opening the lobby. Guests may vote
# for any published option; local progression never removes the shared selection.
func available_choices() -> Dictionary:
	var database = get_node("/root/BallDatabase")
	var result = {"deck": [], "difficulty": []}
	for resource in database.id_to_deck.values():
		if str(resource.id) != "DAILY" and _available_to_host(resource):
			result.deck.append({"id": str(resource.id), "label": tr(str(resource.name))})
	for resource in database.id_to_difficulty.values():
		if _available_to_host(resource):
			result.difficulty.append({"id": str(resource.id), "label": tr(str(resource.name))})
	for field in result:
		result[field].sort_custom(func(a, b): return a.id < b.id)
	return result


func _available_to_host(resource: Resource) -> bool:
	var global_node = get_node("/root/Global")
	return (
		resource.get("can_be_chosen")
		and get_node("/root/AchievementManager").is_resource_unlocked(resource)
		and (not global_node.is_locked() or resource.get("available_in_demo"))
	)


func native_defaults() -> Dictionary:
	var menu = get_node("/root/UIManager").decks_menu
	return {
		"deck": str(menu.decks[menu.index_deck].id),
		"difficulty": str(menu.difficulties[menu.index_diff].id)
	}


func capture_config(selection: Dictionary = {}) -> Dictionary:
	var chosen = native_defaults() if selection.is_empty() else selection
	var generator = RandomNumberGenerator.new()
	generator.randomize()
	return {
		"deck": chosen.get("deck", ""),
		"difficulty": chosen.get("difficulty", ""),
		"run_mode": "normal",
		"seed": generator.randi_range(1, 2147483647)
	}


func validate_config(config: Dictionary) -> bool:
	if (
		config.get("run_mode", "normal") != "normal"
		or not config.get("deck") is String
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
	var deck = database.id_to_deck[config.deck]
	var difficulty = database.id_to_difficulty[config.difficulty]
	return (
		config.deck != "DAILY"
		and deck.can_be_chosen
		and difficulty.can_be_chosen
		and (
			not get_node("/root/Global").is_locked()
			or (deck.available_in_demo and difficulty.available_in_demo)
		)
	)


func start(config: Dictionary) -> Error:
	if not validate_config(config):
		return ERR_INVALID_DATA
	if not at_main_menu():
		return ERR_BUSY
	var global_node = get_node("/root/Global")
	var database = get_node("/root/BallDatabase")
	global_node.chosen_run_state = null
	global_node.chosen_deck = database.id_to_deck[config.deck]
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

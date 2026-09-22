extends Node

var _round_key = ""
var _end_key = ""
var _bindings: Array[Dictionary] = []


static func capture(game: Node, ui: Node) -> Dictionary:
	var phase = "play"
	if game.in_shop:
		phase = "shop"
	elif game.game_ended:
		phase = "ended"
	elif ui.round_over_menu.is_open:
		phase = "payout"
	return {
		"phase": phase,
		"won": game.round_won and not game.round_game_over,
		"score": game.score_this_round,
		"bonus_money": game.extra_money_earned,
		"money_before": game.money_last_round,
		"round_reward": game.get_round_win_reward(),
		"balls_pocketed": game.balls_pocketed,
		"money_earned": game.money_earned,
		"game_time": game.game_time
	}


static func valid(data) -> bool:
	if not data is Dictionary or data.get("phase") not in ["play", "payout", "shop", "ended"]:
		return false
	if not data.get("won") is bool:
		return false
	for key in [
		"score", "bonus_money", "money_before", "round_reward", "money_earned", "game_time"
	]:
		var value = data.get(key)
		if not (value is int or value is float) or not is_finite(value) or absf(value) > 1.0e18:
			return false
	return data.get("balls_pocketed") is int and data.balls_pocketed >= 0


func setup() -> void:
	var menu = get_node("/root/UIManager").round_over_menu
	for button in menu.find_children("*", "", true, false):
		if not button.has_signal("pressed"):
			continue
		for connection in button.pressed.get_connections():
			if connection.callable.get_method() == "_on_continue_button_pressed":
				button.pressed.disconnect(connection.callable)
				_bindings.append({"button": button, "connection": connection})
				button.pressed.connect(_dismiss_round)


func apply(data: Dictionary) -> void:
	var ui = get_node("/root/UIManager")
	var result: Dictionary = data.results
	var key = "%s:%s" % [data.scene_id, data.rounds_played]
	if result.phase == "payout":
		if _round_key != key:
			_close(ui.round_over_menu)
			_round_key = key
			ui.round_over_menu.round_won = result.won
			ui.round_over_menu.just_opened_or_closed = false
			ui.round_over_menu.open_menu()
			ui.round_over_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	elif result.phase != "shop":
		_close(ui.round_over_menu)
	if result.phase == "ended":
		if _end_key != key:
			_close(ui.game_over_menu)
			_end_key = key
			ui.game_over_menu.win = result.won
			ui.game_over_menu.just_opened_or_closed = false
			ui.game_over_menu.open_menu()
			ui.game_over_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		_close(ui.game_over_menu)


func clear() -> void:
	var ui = get_node("/root/UIManager")
	_close(ui.round_over_menu)
	_close(ui.game_over_menu)
	_round_key = ""
	_end_key = ""


func end_session() -> void:
	clear()
	for binding in _bindings:
		binding.button.pressed.disconnect(_dismiss_round)
		binding.button.pressed.connect(binding.connection.callable, binding.connection.flags)
	_bindings.clear()


func _dismiss_round() -> void:
	_close(get_node("/root/UIManager").round_over_menu)


func _close(menu: Node) -> void:
	if not menu.is_open:
		return
	menu.just_opened_or_closed = false
	menu.instant_close_menu()
	menu.underlay_canvas.hide()

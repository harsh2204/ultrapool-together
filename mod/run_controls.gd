extends Node

const FINISH_ACTIONS = [
	"_on_main_menu_button_pressed",
	"_on_restart_button_pressed",
	"_on_play_again_button_pressed",
	"_on_canvas_l_play_again_button_pressed",
	"go_main_menu",
	"go_play_again"
]
const ENDLESS_ACTIONS = ["_on_endless_button_pressed"]

var _controller: Node
var _bindings: Array[Dictionary] = []
var _disabled: Array[Dictionary] = []


func setup(controller: Node) -> void:
	_controller = controller


func begin_session() -> void:
	var ui = get_node("/root/UIManager")
	for button in ui.find_children("*", "", true, false):
		if not button.has_signal("pressed"):
			continue
		var connections = button.pressed.get_connections()
		var methods: Array = connections.map(
			func(connection): return connection.callable.get_method()
		)
		var finishes = methods.any(func(method): return method in FINISH_ACTIONS)
		var endless = methods.any(func(method): return method in ENDLESS_ACTIONS)
		if not finishes and not endless:
			continue
		for connection in connections:
			button.pressed.disconnect(connection.callable)
		var handler: Callable = (
			_endless.bind(connections) if endless and not finishes else _finish_match
		)
		button.pressed.connect(handler)
		_bindings.append({"button": button, "connections": connections, "handler": handler})
	for path in ["%PlayedDemo", "%RestoreButton"]:
		var button = ui.settings_menu.get_node(path)
		_disabled.append({"button": button, "disabled": button.disabled})
		button.set_disabled(true)


func end_session() -> void:
	for binding in _bindings:
		if not is_instance_valid(binding.button):
			continue
		binding.button.pressed.disconnect(binding.handler)
		for connection in binding.connections:
			if connection.callable.is_valid():
				binding.button.pressed.connect(connection.callable, connection.flags)
	_bindings.clear()
	for entry in _disabled:
		if is_instance_valid(entry.button):
			entry.button.set_disabled(entry.disabled)
	_disabled.clear()


func _endless(original_connections: Array) -> void:
	if not _controller.is_table_host():
		_controller._status("Only the table host can start Endless. Guests follow automatically.")
		return
	for connection in original_connections:
		if connection.callable.get_method() in ENDLESS_ACTIONS and connection.callable.is_valid():
			connection.callable.call()


func _finish_match() -> void:
	var ui = get_node("/root/UIManager")
	for popup in ui.active_popups.duplicate():
		popup.just_opened_or_closed = false
		popup.instant_close_menu()
	ui.popup_queue.clear()
	ui.update_pause()
	_controller._set_panel(true)
	if _controller._match_complete() or _controller.finished:
		_controller._lobby_request({"action": "reset"})
		_controller._status("Match finished. Ready up when everyone is back for a new run.")
	else:
		_controller._status("Finish the match from the lobby vote, then ready up for a new run.")

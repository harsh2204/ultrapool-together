extends Node

const EXIT_ACTIONS = [
	"_on_main_menu_button_pressed",
	"_on_restart_button_pressed",
	"_on_play_again_button_pressed",
	"_on_canvas_l_play_again_button_pressed",
	"_on_endless_button_pressed",
	"go_main_menu",
	"go_play_again"
]

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
		if not connections.any(
			func(connection): return connection.callable.get_method() in EXIT_ACTIONS
		):
			continue
		for connection in connections:
			button.pressed.disconnect(connection.callable)
		button.pressed.connect(_open_lobby)
		_bindings.append({"button": button, "connections": connections})
	for path in ["%PlayedDemo", "%RestoreButton"]:
		var button = ui.settings_menu.get_node(path)
		_disabled.append({"button": button, "disabled": button.disabled})
		button.set_disabled(true)


func end_session() -> void:
	for binding in _bindings:
		if not is_instance_valid(binding.button):
			continue
		binding.button.pressed.disconnect(_open_lobby)
		for connection in binding.connections:
			if connection.callable.is_valid():
				binding.button.pressed.connect(connection.callable, connection.flags)
	_bindings.clear()
	for entry in _disabled:
		if is_instance_valid(entry.button):
			entry.button.set_disabled(entry.disabled)
	_disabled.clear()


func _open_lobby() -> void:
	var ui = get_node("/root/UIManager")
	for popup in ui.active_popups.duplicate():
		popup.just_opened_or_closed = false
		popup.instant_close_menu()
	ui.popup_queue.clear()
	ui.update_pause()
	_controller._set_panel(true)
	_controller._status("Use the lobby vote to end this match, then ready up for a new run.")

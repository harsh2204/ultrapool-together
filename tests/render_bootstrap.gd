extends "res://singletons/logger.gd"

var _steam_singleton: Object


func _init() -> void:
	Engine.max_fps = 30
	if Engine.has_singleton("Steam"):
		_steam_singleton = Engine.get_singleton("Steam")
		Engine.unregister_singleton("Steam")


func _exit_tree() -> void:
	if _steam_singleton != null:
		Engine.register_singleton("Steam", _steam_singleton)


func _emit_to_console(line: String) -> void:
	if is_inside_tree():
		super._emit_to_console(line)

extends "res://singletons/settings_manager.gd"


func _reload_state() -> void:
	var settings = SaveManager.save.settings
	settings.low_fps_mode = true
	settings.is_fullscreen = false
	settings.is_analytics = false
	settings.resolution = Vector2i(
		ProjectSettings.get_setting("display/window/size/window_width_override", 1280),
		ProjectSettings.get_setting("display/window/size/window_height_override", 720)
	)
	super._reload_state()

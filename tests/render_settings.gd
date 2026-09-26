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
	# Native settings may restore bus volumes; keep only this isolated test silent.
	for index in AudioServer.bus_count:
		AudioServer.set_bus_mute(index, true)
	if ProjectSettings.get_setting("render_test/background", false):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

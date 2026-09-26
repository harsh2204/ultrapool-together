extends "res://singletons/logger.gd"

var _steam_singleton: Object
var _background_capture = false


func _init() -> void:
	Engine.max_fps = 30
	_background_capture = bool(ProjectSettings.get_setting("render_test/background", false))
	_mute_audio()
	if Engine.has_singleton("Steam"):
		_steam_singleton = Engine.get_singleton("Steam")
		Engine.unregister_singleton("Steam")


func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mute_audio()
	if _background_capture:
		_keep_background()
		RenderingServer.viewport_set_update_mode(
			get_tree().root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS
		)
	_report_capture_environment.call_deferred()


func _process(_delta: float) -> void:
	if _background_capture:
		# A minimized macOS window skips ordinary presentation. Render its viewport
		# without swapping the desktop surface so the shared frame_post_draw capture
		# fixture still receives actual rendered images.
		RenderingServer.force_draw(false)


func _keep_background() -> void:
	# Configure once at startup; settings reloads reapply these flags separately.
	# Repeated native minimize requests can emit focus/move events that release
	# synthetic input while a fixture is holding an item.
	var window = get_tree().root
	window.unfocusable = true
	window.mouse_passthrough = true
	if window.mode != Window.MODE_MINIMIZED:
		window.mode = Window.MODE_MINIMIZED


func _report_capture_environment() -> void:
	prints(
		"RENDER_CAPTURE_ENV",
		JSON.stringify(
			{
				"background": _background_capture,
				"display_driver": DisplayServer.get_name(),
				"max_fps": Engine.max_fps,
				"low_processor_usage": OS.low_processor_usage_mode,
				"low_processor_sleep_usec": OS.low_processor_usage_mode_sleep_usec,
				"window_mode": get_tree().root.mode,
				"unfocusable": get_tree().root.unfocusable,
				"mouse_passthrough": get_tree().root.mouse_passthrough
			}
		)
	)


func _mute_audio() -> void:
	for index in AudioServer.bus_count:
		AudioServer.set_bus_mute(index, true)


func _exit_tree() -> void:
	if _steam_singleton != null:
		Engine.register_singleton("Steam", _steam_singleton)


func _emit_to_console(line: String) -> void:
	if is_inside_tree():
		super._emit_to_console(line)

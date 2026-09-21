extends "res://addons/talo/talo_manager.gd"


func _load_config() -> void:
	super._load_config()
	settings.auto_connect_socket = false
	settings.auto_start_session = false
	settings.continuity_enabled = false
	settings.offline_mode = true
	settings.api_url = "http://127.0.0.1:1"
	settings.socket_url = "ws://127.0.0.1:1"

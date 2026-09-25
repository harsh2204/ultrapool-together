extends Node

# Interactive same-PC host/guest harness over LAN loopback.
# Hosts or joins UDP 24817, opens the lobby, and stays running for manual play.

const PORT := 24817
const TOKEN := "local-session-password"
const PROFILE_MARKER := "UltrapoolTogetherLocalSession"

var mod: Node
var role := "host"


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg == "--guest":
			role = "guest"
	_run.call_deferred()


func _run():
	if not OS.get_user_data_dir().contains(PROFILE_MARKER):
		print("LOCAL_SESSION_REFUSE wrong save profile; expected ", PROFILE_MARKER)
		get_tree().quit(2)
		return
	mod = get_node("/root/UltrapoolTogether")
	get_node("/root/SettingsManager").use_analytics = false
	get_node("/root/AnalyticsManager").state = 0
	get_node("/root/PlatformManager")._steam = null
	get_node("/root/CloudSaveManager").backend = null
	get_node("/root/TutorialManager").ENABLED = false
	_place_window()
	await get_tree().create_timer(2).timeout
	if role == "host":
		var error: Error = mod.transport.host_lan(PORT, TOKEN)
		if error != OK:
			print("LOCAL_SESSION_FAIL host_lan ", error)
			get_tree().quit(1)
			return
		print("LOCAL_SESSION_READY host listening on 127.0.0.1:", PORT)
	else:
		var error: Error = mod.transport.join_lan("127.0.0.1", PORT, TOKEN)
		if error != OK:
			print("LOCAL_SESSION_FAIL join_lan ", error)
			get_tree().quit(1)
			return
		print("LOCAL_SESSION_READY guest joining 127.0.0.1:", PORT)
	mod._set_panel(true)
	print(
		"LOCAL_SESSION_OPEN ",
		role,
		" - use the lobby (F8), then seat/ready/start. Close both windows when finished."
	)


func _place_window():
	var size := Vector2i(1280, 720)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	var origin := Vector2i(40, 40) if role == "host" else Vector2i(700, 80)
	DisplayServer.window_set_position(origin)
	DisplayServer.window_set_title("Ultrapool Together Local Session · " + role)
extends Node

const VERSION = "0.1.0"
const GAME_VERSION = "0.15.7"
const PORT = 24816
const FRAME_INTERVAL = 0.10
const MAX_FRAME_BYTES = 500000

var transport: Node
var adapter: Node
var hud: CanvasLayer
var remote_view: TextureRect
var panel: PanelContainer
var status: Label
var turn_label: Label
var score_label: Label
var connection: LineEdit
var password: LineEdit
var mode: OptionButton
var angle: HSlider
var power: HSlider
var shoot_button: Button
var pass_button: Button
var start_button: Button
var room_label: LineEdit
var arrow: Control
var active = false
var turn_owner = 0
var shot_number = 0
var shot_pending = false
var shot_start_score = 0.0
var settle_time = 0.0
var elapsed_shot = 0.0
var scores = [0.0, 0.0]
var shots = [0, 0]
var pvp = false
var finished = false
var latest_state: Dictionary = {}
var frame_time = 0.0
var state_time = 0.0
var frame_id = 0
var waiting_frame = -1
var frame_sent_at = 0
var capture_busy = false
var last_guest_frame = 0
var guest_process_modes: Dictionary = {}

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	var base = get_script().resource_path.get_base_dir()
	transport = load(base.path_join("transport.gd")).new()
	adapter = load(base.path_join("game_adapter.gd")).new()
	add_child(transport)
	add_child(adapter)
	transport.connected.connect(_connected)
	transport.disconnected.connect(_disconnected)
	transport.received.connect(_received)
	transport.status_changed.connect(_status)
	_build_ui(base)
	if str(ProjectSettings.get_setting("application/config/version", "")) != GAME_VERSION:
		_status("Unsupported game version. This build requires Ultrapool " + GAME_VERSION)
		set_process(false)
		adapter.set_process(false)
		for button in panel.find_children("*", "Button", true, false):
			button.disabled = true
		return
	print("[Together] READY v", VERSION, " / game ", GAME_VERSION, " / saves ", OS.get_user_data_dir())
	if "--together-smoke" in OS.get_cmdline_user_args():
		await get_tree().create_timer(3.0).timeout
		print("[Together] SMOKE PASS: UI, adapter and transport loaded")
		get_tree().quit()

func _build_ui(base: String):
	hud = CanvasLayer.new()
	hud.layer = 120
	add_child(hud)
	remote_view = TextureRect.new()
	remote_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	remote_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	remote_view.stretch_mode = TextureRect.STRETCH_SCALE
	remote_view.mouse_filter = Control.MOUSE_FILTER_STOP
	remote_view.hide()
	hud.add_child(remote_view)
	arrow = load(base.path_join("aim_arrow.gd")).new()
	arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(arrow)
	var dock = PanelContainer.new()
	dock.position = Vector2(12, 116)
	dock.custom_minimum_size = Vector2(300, 0)
	hud.add_child(dock)
	var box = VBoxContainer.new()
	dock.add_child(_margin(box, 12))
	var first = VBoxContainer.new()
	box.add_child(first)
	first.add_child(_label("ULTRAPOOL TOGETHER  •  0.1", 16))
	turn_label = _label("Two players · one shared table", 18)
	turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	first.add_child(turn_label)
	var connection_row = HBoxContainer.new()
	first.add_child(connection_row)
	connection_row.add_child(_button("Connection / F8", func(): panel.visible = not panel.visible))
	connection_row.add_child(_button("Disconnect", func(): transport.close(); _disconnected("Disconnected")))
	var aim_row = VBoxContainer.new()
	box.add_child(aim_row)
	aim_row.add_child(_label("Aim", 16))
	angle = HSlider.new()
	angle.min_value = -180
	angle.max_value = 180
	angle.step = 1
	angle.custom_minimum_size.x = 260
	angle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aim_row.add_child(angle)
	aim_row.add_child(_label("Power", 16))
	power = HSlider.new()
	power.min_value = 26
	power.max_value = 100
	power.value = 70
	power.custom_minimum_size.x = 260
	aim_row.add_child(power)
	shoot_button = _button("Take shot", _request_shot)
	aim_row.add_child(shoot_button)
	pass_button = _button("Pass turn", _request_pass)
	aim_row.add_child(pass_button)
	start_button = _button("Start score match", _start_match)
	aim_row.add_child(start_button)
	score_label = _label("Co-op: alternate shots through a shared run. Host handles menus and the shop.", 15)
	score_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	score_label.custom_minimum_size.x = 270
	box.add_child(score_label)
	status = _label("Host or join with F8. Steam room codes work over the Internet; LAN supports direct IP.", 14)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 270
	box.add_child(status)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-290, -250)
	panel.custom_minimum_size = Vector2(580, 440)
	hud.add_child(panel)
	var lobby = VBoxContainer.new()
	lobby.add_theme_constant_override("separation", 12)
	panel.add_child(_margin(lobby, 22))
	lobby.add_child(_label("Play together", 28))
	lobby.add_child(_label("Co-op first · shared run · host controls the shop", 16))
	mode = OptionButton.new()
	mode.add_item("Co-op — alternate shots in one run")
	mode.add_item("PvP — five shots each, highest total wins")
	lobby.add_child(mode)
	var steam_row = HBoxContainer.new()
	lobby.add_child(steam_row)
	steam_row.add_child(_button("Host Steam room", func(): _host(true)))
	steam_row.add_child(_button("Join Steam room", func(): _join(true)))
	connection = LineEdit.new()
	connection.placeholder_text = "Paste Steam room code, or host's LAN / VPN IP"
	lobby.add_child(connection)
	password = LineEdit.new()
	password.placeholder_text = "LAN room password (same on both PCs)"
	password.secret = true
	lobby.add_child(password)
	var lan_row = HBoxContainer.new()
	lobby.add_child(lan_row)
	lan_row.add_child(_button("Host LAN / VPN", func(): _host(false)))
	lan_row.add_child(_button("Join LAN / VPN", func(): _join(false)))
	room_label = LineEdit.new()
	room_label.editable = false
	room_label.placeholder_text = "Your Steam room code appears here"
	lobby.add_child(room_label)
	lobby.add_child(_button("Copy room code", func(): DisplayServer.clipboard_set(room_label.text)))
	var hint = _label("Both players need this mod and Ultrapool 0.15.7. The host streams the table; the guest takes shots with the aim controls. Audio stays on the host. F8 closes this panel.", 15)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 525
	lobby.add_child(hint)
	lobby.add_child(_button("Close", func(): panel.hide()))
	var style = StyleBoxFlat.new()
	style.bg_color = Color("162326")
	style.border_color = Color("6fbfab")
	style.set_border_width_all(1)
	dock.add_theme_stylebox_override("panel", style)
	panel.add_theme_stylebox_override("panel", style)

func _label(value: String, size: int) -> Label:
	var label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	return label

func _button(value: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = value
	button.pressed.connect(action)
	return button

func _margin(child: Control, padding: int) -> MarginContainer:
	var margin = MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, padding)
	margin.add_child(child)
	return margin

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()

func _host(steam: bool):
	if active:
		_status("Disconnect before creating another room.")
		return
	pvp = mode.selected == 1
	if not steam and password.text.length() < 8:
		_status("Choose a LAN password of at least 8 characters.")
		return
	var error = transport.host_steam() if steam else transport.host_lan(PORT, password.text)
	if error == OK:
		room_label.text = transport.room_code
	else:
		_status("Could not host (%s). Keep Steam running, or use LAN / VPN." % error)

func _join(steam: bool):
	if active:
		_status("Disconnect before joining another room.")
		return
	if not steam and (connection.text.strip_edges().is_empty() or password.text.length() < 8):
		_status("Enter the host IP and the shared LAN password (8+ characters).")
		return
	var error = transport.join_steam(connection.text.strip_edges()) if steam else transport.join_lan(connection.text.strip_edges(), PORT, password.text)
	if error != OK:
		_status("Could not join (%s). Check the room code or IP and password." % error)

func _connected():
	active = true
	panel.hide()
	turn_owner = 0
	shot_pending = false
	finished = false
	scores = [0.0, 0.0]
	shots = [0, 0]
	waiting_frame = -1
	last_guest_frame = 0
	if transport.is_host:
		adapter.begin_session()
		_publish_state()
	else:
		_suspend_guest_game()
		remote_view.show()
	_status("Connected. Host starts or continues a normal run. Use the mod aim controls to shoot.")

func _disconnected(reason: String):
	active = false
	adapter.end_session()
	for node in guest_process_modes:
		if is_instance_valid(node):
			node.process_mode = guest_process_modes[node]
	guest_process_modes.clear()
	get_tree().paused = false
	remote_view.hide()
	remote_view.texture = null
	shot_pending = false
	waiting_frame = -1
	latest_state.clear()
	_status(reason + ". Host can continue the run locally; reconnect to share it again.")

func _status(value: String):
	if is_instance_valid(status):
		status.text = value
	print("[Together] ", value)

func _process(delta):
	if not is_instance_valid(adapter):
		return
	if active and not transport.is_host:
		_suspend_guest_game()
	if active and transport.is_host:
		if shot_pending:
			var state = adapter.game_data()
			if not state.available:
				transport.close()
				_disconnected("Run closed during a shot; session ended")
				return
			elapsed_shot += delta
			settle_time = settle_time + delta if adapter.is_settled() else 0.0
			if state.round_finalized or (elapsed_shot > 1.0 and settle_time >= 0.8):
				_finish_shot()
		state_time += delta
		if state_time >= 0.15:
			state_time = 0
			_publish_state()
		frame_time += delta
		if waiting_frame >= 0 and Time.get_ticks_msec() - frame_sent_at > 5000:
			transport.close()
			_disconnected("Guest stopped acknowledging video")
		elif frame_time >= FRAME_INTERVAL and waiting_frame < 0 and not capture_busy:
			frame_time = 0
			_capture_frame()
	_update_hud()

func _suspend_guest_game():
	for node in get_tree().root.get_children():
		if node != self and not guest_process_modes.has(node):
			guest_process_modes[node] = node.process_mode
			node.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = true

func _update_hud():
	var my_turn = active and turn_owner == (0 if transport.is_host else 1)
	var ready = active and bool(latest_state.get("can_shoot", false)) and not shot_pending and not finished
	shoot_button.disabled = not (my_turn and ready)
	pass_button.disabled = not (my_turn and ready) or pvp
	start_button.visible = active and transport.is_host and pvp
	start_button.disabled = shot_pending or not bool(latest_state.get("can_shoot", false))
	if active:
		turn_label.text = ("MATCH FINISHED" if finished else ("YOUR SHOT" if my_turn else "PARTNER'S SHOT")) + (" · resolving…" if shot_pending else "")
	else:
		turn_label.text = "Host or join a room · F8"
	if pvp and active:
		score_label.text = "PvP  Host: %.0f (%d/5)    Guest: %.0f (%d/5)%s" % [scores[0], shots[0], scores[1], shots[1], _winner() if finished else ""]
	elif active:
		score_label.text = "Co-op · shared score %.0f · host manages the shop · aim %.0f° · power %.0f%%" % [float(latest_state.get("score", 0)), angle.value, power.value]
	arrow.visible = my_turn and ready and not panel.visible
	if arrow.visible:
		arrow.state = latest_state
		arrow.direction = _shot_vector()
		arrow.queue_redraw()

func _shot_vector() -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(angle.value)) * power.value * 2.0

func _request_shot():
	if not active or shot_pending or finished or not latest_state.get("can_shoot", false):
		return
	if turn_owner != (0 if transport.is_host else 1):
		return
	var vector = _shot_vector()
	if transport.is_host:
		_take_shot(0, vector, shot_number)
	else:
		transport.send({"kind": "shot", "x": vector.x, "y": vector.y, "turn": shot_number})

func _take_shot(player: int, vector: Vector2, expected_turn: int):
	if not active or not transport.is_host or turn_owner != player or shot_pending or finished or expected_turn != shot_number:
		return
	if not vector.is_finite() or vector.length() < 51 or vector.length() > 200.1:
		return
	shot_start_score = adapter.score()
	if not adapter.shoot(vector):
		return
	shot_pending = true
	settle_time = 0
	elapsed_shot = 0
	_publish_state()

func _finish_shot():
	scores[turn_owner] += maxf(0.0, adapter.shot_score() - shot_start_score)
	shots[turn_owner] += 1
	shot_pending = false
	shot_number += 1
	finished = pvp and shots[0] >= 5 and shots[1] >= 5
	turn_owner = 1 - turn_owner
	_publish_state()

func _request_pass():
	if transport.is_host:
		_pass(0, shot_number)
	else:
		transport.send({"kind": "pass", "turn": shot_number})

func _pass(player: int, expected_turn: int):
	if pvp or player != turn_owner or expected_turn != shot_number or shot_pending or not adapter.can_shoot():
		return
	turn_owner = 1 - turn_owner
	shot_number += 1
	_publish_state()

func _start_match():
	if not transport.is_host or shot_pending or not adapter.can_shoot():
		return
	scores = [0.0, 0.0]
	shots = [0, 0]
	turn_owner = 0
	shot_number += 1
	finished = false
	_publish_state()

func _winner() -> String:
	if scores[0] == scores[1]:
		return " · DRAW"
	return " · HOST WINS" if scores[0] > scores[1] else " · GUEST WINS"

func _publish_state():
	latest_state = adapter.game_data()
	latest_state.merge({"kind": "state", "turn_owner": turn_owner, "turn": shot_number, "pending": shot_pending, "pvp": pvp, "scores": scores, "shots": shots, "finished": finished}, true)
	transport.send(latest_state)

func _received(message: Dictionary):
	var kind = message.get("kind", "")
	if transport.is_host:
		match kind:
			"shot":
				if _number(message.get("x")) and _number(message.get("y")) and message.get("turn") is int:
					_take_shot(1, Vector2(message.x, message.y), message.turn)
			"pass":
				if message.get("turn") is int:
					_pass(1, message.turn)
			"frame_ack":
				if message.get("id") == waiting_frame:
					waiting_frame = -1
		return
	if kind == "state":
		if not _valid_state(message):
			return
		latest_state = message
		turn_owner = message.turn_owner
		shot_number = message.turn
		shot_pending = message.pending
		pvp = message.pvp
		scores = message.scores
		shots = message.shots
		finished = message.finished
	elif kind == "frame":
		if not message.get("jpg") is PackedByteArray or not message.get("id") is int:
			return
		if message.jpg.size() > MAX_FRAME_BYTES or message.id <= last_guest_frame:
			return
		var picture = Image.new()
		if picture.load_jpg_from_buffer(message.jpg) != OK or picture.get_width() > 1280 or picture.get_height() > 800:
			return
		remote_view.texture = ImageTexture.create_from_image(picture)
		last_guest_frame = message.id
		transport.send({"kind": "frame_ack", "id": message.id})

func _number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _valid_state(message: Dictionary) -> bool:
	if not message.get("turn_owner") is int or message.turn_owner < 0 or message.turn_owner > 1 or not message.get("turn") is int:
		return false
	for key in ["pending", "pvp", "finished", "can_shoot"]:
		if not message.get(key) is bool:
			return false
	for key in ["scores", "shots", "cue_screen", "viewport_size", "aim_scale"]:
		if not message.get(key) is Array or message[key].size() != 2:
			return false
		for value in message[key]:
			if not _number(value):
				return false
	return _number(message.get("score"))

func _capture_frame():
	if DisplayServer.get_name() == "headless":
		return
	capture_busy = true
	await RenderingServer.frame_post_draw
	if active and transport.is_host and waiting_frame < 0:
		var picture = get_viewport().get_texture().get_image()
		var ratio = minf(1.0, minf(1280.0 / picture.get_width(), 800.0 / picture.get_height()))
		picture.resize(maxi(1, int(picture.get_width() * ratio)), maxi(1, int(picture.get_height() * ratio)))
		var jpg = picture.save_jpg_to_buffer(0.7)
		if jpg.size() <= MAX_FRAME_BYTES:
			frame_id += 1
			waiting_frame = frame_id
			frame_sent_at = Time.get_ticks_msec()
			transport.send({"kind": "frame", "id": frame_id, "jpg": jpg})
	capture_busy = false

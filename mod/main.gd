extends Node

const VERSION = "0.2.1"
const GAME_VERSION = "0.15.7"
const SNAPSHOT_INTERVAL = 0.05
const SNAPSHOT_TIMEOUT_MS = 5000

var transport: Node
var adapter: Node
var table_sync: Node
var ui_root: Control
var panel: PanelContainer
var turn_label: Label
var score_label: Label
var status: Label
var mode: OptionButton
var host_button: Button
var invite_button: MenuButton
var pass_button: Button
var restart_button: Button
var leave_button: Button
var room_code: LineEdit
var code_panel: VBoxContainer

var active = false
var supported = true
var local_player = 0
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
var awaiting_shot_turn = -1
var snapshot_time = 0.0
var state_time = 0.0
var snapshot_id = 0
var waiting_snapshot = -1
var snapshot_sent_at = 0
var last_guest_snapshot = 0


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	var base = get_script().resource_path.get_base_dir()
	transport = load(base.path_join("transport.gd")).new()
	adapter = load(base.path_join("game_adapter.gd")).new()
	table_sync = load(base.path_join("table_sync.gd")).new()
	add_child(transport)
	add_child(adapter)
	add_child(table_sync)
	_build_ui()
	transport.connected.connect(_connected)
	transport.disconnected.connect(_disconnected)
	transport.received.connect(_received)
	transport.status_changed.connect(_status)
	transport.room_ready.connect(_room_ready)
	if str(ProjectSettings.get_setting("application/config/version", "")) != GAME_VERSION:
		supported = false
		_status("This mod requires Ultrapool " + GAME_VERSION + ".")
		set_process(false)
		adapter.set_process(false)
		host_button.disabled = true
		return
	transport.listen_for_invites()
	print("[Together] Ready v", VERSION)


func _build_ui():
	var hud = CanvasLayer.new()
	hud.layer = 120
	add_child(hud)
	var root = Control.new()
	ui_root = root
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dock = VBoxContainer.new()
	root.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dock.offset_left = -350
	dock.offset_right = -16
	dock.offset_top = 16
	dock.offset_bottom = 16
	dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dock.custom_minimum_size.x = 314
	var row = HBoxContainer.new()
	dock.add_child(row)
	turn_label = _label("")
	turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(turn_label)
	pass_button = _button("Pass", _request_pass)
	pass_button.hide()
	row.add_child(pass_button)
	row.add_child(_button("Multiplayer · F8", _toggle_panel))
	score_label = _label("")
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dock.add_child(score_label)
	panel = PanelContainer.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -210
	panel.offset_bottom = 210
	panel.custom_minimum_size = Vector2(440, 0)
	var margin = MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var lobby = VBoxContainer.new()
	lobby.add_theme_constant_override("separation", 12)
	margin.add_child(lobby)
	var title = _label("Play together")
	title.add_theme_font_size_override("font_size", 24)
	lobby.add_child(title)
	mode = OptionButton.new()
	mode.add_item("Co-op")
	mode.add_item("PvP · five shots each")
	lobby.add_child(mode)
	host_button = _button("Host game", _host)
	lobby.add_child(host_button)
	invite_button = MenuButton.new()
	invite_button.text = "Invite friend"
	invite_button.flat = false
	invite_button.focus_mode = Control.FOCUS_ALL
	invite_button.about_to_popup.connect(_refresh_friends)
	invite_button.get_popup().id_pressed.connect(_invite_selected)
	invite_button.disabled = true
	lobby.add_child(invite_button)
	status = _label("Open the mod on both PCs, then host and invite through Steam.")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 400
	lobby.add_child(status)
	code_panel = VBoxContainer.new()
	code_panel.hide()
	lobby.add_child(_button("Use a room code", func(): code_panel.visible = not code_panel.visible))
	lobby.add_child(code_panel)
	room_code = LineEdit.new()
	room_code.placeholder_text = "Steam room code"
	code_panel.add_child(room_code)
	var code_row = HBoxContainer.new()
	code_panel.add_child(code_row)
	code_row.add_child(_button("Copy", func(): DisplayServer.clipboard_set(room_code.text)))
	code_row.add_child(_button("Join", _join))
	restart_button = _button("Play another match", _start_match)
	restart_button.hide()
	lobby.add_child(restart_button)
	leave_button = _button("Leave game", _leave)
	leave_button.hide()
	lobby.add_child(leave_button)
	lobby.add_child(_button("Close", func(): panel.hide()))
	panel.hide()


func _label(value: String) -> Label:
	var label = Label.new()
	label.text = value
	return label


func _button(value: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = value
	button.pressed.connect(action)
	return button


func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_toggle_panel()
		get_viewport().set_input_as_handled()


func _toggle_panel():
	panel.visible = not panel.visible


func _host():
	if not supported or active:
		return
	pvp = mode.selected == 1
	if transport.host_steam() != OK:
		_status("Could not create a Steam game. Check that Steam is online.")


func _join():
	if supported and not active and transport.join_steam(room_code.text.strip_edges()) != OK:
		_status("Could not join. Check the room code and Steam connection.")


func _room_ready():
	room_code.text = transport.room_code
	code_panel.show()


func _refresh_friends():
	var popup = invite_button.get_popup()
	popup.clear()
	for friend in transport.online_friends():
		var index = popup.item_count
		popup.add_item(friend.name, index)
		popup.set_item_metadata(index, friend.id)
	if popup.item_count == 0:
		popup.add_item("No online friends")
		popup.set_item_disabled(0, true)
		_status("No online friends found. Your friend can join with the room code.")


func _invite_selected(id: int):
	var popup = invite_button.get_popup()
	transport.invite_friend(int(popup.get_item_metadata(popup.get_item_index(id))))


func _leave():
	transport.close()
	_disconnected("Left the game.")


func _connected():
	active = true
	local_player = 0 if transport.is_host else 1
	invite_button.get_popup().hide()
	panel.hide()
	turn_owner = 0
	shot_number = 0
	shot_pending = false
	finished = false
	scores = [0.0, 0.0]
	shots = [0, 0]
	latest_state.clear()
	awaiting_shot_turn = -1
	waiting_snapshot = -1
	snapshot_id = 0
	last_guest_snapshot = 0
	if local_player == 1 and not table_sync.begin_guest():
		transport.close()
		_disconnected("Return to the main menu before joining a friend.")
		return
	adapter.begin_session(self)
	if local_player == 0:
		_publish_state()
	if active:
		_status("Connected. Take turns using the game's normal controls.")


func _disconnected(reason: String):
	active = false
	invite_button.get_popup().hide()
	adapter.end_session()
	table_sync.end_guest()
	shot_pending = false
	awaiting_shot_turn = -1
	waiting_snapshot = -1
	latest_state.clear()
	_status(reason)
	panel.show()


func _status(value: String):
	status.text = value
	print("[Together] ", value)


func _process(delta):
	if active and local_player == 0:
		if shot_pending:
			var state = adapter.game_data()
			if not state.available:
				_leave()
				_status("The run closed during a shot.")
				return
			elapsed_shot += delta
			settle_time = settle_time + delta if adapter.is_settled() else 0.0
			if state.round_finalized or (elapsed_shot > 1.0 and settle_time >= 0.8):
				_finish_shot()
				if not active:
					return
		state_time += delta
		if state_time >= 0.15:
			state_time = 0.0
			_publish_state()
			if not active:
				return
		snapshot_time += delta
		if waiting_snapshot >= 0 and Time.get_ticks_msec() - snapshot_sent_at > SNAPSHOT_TIMEOUT_MS:
			_leave()
			_status("Your partner stopped receiving table updates.")
		elif waiting_snapshot < 0 and snapshot_time >= SNAPSHOT_INTERVAL:
			snapshot_time = 0.0
			_publish_snapshot()
	_update_hud()


func can_control() -> bool:
	if not _turn_ready():
		return false
	if get_node("/root/InputManager").is_controller():
		return true
	var hovered = get_viewport().gui_get_hovered_control()
	return hovered == null or not ui_root.is_ancestor_of(hovered)


func _turn_ready() -> bool:
	if not active or panel.visible or turn_owner != local_player or shot_pending or finished:
		return false
	if local_player == 0:
		return adapter.can_shoot()
	return (
		awaiting_shot_turn < 0
		and latest_state.get("can_shoot", false)
		and table_sync.ready_for_input()
	)


func submit_shot(vector: Vector2) -> bool:
	if not can_control() or not vector.is_finite() or vector.length() <= 50.0:
		return false
	vector = vector.limit_length(200.0)
	if local_player == 0:
		return _take_shot(0, vector, shot_number)
	awaiting_shot_turn = shot_number
	transport.send({"kind": "shot", "x": vector.x, "y": vector.y, "turn": shot_number})
	return true


func _take_shot(player: int, vector: Vector2, expected_turn: int) -> bool:
	if (
		not active
		or local_player != 0
		or turn_owner != player
		or shot_pending
		or finished
		or expected_turn != shot_number
	):
		return false
	if not vector.is_finite() or vector.length() <= 50.0 or vector.length() > 200.1:
		return false
	shot_start_score = adapter.score()
	if not adapter.shoot(vector):
		return false
	shot_pending = true
	settle_time = 0.0
	elapsed_shot = 0.0
	_publish_state()
	return true


func _finish_shot():
	scores[turn_owner] += maxf(0.0, adapter.shot_score() - shot_start_score)
	shots[turn_owner] += 1
	shot_pending = false
	shot_number += 1
	finished = pvp and shots[0] >= 5 and shots[1] >= 5
	turn_owner = 1 - turn_owner
	_publish_state()


func _request_pass():
	if not _turn_ready() or pvp:
		return
	if local_player == 0:
		_pass(0, shot_number)
	else:
		awaiting_shot_turn = shot_number
		transport.send({"kind": "pass", "turn": shot_number})


func _pass(player: int, expected_turn: int) -> bool:
	if (
		not active
		or local_player != 0
		or pvp
		or player != turn_owner
		or expected_turn != shot_number
		or shot_pending
		or not adapter.can_shoot()
	):
		return false
	turn_owner = 1 - turn_owner
	shot_number += 1
	_publish_state()
	return true


func _start_match():
	if not active or local_player != 0 or shot_pending or not adapter.can_shoot():
		return
	scores = [0.0, 0.0]
	shots = [0, 0]
	turn_owner = 0
	shot_number += 1
	finished = false
	_publish_state()


func _winner() -> String:
	if scores[0] == scores[1]:
		return "Draw"
	return "You won" if scores[local_player] > scores[1 - local_player] else "Your partner won"


func _update_hud():
	invite_button.disabled = not transport.invite_ready()
	host_button.disabled = transport.session_open()
	mode.disabled = transport.session_open()
	leave_button.visible = transport.session_open()
	restart_button.visible = active and local_player == 0 and pvp and finished
	restart_button.disabled = not latest_state.get("can_shoot", false)
	pass_button.visible = active and not pvp
	pass_button.disabled = not _turn_ready()
	turn_label.text = ""
	score_label.text = ""
	if not active:
		return
	if finished:
		turn_label.text = _winner()
	elif shot_pending or awaiting_shot_turn >= 0:
		turn_label.text = "Shot in play"
	elif latest_state.get("in_shop", false):
		turn_label.text = "Host is shopping"
	elif not latest_state.get("table_active", false):
		turn_label.text = "Waiting for the table"
	else:
		turn_label.text = "Your turn" if turn_owner == local_player else "Partner's turn"
	if pvp:
		score_label.text = (
			"You %.0f (%d/5) · Partner %.0f (%d/5)"
			% [
				scores[local_player],
				shots[local_player],
				scores[1 - local_player],
				shots[1 - local_player]
			]
		)
	elif local_player == 1 and latest_state.get("available", false):
		score_label.text = (
			"Round %d · %d shots left · Score %.0f"
			% [latest_state.round, latest_state.shots_left, latest_state.score]
		)


func _publish_state():
	latest_state = adapter.game_data()
	latest_state.merge(
		{
			"kind": "state",
			"turn_owner": turn_owner,
			"turn": shot_number,
			"pending": shot_pending,
			"pvp": pvp,
			"scores": scores.duplicate(),
			"shots": shots.duplicate(),
			"finished": finished
		},
		true
	)
	transport.send(latest_state)


func _publish_snapshot():
	snapshot_id += 1
	waiting_snapshot = snapshot_id
	snapshot_sent_at = Time.get_ticks_msec()
	transport.send({"kind": "snapshot", "id": snapshot_id, "scene": table_sync.capture()})


func _received(message: Dictionary):
	if not active:
		return
	var kind = message.get("kind", "")
	if local_player == 0:
		if (
			kind == "shot"
			and _number(message.get("x"))
			and _number(message.get("y"))
			and message.get("turn") is int
		):
			var accepted = _take_shot(1, Vector2(message.x, message.y), message.turn)
			transport.send({"kind": "shot_result", "turn": message.turn, "accepted": accepted})
		elif kind == "pass" and message.get("turn") is int:
			var accepted = _pass(1, message.turn)
			transport.send({"kind": "shot_result", "turn": message.turn, "accepted": accepted})
		elif kind == "snapshot_ack" and message.get("id") == waiting_snapshot:
			waiting_snapshot = -1
		return
	if kind == "state" and _valid_state(message):
		latest_state = message
		turn_owner = message.turn_owner
		shot_number = message.turn
		shot_pending = message.pending
		pvp = message.pvp
		scores = message.scores
		shots = message.shots
		finished = message.finished
		if shot_pending or awaiting_shot_turn != shot_number:
			awaiting_shot_turn = -1
	elif (
		kind == "shot_result"
		and message.get("turn") == awaiting_shot_turn
		and message.get("accepted") == false
	):
		awaiting_shot_turn = -1
	elif (
		kind == "snapshot"
		and message.get("id") is int
		and message.id > last_guest_snapshot
		and message.get("scene") is Dictionary
	):
		if not table_sync.apply_snapshot(message.scene):
			_leave()
			_status("The host sent an incompatible table update.")
			return
		last_guest_snapshot = message.id
		transport.send({"kind": "snapshot_ack", "id": message.id})


func _number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _valid_state(message: Dictionary) -> bool:
	if (
		not message.get("turn_owner") is int
		or not message.turn_owner in [0, 1]
		or not message.get("turn") is int
		or message.turn < 0
	):
		return false
	for key in ["available", "table_active", "can_shoot", "in_shop", "pending", "pvp", "finished"]:
		if not message.get(key) is bool:
			return false
	for key in ["scores", "shots"]:
		if not message.get(key) is Array or message[key].size() != 2:
			return false
		for value in message[key]:
			if not _number(value) or value < 0:
				return false
	for key in ["round", "shots_left"]:
		if not message.get(key) is int:
			return false
	return _number(message.get("score"))

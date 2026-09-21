extends Control

signal host_requested
signal join_requested(code: String)
signal friends_requested
signal invite_requested(id: int)
signal slot_requested(table: int, slot: int)
signal ready_requested(ready: bool)
signal table_count_requested(count: int)
signal shot_budget_requested(shots: int)
signal start_requested
signal return_requested
signal leave_requested
signal close_requested

const INK = Color("eaf0e7")
const MUTED = Color("8baeb2")
const GOLD = Color("e8b861")
const FELT = Color("35d5ab")
const TABLE_COLORS = [
	Color("35d5ab"),
	Color("ee9073"),
	Color("edc86b"),
	Color("a998e4"),
	Color("69bddb"),
	Color("ed91b8"),
	Color("a9cf71"),
	Color("c9b394")
]

var _state: Dictionary = {}
var _local_id = 0
var _is_host = false
var _room_open = false
var _code = ""


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	%Host.pressed.connect(func(): host_requested.emit())
	%Join.pressed.connect(_join)
	%JoinCode.text_submitted.connect(func(_text): _join())
	%JoinCode.text_changed.connect(func(text): %Join.disabled = text.strip_edges().is_empty())
	%Copy.pressed.connect(_copy_code)
	%Invite.about_to_popup.connect(func(): friends_requested.emit())
	%Invite.get_popup().id_pressed.connect(_invite)
	%TableCount.value_changed.connect(func(value): table_count_requested.emit(int(value)))
	%ShotBudget.value_changed.connect(func(value): shot_budget_requested.emit(int(value)))
	%Ready.pressed.connect(_toggle_ready)
	%Start.pressed.connect(func(): start_requested.emit())
	%Return.pressed.connect(func(): return_requested.emit())
	%Leave.pressed.connect(func(): leave_requested.emit())
	%Close.pressed.connect(func(): close_requested.emit())
	resized.connect(_resize_tables)
	set_friends([])
	set_connection("", false, false)
	render({}, 0, false)
	_resize_tables()


func render(state: Dictionary, local_id: int, is_host: bool):
	var roster_changed = state != _state or local_id != _local_id
	_state = state.duplicate(true)
	_local_id = local_id
	_is_host = is_host
	var players: Array = state.get("players", [])
	var started: bool = state.get("started", false)
	var connected = 0
	for player in players:
		if player.get("connected", true):
			connected += 1
	%Count.text = "%d / %d PLAYERS" % [connected, state.get("capacity", 8)]
	%TableCount.set_block_signals(true)
	%TableCount.max_value = maxi(maxi(1, connected), state.get("table_count", 1))
	%TableCount.set_value_no_signal(state.get("table_count", 1))
	%TableCount.set_block_signals(false)
	%TableCount.editable = is_host and not started
	%ShotBudget.set_value_no_signal(state.get("shot_budget", 6))
	%ShotBudget.editable = is_host and not started
	%ShotBudget.get_parent().visible = state.get("table_count", 1) > 1
	%RoomTitle.text = "MATCH IN PROGRESS" if started else "YOUR LOBBY"
	%Rules.text = (
		"One table. One shared run. Take turns and shop together."
		if state.get("table_count", 1) == 1
		else "%d tables compete. Players at the same table are partners." % state.table_count
	)
	if not is_host and not started:
		%Rules.text += " The host chooses the match settings."
	var local_player = _player(local_id)
	var seated: bool = local_player.get("table", -1) >= 0
	var ready: bool = local_player.get("ready", false)
	%Ready.text = "Ready · click to undo" if ready else "Ready up"
	%Ready.disabled = started or not seated or not local_player.get("connected", false)
	%Ready.visible = not started
	%Start.visible = is_host and not started
	%Start.disabled = not state.get("can_start", false)
	%Return.visible = is_host and started
	%Leave.text = "Leave match" if started else "Leave lobby"
	%Close.text = "Back to game · F8" if started else "Close · F8"
	%FooterRule.text = _readiness_text(players, local_player, started)
	%FooterRule.visible = _room_open
	if roster_changed:
		_build_tables()
		_build_bench()
	_resize_tables()


func set_status(text: String):
	%Status.text = text
	%Status.visible = not text.is_empty()


func set_connection(code: String, room_open: bool, invite_ready: bool):
	_code = code
	_room_open = room_open
	%Home.visible = not room_open
	%Room.visible = room_open
	%RoomBar.visible = room_open
	%Actions.visible = room_open
	%FooterRule.visible = room_open
	%Code.text = code if not code.is_empty() else "CREATING STEAM ROOM…"
	%Copy.disabled = code.is_empty()
	%Invite.disabled = not invite_ready
	%Join.disabled = %JoinCode.text.strip_edges().is_empty()
	if not room_open:
		%Invite.get_popup().hide()


func set_friends(friends: Array):
	var popup = %Invite.get_popup()
	popup.clear()
	for friend in friends:
		var index = popup.item_count
		popup.add_item(str(friend.name), index)
		popup.set_item_metadata(index, friend.id)
	if friends.is_empty():
		popup.add_item("No online friends · share your room code")
		popup.set_item_disabled(0, true)


func _join():
	var code: String = %JoinCode.text.strip_edges()
	if not code.is_empty():
		join_requested.emit(code)


func _copy_code():
	if _code.is_empty():
		return
	DisplayServer.clipboard_set(_code)
	set_status("Room code copied. Your friend can paste it into Join lobby.")


func _invite(id: int):
	var popup = %Invite.get_popup()
	var index = popup.get_item_index(id)
	if index >= 0 and not popup.is_item_disabled(index):
		invite_requested.emit(int(popup.get_item_metadata(index)))


func _toggle_ready():
	var local_player = _player(_local_id)
	if local_player.get("table", -1) >= 0 and not _state.get("started", false):
		ready_requested.emit(not local_player.get("ready", false))


func _player(id: int) -> Dictionary:
	for player in _state.get("players", []):
		if player.id == id:
			return player
	return {}


func _readiness_text(players: Array, local_player: Dictionary, started: bool) -> String:
	if started:
		return "The match has started. Close this screen to return to play."
	if local_player.get("table", -1) < 0:
		return "Choose an open seat at a table, then ready up."
	var seated = 0
	var ready = 0
	for player in players:
		if player.get("connected", false) and player.get("table", -1) >= 0:
			seated += 1
			if player.get("ready", false):
				ready += 1
	if _state.get("can_start", false):
		return (
			"Everyone is ready. Start when you are ready."
			if _is_host
			else "Everyone is ready. Waiting for the host to start."
		)
	if players.size() < 2:
		return "Invite a friend to join your lobby."
	for player in players:
		if not player.get("connected", false):
			return "Waiting for every player's connection."
	if seated < players.size():
		return "Waiting for everyone to choose a table."
	for table_id in _state.get("table_count", 1):
		var occupied = false
		for player in players:
			if player.get("table", -1) == table_id:
				occupied = true
				break
		if not occupied:
			return "Every table needs a player. Choose a table or ask the host to reduce the count."
	return "%d / %d ready. Everyone must be ready before the host starts." % [ready, players.size()]


func _build_tables():
	_clear(%Tables)
	for table_id in _state.get("table_count", 1):
		var color: Color = TABLE_COLORS[table_id % TABLE_COLORS.size()]
		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.x = 240
		card.add_theme_stylebox_override("panel", _box(Color("102b30"), color.darkened(0.4), 2))
		%Tables.add_child(card)
		var margin = MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 14)
		card.add_child(margin)
		var content = VBoxContainer.new()
		content.add_theme_constant_override("separation", 9)
		margin.add_child(content)
		var title = Label.new()
		title.text = "TABLE %d" % (table_id + 1)
		title.add_theme_font_size_override("font_size", 20)
		title.add_theme_color_override("font_color", color)
		content.add_child(title)
		var summary = _table_summary(table_id)
		if _state.get("started", false) and not summary.is_empty():
			var score = Label.new()
			score.text = "%.0f POINTS" % summary.get("score", 0)
			score.add_theme_font_size_override("font_size", 23)
			content.add_child(score)
			var progress = Label.new()
			progress.text = (
				"%d shots · %s" % [summary.get("shots_used", 0), summary.get("status", "Playing")]
				if _state.get("table_count", 1) == 1
				else (
					"%d / %d shots · %s"
					% [
						summary.get("shots_used", 0),
						summary.get("shot_budget", 0),
						summary.get("status", "Playing")
					]
				)
			)
			progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			progress.add_theme_font_size_override("font_size", 14)
			progress.add_theme_color_override("font_color", MUTED)
			content.add_child(progress)
		var table_players: Array = []
		for player in _state.get("players", []):
			if player.table == table_id:
				table_players.append(player)
		table_players.sort_custom(func(a, b): return a.slot < b.slot)
		var occupied: Array = []
		for player in table_players:
			occupied.append(player.slot)
			content.add_child(_player_row(player, color))
		if _state.get("started", false):
			continue
		var seat = 0
		while seat in occupied:
			seat += 1
		var join = Button.new()
		join.custom_minimum_size.y = 48
		var here: bool = _player(_local_id).get("table", -1) == table_id
		join.text = "You are seated here" if here else "+  Join this table"
		join.disabled = here or seat >= _state.get("capacity", 8)
		join.pressed.connect(func(): slot_requested.emit(table_id, seat))
		content.add_child(join)


func _player_row(player: Dictionary, color: Color) -> Control:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("0b1d24"), Color("25434a"), 1))
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var marker = ColorRect.new()
	marker.custom_minimum_size = Vector2(5, 0)
	marker.color = color
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(marker)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 2)
	row.add_child(content)
	var name_label = Label.new()
	name_label.text = str(player.name)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = 80
	content.add_child(name_label)
	var detail = Label.new()
	var badges: Array[String] = []
	if player.id == _local_id:
		badges.append("YOU")
	if player.id == _state.get("host_id", 0):
		badges.append("ROOM HOST")
	if player.get("leader", false) or player.id == _table_summary(player.table).get("leader_id", 0):
		badges.append("TABLE HOST")
	if not player.get("connected", false):
		badges.append("DISCONNECTED" if _state.get("started", false) else "CONNECTING…")
	elif _state.get("started", false):
		badges.append(
			"FINISHED" if _table_summary(player.table).get("finished", false) else "PLAYING"
		)
	elif player.get("ready", false):
		badges.append("READY")
	else:
		badges.append("NOT READY")
	detail.text = " · ".join(badges)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", FELT if player.get("ready", false) else MUTED)
	content.add_child(detail)
	return panel


func _table_summary(table_id: int) -> Dictionary:
	for summary in _state.get("table_summaries", []):
		if summary.get("table", -1) == table_id:
			return summary
	return {}


func _build_bench():
	_clear(%Unassigned)
	var unassigned = 0
	for player in _state.get("players", []):
		if player.table >= 0:
			continue
		unassigned += 1
		var row = _player_row(player, GOLD)
		row.custom_minimum_size.x = 220
		%Unassigned.add_child(row)
	%Bench.visible = unassigned > 0


func _clear(parent: Node):
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _resize_tables():
	if not is_node_ready():
		return
	var columns = clampi(int((size.x - 64) / 280), 1, 4)
	%Tables.columns = mini(columns, _state.get("table_count", 1))
	var margin = 16 if size.x < 700 else 32
	$Margin.add_theme_constant_override("margin_left", margin)
	$Margin.add_theme_constant_override("margin_right", margin)


func _apply_theme():
	var native_theme = get_node("/root/UIManager").game_theme
	var palette = Theme.new()
	palette.default_font = native_theme.default_font
	palette.default_font_size = 18
	palette.set_color("font_color", "Label", INK)
	palette.set_color("font_color", "Button", INK)
	palette.set_color("font_hover_color", "Button", Color.WHITE)
	palette.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	palette.set_stylebox("normal", "Button", _box(Color("153239"), Color("36535a"), 1))
	palette.set_stylebox("hover", "Button", _box(Color("21484a"), GOLD, 1))
	palette.set_stylebox("pressed", "Button", _box(Color("0b2028"), FELT, 2))
	palette.set_stylebox("disabled", "Button", _box(Color("102128"), Color("20363d"), 1))
	palette.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), GOLD, 2))
	palette.set_stylebox("normal", "LineEdit", _box(Color("0b1d24"), Color("36535a"), 1))
	palette.set_stylebox("focus", "LineEdit", _box(Color("0b1d24"), GOLD, 2))
	palette.set_color("font_color", "LineEdit", INK)
	palette.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme = palette
	for button in [%Host, %Ready, %Start]:
		button.add_theme_stylebox_override("normal", _box(FELT.darkened(0.13), FELT, 1))
		button.add_theme_stylebox_override("hover", _box(FELT.lightened(0.12), GOLD, 1))
		button.add_theme_color_override("font_color", Color("08241f"))
		button.add_theme_color_override("font_hover_color", Color("08241f"))
	%Bench.add_theme_stylebox_override("panel", _box(Color("171f25"), Color("544a33"), 1))


func _box(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	return style

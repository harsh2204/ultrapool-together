extends Control

signal host_requested
signal join_requested(code: String)
signal friends_requested
signal invite_requested(id: int)
signal slot_requested(table: int, slot: int)
signal ready_requested(ready: bool)
signal table_count_requested(count: int)
signal shot_budget_requested(shots: int)
signal run_vote_requested(field: String, choice: String, catalog_revision: int)
signal start_requested
signal return_requested
signal return_vote_requested(approve: bool)
signal watch_requested(table: int)
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


static func player_color_for(table: int, slot: int, id: int = 0) -> Color:
	if table >= 0 and slot >= 0:
		return TABLE_COLORS[slot % TABLE_COLORS.size()]
	return Color.from_hsv(posmod(hash(str(id)), 360) / 360.0, 0.55, 1.0)


var _state: Dictionary = {}
var _local_id = 0
var _is_host = false
var _room_open = false
var _code = ""
var _player_grids: Array[GridContainer] = []


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
	%MatchMode.item_selected.connect(func(index): _vote_selected("match_mode", %MatchMode, index))
	%StartingSet.item_selected.connect(func(index): _vote_selected("deck", %StartingSet, index))
	%Difficulty.item_selected.connect(func(index): _vote_selected("difficulty", %Difficulty, index))
	%Ready.pressed.connect(_toggle_ready)
	%Start.pressed.connect(func(): start_requested.emit())
	%Return.pressed.connect(func(): return_requested.emit())
	%ApproveReturn.pressed.connect(func(): return_vote_requested.emit(true))
	%CancelReturn.pressed.connect(func(): return_vote_requested.emit(false))
	%Leave.pressed.connect(func(): leave_requested.emit())
	%Close.pressed.connect(func(): close_requested.emit())
	resized.connect(_resize_tables)
	set_friends([])
	set_connection("", false, false)
	render({}, 0, false)
	_resize_tables()


func render(state: Dictionary, local_id: int, is_host: bool):
	var roster_changed = _roster_view(state) != _roster_view(_state) or local_id != _local_id
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
	var multiple_tables: bool = state.get("table_count", 1) > 1
	var racing = multiple_tables and state.get("match_mode", "race") == "race"
	_render_run_votes(state, local_id, started)
	%MatchMode.get_parent().visible = multiple_tables
	%ShotBudget.get_parent().visible = multiple_tables and not racing
	var summaries: Array = state.get("table_summaries", [])
	var complete = (
		started and not summaries.is_empty() and summaries.all(func(table): return table.finished)
	)
	%Settings.visible = not started
	%RoomTitle.text = (
		"MATCH RESULTS" if complete else ("MATCH IN PROGRESS" if started else "YOUR LOBBY")
	)
	%Rules.text = "One table. One shared run. Take turns and shop together."
	if racing:
		%Rules.text = "Race to finish the run first. Each table has its own board and shared shop."
	elif multiple_tables:
		%Rules.text = "Highest score wins. Each table shares the same total shot allowance."
	var local_player = _player(local_id)
	var seated: bool = local_player.get("table", -1) >= 0
	var ready: bool = local_player.get("ready", false)
	%Ready.text = "Ready · click to undo" if ready else "Ready up"
	%Ready.disabled = started or not seated or not local_player.get("connected", false)
	%Ready.visible = not started
	%Start.visible = is_host and not started
	%Start.disabled = not state.get("can_start", false)
	var return_vote: Dictionary = state.get("return_vote", {})
	var voting: bool = started and not complete and return_vote.get("active", false)
	var eligible: Array = return_vote.get("eligible", [])
	var approved: Array = return_vote.get("ready", [])
	%Return.visible = is_host and started and not voting
	%Return.text = "Return to lobby" if complete else "Vote to end match"
	%ApproveReturn.visible = voting and local_id in eligible
	%ApproveReturn.text = "Approved" if local_id in approved else "Approve return to lobby"
	%ApproveReturn.disabled = local_id in approved
	%CancelReturn.visible = voting and local_id in eligible
	%Leave.text = "Leave match" if started else "Leave lobby"
	%Leave.visible = not is_host or not started or complete
	%Close.text = "Back to game · F8" if started else "Close · F8"
	%FooterRule.text = (
		"Match complete. The host can return everyone to the lobby."
		if complete
		else _readiness_text(players, local_player, started)
	)
	if voting:
		%FooterRule.text = (
			"Return to lobby? %d / %d approved. Play continues until everyone agrees."
			% [approved.size(), eligible.size()]
		)
	%FooterRule.visible = _room_open
	if roster_changed:
		_build_tables()
		_build_bench()
	_resize_tables()


func _roster_view(state: Dictionary) -> Dictionary:
	var players: Array = state.get("players", []).duplicate(true)
	for player in players:
		player.erase("run_votes")
	return {
		"players": players,
		"tables": state.get("table_count", 1),
		"mode": state.get("match_mode", "race"),
		"summaries": state.get("table_summaries", []),
		"watched": state.get("watched_table", -1),
		"started": state.get("started", false),
		"host": state.get("host_id", 0)
	}


func _vote_selected(field: String, control: OptionButton, index: int) -> void:
	run_vote_requested.emit(
		field,
		str(control.get_item_metadata(index)),
		int(_state.get("run_vote", {}).get("catalog_revision", -1))
	)


func _render_run_votes(state: Dictionary, local_id: int, started: bool) -> void:
	var vote: Dictionary = state.get("run_vote", {})
	var options: Dictionary = vote.get("options", {})
	var counts: Dictionary = vote.get("counts", {})
	var selected: Dictionary = vote.get("selected", {})
	var local_player = _player(local_id)
	var votes: Dictionary = local_player.get("run_votes", {})
	var disabled: bool = started or not local_player.get("connected", false)
	var winners: Array[String] = []
	var controls = {"deck": %StartingSet, "difficulty": %Difficulty, "match_mode": %MatchMode}
	for field in controls:
		var control: OptionButton = controls[field]
		var entries: Array = options.get(field, [])
		if control.get_meta("run_options", []) != entries or control.item_count == 0:
			control.clear()
			control.add_item("No preference")
			control.set_item_metadata(0, "")
			for entry in entries:
				control.add_item(entry.label)
				control.set_item_metadata(control.item_count - 1, entry.id)
			control.set_meta("run_options", entries.duplicate(true))
		var selected_index = 0
		for index in entries.size():
			var entry: Dictionary = entries[index]
			var count: int = counts.get(field, {}).get(entry.id, 0)
			control.set_item_text(index + 1, "%s · %d" % [entry.label, count])
			if votes.get(field, "") == entry.id:
				selected_index = index + 1
			if selected.get(field, "") == entry.id:
				if field != "match_mode" or state.get("table_count", 1) > 1:
					winners.append(entry.label)
		control.select(selected_index)
		control.disabled = disabled or entries.is_empty()
	%VoteHelp.visible = not started
	%RunSelection.text = (
		("Playing: " if started else "Current result: ") + " · ".join(winners)
		if not winners.is_empty()
		else "Waiting for the host's available starting sets and difficulties."
	)


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
	if _state.get("run_vote", {}).get("options", {}).is_empty():
		return "Waiting for the host's available starting sets and difficulties."
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
	_player_grids.clear()
	for table_id in _state.get("table_count", 1):
		var color: Color = TABLE_COLORS[table_id % TABLE_COLORS.size()]
		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.x = 240
		var card_style = _box(Color("102b30"), color.darkened(0.4), 2)
		card_style.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", card_style)
		%Tables.add_child(card)
		var content = VBoxContainer.new()
		content.add_theme_constant_override("separation", 8)
		card.add_child(content)
		var title = Label.new()
		title.text = "TABLE %d" % (table_id + 1)
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", color)
		content.add_child(title)
		var summary = _table_summary(table_id)
		if _state.get("started", false) and not summary.is_empty():
			_add_progress(content, summary)
		var table_players: Array = []
		for player in _state.get("players", []):
			if player.table == table_id:
				table_players.append(player)
		table_players.sort_custom(func(a, b): return a.slot < b.slot)
		var players = GridContainer.new()
		players.add_theme_constant_override("h_separation", 8)
		players.add_theme_constant_override("v_separation", 8)
		content.add_child(players)
		_player_grids.append(players)
		var occupied: Array = []
		for player in table_players:
			occupied.append(player.slot)
			players.add_child(
				_player_row(player, player_color_for(player.table, player.slot, player.id))
			)
		if _state.get("started", false):
			_add_watch_button(content, table_id, summary)
			continue
		var seat = 0
		while seat in occupied:
			seat += 1
		# The player badge already identifies the local seat; only render an actionable join.
		if _player(_local_id).get("table", -1) == table_id:
			continue
		var join = Button.new()
		join.custom_minimum_size.y = 48
		join.add_theme_font_size_override("font_size", 16)
		join.text = "+  Join this table"
		join.disabled = seat >= _state.get("capacity", 8)
		join.pressed.connect(func(): slot_requested.emit(table_id, seat))
		content.add_child(join)


func _add_progress(content: VBoxContainer, summary: Dictionary):
	var multiple_tables: bool = _state.get("table_count", 1) > 1
	var racing = multiple_tables and _state.get("match_mode", "race") == "race"
	var headline = Label.new()
	headline.text = "%.0f POINTS" % summary.get("score", 0)
	if racing:
		headline.text = "ROUND %d" % maxi(1, summary.get("round", 1))
		if summary.get("run_goal_rounds", 0) > 0:
			headline.text += " / %d" % summary.run_goal_rounds
		if summary.get("finish_order", 0) > 0:
			headline.text = "FINISHED #%d" % summary.finish_order
	headline.add_theme_font_size_override("font_size", 23)
	content.add_child(headline)
	var progress = Label.new()
	var status: String = summary.get("status", "Playing")
	if racing:
		progress.text = "%s · %s" % [_time_text(summary.get("elapsed_ms", 0)), status]
	elif multiple_tables:
		progress.text = (
			"%d / %d shots · %s"
			% [summary.get("shots_used", 0), summary.get("shot_budget", 0), status]
		)
	else:
		progress.text = "%d shots · %s" % [summary.get("shots_used", 0), status]
	progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress.add_theme_font_size_override("font_size", 14)
	progress.add_theme_color_override("font_color", MUTED)
	content.add_child(progress)


func _add_watch_button(content: VBoxContainer, table: int, summary: Dictionary):
	if _state.get("table_count", 1) < 2:
		return
	var own_table: int = _player(_local_id).get("table", -1)
	var watched: int = _state.get("watched_table", own_table)
	if table == own_table and watched == own_table:
		return
	var watch = Button.new()
	watch.custom_minimum_size.y = 40
	watch.add_theme_font_size_override("font_size", 16)
	watch.text = "Return to my table" if table == own_table else "Watch table"
	if watched == table:
		watch.text = "Watching"
	watch.disabled = watched == table or summary.get("status", "") == "Table host disconnected"
	watch.pressed.connect(func(): watch_requested.emit(table))
	content.add_child(watch)


func _time_text(milliseconds: int) -> String:
	var seconds = maxi(0, milliseconds) / 1000
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _player_row(player: Dictionary, color: Color) -> Control:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = _box(Color("0b1d24"), Color("25434a"), 1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
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
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = 80
	content.add_child(name_label)
	var detail = Label.new()
	var badges: Array[String] = []
	if player.id == _local_id:
		badges.append("YOU")
	if player.id == _state.get("host_id", 0):
		badges.append("ROOM HOST")
	elif (
		player.get("leader", false) or player.id == _table_summary(player.table).get("leader_id", 0)
	):
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
		var row = _player_row(player, player_color_for(player.table, player.slot, player.id))
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
	# Keep the desktop header on one row; wrap the room-code group at narrow widths.
	var header = $Margin/Layout/Header
	var room_parent = header if size.x >= 1000 else $Margin/Layout
	if %RoomBar.get_parent() != room_parent:
		%RoomBar.reparent(room_parent)
		room_parent.move_child(%RoomBar, 1)
	var margin = 16 if size.x < 700 else 32
	$Margin.add_theme_constant_override("margin_left", margin)
	$Margin.add_theme_constant_override("margin_right", margin)
	var width = size.x - margin * 2
	var columns = clampi(int((width + 16) / 256), 1, 4)
	%Tables.columns = mini(columns, _state.get("table_count", 1))
	var card_width = (width - (%Tables.columns - 1) * 16) / %Tables.columns
	for players in _player_grids:
		players.columns = clampi(int((card_width - 16) / 240), 1, 4)


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
	palette.set_stylebox("panel", "PopupMenu", _box(Color("102b30"), Color("36535a"), 1))
	palette.set_stylebox("hover", "PopupMenu", _box(Color("21484a"), GOLD, 1))
	palette.set_color("font_color", "PopupMenu", INK)
	palette.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	palette.set_color("font_disabled_color", "PopupMenu", MUTED)
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

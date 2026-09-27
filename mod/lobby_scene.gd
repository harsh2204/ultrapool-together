extends Control

signal host_requested
signal join_requested(code: String)
signal rejoin_requested
signal friends_requested
signal invite_requested(id: int)
signal slot_requested(table: int, slot: int)
signal ready_requested(ready: bool)
signal table_count_requested(count: int)
signal shot_budget_requested(shots: int)
signal run_vote_requested(field: String, choice: String, catalog_revision: int)
signal clone_rounds_requested(enabled: bool)
signal multiplayer_balls_requested(enabled: bool)
signal expansion_set_requested(set_id: String, enabled: bool)
signal start_requested
signal return_requested
signal return_vote_requested(approve: bool)
signal watch_requested(table: int)
signal leave_requested
signal close_requested

const VoteOption = preload("lobby_vote_option.gd")
const ExpansionRegistry = preload("sets/registry.gd")

const INK = Color("eaf0e7")
const MUTED = Color("8baeb2")
const GOLD = Color("e8b861")
const FELT = Color("35d5ab")
const PLAQUE_INK = Color("3b2610")
const BUTTON_CONTENT = [15, 11, 15, 11]
const FIELD_CONTENT = [15, 11, 15, 11]
const DROPDOWN_CONTENT = [15, 11, 30, 11]
const TABLE_CARD_CONTENT = [16, 14, 16, 14]
const PLAQUE_CONTENT = [24, 3, 24, 5]
const ROW_CONTENT = [8, 5, 8, 5]
const ROW_SPACING = 6
const ROSTER_MIN_HEIGHT = 48
const TABLE_BUTTON_HEIGHT = 44
# Felt area inside the backdrop's rail and cushion, as fractions of the backdrop image.
# Only the header board and the bottom action row may sit outside it.
const BACKDROP_INLAY = Rect2(0.054, 0.095, 0.892, 0.804)
const INLAY_PADDING = 4
const BOTTOM_MARGIN = 20
const DECK_ROW_WIDTH = 716
const DIFFICULTY_ROW_WIDTH = 404
const CHALK_TRACK = Color(0, 0, 0, 0.22)
const CHALK_GRABBER = Color(0.95, 0.93, 0.89, 0.55)
const CHALK_GRABBER_HOVER = Color(0.95, 0.93, 0.89, 0.8)
const HEADER_PLANK_GROW = Vector2(18, 8)
const PLAYER_CHIP_SIZE = Vector2(20, 20)
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


# Shared UI art from the controller; null keeps the flat styles.
var skin: RefCounted

var _state: Dictionary = {}
var _local_id = 0
var _is_host = false
var _room_open = false
var _code = ""
var _player_grids: Array[GridContainer] = []
var _vote_catalogs: Dictionary = {}
var _vote_buttons: Dictionary = {}
var _vote_groups: Dictionary = {}
var _header_plank: Panel
var _expansion_checks: Dictionary = {}


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	_ensure_expansion_toggles()
	%Host.pressed.connect(func(): host_requested.emit())
	%Rejoin.pressed.connect(func(): rejoin_requested.emit())
	%Join.pressed.connect(_join)
	%JoinCode.text_submitted.connect(func(_text): _join())
	%JoinCode.text_changed.connect(func(text): %Join.disabled = text.strip_edges().is_empty())
	%Copy.pressed.connect(_copy_code)
	%Invite.about_to_popup.connect(func(): friends_requested.emit())
	%Invite.get_popup().id_pressed.connect(_invite)
	%TableCount.value_changed.connect(func(value): table_count_requested.emit(int(value)))
	%ShotBudget.value_changed.connect(func(value): shot_budget_requested.emit(int(value)))
	%MatchMode.item_selected.connect(func(index): _vote_selected("match_mode", %MatchMode, index))
	%CloneRounds.toggled.connect(func(enabled): clone_rounds_requested.emit(enabled))
	%MultiplayerBalls.toggled.connect(func(enabled): multiplayer_balls_requested.emit(enabled))
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
	%ShotBudget.set_value_no_signal(state.get("shot_budget", 6))
	%ShotBudget.editable = is_host and not started
	var multiple_tables: bool = state.get("table_count", 1) > 1
	var racing = multiple_tables and state.get("match_mode", "race") == "race"
	var single_table: bool = bool(state.get("single_table_difficulty", false))
	%TableCount.editable = is_host and not started and not single_table
	_render_run_votes(state, local_id, started)
	%MatchMode.get_parent().visible = multiple_tables
	%ShotBudget.get_parent().visible = multiple_tables and not racing
	%CloneRounds.set_pressed_no_signal(bool(state.get("clone_rounds", false)))
	%CloneRounds.disabled = not is_host or started
	%MultiplayerBalls.set_pressed_no_signal(bool(state.get("multiplayer_balls", false)))
	%MultiplayerBalls.disabled = not is_host or started
	_render_expansion_toggles(state, is_host, started)
	var summaries: Array = state.get("table_summaries", [])
	var complete = (
		started and not summaries.is_empty() and summaries.all(func(table): return table.finished)
	)
	%Settings.visible = not started
	%VoteChoices.visible = not started
	%Rules.visible = started
	%RoomTitle.text = (
		"MATCH RESULTS" if complete else ("MATCH IN PROGRESS" if started else "YOUR LOBBY")
	)
	%Rules.text = "One table. One shared run. Take turns and shop together."
	if single_table:
		%Rules.text = (
			"All Nighter (One Table): same long run as All Nighter, locked to a single shared table."
		)
	if state.get("clone_rounds", false):
		%Rules.text = "Clone-table rounds: everyone plays the same layout at once; only the winner shops next."
	if state.get("multiplayer_balls", false):
		%Rules.text += (
			" Opt-in multiplayer balls may appear rarely in the shop (never in the starting rack)."
		)
	var expansion_flags: Dictionary = ExpansionRegistry.normalize_flags(
		state.get("expansion_sets", {})
	)
	if ExpansionRegistry.any_enabled(expansion_flags):
		var names: Array = []
		for set_id in ExpansionRegistry.SET_IDS:
			if bool(expansion_flags.get(set_id, false)):
				names.append(ExpansionRegistry.SET_LABELS[set_id])
		%Rules.text += " Expansion sets (%s) may appear rarely in the shop." % ", ".join(names)
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


func vote_button(field: String, choice: String) -> Button:
	return _vote_buttons.get(field, {}).get(choice)


func _build_vote_choices(field: String, entries: Array) -> void:
	if _vote_catalogs.get(field) == entries:
		return
	# PERF-026: catalog changes alone construct cards or resolve native textures.
	# Vote updates retain the same controls, focus, styles, and resource references.
	var container = %StartingSet if field == "deck" else %Difficulty
	_clear(container)
	_vote_catalogs[field] = entries.duplicate(true)
	_vote_buttons[field] = {}
	var group = ButtonGroup.new()
	group.allow_unpress = false
	_vote_groups[field] = group
	var choices: Array = [{"id": "", "label": "No preference"}]
	choices.append_array(entries)
	for entry in choices:
		var card = VoteOption.new()
		if _skinned():
			card.apply_skin(skin)
		card.button_group = group
		card.configure(field, entry.id, entry.label, _vote_texture(field, entry.id))
		card.pressed.connect(_card_vote_selected.bind(field, entry.id))
		container.add_child(card)
		_vote_buttons[field][entry.id] = card


func _vote_texture(field: String, choice: String) -> Texture2D:
	if choice.is_empty():
		return null
	var database = get_node("/root/BallDatabase")
	if field == "deck":
		var deck = database.id_to_deck.get(choice)
		if deck != null:
			# These are the same BallSet posters used by the native shop.
			var ball_set = database.get_set_by_id(str(deck.ball_set))
			return ball_set.poster if ball_set != null else null
	else:
		var difficulty = database.id_to_difficulty.get(choice)
		if difficulty != null:
			return difficulty.difficultyIcon
	return null


func _card_vote_selected(field: String, choice: String) -> void:
	run_vote_requested.emit(
		field, choice, int(_state.get("run_vote", {}).get("catalog_revision", -1))
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
	for field in ["deck", "difficulty"]:
		var entries: Array = options.get(field, [])
		_build_vote_choices(field, entries)
		var voter_groups: Dictionary = {}
		for player in state.get("players", []):
			if not player.get("connected", false):
				continue
			var choice: String = player.get("run_votes", {}).get(field, "")
			if not voter_groups.has(choice):
				voter_groups[choice] = []
			voter_groups[choice].append(
				{
					"id": player.id,
					"name": str(player.name),
					"color":
					player_color_for(player.get("table", -1), player.get("slot", -1), player.id)
				}
			)
		for choice in _vote_buttons[field]:
			var voters: Array[Dictionary] = []
			voters.assign(voter_groups.get(choice, []))
			_vote_buttons[field][choice].render_votes(
				voters,
				votes.get(field, "") == choice,
				selected.get(field, "") == choice and not choice.is_empty(),
				disabled or entries.is_empty()
			)
		for entry in entries:
			if selected.get(field, "") == entry.id:
				winners.append(entry.label)

	# The competition mode keeps its compact selector beside the host settings.
	var modes: Array = options.get("match_mode", [])
	if %MatchMode.get_meta("run_options", []) != modes or %MatchMode.item_count == 0:
		%MatchMode.clear()
		%MatchMode.add_item("No preference")
		%MatchMode.set_item_metadata(0, "")
		for entry in modes:
			%MatchMode.add_item(entry.label)
			%MatchMode.set_item_metadata(%MatchMode.item_count - 1, entry.id)
		%MatchMode.set_meta("run_options", modes.duplicate(true))
	var mode_index = 0
	for index in modes.size():
		var entry: Dictionary = modes[index]
		var count: int = counts.get("match_mode", {}).get(entry.id, 0)
		var label = "%s · %d" % [entry.label, count]
		if %MatchMode.get_item_text(index + 1) != label:
			%MatchMode.set_item_text(index + 1, label)
		if votes.get("match_mode", "") == entry.id:
			mode_index = index + 1
		if selected.get("match_mode", "") == entry.id and state.get("table_count", 1) > 1:
			winners.append(entry.label)
	%MatchMode.select(mode_index)
	%MatchMode.disabled = disabled or modes.is_empty()
	%VoteHelp.visible = false
	var result_text = (
		("Playing: " if started else "Current result: ") + " · ".join(winners)
		if not winners.is_empty()
		else "Waiting for the host's available starting sets and difficulties."
	)
	if %RunSelection.text != result_text:
		%RunSelection.text = result_text
	%RunSelection.tooltip_text = %VoteHelp.text + "\n" + %VoteHelp.tooltip_text


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
	_resize_tables()


func set_rejoin(code: String):
	var available = not code.is_empty() and not _room_open
	%Rejoin.visible = available
	%RejoinNote.visible = available
	%Rejoin.tooltip_text = "Rejoin room " + code if available else ""


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


func _ensure_expansion_toggles() -> void:
	if not _expansion_checks.is_empty():
		return
	var settings = %MultiplayerBalls.get_parent().get_parent()
	var row = HBoxContainer.new()
	row.name = "ExpansionSetting"
	row.add_theme_constant_override("separation", 8)
	var label = Label.new()
	label.text = "Sets"
	row.add_child(label)
	var flow = HFlowContainer.new()
	flow.name = "ExpansionSets"
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 4)
	for set_id in ExpansionRegistry.SET_IDS:
		var check = CheckBox.new()
		check.text = ExpansionRegistry.SET_LABELS[set_id]
		check.focus_mode = Control.FOCUS_ALL
		var captured = set_id
		check.toggled.connect(
			func(enabled): expansion_set_requested.emit(captured, enabled)
		)
		flow.add_child(check)
		_expansion_checks[set_id] = check
	row.add_child(flow)
	settings.add_child(row)
	settings.move_child(row, %MultiplayerBalls.get_parent().get_index() + 1)


func _render_expansion_toggles(state: Dictionary, is_host: bool, started: bool) -> void:
	_ensure_expansion_toggles()
	var flags = ExpansionRegistry.normalize_flags(state.get("expansion_sets", {}))
	for set_id in ExpansionRegistry.SET_IDS:
		var check: CheckBox = _expansion_checks[set_id]
		check.set_pressed_no_signal(bool(flags.get(set_id, false)))
		check.disabled = not is_host or started


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
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.x = 240
		card.add_theme_stylebox_override("panel", _table_card_style(color))
		%Tables.add_child(card)
		var content = VBoxContainer.new()
		content.add_theme_constant_override("separation", 8)
		card.add_child(content)
		var title = Label.new()
		title.text = "TABLE %d" % (table_id + 1)
		if _skinned():
			title.add_theme_stylebox_override("normal", skin.style("plaque_brass", PLAQUE_CONTENT))
			title.add_theme_font_size_override("font_size", 16)
			title.add_theme_color_override("font_color", PLAQUE_INK)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		else:
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
		# Long rosters scroll inside their card so the lobby body itself never has to.
		var roster = ScrollContainer.new()
		roster.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
		roster.custom_minimum_size.y = ROSTER_MIN_HEIGHT
		content.add_child(roster)
		var players = GridContainer.new()
		players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		players.add_theme_constant_override("h_separation", 8)
		players.add_theme_constant_override("v_separation", ROW_SPACING)
		roster.add_child(players)
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
		join.custom_minimum_size.y = TABLE_BUTTON_HEIGHT
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
	if _skinned() and table == own_table:
		watch.icon = skin.texture("icon_return")
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
	panel.add_theme_stylebox_override("panel", _player_row_style())
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	row.add_child(_player_marker(color))
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 2)
	row.add_child(content)
	var name_label = Label.new()
	name_label.text = str(player.name)
	name_label.add_theme_font_size_override("font_size", 16)
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
	detail.add_theme_font_size_override("font_size", 11)
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
	var margin_left = margin
	var margin_right = margin
	var margin_bottom = BOTTOM_MARGIN
	if _skinned():
		var inlay = inlay_rect()
		margin_left = maxi(margin, ceili(inlay.position.x) + INLAY_PADDING)
		margin_right = maxi(margin, ceili(size.x - inlay.end.x) + INLAY_PADDING)
		# The action row may sit on the rail; without it the body must stop at the felt.
		if not %Actions.visible:
			margin_bottom = maxi(BOTTOM_MARGIN, ceili(size.y - inlay.end.y) + INLAY_PADDING)
	$Margin.add_theme_constant_override("margin_left", margin_left)
	$Margin.add_theme_constant_override("margin_right", margin_right)
	$Margin.add_theme_constant_override("margin_bottom", margin_bottom)
	var width = size.x - margin_left - margin_right
	var heading = $Margin/Layout/Body/Content/Room/RoomHeading
	var heading_width = (
		%RoomTitle.get_combined_minimum_size().x
		+ %Settings.get_combined_minimum_size().x
		+ %Count.get_combined_minimum_size().x
		+ heading.get_theme_constant("separation") * 2
	)
	var settings_parent = heading if width >= heading_width else %Room
	if %Settings.get_parent() != settings_parent:
		%Settings.reparent(settings_parent)
		settings_parent.move_child(%Settings, 1)
	%DeckVotes.custom_minimum_size.x = minf(DECK_ROW_WIDTH, width)
	%DifficultyVotes.custom_minimum_size.x = minf(DIFFICULTY_ROW_WIDTH, width)
	var columns = clampi(int((width + 16) / 256), 1, 4)
	%Tables.columns = mini(columns, _state.get("table_count", 1))
	var card_width = (width - (%Tables.columns - 1) * 16) / %Tables.columns
	for players in _player_grids:
		players.columns = clampi(int((card_width - 16) / 240), 1, 4)
	_place_header_plank()


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
	if _skinned():
		_apply_skin(palette)
		return
	for button in [%Host, %Rejoin, %Ready, %Start]:
		button.add_theme_stylebox_override("normal", _box(FELT.darkened(0.13), FELT, 1))
		button.add_theme_stylebox_override("hover", _box(FELT.lightened(0.12), GOLD, 1))
		button.add_theme_color_override("font_color", Color("08241f"))
		button.add_theme_color_override("font_hover_color", Color("08241f"))
	%Bench.add_theme_stylebox_override("panel", _box(Color("171f25"), Color("544a33"), 1))


func _skinned() -> bool:
	return skin != null and skin.has_art()


# Pool-hall chalkboard art. Content margins match the flat styles so control sizes stay put.
func _apply_skin(palette: Theme) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		palette.set_stylebox(state, "Button", skin.button_style("dark", state, BUTTON_CONTENT))
		var dropdown = (
			skin.disabled("field_dropdown", DROPDOWN_CONTENT)
			if state == "disabled"
			else skin.style("field_dropdown", DROPDOWN_CONTENT)
		)
		palette.set_stylebox(state, "OptionButton", dropdown)
	palette.set_stylebox("focus", "OptionButton", _box(Color(0, 0, 0, 0), GOLD, 2))
	palette.set_icon("arrow", "OptionButton", skin.blank())
	palette.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.55))
	palette.set_constant("outline_size", "Button", 3)
	palette.set_constant("h_separation", "Button", 8)
	palette.set_constant("icon_max_width", "Button", 28)
	palette.set_stylebox("normal", "LineEdit", skin.style("field_text", FIELD_CONTENT))
	palette.set_stylebox("read_only", "LineEdit", skin.disabled("field_text", FIELD_CONTENT))
	palette.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), GOLD, 2))
	palette.set_stylebox("scroll", "VScrollBar", _chalk_bar(CHALK_TRACK))
	palette.set_stylebox("grabber", "VScrollBar", _chalk_bar(CHALK_GRABBER))
	palette.set_stylebox("grabber_highlight", "VScrollBar", _chalk_bar(CHALK_GRABBER_HOVER))
	palette.set_stylebox("grabber_pressed", "VScrollBar", _chalk_bar(Color.WHITE))
	palette.set_stylebox("panel", "PopupMenu", skin.style("panel_chalk", [18, 14, 18, 14]))
	palette.set_stylebox("hover", "PopupMenu", skin.style("slot_chalk", [8, 4, 8, 4]))
	for button in [%Host, %Rejoin, %Ready, %Start]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(
				state, skin.button_style("green", state, BUTTON_CONTENT)
			)
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
	%Bench.add_theme_stylebox_override("panel", skin.style("panel_chalk", TABLE_CARD_CONTENT))
	var icons = {
		%Copy: "icon_copy",
		%Invite: "icon_invite",
		%Close: "icon_close",
		%Leave: "icon_leave",
		%Return: "icon_return",
		%ApproveReturn: "icon_approve",
		%CancelReturn: "icon_deny"
	}
	for button in icons:
		button.icon = skin.texture(icons[button])
	%VoteHelp.text = "Chalk check: your vote · Gold gem: current result · Chips show live votes."
	$Background.visible = false
	$TopRail.visible = false
	$Margin/Layout/Divider.visible = false
	var backdrop = TextureRect.new()
	backdrop.name = "Backdrop"
	backdrop.texture = skin.texture("backdrop")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	move_child(backdrop, 0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_header_plank = Panel.new()
	_header_plank.name = "HeaderPlank"
	_header_plank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_plank.add_theme_stylebox_override("panel", skin.style("header_plank"))
	add_child(_header_plank)
	move_child(_header_plank, 1)
	$Margin/Layout/Header.item_rect_changed.connect(_place_header_plank)
	var brand = $Margin/Layout/Header/Brand
	brand.get_node("Title").visible = false
	brand.get_node("Together").visible = false
	var logo = TextureRect.new()
	logo.name = "Logo"
	logo.texture = skin.texture("logo")
	logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 52)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	logo.tooltip_text = "Ultrapool Together"
	brand.add_child(logo)


# The backdrop's felt area in local coordinates, following its keep-aspect-covered scaling.
func inlay_rect() -> Rect2:
	if not _skinned():
		return Rect2(Vector2.ZERO, size)
	var texture_size: Vector2 = skin.texture("backdrop").get_size()
	var shown = texture_size * maxf(size.x / texture_size.x, size.y / texture_size.y)
	var origin = (size - shown) / 2
	return Rect2(origin + BACKDROP_INLAY.position * shown, BACKDROP_INLAY.size * shown)


func _place_header_plank() -> void:
	if _header_plank == null:
		return
	var header: Control = $Margin/Layout/Header
	_header_plank.position = header.global_position - global_position - HEADER_PLANK_GROW
	_header_plank.size = header.size + HEADER_PLANK_GROW * 2


func _chalk_bar(color: Color) -> StyleBoxFlat:
	var bar = StyleBoxFlat.new()
	bar.bg_color = color
	bar.set_corner_radius_all(3)
	bar.content_margin_left = 3
	bar.content_margin_right = 3
	return bar


func _table_card_style(color: Color) -> StyleBox:
	if _skinned():
		return skin.style("panel_chalk", TABLE_CARD_CONTENT)
	var card_style = _box(Color("102b30"), color.darkened(0.4), 2)
	card_style.set_content_margin_all(12)
	return card_style


func _player_row_style() -> StyleBox:
	if _skinned():
		return skin.style("slot_chalk", ROW_CONTENT)
	var style = _box(Color("0b1d24"), Color("25434a"), 1)
	style.content_margin_left = ROW_CONTENT[0]
	style.content_margin_top = ROW_CONTENT[1]
	style.content_margin_right = ROW_CONTENT[2]
	style.content_margin_bottom = ROW_CONTENT[3]
	return style


func _player_marker(color: Color) -> Control:
	if _skinned():
		var chip = TextureRect.new()
		chip.texture = skin.texture("chip_voter")
		chip.custom_minimum_size = PLAYER_CHIP_SIZE
		chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.modulate = color
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return chip
	var marker = ColorRect.new()
	marker.custom_minimum_size = Vector2(5, 0)
	marker.color = color
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return marker


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

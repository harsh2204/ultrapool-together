extends Node
## After-hours rack. Shared discussion layout over immutable final builds.
## PERF-010/026: retain controls; reconcile only changed summary/build data.

const EndRunState = preload("end_run_state.gd")
const CueModels = preload("cue_models.gd")
const CrtStack = preload("crt_stack.gd")
const CREAM = Color("f0e6cb")
const MUTED = Color("aebeb1")


class Felt:
	extends Control
	var _style: StyleBoxFlat
	var chalk = 0.0:
		set(value):
			chalk = value
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("101a18"))
		var inset = Rect2(Vector2(12, 12), size - Vector2(24, 24))
		draw_style_box(_felt_style(), inset)
		for x in [22.0, size.x * 0.5, size.x - 22.0]:
			for y in [22.0, size.y - 22.0]:
				draw_circle(Vector2(x, y), 8.0, Color("091510"))
		# A single chalk rack settles onto the felt when standings become final.
		if chalk > 0.0 and size.x >= 760.0:
			var center = Vector2(size.x - 90, 79)
			var points = PackedVector2Array(
				[
					center + Vector2(0, -31),
					center + Vector2(37, 31),
					center + Vector2(-37, 31),
					center + Vector2(0, -31)
				]
			)
			draw_polyline(points, Color(0.93, 0.90, 0.76, chalk), 2.0, true)
			for row in range(3):
				for column in range(row + 1):
					draw_circle(
						center + Vector2((column - row * 0.5) * 15, row * 13 - 9),
						5.5,
						Color(0.93, 0.90, 0.76, chalk * 0.8)
					)

	func _felt_style() -> StyleBoxFlat:
		if _style != null:
			return _style
		var style = StyleBoxFlat.new()
		style.bg_color = Color("173e32")
		style.border_color = Color("654c31")
		style.set_border_width_all(5)
		style.set_corner_radius_all(20)
		_style = style
		return style


var _controller: Node
var _ui: Node
var _layer: CanvasLayer
var _root: Control
var _felt: Felt
var _heading: Label
var _status: Label
var _table_title: Label
var _stats: Label
var _empty: Label
var _tabs: Array[Button] = []
var _rack: Control
var _discussion_hint: Label
var _reset: Button
var _cue_label: Label
var _continue: Button
var _selected = -1
var _signature: Array = []
var _build_key: Array = []
var _dismissed = false
var _celebrated = false
var _chalk_tween: Tween
var _native_menu: Node
var _native_visibility: Array = []
var _native_focus: Control
var _session_active = false
var _holding_table = -1
var _pending_pickup = -1
var _pending_release = -2
var _last_drag_position = Vector2(0.5, 0.5)
var _have_drag_position = false


func setup(controller: Node) -> void:
	_controller = controller
	_ui = get_node("/root/UIManager")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_controller.end_run_discussion_changed.connect(refresh_discussion)
	_controller.end_run_discussion_rejected.connect(_discussion_rejected)
	set_process(false)


func begin_session() -> void:
	end_session()
	_session_active = true
	_dismissed = false
	_selected = _controller.table_id
	set_process(true)


func end_session() -> void:
	_cancel_drag()
	# Match teardown invalidates any pickup still awaiting its old host grant.
	_holding_table = -1
	_pending_pickup = -1
	_pending_release = -2
	_have_drag_position = false
	set_process(false)
	_session_active = false
	_restore_native()
	if _chalk_tween != null and _chalk_tween.is_valid():
		_chalk_tween.kill()
	_chalk_tween = null
	_dismissed = false
	_celebrated = false
	_signature = []
	_build_key = []
	_selected = -1
	if _root != null:
		_root.hide()
		_felt.chalk = 0.0
		_rack.clear()


func is_open() -> bool:
	return _root != null and _root.visible


func reopen() -> void:
	if not _session_active or not _controller.active or not _controller.finished:
		return
	_dismissed = false
	_controller.spectator.close()
	_controller._set_panel(false)
	refresh()


func refresh() -> void:
	if not _session_active or _root == null or not _controller.active or not _controller.finished:
		return
	var summaries: Array = _controller.lobby.get("table_summaries", [])
	var available: Array = []
	for table in range(mini(int(_controller.lobby.get("table_count", 0)), EndRunState.MAX_TABLES)):
		available.append(_controller.final_builds.has_table(table))
	var next = [summaries, available, _controller.lobby.get("players", [])]
	if next != _signature:
		_signature = next.duplicate(true)
		_refresh_summaries(summaries, available)
	_update_visibility()


func _process(_delta: float) -> void:
	_update_visibility()
	if _controller.active and _controller.finished and not _dismissed:
		_suppress_native()


func _update_visibility() -> void:
	var show_review = (
		_session_active
		and _controller.active
		and _controller.finished
		and not _dismissed
		and not _controller.panel.visible
		and not _controller.is_spectating()
	)
	if _root.visible != show_review:
		if not show_review:
			_cancel_drag()
		_root.visible = show_review
		if show_review:
			_suppress_native()
			_tabs[maxi(_selected, 0)].grab_focus()


func _suppress_native() -> void:
	if not is_instance_valid(_ui) or not _ui.game_over_menu.is_open:
		return
	var menu = _ui.game_over_menu
	if _native_menu != menu:
		_restore_native()
		_native_menu = menu
		_native_visibility = [menu.canvas.visible, menu.underlay_canvas.visible]
	# Native open/setup, audio, final stats, popup registration and pause all run
	# normally. Only its presentation is covered; no native scene/script replacement.
	var focus = get_viewport().gui_get_focus_owner()
	if focus != null and menu.is_ancestor_of(focus):
		_native_focus = focus
		focus.release_focus()
		if _root.visible:
			_tabs[maxi(_selected, 0)].grab_focus()
	if menu.canvas.visible:
		menu.canvas.hide()
	if menu.underlay_canvas.visible:
		menu.underlay_canvas.hide()


func _restore_native() -> void:
	if is_instance_valid(_native_menu) and _native_menu.is_open:
		_native_menu.canvas.visible = _native_visibility[0]
		_native_menu.underlay_canvas.visible = _native_visibility[1]
		if is_instance_valid(_native_focus) and _native_focus.is_visible_in_tree():
			_native_focus.grab_focus()
	_native_menu = null
	_native_visibility = []
	_native_focus = null


func _exit_tree() -> void:
	_restore_native()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		if _holding_table >= 0:
			_cancel_drag()
		else:
			_open_lobby()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	CrtStack.place_under(_layer, self, 1)
	add_child(_layer)
	_root = Control.new()
	_root.name = "AfterHoursRack"
	_root.theme = _controller.ui_root.theme
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_felt = Felt.new()
	_felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_felt)
	_felt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_felt.resized.connect(_felt.queue_redraw)
	var margin = MarginContainer.new()
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	column.add_child(_label("AFTER HOURS", 11, MUTED))
	_heading = _label("Leave it on the felt.", 26)
	column.add_child(_heading)
	_status = _label("Your table is done. Take a look around.", 14, MUTED)
	column.add_child(_status)
	var tabs = HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 8)
	column.add_child(tabs)
	for table in range(EndRunState.MAX_TABLES):
		var button = _button("Table %d" % (table + 1), _select_table.bind(table))
		button.toggle_mode = true
		button.hide()
		tabs.add_child(button)
		_tabs.append(button)
	_table_title = _label("", 18)
	column.add_child(_table_title)
	_stats = _label("", 13, MUTED)
	column.add_child(_stats)
	var content = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size.y = 180
	column.add_child(content)
	_rack = load(get_script().resource_path.get_base_dir().path_join("end_run_native_rack.gd")).new()
	content.add_child(_rack)
	_rack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rack.setup(_controller)
	_rack.pickup_requested.connect(_on_pickup)
	_rack.motion_requested.connect(_on_motion)
	_rack.release_requested.connect(_on_release)
	_rack.cancel_requested.connect(_cancel_drag)
	_empty = _label("Setting out the final rack…", 18, MUTED)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_empty)
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_discussion_hint = _label("Drag balls to discuss this rack. Everyone sees the changes.", 13, MUTED)
	column.add_child(_discussion_hint)
	_cue_label = _label("", 12, MUTED)
	column.add_child(_cue_label)
	var footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	footer.add_child(_button("Lobby & live tables", _open_lobby))
	_reset = _button("Reset arrangement", _reset_arrangement)
	_reset.tooltip_text = "Restore this table's recorded final arrangement for everyone."
	footer.add_child(_reset)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_continue = _button("Continue", _continue_to_end)
	_continue.tooltip_text = "Finish reviewing and open your result screen."
	footer.add_child(_continue)
	_root.hide()


func _refresh_summaries(summaries: Array, available: Array) -> void:
	var complete = EndRunState.complete(summaries)
	var mode = (
		"coop" if available.size() == 1 else str(_controller.lobby.get("match_mode", "score"))
	)
	var winners = EndRunState.winner_tables(summaries, mode)
	var finished_count = 0
	for summary in summaries:
		if summary.get("finished", false):
			finished_count += 1
	for table in range(_tabs.size()):
		var button = _tabs[table]
		button.visible = table < available.size()
		if not button.visible:
			continue
		button.text = "Table %d%s" % [table + 1, " · chalked" if table in winners else ""]
		button.set_pressed_no_signal(table == _selected)
	var builds_ready = complete
	for summary in summaries:
		if (
			not summary.get("closed", false)
			and not _controller.final_builds.has_table(summary.table)
		):
			builds_ready = false
	_continue.disabled = not builds_ready
	if complete:
		if winners.is_empty():
			_heading.text = "Last call. Good game."
		elif winners.size() > 1:
			_heading.text = "Room for another rack."
		elif mode == "coop":
			_heading.text = "Run complete. Rack ’em up."
		else:
			_heading.text = "Table %d leaves its mark." % (winners[0] + 1)
		_status.text = (
			"A tie. Both tables share the finish."
			if winners.size() == 2
			else (
				"A tie. The leading tables share the finish."
				if winners.size() > 2
				else "All tables are in. Browse their builds before you head out."
			)
		)
		if not _celebrated and not winners.is_empty():
			_celebrated = true
			_chalk_tween = create_tween()
			_chalk_tween.tween_property(_felt, "chalk", 0.9, 0.65).set_trans(Tween.TRANS_SINE)
	else:
		_heading.text = "Leave it on the felt."
		_status.text = (
			"%d/%d tables finished · Browse a final rack or watch the remaining tables."
			% [finished_count, available.size()]
		)
	if _selected < 0 or _selected >= available.size():
		_selected = _controller.table_id
	_render_table(summaries)


func _select_table(table: int) -> void:
	_cancel_drag()
	_selected = table
	for index in range(_tabs.size()):
		_tabs[index].set_pressed_no_signal(index == table)
	_render_table(_controller.lobby.get("table_summaries", []))


func _render_table(summaries: Array) -> void:
	var summary: Dictionary = {}
	for entry in summaries:
		if entry.table == _selected:
			summary = entry
	var names: Array[String] = []
	for member in _controller._members(_selected, false):
		names.append(str(member.name))
	_table_title.text = "Table %d  /  %s" % [_selected + 1, " + ".join(names)]
	_stats.text = (
		"%s · %.0f points · %d shots · Round %d"
		% [
			summary.get("status", "Playing"),
			summary.get("score", 0.0),
			summary.get("shots_used", 0),
			summary.get("round", 1)
		]
	)
	_empty.text = (
		"The table closed before its final build arrived."
		if summary.get("closed", false)
		else (
			"Setting out the final rack…"
			if summary.get("finished", false)
			else "Still playing. Its final build will appear here."
		)
	)
	var key = [_selected, _controller.final_builds.has_table(_selected)]
	if key == _build_key:
		return
	_build_key = key
	var record = _controller.final_builds.get_record(_selected)
	_empty.visible = record.is_empty()
	_rack.visible = not record.is_empty()
	_cue_label.visible = not record.is_empty()
	_discussion_hint.visible = not record.is_empty()
	_reset.disabled = record.is_empty()
	if record.is_empty():
		_rack.clear()
		return
	var discussion: Dictionary = _controller.end_discussion_snapshot(_selected)
	_rack.present(record, discussion.get("order", []))
	var cues: Array[String] = []
	for member in record.cues.players:
		cues.append(
			"%s: %s" % [_controller._player_name(member.id), CueModels.entry(member.equipped).label]
		)
	_cue_label.text = "Cues · " + " · ".join(cues)
	refresh_discussion(_selected)


func refresh_discussion(table: int) -> void:
	if _controller == null:
		return
	var snapshot: Dictionary = _controller.end_discussion_snapshot(table)
	if snapshot.is_empty():
		return
	var drag: Dictionary = snapshot.get("drag", {})
	var actor = int(drag.get("actor", 0))
	var local_actor: int = _controller._local_id
	if not _session_active or table != _selected or _rack == null or not _rack.visible:
		# A reliable begin may arrive after a tab change or pointer cancellation.
		# Retire its hold even though that table is no longer being rendered.
		if table == _holding_table and actor == local_actor:
			_holding_table = -1
			_pending_pickup = -1
			_pending_release = -2
			_have_drag_position = false
			_controller.cancel_end_drag(table, int(drag.get("token", 0)))
		elif table == _holding_table and drag.is_empty() and _pending_pickup < 0:
			_holding_table = -1
			_pending_release = -2
			_have_drag_position = false
		return
	var actor_name: String = _controller._player_name(actor) if actor > 0 else ""
	_rack.apply_discussion(snapshot, local_actor, actor_name)
	_reset.disabled = not drag.is_empty()
	if actor > 0:
		_discussion_hint.text = (
			"Place the ball in a slot. Escape cancels."
			if actor == local_actor else actor_name + " is moving a ball."
		)
	else:
		_discussion_hint.text = "Drag balls to discuss this rack. Everyone sees the changes."
	# A quick pointer release can precede the reliable pickup acknowledgement.
	# Retain exactly one intended drop until its host-issued token arrives.
	if actor == local_actor and _holding_table == table:
		_pending_pickup = -1
		var token = int(drag.get("token", 0))
		if _have_drag_position:
			_have_drag_position = false
			_controller.move_end_drag(table, token, _last_drag_position)
		if _pending_release != -2:
			var target = _pending_release
			_pending_release = -2
			if target < 0:
				_controller.cancel_end_drag(table, token)
			else:
				_controller.drop_end_drag(table, token, target)
	elif drag.is_empty() and _pending_pickup < 0:
		_holding_table = -1


func _on_pickup(original_slot: int) -> void:
	if not is_open() or _selected < 0:
		_rack.cancel_local_drag()
		return
	if _holding_table >= 0 and _pending_pickup >= 0:
		_rack.cancel_local_drag()
		_discussion_hint.text = "Waiting for your previous move…"
		return
	_holding_table = _selected
	_pending_pickup = original_slot
	_pending_release = -2
	_have_drag_position = false
	_discussion_hint.text = "Picking up ball…"
	_controller.request_end_drag(_selected, original_slot)


func _on_motion(position: Vector2) -> void:
	if _holding_table < 0:
		return
	_last_drag_position = position
	var snapshot: Dictionary = _controller.end_discussion_snapshot(_holding_table)
	var drag: Dictionary = snapshot.get("drag", {})
	if int(drag.get("actor", 0)) == _controller._local_id:
		_controller.move_end_drag(_holding_table, int(drag.token), position)
	else:
		_have_drag_position = true


func _on_release(target_slot: int) -> void:
	if _holding_table < 0:
		return
	var table = _holding_table
	var drag: Dictionary = _controller.end_discussion_snapshot(table).get("drag", {})
	if int(drag.get("actor", 0)) != _controller._local_id:
		_pending_release = target_slot
		return
	# Retain ownership until the reliable response clears the authoritative hold.
	_pending_pickup = -1
	_pending_release = -2
	_have_drag_position = false
	if target_slot < 0:
		_controller.cancel_end_drag(table, int(drag.token))
	else:
		_controller.drop_end_drag(table, int(drag.token), target_slot)


func _cancel_drag() -> void:
	if _rack != null:
		_rack.cancel_local_drag()
	if _holding_table < 0 or _controller == null:
		return
	# Keep an unacknowledged pickup's cancel intent until its token arrives,
	# including when this player changes tabs or leaves the review.
	_on_release(-1)


func _discussion_rejected(table: int, action: String, reason: String) -> void:
	var drag: Dictionary = _controller.end_discussion_snapshot(table).get("drag", {})
	var own_hold = (
		_controller.active and _controller.finished
		and int(drag.get("actor", 0)) == _controller._local_id
	)
	if table == _holding_table:
		_pending_pickup = -1
		_pending_release = -2
		_have_drag_position = false
		if not own_hold:
			_holding_table = -1
	if own_hold and action in ["drop", "cancel"]:
		_holding_table = table
	if table == _selected and _rack != null:
		_rack.cancel_local_drag()
		refresh_discussion(table)
		_discussion_hint.text = reason
		if own_hold and action == "cancel":
			_discussion_hint.text += " Press Escape to put the ball back."
	# A rejected drop retains the server hold. Cancel once with its current
	# revision/token; never loop on a rejected cancellation. Escape can retry.
	if own_hold and action == "drop":
		_controller.cancel_end_drag(table, int(drag.token))


func _reset_arrangement() -> void:
	if _selected >= 0 and not _reset.disabled:
		_controller.reset_end_discussion(_selected)


func _continue_to_end() -> void:
	if _continue.disabled or not EndRunState.complete(_controller.lobby.get("table_summaries", [])):
		return
	_cancel_drag()
	_dismissed = true
	_root.hide()
	_restore_native()
	if not _ui.game_over_menu.is_open:
		_controller._set_panel(true)


func _open_lobby() -> void:
	_cancel_drag()
	_controller._set_panel(true)
	_update_visibility()


func _label(text: String, size: int, color: Color = CREAM) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(callback)
	return button

extends Node
## Playing-table overlay for TOGETHER called shots plus every ability indicator
## drawn by ability_overlay.gd (MOD-01..12). Host and guest see the same drawing;
## the spectator view reuses the same helper for watched tables.

const AbilityOverlay = preload("ability_overlay.gd")
const CALL_COLOR = AbilityOverlay.CALL_COLOR
const BOUNTY_COLOR = AbilityOverlay.BOUNTY_COLOR

var _controller: Node
var _service: Node
var _overlay: Control
var _hint: Label
var _data: Dictionary = {}
var _expansion: Dictionary = {}
var _cue_feedback: Dictionary = {}
var _last_call: Dictionary = {}
var _ball_ids: Array[int] = []
var _selected_ball = 0
var _call_press = false
var _names: Dictionary = {}
var _names_at = 0
var _signature: Array = []
var _hint_text = ""


func setup(controller: Node, service: Node) -> void:
	_controller = controller
	_service = service
	_overlay = AbilityOverlay.make_overlay(draw_overlay)
	_controller.ui_root.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hint.add_theme_constant_override("shadow_offset_x", 1)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_controller.ui_root.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.offset_left = -350
	_hint.offset_right = -20
	_hint.offset_top = -50
	_hint.offset_bottom = -20
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	clear()


func clear() -> void:
	_data = {}
	_expansion = {}
	_cue_feedback = {}
	_last_call.clear()
	_ball_ids.clear()
	_selected_ball = 0
	_call_press = false
	_names.clear()
	_names_at = 0
	_signature = []
	_hint_text = ""
	if _hint != null:
		_hint.hide()
		_overlay.hide()


func refresh(data: Dictionary, expansion: Dictionary = {}, cue_feedback: Dictionary = {}) -> void:
	_data = data
	_expansion = expansion
	_cue_feedback = cue_feedback
	var visible: bool = (
		_controller.active
		and not _controller.is_spectating()
		and _controller.latest_state.get("table_active", false)
		and not _controller.latest_state.get("in_shop", false)
		and not _controller.finished
		and not _controller.panel.visible
		and not _controller.shop_sync.is_open()
	)
	if _overlay.visible != visible:
		_overlay.visible = visible
	if not visible:
		_set_hint("")
		_signature = []
		return
	_refresh_names()
	_ball_ids.clear()
	for ball in data.get("balls", []):
		if ball.alive and ball.callable and "TOGETHER_CALL" in ball.kinds:
			_ball_ids.append(ball.id)
	if not _selected_ball in _ball_ids:
		_selected_ball = _ball_ids[0] if not _ball_ids.is_empty() else 0
	var called: Dictionary = data.get("call", {})
	if not called.is_empty() and called != _last_call:
		_selected_ball = called.ball
	_last_call = called.duplicate()
	var choosing: bool = _can_call()
	var hint = ""
	if choosing:
		hint = "Called Shot · click a pocket"
		if _ball_ids.size() > 1:
			hint = "Called Shot · choose a ball, then a pocket"
	elif not called.is_empty() and not data.get("pending", false):
		hint = "%s called the highlighted pocket" % _player_name(called.actor)
	_set_hint(hint)
	# PERF-028: redraw only when display state or a tracked ball's position changed.
	var signature: Array = AbilityOverlay.signature(data, expansion, [_selected_ball, choosing], cue_feedback)
	for pair in AbilityOverlay.tracked_balls(data, expansion):
		signature.append(_service.ball_position(pair[0], pair[1]))
	if signature != _signature:
		_signature = signature
		_overlay.queue_redraw()


func _set_hint(text: String) -> void:
	if text == _hint_text:
		return
	_hint_text = text
	if text.is_empty():
		_hint.hide()
		return
	_hint.text = text
	_hint.show()


func _can_call() -> bool:
	return (
		_overlay.visible
		and not _ball_ids.is_empty()
		and not _data.get("pending", false)
		and not _controller.shot_pending
		and _data.get("last_shooter", 0) > 0
		and _data.last_shooter == _controller.transport.local_id()
		and not get_node("/root/UIManager").is_popup_open()
	)


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed and _choose_at(event.position):
		_call_press = true
		get_viewport().set_input_as_handled()
	elif not event.pressed and _call_press:
		get_viewport().set_input_as_handled()
		_release_call_press.call_deferred()


func _release_call_press() -> void:
	_call_press = false


func blocks_shot_input() -> bool:
	return _call_press


func _choose_at(position: Vector2) -> bool:
	if not _can_call():
		return false
	var transform = get_viewport().get_canvas_transform()
	for ball in _data.get("balls", []):
		if not ball.id in _ball_ids:
			continue
		var center: Vector2 = transform * _service.ball_position(ball.id, ball.position)
		if position.distance_to(center) <= 18.0:
			_selected_ball = ball.id
			_signature = []
			_overlay.queue_redraw()
			return true
	for pocket in _data.get("pockets", []):
		if not pocket.open or pocket.index < 0 or pocket.index >= 6:
			continue
		if position.distance_to(transform * pocket.position) <= 25.0:
			_service.request_call(_selected_ball, pocket.index)
			return true
	return false


func _refresh_names() -> void:
	var now = Time.get_ticks_msec()
	if now < _names_at:
		return
	_names_at = now + 1000
	_names.clear()
	for person in _controller.transport.participants():
		_names[person.id] = person.name


func _player_name(id: int) -> String:
	return str(_names.get(id, "Player")).left(24)


func _resolve(id: int, raw: Vector2) -> Vector2:
	return _service.ball_position(id, raw)


func draw_overlay(canvas: CanvasItem) -> void:
	AbilityOverlay.draw(
		canvas,
		_hint.get_theme_font("font"),
		get_viewport().get_canvas_transform(),
		_resolve,
		Vector2.ZERO,
		_player_name,
		_data,
		_expansion,
		_selected_ball,
		_can_call(),
		_cue_feedback
	)

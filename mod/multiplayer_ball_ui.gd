extends Node

const CALL_COLOR = Color(0.65, 0.88, 1.0)
const BOUNTY_COLOR = Color(1.0, 0.76, 0.25)


class BallOverlay:
	extends Control
	var ui: Node

	func _draw() -> void:
		ui.draw_overlay(self)


var _controller: Node
var _service: Node
var _overlay: BallOverlay
var _hint: Label
var _data: Dictionary = {}
var _last_call: Dictionary = {}
var _ball_ids: Array[int] = []
var _selected_ball = 0
var _call_press = false
var _names: Dictionary = {}
var _names_at = 0


func setup(controller: Node, service: Node) -> void:
	_controller = controller
	_service = service
	_overlay = BallOverlay.new()
	_overlay.ui = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_last_call.clear()
	_ball_ids.clear()
	_selected_ball = 0
	_call_press = false
	_names.clear()
	_names_at = 0
	if _hint != null:
		_hint.hide()
		_overlay.hide()


func refresh(data: Dictionary) -> void:
	_data = data
	_overlay.visible = (
		_controller.active
		and not _controller.is_spectating()
		and _controller.latest_state.get("table_active", false)
		and not _controller.latest_state.get("in_shop", false)
		and not _controller.finished
		and not _controller.panel.visible
		and not _controller.shop_sync.is_open()
	)
	_hint.hide()
	if not _overlay.visible:
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
	if _can_call():
		_hint.text = "Called Shot · click a pocket"
		if _ball_ids.size() > 1:
			_hint.text = "Called Shot · choose a ball, then a pocket"
		_hint.show()
	elif not called.is_empty() and not data.get("pending", false):
		_hint.text = "%s called the highlighted pocket" % _player_name(called.actor)
		_hint.show()
	_overlay.queue_redraw()


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


func draw_overlay(canvas: Control) -> void:
	var transform = get_viewport().get_canvas_transform()
	var called: Dictionary = _data.get("call", {})
	var choosing = _can_call()
	for pocket in _data.get("pockets", []):
		if not pocket.open or pocket.index < 0 or pocket.index >= 6:
			continue
		if pocket.index == called.get("pocket", -1):
			canvas.draw_circle(transform * pocket.position, 21.0, CALL_COLOR, false, 2.0, true)
	for ball in _data.get("balls", []):
		if not ball.alive:
			continue
		var position: Vector2 = transform * _service.ball_position(ball.id, ball.position)
		if "TOGETHER_RELAY" in ball.kinds and ball.marker > 0:
			var color = Color.from_hsv(posmod(hash(str(ball.marker)), 360) / 360.0, 0.55, 1.0)
			canvas.draw_circle(position, 14.0, color, false, 1.5, true)
			_caption(canvas, position + Vector2(17, 20), _player_name(ball.marker), color)
		if "TOGETHER_PATIENCE" in ball.kinds:
			for pip in range(mini(ball.charge, 3)):
				canvas.draw_circle(position + Vector2((pip - 1) * 6, -19), 2.0, CALL_COLOR)
		if "TOGETHER_BOUNTY" in ball.kinds:
			canvas.draw_circle(position, 13.0, BOUNTY_COLOR, false, 1.5, true)
			for axis in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
				canvas.draw_line(position + axis * 10, position + axis * 17, BOUNTY_COLOR, 1.5)
		if ball.id == called.get("ball", -1) or (choosing and ball.id == _selected_ball):
			canvas.draw_circle(position, 17.0, CALL_COLOR, false, 1.5, true)


func _caption(canvas: Control, position: Vector2, text: String, color: Color) -> void:
	var font = _hint.get_theme_font("font")
	canvas.draw_string_outline(
		font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK
	)
	canvas.draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

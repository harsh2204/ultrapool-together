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
var _panel: PanelContainer
var _status: Label
var _choices: HBoxContainer
var _balls: OptionButton
var _pockets: OptionButton
var _call_button: Button
var _data: Dictionary = {}
var _ball_ids: Array[int] = []
var _pocket_indices: Array[int] = []
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
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controller.ui_root.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -340
	_panel.offset_right = -16
	_panel.offset_top = -118
	_panel.offset_bottom = -16
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var background = StyleBoxFlat.new()
	background.bg_color = Color(0.04, 0.05, 0.07, 0.92)
	background.set_content_margin_all(10)
	background.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", background)
	var column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)
	var title = Label.new()
	title.text = "Called Shot"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	_status = Label.new()
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_font_size_override("font_size", 13)
	column.add_child(_status)
	_choices = HBoxContainer.new()
	_choices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_choices)
	_balls = OptionButton.new()
	_balls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_balls.tooltip_text = "Choose a ball for your teammate's next shot."
	_choices.add_child(_balls)
	_pockets = OptionButton.new()
	_choices.add_child(_pockets)
	_call_button = Button.new()
	_call_button.text = "Call pocket"
	_call_button.pressed.connect(_submit_call)
	_choices.add_child(_call_button)
	clear()


func clear() -> void:
	_data = {}
	_ball_ids.clear()
	_pocket_indices.clear()
	_names.clear()
	_names_at = 0
	if _panel != null:
		_panel.hide()
		_overlay.hide()
		_balls.clear()
		_pockets.clear()


func refresh(data: Dictionary) -> void:
	_data = data
	var table_visible = (
		_controller.active
		and _controller.latest_state.get("table_active", false)
		and not _controller.latest_state.get("in_shop", false)
		and not _controller.finished
		and not _controller.panel.visible
		and not _controller.shop_sync.is_open()
	)
	_overlay.visible = table_visible
	if not table_visible:
		_panel.hide()
		return
	_refresh_names()
	_refresh_choices()
	_panel.visible = not _ball_ids.is_empty() and not data.get("pending", false)
	if _panel.visible:
		var caller: int = data.get("last_shooter", 0)
		var own_call = caller > 0 and caller == _controller.transport.local_id()
		_choices.visible = own_call
		_call_button.disabled = not own_call or _pocket_indices.is_empty()
		var called: Dictionary = data.get("call", {})
		if not called.is_empty():
			_status.text = "%s · Pocket %d" % [_player_name(called.actor), called.pocket + 1]
		elif caller > 0:
			_status.text = "Your call" if own_call else "%s's call" % _player_name(caller)
		else:
			_status.text = "Available after the first shot"
	_overlay.queue_redraw()


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


func _refresh_choices() -> void:
	var ball_ids: Array[int] = []
	var pockets: Array[int] = []
	for ball in _data.get("balls", []):
		if ball.alive and ball.callable and "TOGETHER_CALL" in ball.kinds:
			ball_ids.append(ball.id)
	for pocket in _data.get("pockets", []):
		if pocket.open and pocket.index >= 0 and pocket.index < 6:
			pockets.append(pocket.index)
	if ball_ids == _ball_ids and pockets == _pocket_indices:
		return
	var selected_ball = _selected(_balls)
	var selected_pocket = _selected(_pockets)
	_ball_ids = ball_ids
	_pocket_indices = pockets
	_balls.clear()
	for ball in _data.get("balls", []):
		if ball.id in _ball_ids:
			var index = _balls.item_count
			var label = "Ball %d" % (index + 1) if _ball_ids.size() > 1 else "Called Shot"
			_balls.add_item(label)
			_balls.set_item_metadata(index, ball.id)
			if ball.id == selected_ball:
				_balls.select(index)
	_pockets.clear()
	for pocket in _pocket_indices:
		var index = _pockets.item_count
		_pockets.add_item("Pocket %d" % (pocket + 1))
		_pockets.set_item_metadata(index, pocket)
		if pocket == selected_pocket:
			_pockets.select(index)


func _selected(choice: OptionButton) -> int:
	return choice.get_item_metadata(choice.selected) if choice.selected >= 0 else -1


func _submit_call() -> void:
	if _call_button.disabled:
		return
	_service.request_call(_selected(_balls), _selected(_pockets))


func draw_overlay(canvas: Control) -> void:
	var transform = get_viewport().get_canvas_transform()
	var called: Dictionary = _data.get("call", {})
	var choosing = _panel.visible and _choices.visible
	for pocket in _data.get("pockets", []):
		if not pocket.open or pocket.index < 0 or pocket.index >= 6:
			continue
		var position: Vector2 = transform * pocket.position
		if choosing:
			_caption(canvas, position + Vector2(-4, 5), str(pocket.index + 1), CALL_COLOR)
		if (
			pocket.index == called.get("pocket", -1)
			or (choosing and pocket.index == _selected(_pockets))
		):
			canvas.draw_circle(position, 20.0, CALL_COLOR, false, 2.0, true)
	for ball in _data.get("balls", []):
		if not ball.alive:
			continue
		var position: Vector2 = transform * _service.ball_position(ball.id, ball.position)
		if "TOGETHER_RELAY" in ball.kinds and ball.marker > 0:
			var color = Color.from_hsv(posmod(hash(str(ball.marker)), 360) / 360.0, 0.55, 1.0)
			canvas.draw_circle(position, 14.0, color, false, 1.5, true)
			_caption(canvas, position + Vector2(17, -10), _player_name(ball.marker), color)
		if "TOGETHER_PATIENCE" in ball.kinds:
			for pip in range(mini(ball.charge, 3)):
				canvas.draw_circle(position + Vector2((pip - 1) * 6, -19), 2.0, CALL_COLOR)
		if "TOGETHER_BOUNTY" in ball.kinds:
			canvas.draw_circle(position, 13.0, BOUNTY_COLOR, false, 1.5, true)
			for axis in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
				canvas.draw_line(position + axis * 10, position + axis * 17, BOUNTY_COLOR, 1.5)
		if ball.id == called.get("ball", -1) or (choosing and ball.id == _selected(_balls)):
			canvas.draw_circle(position, 17.0, CALL_COLOR, false, 1.5, true)
			if choosing and _ball_ids.size() > 1 and ball.id in _ball_ids:
				_caption(
					canvas, position + Vector2(18, 5), str(_ball_ids.find(ball.id) + 1), CALL_COLOR
				)


func _caption(canvas: Control, position: Vector2, text: String, color: Color) -> void:
	var font = ThemeDB.fallback_font
	canvas.draw_string_outline(
		font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK
	)
	canvas.draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

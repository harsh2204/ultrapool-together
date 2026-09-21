extends Node

const SEND_INTERVAL = 0.05
const STALE_SECONDS = 1.5


class CursorOverlay:
	extends Control
	var presence: Node

	func _draw() -> void:
		presence.draw_overlay(self)


var _controller: Node
var _transport: Node
var _shop: Node
var _overlay: CursorOverlay
var _send_time = 0.0
var _name_time = 0.0
var _sequence = 0
var _remote_sequence = -1
var _remote: Dictionary = {}
var _remote_age = STALE_SECONDS
var _display_position = Vector2.ZERO
var _display_origin = Vector2.ZERO
var _display_vector = Vector2.ZERO
var _partner_name = "Partner"


func setup(controller: Node, transport: Node, shop: Node) -> void:
	_controller = controller
	_transport = transport
	_shop = shop
	var layer = CanvasLayer.new()
	layer.layer = 121
	add_child(layer)
	_overlay = CursorOverlay.new()
	_overlay.presence = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func tick(delta: float, active: bool, can_aim: bool) -> void:
	if not active:
		if not _remote.is_empty():
			clear()
		return
	_remote_age += delta
	_send_time += delta
	_name_time += delta
	if _name_time >= 1.0:
		_name_time = 0.0
		for person in _transport.participants():
			if not person.you:
				_partner_name = person.name
	if _send_time >= SEND_INTERVAL:
		_send_time = 0.0
		_sequence += 1
		var message = _capture(can_aim)
		message.kind = "presence"
		message.seq = _sequence
		_transport.send_unreliable(message)
	if not _remote.is_empty():
		var weight = minf(delta * 24.0, 1.0)
		_display_position = _display_position.lerp(_remote.position, weight)
		_display_origin = _display_origin.lerp(_remote.origin, weight)
		_display_vector = _display_vector.lerp(_remote.vector, weight)
	_overlay.queue_redraw()


func receive(message: Dictionary) -> bool:
	if message.get("kind") != "presence":
		return false
	if not _valid(message) or message.seq <= _remote_sequence:
		return true
	if _remote.is_empty() or _remote.space != message.space or _remote_age >= STALE_SECONDS:
		_display_position = message.position
		_display_origin = message.origin
		_display_vector = message.vector
	_remote = message
	_remote_sequence = message.seq
	_remote_age = 0.0
	return true


func clear() -> void:
	_remote.clear()
	_remote_sequence = -1
	_sequence = 0
	_send_time = 0.0
	_name_time = 1.0
	_remote_age = STALE_SECONDS
	_partner_name = "Partner"
	if _overlay != null:
		_overlay.queue_redraw()


func _capture(can_aim: bool) -> Dictionary:
	var state = {
		"space": "none",
		"position": Vector2.ZERO,
		"target": "",
		"aiming": false,
		"origin": Vector2.ZERO,
		"vector": Vector2.ZERO
	}
	var viewport = get_viewport()
	var mouse = viewport.get_mouse_position()
	if (
		_controller.panel.visible
		or not get_window().has_focus()
		or not viewport.get_visible_rect().has_point(mouse)
	):
		return state
	var shop_rect: Rect2 = _shop.presence_rect()
	if shop_rect.has_area():
		if shop_rect.has_point(mouse):
			state.space = "shop"
			state.position = (mouse - shop_rect.position) / shop_rect.size
			state.target = _shop.presence_target()
		return state
	var game = get_node("/root/Global").gameManager
	if not is_instance_valid(game) or game.in_shop:
		return state
	state.space = "table"
	state.position = viewport.get_canvas_transform().affine_inverse() * mouse
	var player = game.player_ball
	if is_instance_valid(player) and can_aim and player.preparing_shot and player.shot is Vector2:
		state.aiming = true
		state.origin = player.global_position
		state.vector = player.shot.limit_length(200.0)
		if get_node("/root/InputManager").is_controller():
			state.position = state.origin + state.vector
	return state


func draw_overlay(canvas: Control) -> void:
	if _remote.is_empty() or _remote_age >= STALE_SECONDS or _remote.space == "none":
		return
	if _controller.panel.visible:
		return
	var position: Vector2
	var shop_rect: Rect2 = _shop.presence_rect()
	var color = Color("70dbd0") if _controller.local_player == 1 else Color("ffca72")
	color.a = clampf((STALE_SECONDS - _remote_age) / 0.4, 0.0, 1.0)
	if _remote.space == "shop":
		if not shop_rect.has_area():
			return
		position = shop_rect.position + _display_position * shop_rect.size
		if not _remote.target.is_empty():
			var target: Vector2 = _shop.presence_target_position(_remote.target)
			if target.is_finite():
				position = target
	else:
		if shop_rect.has_area():
			return
		var transform = get_viewport().get_canvas_transform()
		position = transform * _display_position
		if _remote.aiming:
			var start = transform * _display_origin
			var end = transform * (_display_origin + _display_vector)
			canvas.draw_line(start, end, color, 2.0, true)
			canvas.draw_circle(start, 5.0, color, false, 1.5, true)
			if start.distance_squared_to(end) > 4.0:
				var direction = (end - start).normalized()
				canvas.draw_line(end, end - direction.rotated(0.5) * 10, color, 2.0, true)
				canvas.draw_line(end, end - direction.rotated(-0.5) * 10, color, 2.0, true)
	if not get_viewport().get_visible_rect().has_point(position):
		return
	var pointer = PackedVector2Array(
		[position, position + Vector2(3, 19), position + Vector2(8, 12), position + Vector2(16, 11)]
	)
	canvas.draw_colored_polygon(pointer, color)
	var outline = pointer.duplicate()
	outline.append(position)
	canvas.draw_polyline(outline, Color(0, 0, 0, color.a), 2.0, true)
	var font = ThemeDB.fallback_font
	var text_size = font.get_string_size(_partner_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var label = position + Vector2(20, 18)
	label.x = minf(label.x, get_viewport().get_visible_rect().size.x - text_size.x - 6)
	canvas.draw_rect(
		Rect2(label - Vector2(4, 15), text_size + Vector2(8, 4)),
		Color(0.04, 0.05, 0.07, color.a * 0.8)
	)
	canvas.draw_string(font, label, _partner_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


func _valid(message: Dictionary) -> bool:
	if (
		not message.get("seq") is int
		or message.seq < 0
		or not message.get("space") in ["none", "table", "shop"]
		or not message.get("target") is String
		or message.target.length() > 128
		or not message.get("aiming") is bool
	):
		return false
	for field in ["position", "origin", "vector"]:
		if not message.get(field) is Vector2 or not message[field].is_finite():
			return false
	if message.vector.length() > 200.1 or message.origin.length() > 100000.0:
		return false
	if message.space == "shop":
		return (
			Rect2(Vector2.ZERO, Vector2.ONE).grow(0.001).has_point(message.position)
			and not message.aiming
		)
	return (
		message.position.length() <= 100000.0 and (message.space == "table" or not message.aiming)
	)

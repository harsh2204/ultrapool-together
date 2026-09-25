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
var _remotes: Dictionary = {}
var _names: Dictionary = {}


func setup(controller: Node, transport: Node, shop: Node) -> void:
	_controller = controller
	_transport = transport
	_shop = shop
	_transport.peer_left.connect(_remove_peer)
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
		if not _remotes.is_empty():
			clear()
		return
	_send_time += delta
	_name_time += delta
	if _name_time >= 1.0:
		_name_time = 0.0
		_names.clear()
		for person in _transport.participants():
			if person.connected:
				_names[person.id] = person.name
		for id in _remotes.keys():
			if not _names.has(id):
				_remotes.erase(id)
	if _send_time >= SEND_INTERVAL and _controller.table_id >= 0:
		_send_time = 0.0
		_sequence += 1
		var message = _capture(can_aim)
		message.kind = "presence"
		message.seq = _sequence
		message.actor = _transport.local_id()
		message.table = _controller.table_id
		message.match = _controller.match_id
		if _transport.is_host:
			_relay(message)
		else:
			_transport.send_unreliable(message)
	var weight = minf(delta * 24.0, 1.0)
	for remote in _remotes.values():
		remote.age += delta
		remote.position = remote.position.lerp(remote.message.position, weight)
		remote.origin = remote.origin.lerp(remote.message.origin, weight)
		remote.vector = remote.vector.lerp(remote.message.vector, weight)
	_overlay.queue_redraw()


func receive(sender: int, message: Dictionary) -> bool:
	if message.get("kind") != "presence":
		return false
	if not _valid(message) or message.match != _controller.match_id:
		return true
	var actor: int
	if _transport.is_host:
		actor = sender
		if not _transport.connected_peers().has(actor):
			return true
		var table: int = _controller.player_table(actor)
		if table < 0:
			return true
		message = message.duplicate()
		message.actor = actor
		message.table = table
		_relay(message)
	else:
		if sender != _transport.host_id():
			return true
		actor = message.actor
	if (
		actor == _transport.local_id()
		or message.table != _controller.table_id
		or _controller.player_table(actor) != message.table
	):
		return true
	var remote: Dictionary = _remotes.get(actor, {})
	if not remote.is_empty() and remote.age < STALE_SECONDS:
		if remote.message.table == message.table and message.seq <= remote.message.seq:
			return true
	if remote.is_empty() or remote.age >= STALE_SECONDS or remote.message.space != message.space:
		remote = {"position": message.position, "origin": message.origin, "vector": message.vector}
	remote.message = message
	remote.age = 0.0
	_remotes[actor] = remote
	return true


func _relay(message: Dictionary) -> void:
	for id in _transport.connected_peers():
		if id != message.actor and _controller.player_table(id) == message.table:
			_transport.send_to(id, message, true)


func _remove_peer(id: int, _reason: String) -> void:
	_remotes.erase(id)
	_names.erase(id)


func clear() -> void:
	_remotes.clear()
	_names.clear()
	_send_time = 0.0
	_name_time = 1.0
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
	if _controller.panel.visible:
		return
	for id in _remotes:
		var remote: Dictionary = _remotes[id]
		if (
			remote.age < STALE_SECONDS
			and remote.message.space != "none"
			and remote.message.table == _controller.table_id
		):
			_draw_cursor(canvas, id, remote)


func _draw_cursor(canvas: Control, id: int, remote: Dictionary) -> void:
	var message: Dictionary = remote.message
	var position: Vector2
	var shop_rect: Rect2 = _shop.presence_rect()
	var color: Color = _controller.player_color(id)
	color.a = clampf((STALE_SECONDS - remote.age) / 0.4, 0.0, 1.0)
	if message.space == "shop":
		if not shop_rect.has_area():
			return
		position = shop_rect.position + remote.position * shop_rect.size
		if not message.target.is_empty():
			var target: Vector2 = _shop.presence_target_position(message.target)
			if target.is_finite():
				position = target
	else:
		if shop_rect.has_area():
			return
		var transform = get_viewport().get_canvas_transform()
		position = transform * remote.position
		if message.aiming:
			var start = transform * remote.origin
			var end = transform * (remote.origin + remote.vector)
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
	var name: String = _names.get(id, "Player")
	var text_size = font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var label = position + Vector2(20, 18)
	label.x = minf(label.x, get_viewport().get_visible_rect().size.x - text_size.x - 6)
	canvas.draw_rect(
		Rect2(label - Vector2(4, 15), text_size + Vector2(8, 4)),
		Color(0.04, 0.05, 0.07, color.a * 0.8)
	)
	canvas.draw_string(font, label, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


func _valid(message: Dictionary) -> bool:
	if (
		not message.get("match") is int
		or message.match < 0
		or not message.get("actor") is int
		or message.actor <= 0
		or not message.get("table") is int
		or message.table < 0
		or message.table >= _transport.MAX_PLAYERS
		or not message.get("seq") is int
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

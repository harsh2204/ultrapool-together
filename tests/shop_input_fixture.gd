extends Node

var viewport: SubViewport
var _shop: Node2D
var _parent: Node
var _index: int
var _transform: Transform2D
var _layer: CanvasLayer
var _resize_connections: Array = []


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	set_process(false)


func begin(shop: Node2D):
	_shop = shop
	_parent = shop.get_parent()
	_index = shop.get_index()
	_transform = shop.transform
	for connection in get_viewport().size_changed.get_connections():
		var target = connection.callable.get_object()
		if target == shop or (target is Node and shop.is_ancestor_of(target)):
			_resize_connections.append(connection)
	viewport = SubViewport.new()
	viewport.size = get_viewport().get_visible_rect().size
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.canvas_transform = get_viewport().get_canvas_transform()
	_layer = CanvasLayer.new()
	_layer.layer = 0
	add_child(_layer)
	var display = TextureRect.new()
	display.texture = viewport.get_texture()
	display.size = viewport.size
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(display)
	shop.reparent(viewport, true)
	for connection in _resize_connections:
		viewport.size_changed.connect(connection.callable, connection.flags)
	set_process(true)


func finish():
	set_process(false)
	_shop.drop()
	if _shop.selected_ball != null:
		_shop.unselect_ball(_shop.selected_ball)
	if _shop.selected_passive != null:
		_shop.unselect_passive(_shop.selected_passive)
	_shop.hovered_slot = null
	_shop.reparent(_parent, true)
	_parent.move_child(_shop, _index)
	_shop.transform = _transform
	for connection in _resize_connections:
		get_viewport().size_changed.connect(connection.callable, connection.flags)
	_resize_connections.clear()
	_layer.queue_free()
	viewport.queue_free()
	viewport = null
	_shop = null


func _process(_delta):
	viewport.canvas_transform = get_viewport().get_canvas_transform()


func motion(position: Vector2, held = false):
	var event = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - viewport.get_mouse_position()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	viewport.push_input(event, true)


func button(position: Vector2, pressed: bool):
	await get_tree().process_frame
	var event = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	viewport.push_input(event, true)


func hover(item: Node2D):
	for _frame in 15:
		await get_tree().process_frame
		motion(item.get_global_transform_with_canvas().origin)

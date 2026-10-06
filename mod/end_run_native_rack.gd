extends Control
## PERF-019/024/026: one retained, scriptless native inventory scene. Discussion
## gestures change only display order/poses; native inventory and resources are
## never passed through gameplay setters, score effects, or passive setup.

signal pickup_requested(original_slot: int)
signal motion_requested(position: Vector2)
signal release_requested(target_display_slot: int)
signal cancel_requested

const SceneReader = preload("spectator_scene.gd")
const BASE = "PanelContainer/VBoxContainer/TextureRect"
const WIDTH = 616.0
const BASE_HEIGHT = 392.0
const ROW_HEIGHT = 78.0
const COLUMNS = 8
const HIT_SIZE = Vector2(58, 58)

## Inspection surfaces use original inventory identities, including empty slots.
## slots contains {node, button, position}; items contains {node, state, points}.
var native_root: Control
var slots: Array = []
var items: Dictionary = {}
var point_labels: Dictionary = {}
var passive_slots: Array = []
var passive_items: Dictionary = {}
var cube_slots: Array = []
var cube_items: Dictionary = {}
var displayed_order: Array = []

var _database: Node
var _global: Node
var _scroll: ScrollContainer
var _extent: Control
var _design: Control
var _ball_template: Node2D
var _passive_template: Node2D
var _slot_template: Node2D
var _ball_material: ShaderMaterial
var _mixed_material: ShaderMaterial
var _sparks: Array = []
var _plates: Array = []
var _native_slots: Array = []
var _slot_pool: Array = []
var _cube_slot_pool: Array = []
var _ball_pool: Array = []
var _passive_pool: Array = []
var _passive_hovers: Array = []
var _cube_pool: Array = []
var _original_to_display: Dictionary = {}
var _record_key: Array = []
var _build: Array = []
var _height = BASE_HEIGHT
var _overflow_label: Label
var _cube_label: Label
var _actor_label: Label
var _layout_queued = false
var _drag: Dictionary = {}
var _rendered_drag_slot = -1
var _local_actor = 0
var _local_slot = -1
var _local_position = Vector2.ZERO
var _pointer_held = false
var _keyboard_held = false
var _awaiting_pickup = false


func setup(controller: Node) -> void:
	if native_root != null:
		return
	_database = controller.get_node("/root/BallDatabase")
	_global = controller.get_node("/root/Global")
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	custom_minimum_size = Vector2(260, 180)
	_ball_material = load("res://materials/ball.tres")
	_mixed_material = load("res://materials/mixed_ball.tres")
	var ball_scene: PackedScene = load("res://ui/display_item_ball_complex.tscn")
	_ball_template = SceneReader.create(ball_scene)
	_passive_template = SceneReader.create(load("res://ui/passives/passive_item.tscn"))
	_slot_template = SceneReader.create(load("res://ui/slot_display.tscn"))
	var sparks = SceneReader.exported(ball_scene, "sparks")
	if sparks is Array:
		_sparks = sparks.duplicate()
	var plates = SceneReader.exported(
		load("res://ui/passives/passive_visuals.tscn"), "plates_sprites"
	)
	if plates is Array:
		_plates = plates.duplicate()
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_scroll)
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_extent = Control.new()
	_extent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_extent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_extent)
	_design = Control.new()
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extent.add_child(_design)
	native_root = SceneReader.create(load("res://ui/continue_run_info.tscn"))
	native_root.name = "NativeFinalBuild"
	native_root.custom_minimum_size = Vector2(WIDTH, BASE_HEIGHT)
	native_root.size = Vector2(WIDTH, BASE_HEIGHT)
	_design.add_child(native_root)
	# RunState-only placeholders are not in the immutable inventory archive.
	# Hiding these avoids inventing money, health, deck, seed or progression data.
	for path in ["BottomLeft", "BottomLeftDaily", "Wallet", "Map"]:
		var metadata = native_root.get_node_or_null(BASE + "/Node2D/" + path)
		if metadata is CanvasItem:
			metadata.hide()
	var inventory = native_root.get_node(BASE + "/Node2D/Inventory")
	_native_slots = inventory.get_node("Triangle").get_children()
	_native_slots.append_array(inventory.get_node("Reserve").get_children())
	for marker in _native_slots:
		_slot_pool.append(_new_slot(marker, _slot_pool.size()))
	passive_slots = native_root.get_node(BASE + "/PassivesInfo").get_children()
	for index in 4:
		_passive_pool.append(_new_passive())
		_passive_hovers.append(_new_hover())
	_overflow_label = _label("More balls", 18)
	_cube_label = _label("Cubes", 18)
	_actor_label = _label("", 14)
	_actor_label.z_index = 101
	_actor_label.add_theme_color_override("font_outline_color", Color("171e20"))
	_actor_label.add_theme_constant_override("outline_size", 4)
	_actor_label.hide()
	resized.connect(_queue_layout)
	native_root.resized.connect(_queue_layout)
	# Native containers settle their child insets after the root receives its
	# size. Track the complete short ancestor chain: a panel can move by its
	# margin while the innermost TextureRect keeps the same local rectangle.
	for path in ["PanelContainer", "PanelContainer/VBoxContainer", BASE]:
		native_root.get_node(path).item_rect_changed.connect(_queue_layout)
	_queue_layout()
	set_process_input(true)


## order[display slot] = original inventory slot. Null slots retain identities.
func present(record: Dictionary, order: Array = []) -> void:
	if native_root == null or record.is_empty():
		clear()
		return
	var key = [record.get("match"), record.get("table"), record.get("leader")]
	if key != _record_key:
		cancel_local_drag()
		_drag = {}
		_record_key = key
		var inventory: Dictionary = record.inventory
		_build = inventory.build.duplicate(true)
		_ensure_slots(_build.size(), inventory.cubes.size())
		items = {}
		point_labels = {}
		for index in _ball_pool.size():
			var entry: Dictionary = _ball_pool[index]
			var state = _build[index] if index < _build.size() else null
			entry.node.visible = state != null
			if state != null:
				_hydrate_ball(entry, state)
				items[index] = entry
				point_labels[index] = entry.label
		passive_items = {}
		for index in 4:
			var state = inventory.passives[index]
			var entry: Dictionary = _passive_pool[index]
			entry.node.visible = state != null
			if state != null:
				_hydrate_passive(entry, state)
				passive_items[index] = entry
				_passive_hovers[index].tooltip_text = _passive_tooltip(state)
			else:
				_passive_hovers[index].tooltip_text = "Empty snack slot"
		cube_items = {}
		for index in _cube_pool.size():
			var state = inventory.cubes[index] if index < inventory.cubes.size() else null
			var entry: Dictionary = _cube_pool[index]
			entry.node.visible = state != null
			if state != null:
				_hydrate_ball(entry, state)
				cube_items[index] = entry
			entry.hover.visible = state != null
			if state != null:
				entry.hover.tooltip_text = _item_tooltip(state)
		_scroll.scroll_vertical = 0
	_set_order(order)
	show()
	_queue_layout()


## Acknowledgement never restarts pointer capture after mouse-up. An older
## snapshot can precede the grant, so only the root's explicit rejection handler
## cancels an awaiting pickup; established holds follow authoritative state.
func apply_discussion(snapshot: Dictionary, local_actor: int, actor_name: String = "") -> void:
	_local_actor = local_actor
	_set_order(snapshot.get("order", []))
	_drag = snapshot.get("drag", {}).duplicate()
	if _local_slot >= 0:
		var accepted = (
			int(_drag.get("actor", 0)) == local_actor and int(_drag.get("slot", -1)) == _local_slot
		)
		if accepted:
			_awaiting_pickup = false
		elif not _awaiting_pickup:
			cancel_local_drag()
	_actor_label.text = actor_name
	_render_drag()


func cancel_local_drag() -> void:
	_local_slot = -1
	_pointer_held = false
	_keyboard_held = false
	_awaiting_pickup = false
	_render_drag()


func clear() -> void:
	_drag = {}
	cancel_local_drag()
	_record_key = []
	_build = []
	displayed_order = []
	_original_to_display = {}
	items = {}
	point_labels = {}
	passive_items = {}
	cube_items = {}
	for pool in [_ball_pool, _passive_pool, _cube_pool]:
		for entry in pool:
			entry.node.hide()
	if _actor_label != null:
		_actor_label.hide()
	hide()


func slot_center(display_slot: int) -> Vector2:
	if display_slot < 0 or display_slot >= slots.size():
		return global_position
	return _design.get_global_transform() * slots[display_slot].position


func _set_order(order: Array) -> void:
	var next: Array = []
	var seen: Dictionary = {}
	if order.size() == _build.size():
		for original in order:
			if (
				not original is int
				or original < 0
				or original >= _build.size()
				or seen.has(original)
			):
				next = []
				break
			seen[original] = true
			next.append(original)
	if next.size() != _build.size():
		next = range(_build.size())
	if next == displayed_order:
		return
	displayed_order = next
	_original_to_display = {}
	for index in displayed_order.size():
		_original_to_display[displayed_order[index]] = index
	_position_items()


func _new_slot(marker: Node2D, display_slot: int) -> Dictionary:
	var button = Button.new()
	button.name = "ReviewSlot%d" % display_slot
	button.size = HIT_SIZE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	var focus = StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("e5ddaf")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(29)
	button.add_theme_stylebox_override("focus", focus)
	button.gui_input.connect(_slot_input.bind(display_slot))
	_design.add_child(button)
	return {"node": marker, "button": button, "position": Vector2.ZERO}


func _ensure_slots(build_count: int, cube_count: int) -> void:
	# Counts have already passed the bounded archive validator (64/4/64).
	while _slot_pool.size() < build_count:
		var marker: Node2D = _slot_template.duplicate()
		_design.add_child(marker)
		_slot_pool.append(_new_slot(marker, _slot_pool.size()))
	while _ball_pool.size() < build_count:
		_ball_pool.append(_new_ball())
	while _cube_slot_pool.size() < cube_count:
		var marker: Node2D = _slot_template.duplicate()
		_design.add_child(marker)
		_cube_slot_pool.append(marker)
		var entry = _new_ball()
		entry.hover = _new_hover()
		_cube_pool.append(entry)
	slots = _slot_pool.slice(0, build_count)
	cube_slots = _cube_slot_pool.slice(0, cube_count)
	for index in _slot_pool.size():
		_slot_pool[index].node.visible = index < build_count
		_slot_pool[index].button.visible = index < build_count
	for index in _cube_slot_pool.size():
		_cube_slot_pool[index].visible = index < cube_count


func _new_ball() -> Dictionary:
	var node: Node2D = _ball_template.duplicate()
	_design.add_child(node)
	node.hide()
	var sphere: Sprite2D = node.get_node("visuals/ball")
	var entry = {
		"node": node,
		"sphere": sphere,
		"edge": node.get_node("visuals/edge"),
		"spark": node.get_node("visuals/spark"),
		"label": node.get_node("ScoreUI/Score/ScoreLabel"),
		"state": {},
		"points": 0
	}
	# Scriptless duplicates must own shader parameters, never the borrowed scene.
	if entry.edge.material != null:
		entry.edge.material = entry.edge.material.duplicate()
	return entry


func _hydrate_ball(entry: Dictionary, state: Dictionary) -> void:
	var resource = _database.id_to_ball[state.data]
	if entry.state.get("data") != state.data or entry.state.get("mixed") != state.mixed:
		var material: ShaderMaterial = (
			(_mixed_material if state.mixed != "" else _ball_material).duplicate()
		)
		material.set_shader_parameter("tex", resource.texture)
		if state.mixed != "":
			material.set_shader_parameter("mixed_tex", _database.id_to_ball[state.mixed].texture)
		var basis = Basis.IDENTITY.rotated(Vector3.FORWARD, PI / 2.0).rotated(
			Vector3.RIGHT, PI / 1.5
		)
		material.set_shader_parameter("rotation_x", basis.x)
		material.set_shader_parameter("rotation_y", basis.y)
		material.set_shader_parameter("rotation_z", basis.z)
		entry.sphere.material = material
		if entry.edge.material is ShaderMaterial:
			entry.edge.material.set_shader_parameter(
				"selout_color", resource.main_color.lerp(Color.BLACK, 0.3)
			)
	# Native BallItem.get_score() is exactly base_score + temp_extra_score. This
	# is a saved item value, not a promise about a future shot's multipliers/effects.
	entry.points = int(state.base_score) + int(state.temp_extra_score)
	# Native formatting is pure, but its early raw-number branch also catches
	# negative values. Format the magnitude so large debts fit the same badge.
	entry.label.text = (
		("-" if entry.points < 0 else "") + _global.format_number(absi(entry.points), 4, 0)
	)
	entry.label.show()
	entry.label.get_parent().show()
	entry.node.get_node("ScoreUI").show()
	if not _sparks.is_empty():
		entry.spark.texture = _sparks[clampi(int(state.level) - 1, 0, _sparks.size() - 1)]
	entry.state = state.duplicate(true)


func _new_passive() -> Dictionary:
	var node: Node2D = _passive_template.duplicate()
	_design.add_child(node)
	node.get_node("PassiveVisuals").scale = Vector2(1.4, 1.4)
	node.hide()
	return {
		"node": node,
		"item": node.get_node("PassiveVisuals/ItemTransform/Item"),
		"shadow": node.get_node("PassiveVisuals/Plate/ItemShadow"),
		"plate": node.get_node("PassiveVisuals/Plate"),
		"label": node.get_node("ScoreUI/Score/CountLabel"),
		"score_ui": node.get_node("ScoreUI"),
		"state": {}
	}


func _hydrate_passive(entry: Dictionary, state: Dictionary) -> void:
	var resource = _database.id_to_passive[state.data]
	entry.item.texture = resource.texture
	entry.shadow.texture = resource.texture
	var rarity = int(resource.rarity)
	var plate_index = rarity if rarity >= 0 and rarity <= 2 else 0
	if plate_index < _plates.size():
		entry.plate.texture = _plates[plate_index]
	var counted = resource
	if state.data == "GUMMY-BRAIN":
		counted = _database.id_to_passive.get(state.get("copy_id", ""))
	entry.score_ui.visible = counted != null and counted.passive_has_number_in_round
	entry.label.text = str(state.base_score)
	entry.state = state.duplicate(true)


func _queue_layout() -> void:
	if _layout_queued or _design == null:
		return
	_layout_queued = true
	call_deferred("_layout")


func _layout() -> void:
	_layout_queued = false
	var extra_count = maxi(slots.size() - 16, 0)
	var extra_rows = ceili(float(extra_count) / COLUMNS)
	var cube_rows = ceili(float(cube_slots.size()) / COLUMNS)
	var extra_start = BASE_HEIGHT + 42.0
	var cube_start = (
		BASE_HEIGHT + (36.0 + extra_rows * ROW_HEIGHT if extra_count > 0 else 0.0) + 42.0
	)
	_height = BASE_HEIGHT
	if extra_count > 0:
		_height += 36.0 + extra_rows * ROW_HEIGHT
	if not cube_slots.is_empty():
		_height += 36.0 + cube_rows * ROW_HEIGHT
	_design.size = Vector2(WIDTH, _height)
	var factor = minf(1.0, maxf(0.1, (size.x - 20.0) / WIDTH))
	# Standard inventories fit the available height. Expanded inventories keep
	# readable native art and use the bounded supplemental scroll region.
	if extra_count == 0 and cube_slots.is_empty():
		factor = minf(factor, maxf(0.1, size.y / BASE_HEIGHT))
	_design.scale = Vector2(factor, factor)
	_design.position = Vector2(maxf(0, (size.x - WIDTH * factor - 14.0) / 2.0), 0)
	_extent.custom_minimum_size = Vector2(0, _height * factor)
	_overflow_label.visible = extra_count > 0
	_overflow_label.position = Vector2(26, BASE_HEIGHT + 4)
	_cube_label.visible = not cube_slots.is_empty()
	_cube_label.position = Vector2(26, cube_start - 38)
	var inverse = _design.get_global_transform().affine_inverse()
	for index in slots.size():
		var entry: Dictionary = slots[index]
		if index < 16:
			entry.position = inverse * entry.node.global_position
		else:
			entry.position = _row_position(index - 16, extra_start)
			entry.node.position = entry.position
		entry.button.position = entry.position - HIT_SIZE / 2.0
	for index in cube_slots.size():
		cube_slots[index].position = _row_position(index, cube_start)
	for index in 4:
		_passive_pool[index].node.position = inverse * passive_slots[index].global_position
		_passive_hovers[index].position = _passive_pool[index].node.position - HIT_SIZE / 2.0
	for index in cube_items:
		cube_items[index].node.position = cube_slots[index].position
		cube_items[index].hover.position = cube_slots[index].position - HIT_SIZE / 2.0
	_position_items()


func _row_position(index: int, start: float) -> Vector2:
	return Vector2(46 + (index % COLUMNS) * 74, start + (index / COLUMNS) * ROW_HEIGHT)


func _position_items() -> void:
	for display_slot in displayed_order.size():
		if display_slot >= slots.size():
			break
		var original: int = displayed_order[display_slot]
		var button: Button = slots[display_slot].button
		button.set_meta("original_slot", original)
		if items.has(original):
			var entry: Dictionary = items[original]
			entry.node.position = slots[display_slot].position
			entry.node.z_index = 2
			button.tooltip_text = _item_tooltip(entry.state)
		else:
			button.tooltip_text = "Empty slot"
	_rendered_drag_slot = -1
	_render_drag()


func _item_tooltip(state: Dictionary) -> String:
	var title: String = _database.id_to_ball[state.data].get_formatted_name()
	if state.mixed != "":
		title += " + " + _database.id_to_ball[state.mixed].get_formatted_name()
	var points = int(state.base_score) + int(state.temp_extra_score)
	var result = (
		"%s\n%d points (%d base, %+d temporary)\nLevel %d"
		% [title, points, state.base_score, state.temp_extra_score, state.level]
	)
	var flags: Array[String] = []
	for flag in ["flaming", "fleeting", "star_power", "shielded", "shield_broken", "locked"]:
		if state.get(flag, false):
			flags.append(flag.replace("_", " ").capitalize())
	if not flags.is_empty():
		result += "\n" + ", ".join(flags)
	return result


func _passive_tooltip(state: Dictionary) -> String:
	var resource = _database.id_to_passive[state.data]
	var result: String = resource.get_formatted_name()
	var counted = resource
	if state.get("copy_id", "") != "":
		counted = _database.id_to_passive[state.copy_id]
		result += "\nCopying " + counted.get_formatted_name()
	elif state.data == "GUMMY-BRAIN":
		counted = null
	if counted != null and counted.passive_has_number_in_round:
		result += "\nCount: " + str(state.base_score)
	return result


func _new_hover() -> Control:
	var control = Control.new()
	control.size = HIT_SIZE
	control.mouse_filter = Control.MOUSE_FILTER_PASS
	_design.add_child(control)
	return control


func _slot_input(event: InputEvent, display_slot: int) -> void:
	if not is_visible_in_tree() or display_slot >= displayed_order.size():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_begin_pickup(display_slot, false)
		slots[display_slot].button.accept_event()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		if _keyboard_held:
			_keyboard_held = false
			release_requested.emit(display_slot)
		else:
			_begin_pickup(display_slot, true)
		slots[display_slot].button.accept_event()


func _begin_pickup(display_slot: int, keyboard: bool) -> void:
	var original = int(displayed_order[display_slot])
	if not items.has(original) or _local_slot >= 0 or not _drag.is_empty():
		return
	_local_slot = original
	_pointer_held = not keyboard
	_keyboard_held = keyboard
	_awaiting_pickup = true
	_local_position = slots[display_slot].position / Vector2(WIDTH, _height)
	_render_drag()
	pickup_requested.emit(original)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _local_slot < 0:
		return
	if event.is_action_pressed("ui_cancel"):
		cancel_local_drag()
		cancel_requested.emit()
		get_viewport().set_input_as_handled()
	elif _pointer_held and event is InputEventMouseMotion:
		var point: Vector2 = _design.get_global_transform().affine_inverse() * event.position
		_local_position = (point / Vector2(WIDTH, _height)).clamp(Vector2.ZERO, Vector2.ONE)
		_render_drag()
		motion_requested.emit(_local_position)
		get_viewport().set_input_as_handled()
	elif (
		_pointer_held
		and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		_pointer_held = false
		var target = _drop_target(event.position)
		release_requested.emit(target)
		get_viewport().set_input_as_handled()


func _drop_target(global_point: Vector2) -> int:
	if not get_global_rect().has_point(global_point):
		return -1
	var point: Vector2 = _design.get_global_transform().affine_inverse() * global_point
	for index in slots.size():
		if Rect2(slots[index].position - HIT_SIZE / 2.0, HIT_SIZE).has_point(point):
			return index
	return -1


func _render_drag() -> void:
	if _actor_label == null:
		return
	var original = int(_drag.get("slot", -1))
	var position: Vector2 = _drag.get("position", Vector2.ZERO)
	var use_local = _local_slot >= 0 and (_pointer_held or _keyboard_held or _awaiting_pickup)
	if use_local:
		original = _local_slot
		position = _local_position
	if (
		_rendered_drag_slot >= 0
		and _rendered_drag_slot != original
		and items.has(_rendered_drag_slot)
	):
		var prior_display = int(_original_to_display.get(_rendered_drag_slot, -1))
		if prior_display >= 0 and prior_display < slots.size():
			items[_rendered_drag_slot].node.position = slots[prior_display].position
			items[_rendered_drag_slot].node.z_index = 2
	_rendered_drag_slot = original
	if not items.has(original):
		_actor_label.hide()
		return
	var point = position * Vector2(WIDTH, _height)
	if not use_local and int(_drag.get("seq", 0)) == 0:
		var display_slot = int(_original_to_display.get(original, -1))
		if display_slot >= 0 and display_slot < slots.size():
			point = slots[display_slot].position
	items[original].node.position = point
	items[original].node.z_index = 100
	_actor_label.position = point + Vector2(32, -35)
	_actor_label.visible = not _actor_label.text.is_empty()


func _label(text: String, font_size: int) -> Label:
	var label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("ede5ce"))
	_design.add_child(label)
	return label


func _exit_tree() -> void:
	for template in [_ball_template, _passive_template, _slot_template]:
		if is_instance_valid(template):
			template.free()
	_sparks = []
	_plates = []

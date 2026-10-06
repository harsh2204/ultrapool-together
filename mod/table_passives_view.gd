extends RefCounted
## PERF-015/019/020: owned snacks beside the table use the installed native art,
## but never instantiate PassiveItem scripts or register native snack effects.
## Four visual slots are prepared once; snapshot work only changes their properties.

const SceneReader = preload("spectator_scene.gd")
const MAX_SLOTS = 4
const CONTAINER_PATH = "CursedBallsManager/PassiveContainer"

## Occupied inventory slots only. Entries expose native nodes for fixture oracles.
var entries: Dictionary = {}
var _pool: Array = []
var _holder: Node2D
var _container: Node2D
var _database: Node
var _table: Node2D
var _template: Node2D
var _plates: Array = []
var _gap = -65.0
var _viewport: Viewport
var _layout_size = Vector2.ZERO
var _last: Array = []


func setup(table: Node2D, database: Node, native_scene: PackedScene = null) -> void:
	dispose()
	_database = database
	_table = table
	_container = table.get_node_or_null(CONTAINER_PATH)
	if _container == null:
		return
	_holder = _container.get_node("Items")
	# Table variants inherit this native adaptive container and its pivot positions.
	var source: PackedScene = native_scene if native_scene != null else load("res://table.tscn")
	_gap = float(_property(source, CONTAINER_PATH, "gap", -65.0))
	var item_scene: PackedScene = _property(
		source, "CursedBallsManager", "passive_ball_scene", null
	)
	if item_scene == null:
		return
	_template = SceneReader.create(item_scene)
	var visuals_scene: PackedScene = load("res://ui/passives/passive_visuals.tscn")
	var plates = SceneReader.exported(visuals_scene, "plates_sprites")
	if plates is Array:
		_plates = plates.duplicate()
	for slot in MAX_SLOTS:
		var node: Node2D = _template.duplicate()
		node.name = "TogetherSnack%d" % slot
		node.hide()
		_holder.add_child(node)
		_pool.append({
			"node": node,
			"item": node.get_node("PassiveVisuals/ItemTransform/Item"),
			"item_shadow": node.get_node("PassiveVisuals/Plate/ItemShadow"),
			"plate": node.get_node("PassiveVisuals/Plate"),
			"count_label": node.get_node("ScoreUI/Score/CountLabel"),
			"score_ui": node.get_node("ScoreUI"),
			"state": {}
		})
	_viewport = table.get_viewport()
	_viewport.size_changed.connect(update_layout)
	update_layout()


## Inventory has already passed PlayerInventory/TableSync validation. No paths or
## display strings come from the wire; all art and counter rules use native data.
func apply(inventory: Dictionary, show_items: bool = true) -> void:
	if not is_instance_valid(_holder) or _pool.size() != MAX_SLOTS:
		return
	var passives: Array = inventory.get("passives", [])
	if passives.size() != MAX_SLOTS:
		return
	if _holder.visible != show_items:
		_holder.visible = show_items
	if passives == _last:
		return
	for slot in MAX_SLOTS:
		var state = passives[slot]
		var entry: Dictionary = _pool[slot]
		if state == null:
			if entry.node.visible:
				entry.node.hide()
			entry.state = {}
			entries.erase(slot)
			continue
		if not state is Dictionary or not _database.id_to_passive.has(state.get("data", "")):
			continue
		entries[slot] = entry
		if entry.state != state:
			_update(entry, state)
			entry.state = state.duplicate(true)
		if not entry.node.visible:
			entry.node.show()
	_last = passives.duplicate(true)
	update_layout()


func _update(entry: Dictionary, state: Dictionary) -> void:
	var resource = _database.id_to_passive[state.data]
	if entry.item.texture != resource.texture:
		entry.item.texture = resource.texture
		entry.item_shadow.texture = resource.texture
	# Native PassiveVisuals.update chooses plates only for common/uncommon/rare.
	var rarity: int = int(resource.rarity)
	var plate_index = rarity if rarity >= 0 and rarity <= 2 else 0
	if plate_index < _plates.size() and entry.plate.texture != _plates[plate_index]:
		entry.plate.texture = _plates[plate_index]
	var counted = resource
	if state.data == "GUMMY-BRAIN":
		counted = _database.id_to_passive.get(state.get("copy_id", ""))
	var show_count: bool = counted != null and counted.passive_has_number_in_round
	if entry.score_ui.visible != show_count:
		entry.score_ui.visible = show_count
	var text = str(state.base_score)
	if entry.count_label.text != text:
		entry.count_label.text = text


func update_layout() -> void:
	if not is_instance_valid(_holder) or not is_instance_valid(_viewport):
		return
	_layout_size = _viewport.get_visible_rect().size
	# Native cursed_balls_manager.update_positioning selects vertical lists on a
	# landscape screen. Empty inventory slots do not leave gaps in the native rail.
	var vertical = _layout_size.x >= _layout_size.y
	var pivot: Vector2 = _container.get_node("PivotV" if vertical else "PivotH").position
	if _holder.position != pivot:
		_holder.position = pivot
	var direction = Vector2.DOWN if vertical else Vector2.RIGHT
	var gap = -_gap if vertical else _gap
	var index = 0
	for slot in MAX_SLOTS:
		if entries.has(slot):
			var position = direction * gap * index
			if entries[slot].node.position != position:
				entries[slot].node.position = position
			index += 1


## Table-local native sprite bounds keep the watched table's snack rail onscreen.
func get_bounds() -> Rect2:
	var result = Rect2()
	if not is_instance_valid(_table):
		return result
	var inverse: Transform2D = _table.global_transform.affine_inverse()
	for entry in entries.values():
		for sprite in [entry.plate, entry.item]:
			var bounds: Rect2 = (inverse * sprite.global_transform) * sprite.get_rect()
			result = result.merge(bounds) if result.has_area() else bounds
	return result.grow(8.0) if result.has_area() else result


func clear() -> void:
	for entry in _pool:
		if is_instance_valid(entry.node):
			entry.node.hide()
		entry.state = {}
	entries.clear()
	_last = []


func dispose() -> void:
	if is_instance_valid(_viewport) and _viewport.size_changed.is_connected(update_layout):
		_viewport.size_changed.disconnect(update_layout)
	_viewport = null
	clear()
	for entry in _pool:
		if is_instance_valid(entry.node):
			entry.node.free()
	_pool = []
	if is_instance_valid(_template):
		_template.free()
	_template = null
	# Exported arrays belong to native PackedScenes; never clear their containers.
	_plates = []
	_holder = null
	_container = null
	_database = null
	_table = null
	_layout_size = Vector2.ZERO


static func _property(scene: PackedScene, path: String, key: String, fallback):
	var state = scene.get_state()
	while state != null:
		for index in state.get_node_count():
			# SceneState includes a leading "./" for nodes rooted in this scene.
			# Both forms address the same native node; compare canonical paths.
			if str(state.get_node_path(index)).trim_prefix("./") != path.trim_prefix("./"):
				continue
			for property in state.get_node_property_count(index):
				if str(state.get_node_property_name(index, property)) == key:
					return state.get_node_property_value(index, property)
		state = state.get_base_scene_state()
	return fallback

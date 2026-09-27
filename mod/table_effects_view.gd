extends RefCounted
## GAP-007: retained, presentation-only native floor/projectile visuals.
## PackedScene state is read at setup; no native scripts, signals, physics bodies,
## _ready, or effect/gameplay callbacks are ever instantiated on this boundary.

const SceneReader = preload("spectator_scene.gd")
const Effects = preload("table_effects_sync.gd")
const MAX_CREATES_PER_APPLY = 8
const MAX_APPLY_USEC = 4000

var entries: Dictionary = {}
var stats: Dictionary = {}
var _root: Node2D
var _droplet_template: Node2D
var _energy_template: Node2D
var _textures: Array = []
var _fire_material: Material
var _epoch = ""
var _last: Dictionary = {}
var _latest: Dictionary = {}
var _origin = Vector2.ZERO
var _pocket_states: Dictionary = {}


func setup(parent: Node2D, game_scene: PackedScene) -> void:
	dispose()
	_root = Node2D.new()
	_root.name = "TogetherTableEffects"
	parent.add_child(_root)
	var droplet_scene: PackedScene = SceneReader.exported(game_scene, "droplet_scene")
	var energy_scene: PackedScene = SceneReader.exported(game_scene, "energy_ball_scene")
	if droplet_scene != null:
		_droplet_template = SceneReader.create(droplet_scene)
		var textures = SceneReader.exported(droplet_scene, "droplet_sprites")
		if textures is Array:
			# SceneState returns the shared exported Array. Keep only a local array
			# of resource references; renderer teardown must not edit the prefab.
			_textures = textures.duplicate()
	if energy_scene != null:
		_energy_template = SceneReader.create(energy_scene)
	# Native allowlist: this is the flame's material, never a resource path from the wire.
	_fire_material = load("res://effects/fire_droplet_material.tres")


func apply(effects: Dictionary, origin: Vector2, epoch: String) -> void:
	if epoch != _epoch:
		clear()
		_epoch = epoch
	if effects.get("status", "complete") == "overflow":
		return  # Preserve the last complete state; authority advertises recovery separately.
	if stats.get("pending", 0) == 0 and effects == _last and origin == _origin:
		return
	_origin = origin
	var droplets: Array = effects.get("droplets", [])
	var energy: Array = effects.get("energy", [])
	# Defense in depth for local callers; table_effects_sync validates incoming packets.
	if droplets.size() > Effects.MAX_DROPLETS or energy.size() > Effects.MAX_ENERGY:
		return
	_latest = effects
	var started = Time.get_ticks_usec()
	var created = 0
	var pending = 0
	var present: Dictionary = {}
	for state in droplets:
		present[state.id] = true
		if (
			Time.get_ticks_usec() - started >= MAX_APPLY_USEC
			or (not entries.has(state.id) and created >= MAX_CREATES_PER_APPLY)
		):
			pending += 1
			continue
		if not entries.has(state.id):
			created += 1
		var entry = _entry(state.id, int(state.kind), false)
		if not entry.is_empty() and (entry.state != state or entry.origin != origin):
			_apply_pose(entry.node, state, origin)
			_apply_droplet(entry, state)
			entry.state = state.duplicate(true)
			entry.origin = origin
	for state in energy:
		present[state.id] = true
		if (
			Time.get_ticks_usec() - started >= MAX_APPLY_USEC
			or (not entries.has(state.id) and created >= MAX_CREATES_PER_APPLY)
		):
			pending += 1
			continue
		if not entries.has(state.id):
			created += 1
		var entry = _entry(state.id, -1, true)
		if not entry.is_empty() and (entry.state != state or entry.origin != origin):
			_apply_pose(entry.node, state, origin)
			_apply_energy(entry, state, origin)
			entry.state = state.duplicate(true)
			entry.origin = origin
	for id in entries.keys():
		if not present.has(id):
			entries[id].node.free()
			entries.erase(id)
	_last = effects.duplicate(true)
	stats = {
		"pending": pending,
		"created": created,
		"count": entries.size(),
		"usec": Time.get_ticks_usec() - started
	}


func tick() -> void:
	if stats.get("pending", 0) > 0 and not _latest.is_empty():
		apply(_latest, _origin, _epoch)


func apply_pockets(effects: Dictionary, pockets: Dictionary) -> void:
	if effects.get("status", "complete") == "overflow":
		return
	var states: Dictionary = {}
	for state in effects.get("pockets", []):
		states[state.id] = state
	for id in pockets:
		var pocket: Node2D = pockets[id]
		var state: Dictionary = states.get(
			id, {"id": id, "suction_scale": Vector2.ONE, "suction_color": Color.TRANSPARENT}
		)
		var previous: Dictionary = _pocket_states.get(id, {})
		if previous.get("node") == pocket and previous.get("state") == state:
			continue
		var area = pocket.get_node_or_null("Area2D")
		if area is Node2D:
			_set_changed(area, "scale", state.suction_scale)
		var white_hole = pocket.find_child("WhiteHoleEffect", true, false)
		if white_hole is CanvasItem:
			_set_changed(white_hole, "modulate", state.suction_color)
		_pocket_states[id] = {"node": pocket, "state": state.duplicate(true)}
	for id in _pocket_states.keys():
		if not pockets.has(id):
			_pocket_states.erase(id)


func clear() -> void:
	for entry in entries.values():
		if is_instance_valid(entry.node):
			entry.node.free()
	entries.clear()
	for previous in _pocket_states.values():
		if not is_instance_valid(previous.node):
			continue
		var area = previous.node.get_node_or_null("Area2D")
		if area is Node2D:
			_set_changed(area, "scale", Vector2.ONE)
		var white_hole = previous.node.find_child("WhiteHoleEffect", true, false)
		if white_hole is CanvasItem:
			_set_changed(white_hole, "modulate", Color.TRANSPARENT)
	_last.clear()
	_latest = {}
	stats.clear()
	_pocket_states.clear()
	_epoch = ""


func dispose() -> void:
	clear()
	if is_instance_valid(_root):
		_root.free()
	if is_instance_valid(_droplet_template):
		_droplet_template.free()
	if is_instance_valid(_energy_template):
		_energy_template.free()
	_root = null
	_droplet_template = null
	_energy_template = null
	_textures = []
	_fire_material = null


func _entry(id: int, kind: int, energy: bool) -> Dictionary:
	if entries.has(id) and entries[id].kind != kind:
		entries[id].node.free()
		entries.erase(id)
	if entries.has(id):
		return entries[id]
	var template = _energy_template if energy else _droplet_template
	if not is_instance_valid(template) or not is_instance_valid(_root):
		return {}
	var node: Node2D = template.duplicate(0)
	_enable_visuals(node)
	_root.add_child(node)
	var entry: Dictionary = {"node": node, "kind": kind, "state": {}, "origin": Vector2.INF}
	if energy:
		entry.visuals = node.get_node_or_null("visuals")
		entry.sphere = node.get_node_or_null("visuals/ball")
		entry.trails = Effects.line_nodes(node)
		# Node scripts were never copied. GPU particles and shader TIME remain visual only.
	else:
		entry.sprite = node.get_node_or_null("MainSprite")
		entry.shadow = node.get_node_or_null("shadow")
		entry.flower = node.get_node_or_null("Flower")
		entry.flower_spin = node.get_node_or_null("Flower/Spin")
		entry.flower_shadow = node.get_node_or_null("Flower/FlowerShadow")
		entry.flower_label = node.find_child("FlowerLabel", true, false)
		entry.flower_colors = [
			node.get_node_or_null("Flower/Spin/FlowerCore"),
			node.get_node_or_null("Flower/Spin/FlowerPetals1"),
			node.get_node_or_null("Flower/Spin/FlowerPetals2"),
		]
	entries[id] = entry
	return entry


func _apply_pose(node: Node2D, state: Dictionary, origin: Vector2) -> void:
	_set_changed(node, "position", state.position - origin)
	_set_changed(node, "rotation", state.rotation)
	_set_changed(node, "scale", state.scale)
	_set_changed(node, "modulate", state.color)
	_set_changed(node, "visible", state.visible)


func _apply_droplet(entry: Dictionary, state: Dictionary) -> void:
	var sprite: Sprite2D = entry.sprite
	var shadow: Sprite2D = entry.shadow
	var flower: bool = int(state.kind) == 0
	var texture_index = int(state.texture_index)
	if sprite != null:
		if texture_index >= 0 and texture_index < _textures.size():
			_set_changed(sprite, "texture", _textures[texture_index])
		_set_changed(sprite, "visible", not flower)
		_set_changed(sprite, "rotation", state.sprite_rotation)
		_set_changed(sprite, "self_modulate", state.sprite_color)
		_set_changed(sprite, "flip_h", state.sprite_flip_h)
		if int(state.kind) == 5:
			_set_changed(sprite, "material", _fire_material)
	if shadow != null:
		if texture_index >= 0 and texture_index < _textures.size():
			_set_changed(shadow, "texture", _textures[texture_index])
		_set_changed(shadow, "rotation", state.shadow_rotation)
		_set_changed(shadow, "visible", state.shadow_visible)
	if entry.flower != null:
		_set_changed(entry.flower, "visible", flower)
	if not flower:
		return
	if entry.flower_spin != null:
		_set_changed(entry.flower_spin, "rotation", state.flower_rotation)
	if entry.flower_shadow != null:
		_set_changed(entry.flower_shadow, "rotation", state.flower_rotation)
	if entry.flower_label != null:
		_set_changed(
			entry.flower_label, "text", "" if state.flower_power == 1 else str(state.flower_power)
		)
	for index in mini(entry.flower_colors.size(), state.flower_colors.size()):
		if entry.flower_colors[index] != null:
			_set_changed(entry.flower_colors[index], "modulate", state.flower_colors[index])


func _apply_energy(entry: Dictionary, state: Dictionary, origin: Vector2) -> void:
	if entry.visuals != null:
		_set_changed(entry.visuals, "scale", state.visual_scale)
	if entry.sphere != null:
		_set_changed(entry.sphere, "visible", state.get("sphere_visible", false))
	for trail in state.get("trails", []):
		var index: int = int(trail.index)
		if index < 0 or index >= entry.trails.size():
			continue
		var line: Line2D = entry.trails[index]
		var points = PackedVector2Array()
		for point in trail.points:
			points.append(line.to_local(_root.to_global(point - origin)))
		_set_changed(line, "points", points)
		_set_changed(line, "visible", trail.visible)
		_set_changed(line, "modulate", trail.color)
		_set_changed(line, "width", trail.width)


func _enable_visuals(node: Node) -> void:
	# Only scriptless visual classes survived SceneReader. Enable engine particle
	# animation, without inheriting any native game, timer, audio or collision code.
	node.process_mode = Node.PROCESS_MODE_INHERIT
	for child in node.get_children():
		_enable_visuals(child)


func _set_changed(node: Object, property: StringName, value) -> void:
	if node.get(property) != value:
		node.set(property, value)

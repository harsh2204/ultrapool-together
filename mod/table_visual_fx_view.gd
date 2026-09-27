extends RefCounted
## Retained, scriptless native visual scenes. No physics, native _ready or callbacks.

const Fx = preload("table_visual_fx.gd")
const Reader = preload("spectator_scene.gd")
const MAX_CREATES_PER_APPLY = 12
const MAX_APPLY_USEC = 4000

var entries: Dictionary = {}
var stats: Dictionary = {}
var _parent: Node2D
var _catalog: Dictionary = {}
var _epoch = ""
var _generation: Array = []
var _latest: Dictionary = {}
var _origin = Vector2.ZERO


func setup(parent: Node2D, game_scene: PackedScene) -> void:
	_parent = parent
	_catalog = Fx.catalog(parent, game_scene)


func clear() -> void:
	for entry in entries.values():
		if is_instance_valid(entry.node):
			entry.node.queue_free()
	entries.clear()
	_epoch = ""
	_generation.clear()
	_latest = {}
	stats.clear()


func tick() -> void:
	if stats.get("pending", 0) > 0 and not _latest.is_empty():
		apply(_latest, _origin, _epoch)


func apply(data: Dictionary, origin: Vector2, epoch: String) -> void:
	if not is_instance_valid(_parent):
		return
	if epoch != _epoch:
		clear()
		_epoch = epoch
	if data.get("status", "complete") != "complete":
		# Host exposes overflow; retain the last complete view instead of pretending
		# that every native effect disappeared. A new complete state recovers it.
		return
	_latest = data
	_origin = origin
	var started = Time.get_ticks_usec()
	var present: Dictionary = {}
	var created = 0
	var updates = 0
	var pending = 0
	for item in data.get("items", []):
		present[item.id] = true
		if not _catalog.has(item.kind):
			continue
		if Time.get_ticks_usec() - started >= MAX_APPLY_USEC:
			pending += 1
			continue
		var replace = entries.has(item.id) and entries[item.id].kind != item.kind
		if not entries.has(item.id) or replace:
			if (
				created >= MAX_CREATES_PER_APPLY
				or Time.get_ticks_usec() - started >= MAX_APPLY_USEC
			):
				pending += 1
				continue
			# Part indices are validated against the incoming kind's prefab. Never
			# apply those indices to a retained visual created for a different kind.
			if replace:
				entries[item.id].node.queue_free()
				entries.erase(item.id)
			_create(item)
			created += 1
		var entry: Dictionary = entries[item.id]
		if entry.state != item or entry.origin != origin:
			_apply_item(entry, item, origin)
			entry.state = item.duplicate(true)
			entry.origin = origin
			updates += 1
	for id in entries.keys():
		if not present.has(id):
			entries[id].node.queue_free()
			entries.erase(id)
	stats = {
		"usec": Time.get_ticks_usec() - started,
		"created": created,
		"updated": updates,
		"pending": pending,
		"count": entries.size()
	}


func _create(item: Dictionary) -> void:
	var definition: Dictionary = _catalog[item.kind]
	var node = definition.template.duplicate(0)
	_enable_visual_process(node)
	node.name = "RemoteFx_%s_%d" % [item.kind, item.id]
	var parts: Array = []
	for part in definition.parts:
		var visual = node.get_node_or_null(part.path)
		if visual is CanvasItem and visual.material != null:
			visual.material = visual.material.duplicate()
		parts.append(visual)
	_parent.add_child(node)
	entries[item.id] = {
		"node": node,
		"kind": item.kind,
		"parts": parts,
		"state": {},
		"origin": Vector2.INF,
		"links": []
	}
	if item.kind == "constellation":
		_build_constellation(entries[item.id], item, definition)


func _apply_item(entry: Dictionary, item: Dictionary, origin: Vector2) -> void:
	for state in item.parts:
		var part = entry.parts[state.index]
		if not is_instance_valid(part):
			continue
		var position: Vector2 = state.position - origin if state.index == 0 else state.position
		if part.position != position:
			part.position = position
		if part.rotation != state.rotation:
			part.rotation = state.rotation
		if part.scale != state.scale:
			part.scale = state.scale
		if part.modulate != state.modulate:
			part.modulate = state.modulate
		if part.self_modulate != state.self_modulate:
			part.self_modulate = state.self_modulate
		if part.visible != state.visible:
			part.visible = state.visible
		if part is Sprite2D:
			if state.has("frame") and part.frame != state.frame:
				part.frame = mini(state.frame, part.hframes * part.vframes - 1)
			if state.has("texture") and part.texture != Fx.textures().get(state.texture):
				part.texture = Fx.textures()[state.texture]
		if part is Line2D:
			if state.has("points") and part.points != state.points:
				part.points = state.points
			if state.has("width") and part.width != state.width:
				part.width = state.width
			if state.has("color") and part.default_color != state.color:
				part.default_color = state.color
		if part is GPUParticles2D or part is CPUParticles2D:
			if state.has("emitting") and part.emitting != state.emitting:
				part.emitting = state.emitting
		if part is Label and state.has("text") and part.text != state.text:
			part.text = state.text
		if part.material is ShaderMaterial:
			for key in state.get("shader", {}):
				if part.material.get_shader_parameter(key) != state.shader[key]:
					part.material.set_shader_parameter(key, state.shader[key])


func _build_constellation(entry: Dictionary, item: Dictionary, definition: Dictionary) -> void:
	for point in item.get("stars", []):
		if definition.get("star") is PackedScene:
			var star = Reader.create(definition.star)
			_enable_visual_process(star)
			entry.node.add_child(star)
			star.position = point
	for pair in item.get("connections", []):
		if definition.get("line") is PackedScene:
			var line = Reader.create(definition.line)
			_enable_visual_process(line)
			entry.node.add_child(line)
			if line is Line2D:
				line.points = PackedVector2Array([item.points[pair[0]], item.points[pair[1]]])


func _enable_visual_process(node: Node) -> void:
	# Reader strips scripts, physics, sound and timers. Only native visual classes
	# remain; particles need engine processing even though no game code runs.
	node.process_mode = Node.PROCESS_MODE_INHERIT
	for child in node.get_children():
		_enable_visual_process(child)

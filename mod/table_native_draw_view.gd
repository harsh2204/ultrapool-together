extends RefCounted
## Native presentation trees only; the ritual, scoring and prediction scripts
## are never instantiated, and cannot mutate replica gameplay or shared money.

const Draw = preload("table_native_draw.gd")
const Reader = preload("spectator_scene.gd")
const MAX_CREATES_PER_APPLY = 8
const MAX_APPLY_USEC = 2000

var entries: Dictionary = {}
var stats: Dictionary = {}
var _templates: Dictionary = {}
var _parent: Node2D
var _latest: Dictionary = {}
var _origin = Vector2.ZERO
var _epoch = ""
var _expired: Dictionary = {}
var _hidden_kinds: Dictionary = {}


func set_kind_hidden(kind: String, hidden: bool) -> void:
	if not Draw.PATHS.has(kind) or bool(_hidden_kinds.get(kind, false)) == hidden:
		return
	_hidden_kinds[kind] = hidden
	for entry in entries.values():
		if entry.kind == kind:
			entry.node.visibility_layer = 0 if hidden else entry.visibility_layer


func setup(parent: Node2D, game_scene: PackedScene) -> void:
	dispose()
	_parent = parent
	# Native resource discovery is confined to this lifecycle boundary.
	var table_scene = Reader.exported(game_scene, "table_scene")
	var ball_scene = Reader.exported(game_scene, "ball_scene")
	var score_scene = Reader.exported(game_scene, "score_display_scene")
	if table_scene is PackedScene:
		var table = Reader.create(table_scene)
		_take_template(table, "Pentagram", "pentagram")
		table.free()
	if ball_scene is PackedScene:
		var ball = Reader.create(ball_scene)
		_take_template(ball, "Trail", "trail")
		_take_template(ball, "visuals/deathline", "tether")
		ball.free()
	if score_scene is PackedScene:
		_templates["score"] = Reader.create(score_scene)
	_templates["prediction"] = Reader.create(load("res://prediction_small.tscn"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		dispose()


func dispose() -> void:
	# Templates are off-tree Nodes, so the owning scene cannot release them.
	# Dispose at board/owner teardown while the rendering server is still alive;
	# RefCounted predelete is only a fallback, not the ordinary lifetime boundary.
	clear()
	_free_templates()
	_parent = null
	_hidden_kinds.clear()


func _free_templates() -> void:
	for template in _templates.values():
		if is_instance_valid(template):
			template.free()
	_templates = {}


func _take_template(root: Node, path: String, kind: String) -> void:
	var node = root.get_node_or_null(path)
	if node == null:
		return
	node.get_parent().remove_child(node)
	_templates[kind] = node


func clear() -> void:
	for entry in entries.values():
		if is_instance_valid(entry.node):
			entry.node.queue_free()
	entries.clear()
	_latest = {}
	_expired.clear()
	_epoch = ""
	stats.clear()


func tick() -> void:
	var now = Time.get_ticks_msec()
	for id in entries.keys():
		var entry: Dictionary = entries[id]
		if entry.kind == "score" and entry.until <= now:
			_expired[id] = entry.state
			entry.node.queue_free()
			entries.erase(id)
	if stats.get("pending", 0) > 0 and not _latest.is_empty():
		apply(_latest, _origin, _epoch)


func apply(data: Dictionary, origin: Vector2, epoch: String) -> void:
	if not is_instance_valid(_parent):
		return
	if epoch != _epoch:
		clear()
		_epoch = epoch
	if data.get("status", "complete") != "complete":
		# Discard pending creations: an overflow must never drain a stale generation.
		_latest = {}
		stats["pending"] = 0
		return
	_latest = data
	_origin = origin
	var started = Time.get_ticks_usec()
	var present: Dictionary = {}
	var created = 0
	var pending = 0
	var updated = 0
	for item in data.get("items", []):
		present[item.id] = true
		if not _templates.has(item.kind) or _expired.get(item.id) == item:
			continue
		if Time.get_ticks_usec() - started >= MAX_APPLY_USEC:
			pending += 1
			continue
		if entries.has(item.id) and entries[item.id].kind != item.kind:
			entries[item.id].node.queue_free()
			entries.erase(item.id)
		if not entries.has(item.id):
			if created >= MAX_CREATES_PER_APPLY:
				pending += 1
				continue
			_create(item)
			created += 1
		var entry: Dictionary = entries[item.id]
		if entry.state != item or entry.origin != origin:
			_apply_item(entry, item, origin)
			entry.state = item.duplicate(true)
			entry.origin = origin
			entry.until = Time.get_ticks_msec() + int((item.get("ttl", 0.0) + 0.25) * 1000)
			_expired.erase(item.id)
			updated += 1
	for id in entries.keys():
		if not present.has(id):
			entries[id].node.queue_free()
			entries.erase(id)
	for id in _expired.keys():
		if not present.has(id):
			_expired.erase(id)
	stats = {
		"usec": Time.get_ticks_usec() - started,
		"created": created,
		"updated": updated,
		"pending": pending,
		"count": entries.size()
	}


func _create(item: Dictionary) -> void:
	var node = _templates[item.kind].duplicate(0)
	node.name = "NativeDraw_%s_%d" % [item.kind, item.id]
	var parts: Array = []
	for path in Draw.PATHS[item.kind]:
		var part = node.get_node_or_null(path)
		if part is CanvasItem and part.material != null:
			part.material = part.material.duplicate()
		if part is Line2D and part.gradient != null:
			part.gradient = part.gradient.duplicate()
		if part is Control:
			# Host already resolved centered minimum-size growth.
			part.grow_horizontal = Control.GROW_DIRECTION_END
			part.grow_vertical = Control.GROW_DIRECTION_END
		parts.append(part)
	_parent.add_child(node)
	entries[item.id] = {
		"node": node,
		"kind": item.kind,
		"parts": parts,
		"state": {},
		"origin": Vector2.INF,
		"until": 0,
		"visibility_layer": node.visibility_layer
	}
	if _hidden_kinds.get(item.kind, false):
		node.visibility_layer = 0


func _apply_item(entry: Dictionary, item: Dictionary, origin: Vector2) -> void:
	# Update all child text before sizing their containing panels. Otherwise the
	# template's old "WIN!" minimum can clamp a score-only hidden panel's size.
	for state in item.parts:
		var part = entry.parts[state.index]
		if part is Label and part.text != state.text:
			part.text = state.text
	for state in item.parts:
		var part = entry.parts[state.index]
		if not is_instance_valid(part):
			continue
		if part is Control and part.size != state.size:
			part.size = state.size
		var position: Vector2 = state.position - origin if state.index == 0 else state.position
		if part.position != position:
			part.position = position
		if part.rotation != state.rotation:
			part.rotation = state.rotation
		if part.scale != state.scale:
			part.scale = state.scale
		if part.visible != state.visible:
			part.visible = state.visible
		if part.modulate != state.modulate:
			part.modulate = state.modulate
		if part.self_modulate != state.self_modulate:
			part.self_modulate = state.self_modulate
		if part.z_index != state.z:
			part.z_index = state.z
		if part is Line2D:
			if part.points != state.points:
				part.points = state.points
			if part.width != state.width:
				part.width = state.width
			if part.default_color != state.color:
				part.default_color = state.color
			if state.gradient_colors.is_empty():
				part.gradient = null
			else:
				if part.gradient == null:
					part.gradient = Gradient.new()
				if (
					part.gradient.colors != state.gradient_colors
					or part.gradient.offsets != state.gradient_offsets
				):
					part.gradient.offsets = state.gradient_offsets
					part.gradient.colors = state.gradient_colors
		if part.material is ShaderMaterial:
			for key in state.get("shader", {}):
				if part.material.get_shader_parameter(key) != state.shader[key]:
					part.material.set_shader_parameter(key, state.shader[key])

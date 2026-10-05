extends Node
## Native presentation only. No wire resource paths or native callbacks.
## GAP-007 / PERF-019: bounded active descriptors and short-lived spawn retention.

const Reader = preload("spectator_scene.gd")
const MAX_EFFECTS = 96
const MAX_PARTS = 96
const MAX_POINTS = 64
const MAX_BYTES = 98304
const RETAIN_MSEC = 250
const MAX_SCAN = 192
const MAX_CAPTURE_USEC = 4000
const WISP_TEXTURES = ["apple", "cloud", "compass", "egg", "window", "circle", "gear", "wheel", "upgrade", "time", "mushroom"]

static var _catalog: Dictionary = {}
static var _textures: Dictionary = {}
static var _capture_owners = 0
var _paths: Dictionary = {}
var _tracked: Dictionary = {}
var _epoch = ""
var _overflow_until = 0
var _overflow_live = 0
var capture_stats: Dictionary = {}


static func catalog(context: Node, game_scene: PackedScene = null) -> Dictionary:
	if not _catalog.is_empty():
		return _catalog
	if not context.is_inside_tree():
		return _catalog
	var manager = context.get_node_or_null("/root/EffectManager")
	if manager == null:
		return _catalog
	for key in manager.effects:
		var scene = manager.effects[key]
		if scene is PackedScene:
			_cache_scene(str(key), scene)
	if game_scene == null:
		var global_node = context.get_node_or_null("/root/Global")
		if global_node != null:
			game_scene = global_node.SCENE_GAME
	if game_scene != null:
		for key in ["wisp", "pocket_wisp"]:
			var scene = Reader.exported(game_scene, key + "_scene")
			if scene is PackedScene:
				_cache_scene(key, scene)
	# Fixed installed-game resource names, never a received path. Loaded once.
	for key in WISP_TEXTURES:
		var file_name = "apple_slice" if key == "apple" else key
		_textures[key] = load("res://effects/wisps/%s.png" % file_name)
	return _catalog


static func textures() -> Dictionary:
	return _textures


static func _cache_scene(key: String, scene: PackedScene) -> void:
	var template = Reader.create(scene)
	var parts: Array = []
	var complete = _collect_parts(template, template, parts)
	_catalog[key] = {"scene": scene, "template": template, "parts": parts, "complete": complete}
	if key == "constellation":
		_catalog[key]["star"] = Reader.exported(scene, "star_scn")
		_catalog[key]["line"] = Reader.exported(scene, "line_scn")


static func _collect_parts(root: Node, node: Node, parts: Array) -> bool:
	if parts.size() >= MAX_PARTS:
		return false
	if node is Node2D or node is Control:
		var shaders: Array = []
		var shader_types: Dictionary = {}
		if node.material is ShaderMaterial and node.material.shader != null:
			for uniform in node.material.shader.get_shader_uniform_list():
				var value = node.material.get_shader_parameter(uniform.name)
				if _visual_value(value):
					shaders.append(str(uniform.name))
					shader_types[str(uniform.name)] = typeof(value)
		parts.append({"path": str(root.get_path_to(node)), "shaders": shaders, "shader_types": shader_types})
	for child in node.get_children():
		if not _collect_parts(root, child, parts):
			return false
	return true


func _ready() -> void:
	_capture_owners += 1
	catalog(self)
	for key in _catalog:
		_paths[_catalog[key].scene.resource_path] = key
	get_tree().node_added.connect(_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_node_added):
		get_tree().node_added.disconnect(_node_added)
	_tracked.clear()
	_capture_owners -= 1
	if _capture_owners > 0:
		return
	for entry in _catalog.values():
		if is_instance_valid(entry.template):
			entry.template.free()
	_catalog.clear()
	_textures.clear()


func clear() -> void:
	_tracked.clear()
	_epoch = ""
	_overflow_until = 0
	_overflow_live = 0


func has_pending_or_active_effects() -> bool:
	return not _tracked.is_empty() or _overflow_live > 0 or _overflow_until > Time.get_ticks_msec()


func _node_added(node: Node) -> void:
	if not _paths.has(node.scene_file_path):
		return
	var global_node = get_node_or_null("/root/Global")
	var game = global_node.gameManager if global_node != null else null
	if not is_instance_valid(game) or game.has_method("apply_table") or game.in_shop:
		return
	var epoch = "%d:%d" % [game.get_instance_id(), game.rounds_played]
	if epoch != _epoch:
		clear()
		_epoch = epoch
	if _tracked.size() >= MAX_EFFECTS:
		_overflow_until = Time.get_ticks_msec() + RETAIN_MSEC
		_overflow_live += 1
		node.tree_exiting.connect(_overflow_node_exiting.bind(_epoch), CONNECT_ONE_SHOT)
		return
	var id = node.get_instance_id()
	_tracked[id] = {"node": weakref(node), "kind": _paths[node.scene_file_path], "last": {}, "until": 0}
	node.tree_exiting.connect(_node_exiting.bind(id), CONNECT_ONE_SHOT)
	# Native callers assign position, targets, colors and endpoints after add_child.
	call_deferred("_remember", id)


func _overflow_node_exiting(epoch: String) -> void:
	if epoch == _epoch:
		_overflow_live = maxi(0, _overflow_live - 1)


func _remember(id: int) -> void:
	if not _tracked.has(id):
		return
	var entry: Dictionary = _tracked[id]
	var node = entry.node.get_ref()
	if is_instance_valid(node) and node.is_inside_tree():
		entry.last = _describe(node, entry.kind)


func _node_exiting(id: int) -> void:
	if not _tracked.has(id):
		return
	# Preserve its last visible pose briefly so a sub-tick native effect can be
	# delivered reliably. No old sound or gameplay callback is replayed on join.
	_tracked[id].until = Time.get_ticks_msec() + RETAIN_MSEC


func capture(game: Node) -> Dictionary:
	var started = Time.get_ticks_usec()
	var now = Time.get_ticks_msec()
	var epoch = "%d:%d" % [game.get_instance_id(), game.rounds_played]
	if epoch != _epoch or game.in_shop:
		clear()
		_epoch = epoch
	var result = {"version": 1, "status": "complete", "reason": "", "items": []}
	var scanned = 0
	var bytes = 0
	for id in _tracked.keys():
		scanned += 1
		if scanned > MAX_SCAN or Time.get_ticks_usec() - started > MAX_CAPTURE_USEC:
			return _overflow("capture budget", started, scanned)
		var entry: Dictionary = _tracked[id]
		if not _catalog[entry.kind].complete:
			return _overflow("unsupported native effect layout", started, scanned)
		var node = entry.node.get_ref()
		if entry.until > 0 and entry.until <= now:
			_tracked.erase(id)
			continue
		if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion():
			entry.last = _describe(node, entry.kind)
		elif entry.until == 0:
			_tracked.erase(id)
			continue
		if entry.last.is_empty():
			continue
		var item: Dictionary = entry.last
		bytes += var_to_bytes(item).size()
		if bytes > MAX_BYTES or result.items.size() >= MAX_EFFECTS:
			return _overflow("descriptor budget", started, scanned)
		result.items.append(item)
	if _overflow_live > 0 or _overflow_until > now:
		return _overflow("active effect count", started, scanned)
	# PERF-004/019: the host already summed each item's encoding above; reuse it
	# instead of serializing the whole substate a second time per snapshot.
	var invalid = problem(result, bytes)
	if not invalid.is_empty():
		return _overflow(invalid, started, scanned)
	capture_stats = {"usec": Time.get_ticks_usec() - started, "count": result.items.size(), "bytes": bytes, "scanned": scanned}
	return result


func _overflow(reason: String, started: int, scanned: int) -> Dictionary:
	capture_stats = {"usec": Time.get_ticks_usec() - started, "scanned": scanned, "overflow": reason}
	return {"version": 1, "status": "overflow", "reason": reason, "items": []}


func _describe(node: Node2D, kind: String) -> Dictionary:
	var item = {"id": node.get_instance_id(), "kind": kind, "parts": []}
	var index = 0
	for definition in _catalog[kind].parts:
		var part = node.get_node_or_null(definition.path)
		if part is Node2D or part is Control:
			var state = {"index": index, "position": part.position, "rotation": part.rotation, "scale": part.scale,
				"modulate": part.modulate, "self_modulate": part.self_modulate, "visible": part.visible}
			if part != node and part.is_set_as_top_level() and part.get_parent() is Node2D:
				# Native wisp trails use world-space points. Express their transform
				# relative to the visual parent so spectator world scaling still works.
				var relative: Transform2D = part.get_parent().global_transform.affine_inverse() * part.global_transform
				state.position = relative.origin
				state.rotation = relative.get_rotation()
				state.scale = relative.get_scale()
			if part == node:
				state.position = node.global_position
				state.rotation = node.global_rotation
				state.scale = node.global_scale
			if part is Sprite2D:
				state["frame"] = part.frame
				for key in _textures:
					if part.texture == _textures[key]:
						state["texture"] = key
			if part is Line2D:
				state["points"] = part.points
				state["width"] = part.width
				state["color"] = part.default_color
			if part is GPUParticles2D or part is CPUParticles2D:
				state["emitting"] = part.emitting
			if part is Label:
				state["text"] = part.text
			if not definition.shaders.is_empty() and part.material is ShaderMaterial:
				var shaders: Dictionary = {}
				for key in definition.shaders:
					shaders[key] = part.material.get_shader_parameter(key)
				state["shader"] = shaders
			item.parts.append(state)
		index += 1
	if kind == "constellation":
		item["points"] = PackedVector2Array(node.points)
		item["connections"] = node.connections.duplicate(true)
		var stars = PackedVector2Array()
		for point in node.points:
			stars.append(node.to_local(point))
		item["stars"] = stars
	return item


static func topology(data: Dictionary) -> Dictionary:
	var result: Dictionary = {"status": data.get("status", "complete")}
	for item in data.get("items", []):
		result[item.id] = item.kind
	return result


## encoded_bytes < 0 means "unknown": the network boundary measures the payload
## itself. Host capture passes its item byte sum so validation never re-encodes.
static func problem(data, encoded_bytes: int = -1) -> String:
	if not data is Dictionary:
		return "visual effects type"
	if data.is_empty():
		return ""
	if data.get("version") != 1 or data.get("status") not in ["complete", "overflow"]:
		return "visual effects version/status"
	if not data.get("reason") is String or data.reason.length() > 64:
		return "visual effects reason"
	if not data.get("items") is Array or data.items.size() > MAX_EFFECTS:
		return "visual effects count"
	if data.status == "overflow" and not data.items.is_empty():
		return "visual effects partial overflow"
	var encoded = encoded_bytes if encoded_bytes >= 0 else var_to_bytes(data).size()
	if encoded > MAX_BYTES + 1024:
		return "visual effects bytes"
	var ids: Dictionary = {}
	for item in data.items:
		if not item is Dictionary or not item.get("id") is int or item.id <= 0 or ids.has(item.id):
			return "visual effect identity"
		ids[item.id] = true
		if not item.get("kind") is String or not _catalog.has(item.kind):
			return "visual effect kind"
		if not item.get("parts") is Array or item.parts.size() > MAX_PARTS:
			return "visual effect parts"
		var indices: Dictionary = {}
		for part in item.parts:
			if not part is Dictionary or not part.get("index") is int:
				return "visual effect part identity"
			if part.index < 0 or part.index >= _catalog[item.kind].parts.size() or indices.has(part.index):
				return "visual effect part index"
			indices[part.index] = true
			for key in ["position", "scale"]:
				if not part.get(key) is Vector2 or not _visual_value(part[key]):
					return "visual effect transform"
			if not _number(part.get("rotation")) or not part.get("visible") is bool:
				return "visual effect pose"
			for key in ["modulate", "self_modulate"]:
				if not part.get(key) is Color or not _visual_value(part[key]):
					return "visual effect color"
			if part.has("texture") and part.texture not in WISP_TEXTURES:
				return "visual effect texture"
			if part.has("frame") and (not part.frame is int or part.frame < 0 or part.frame > 4096):
				return "visual effect frame"
			if part.has("points") and not _points(part.points):
				return "visual effect line"
			if part.has("width") and (not _number(part.width) or part.width < 0 or part.width > 1024):
				return "visual effect width"
			if part.has("color") and (not part.color is Color or not _visual_value(part.color)):
				return "visual effect line color"
			if part.has("emitting") and not part.emitting is bool:
				return "visual effect particles"
			if part.has("text") and (not part.text is String or part.text.length() > 256):
				return "visual effect label"
			if part.has("shader"):
				if not part.shader is Dictionary or part.shader.size() > 32:
					return "visual effect shader"
				for key in part.shader:
					if key not in _catalog[item.kind].parts[part.index].shaders or not _visual_value(part.shader[key]):
						return "visual effect shader value"
					var expected: int = _catalog[item.kind].parts[part.index].shader_types[key]
					if typeof(part.shader[key]) != expected and not (expected == TYPE_FLOAT and part.shader[key] is int):
						return "visual effect shader type"
		if item.kind == "constellation":
			if not _points(item.get("points")) or not _points(item.get("stars")) or item.stars.size() != item.points.size() or not item.get("connections") is Array or item.connections.size() > MAX_POINTS:
				return "visual effect constellation"
			for pair in item.connections:
				if not pair is Array or pair.size() != 2:
					return "visual effect link"
				for index in pair:
					if not index is int or index < 0 or index >= item.points.size():
						return "visual effect link index"
	return ""


static func _points(value) -> bool:
	if not value is PackedVector2Array or value.size() > MAX_POINTS:
		return false
	for point in value:
		if not _visual_value(point):
			return false
	return true


static func _number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and abs(float(value)) <= 1.0e7


static func _visual_value(value) -> bool:
	if value is bool:
		return true
	if value is float or value is int:
		return _number(value)
	if value is Vector2:
		return _number(value.x) and _number(value.y)
	if value is Vector3:
		return _number(value.x) and _number(value.y) and _number(value.z)
	if value is Vector4:
		return _number(value.x) and _number(value.y) and _number(value.z) and _number(value.w)
	if value is Color:
		return _number(value.r) and _number(value.g) and _number(value.b) and _number(value.a)
	return false

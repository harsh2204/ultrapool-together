extends RefCounted
## BOARD-02/05–10/21/22, DRAW-06, HUD-06; PERF-018/019/024.
## Sample native ball art, never its callbacks. Sparse indexed differences from
## installed scene defaults bound wire overhead; omitted fields restore defaults.
## Templates are immutable and bounded to the two installed ball scenes.

const Reader = preload("spectator_scene.gd")
const PATHS = [
	"visuals", "visuals/ball", "visuals/static/flash", "visuals/static/edge",
	"visuals/static/FireEffect", "visuals/static/StarEffect",
	"visuals/static/score_effects", "visuals/static/score_effects/outline",
	"visuals/static/score_effects/score_particles", "visuals/static/spark",
	"visuals/static/Panel", "visuals/static/freeze_indicator",
	"visuals/static/fire_indicator", "visuals/static/star_indicator",
	"visuals/static/shield_indicator", "visuals/static/shield_broken_indicator",
	"visuals/static/outline", "visuals/static/shadowTransform/shadow"
]
const PROPERTIES = ["visible", "position", "rotation", "scale", "modulate", "self_modulate"]
const PARTICLE_PROPERTIES = ["emitting", "amount", "speed_scale", "lifetime"]
const PROCESS_PROPERTIES = [
	"color", "emission_sphere_radius", "initial_velocity_min", "initial_velocity_max",
	"scale_min", "scale_max", "angular_velocity_min", "angular_velocity_max"
]
const MAX_FIELDS = 512
const META = "together_ball_visual_nodes"
static var _layouts: Dictionary = {}
static var _sparks: Array = []
static var _spark_defaults: Dictionary = {}


static func prepare() -> void:
	if not _layouts.is_empty():
		return
	_sparks = Reader.exported(load("res://singletons/effect_manager.tscn"), "sparks").duplicate()
	for player in [false, true]:
		var template = Reader.create(load("res://player_ball.tscn" if player else "res://ball.tscn"))
		var fields: Array = []
		for path in PATHS:
			var node = template.get_node_or_null(path)
			if not node is CanvasItem:
				continue
			for property in PROPERTIES:
				if path == "visuals" and property in ["position", "rotation", "scale"]:
					continue
				fields.append([path, property, node.get(property), 0])
			if node is Sprite2D:
				fields.append([path, "frame", node.frame, 0])
				if path == "visuals/static/spark":
					_spark_defaults[int(player)] = node.texture
					fields.append([path, "spark_index", _sparks.find(node.texture), 3])
			if node is GPUParticles2D or node is CPUParticles2D:
				for property in PARTICLE_PROPERTIES:
					fields.append([path, property, node.get(property), 0])
			if node is GPUParticles2D and node.process_material is ParticleProcessMaterial:
				for property in PROCESS_PROPERTIES:
					fields.append([path, property, node.process_material.get(property), 2])
			if node.material is ShaderMaterial and node.material.shader != null:
				for uniform in node.material.shader.get_shader_uniform_list():
					# Ball spin has a dedicated interpolated stream. Textures remain local.
					if str(uniform.name).begins_with("rotation_"):
						continue
					var value = node.material.get_shader_parameter(uniform.name)
					if _value_ok(value):
						fields.append([path, str(uniform.name), value, 1])
		_layouts[int(player)] = fields
		template.free()


static func _nodes(body: Node, isolate: bool = false) -> Dictionary:
	if body.has_meta(META):
		return body.get_meta(META)
	var result: Dictionary = {}
	for path in PATHS:
		var node = body.get_node_or_null(path)
		if not node is CanvasItem:
			continue
		result[path] = node
		if isolate:
			if body.get_script() == null:
				# The scriptless scene reader disables every ancestor, not just the
				# emitter. Restore the complete safe chain for native particles.
				var ancestor: Node = node
				while ancestor != null:
					ancestor.process_mode = Node.PROCESS_MODE_INHERIT
					if ancestor == body:
						break
					ancestor = ancestor.get_parent()
			node.set_meta("together_ball_visual_authoritative", true)
			# Native particle process materials are shared by the packed scene.
			if node is GPUParticles2D and node.process_material != null:
				node.process_material = node.process_material.duplicate()
			if node.material != null:
				node.material = node.material.duplicate()
			if node is GPUParticles2D or node is CPUParticles2D:
				node.process_mode = Node.PROCESS_MODE_INHERIT
	body.set_meta(META, result)
	return result


static func capture(body: Node) -> Dictionary:
	prepare()
	var player: bool = body is PlayerBall
	var nodes = _nodes(body)
	var changes: Array = []
	var index = 0
	for field in _layouts[int(player)]:
		var node = nodes.get(field[0])
		if is_instance_valid(node):
			var value = _read(node, field)
			if not _equal_value(value, field[2]) and _value_ok(value):
				changes.append([index, value])
		index += 1
	return {"v": 1, "p": int(player), "d": changes}


static func problem(data) -> String:
	if not data is Dictionary:
		return "ball visual state"
	if data.is_empty():
		return ""
	if data.size() != 3 or data.get("v") != 1 or typeof(data.get("p")) != TYPE_INT:
		return "ball visual header"
	if data.p < 0 or data.p > 1 or not data.get("d") is Array or data.d.size() > MAX_FIELDS:
		return "ball visual bounds"
	prepare()
	var fields: Array = _layouts[data.p]
	var last = -1
	for entry in data.d:
		if not entry is Array or entry.size() != 2 or typeof(entry[0]) != TYPE_INT:
			return "ball visual field"
		var index: int = entry[0]
		if index <= last or index >= fields.size():
			return "ball visual field identity"
		last = index
		var value = entry[1]
		if not _same_value_type(value, fields[index][2], fields[index][3] == 1) or not _value_ok(value):
			return "ball visual value"
		var property: String = fields[index][1]
		if property == "spark_index" and (value < -1 or value >= _sparks.size()):
			return "ball visual spark texture"
		if property == "amount" and (value < 1 or value > (10 if fields[index][0].ends_with("score_particles") else int(fields[index][2]))):
			return "ball visual particle amount"
		if property == "speed_scale" and (value < 0.0 or value > 4.0):
			return "ball visual particle speed"
		if fields[index][3] == 2 and typeof(value) == TYPE_FLOAT:
			if absf(value) > 1000.0 or (property in ["emission_sphere_radius", "scale_min", "scale_max"] and value < 0.0):
				return "ball visual particle process"
		if property == "lifetime" and (value <= 0.0 or value > 10.0):
			return "ball visual particle lifetime"
		if property == "frame" and (value < 0 or value > 1024):
			return "ball visual sprite frame"
	return ""


static func apply(body: Node, data: Dictionary) -> void:
	if data.is_empty():
		return
	prepare()
	var nodes = _nodes(body, true)
	var fields: Array = _layouts[data.p]
	var cursor = 0
	for index in fields.size():
		var field: Array = fields[index]
		var value = field[2]
		if cursor < data.d.size() and data.d[cursor][0] == index:
			value = data.d[cursor][1]
			cursor += 1
		var node = nodes.get(field[0])
		if not is_instance_valid(node) or _equal_value(_read(node, field), value):
			continue
		if field[3] == 1:
			if node.material is ShaderMaterial:
				node.material.set_shader_parameter(field[1], value)
				if field[0] == "visuals/static/flash" and field[1] == "alpha" and body.get_script() != null:
					body.set("flash_alpha", value)
		elif field[3] == 2:
			if node is GPUParticles2D and node.process_material != null:
				node.process_material.set(field[1], value)
		elif field[3] == 3:
			node.texture = _sparks[value] if value >= 0 else _spark_defaults[data.p]
		elif field[1] == "frame" and node is Sprite2D:
			node.frame = mini(int(value), node.hframes * node.vframes - 1)
		else:
			node.set(field[1], value)


static func _read(node: CanvasItem, field: Array):
	if field[3] == 3:
		return _sparks.find(node.texture)
	if field[3] == 1:
		return node.material.get_shader_parameter(field[1]) if node.material is ShaderMaterial else null
	if field[3] == 2:
		return node.process_material.get(field[1]) if node is GPUParticles2D and node.process_material != null else null
	return node.get(field[1])


static func _value_ok(value) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return true
		TYPE_INT, TYPE_FLOAT:
			return is_finite(float(value)) and absf(float(value)) <= 100000.0
		TYPE_VECTOR2:
			return value.is_finite() and value.abs().x <= 100000.0 and value.abs().y <= 100000.0
		TYPE_VECTOR3:
			return value.is_finite() and value.length_squared() <= 10000000000.0
		TYPE_VECTOR4:
			return is_finite(value.x) and is_finite(value.y) and is_finite(value.z) and is_finite(value.w) and value.length_squared() <= 10000000000.0
		TYPE_COLOR:
			return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a) and absf(value.r) <= 16.0 and absf(value.g) <= 16.0 and absf(value.b) <= 16.0 and absf(value.a) <= 16.0
	return false


static func _same_value_type(value, baseline, shader: bool) -> bool:
	# Godot returns Color after native setters write a packed vec4 uniform.
	return typeof(value) == typeof(baseline) or (shader and typeof(value) in [TYPE_COLOR, TYPE_VECTOR4] and typeof(baseline) in [TYPE_COLOR, TYPE_VECTOR4])


static func _equal_value(left, right) -> bool:
	# Native setters store Color into an installed vec4 uniform. Variant equality
	# across those types does not express component equality. Normalize only the
	# comparison; keep the host's exact typed shader value in the descriptor.
	if typeof(left) in [TYPE_COLOR, TYPE_VECTOR4] and typeof(right) in [TYPE_COLOR, TYPE_VECTOR4]:
		var a: Vector4 = Vector4(left.r, left.g, left.b, left.a) if left is Color else left
		var b: Vector4 = Vector4(right.r, right.g, right.b, right.a) if right is Color else right
		return a == b
	return typeof(left) == typeof(right) and left == right

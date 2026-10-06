extends RefCounted

## GAP-007 / PERF-008/014/019: native effect presentation only. No resource paths,
## callbacks or gameplay instructions cross this boundary. Counts bound capture
## scans and validation; overflow preserves normal table delivery and explicitly
## pauses effect replacement until a complete bounded state becomes available.

const VERSION = 1
const MAX_DROPLETS = 128
const MAX_ENERGY = 32
const MAX_POCKETS = 16
const MAX_SCAN_DROPLETS = 256
const MAX_SCAN_ENERGY = 64
const MAX_SCAN_POCKETS = 32
const MAX_RECOVERY_CHILDREN = 256
const MAX_TRAILS = 4
const MAX_TRAIL_POINTS = 32
const MAX_TRAIL_NODES = 256
const MAX_BYTES = 96 * 1024
# Installed 0.17.2 Droplet enum: FLOWER, OIL, THORN, LAUNCHPAD, STOVE,
# FLAME, CANDY. Keep this explicit; received values never select resources.
const KINDS = [0, 1, 2, 3, 4, 5, 6]
const REASONS = [
	"droplet candidates",
	"droplets",
	"energy candidates",
	"energy",
	"pocket candidates",
	"pockets",
	"descriptor",
	"bytes"
]
const POCKET_VISUAL_PATHS = [
	".", "Doors", "Doors/Left", "Doors/Right", "ShieldIndicator",
	"SkullIndicator", "Label", "ExtraScoreLabelPivot"
]
const COMMON = ["id", "position", "rotation", "scale", "color", "visible"]
const DROPLET_FIELDS = [
	"kind",
	"texture_index",
	"sprite_rotation",
	"sprite_color",
	"sprite_flip_h",
	"shadow_rotation",
	"shadow_visible",
	"flower_rotation",
	"flower_power",
	"flower_colors",
	"charges",
	"direction",
	"held_ball_id",
	"launch_timer"
]
const ENERGY_FIELDS = [
	"velocity", "visual_scale", "spin", "alive", "spawned", "gone", "sphere_visible", "trails"
]


static func empty() -> Dictionary:
	return {
		"version": VERSION,
		"status": "complete",
		"reason": "",
		"droplets": [],
		"energy": [],
		"pockets": []
	}


static func overflow(reason: String) -> Dictionary:
	var data = empty()
	data.status = "overflow"
	data.reason = reason if reason in REASONS else "descriptor"
	return data


static func clear(game: Node) -> void:
	if not is_instance_valid(game):
		return
	for key in ["together_effect_energy", "together_effect_energy_recovery"]:
		if game.has_meta(key):
			game.remove_meta(key)


static func capture(game: Node) -> Dictionary:
	var drops = game.get("droplets")
	var energy = game.get("energy_balls")
	var pockets = game.get("pockets")
	if not drops is Array or not energy is Array or not pockets is Array:
		return overflow("descriptor")
	if drops.size() > MAX_SCAN_DROPLETS:
		return overflow("droplet candidates")
	if energy.size() > MAX_SCAN_ENERGY:
		return overflow("energy candidates")
	if pockets.size() > MAX_SCAN_POCKETS:
		return overflow("pocket candidates")
	# Native unalive() removes an energy ball from the active array before its
	# one-second visual tail is freed. Weak references retain that tail without
	# prolonging its lifetime or scanning the whole table on recurring captures.
	var known = _energy_candidates(game, energy)
	if known == null:
		return overflow("energy candidates")
	var data = empty()
	for drop in drops:
		if not _live(drop):
			continue
		if data.droplets.size() >= MAX_DROPLETS:
			return overflow("droplets")
		var descriptor = _capture_droplet(drop)
		if descriptor.is_empty():
			return overflow("descriptor")
		data.droplets.append(descriptor)
	for reference in known.values():
		var body = reference.get_ref()
		if not _live(body) or not body.inited:
			continue
		if data.energy.size() >= MAX_ENERGY:
			return overflow("energy")
		var descriptor = _capture_energy(body)
		if descriptor.is_empty():
			return overflow("descriptor")
		data.energy.append(descriptor)
	for pocket in pockets:
		if not _live(pocket):
			continue
		if data.pockets.size() >= MAX_POCKETS:
			return overflow("pockets")
		var area = pocket.get_node_or_null("Area2D")
		var pulse = pocket.get_node_or_null("%WhiteHoleEffect")
		if not area is Node2D or not pulse is CanvasItem:
			return overflow("descriptor")
		data.pockets.append(
			{
				"id": pocket.get_instance_id(),
				"suction_scale": area.scale,
				"suction_color": pulse.modulate
			}
		)
	var issue = problem(data)
	if issue != "":
		return overflow("bytes" if issue == "encoded bytes" else "descriptor")
	return data


static func _energy_candidates(game: Node, active: Array):
	var known: Dictionary = game.get_meta("together_effect_energy", {}).duplicate()
	for id in known.keys():
		if not _live(known[id].get_ref()):
			known.erase(id)
	if game.get_meta("together_effect_energy_recovery", false):
		# Only overflow recovery needs discovery. The native Balls container has
		# direct projectile children, so cap its fanout before reading any child.
		# Retired EnergyBall bodies may no longer appear in the active array.
		var container = game.get_node_or_null("Balls")
		if container == null or container.get_child_count() > MAX_RECOVERY_CHILDREN:
			return null
		var rebuilt: Dictionary = {}
		var active_ids: Dictionary = {}
		for body in active:
			if _live(body):
				active_ids[body.get_instance_id()] = true
		for index in container.get_child_count():
			var body = container.get_child(index)
			if not _live(body):
				continue
			var id = body.get_instance_id()
			var script = body.get_script()
			var native_energy = script is Script and script.get_global_name() == &"EnergyBall"
			if not native_energy and not known.has(id) and not active_ids.has(id):
				continue
			if rebuilt.size() >= MAX_SCAN_ENERGY:
				return null
			rebuilt[id] = weakref(body)
		known = rebuilt
	for body in active:
		if _live(body):
			if not known.has(body.get_instance_id()) and known.size() >= MAX_SCAN_ENERGY:
				game.set_meta("together_effect_energy_recovery", true)
				return null
			known[body.get_instance_id()] = weakref(body)
	game.set_meta("together_effect_energy", known)
	game.set_meta("together_effect_energy_recovery", false)
	return known


static func _capture_droplet(drop: Node2D) -> Dictionary:
	var sprite = drop.get_node_or_null("MainSprite")
	var shadow = drop.get_node_or_null("shadow")
	var flower = drop.get_node_or_null("Flower/Spin")
	if not sprite is Sprite2D or not shadow is Node2D or not flower is Node2D:
		return {}
	var colors: Array = []
	for path in ["FlowerCore", "FlowerPetals1", "FlowerPetals2"]:
		var petal = flower.get_node_or_null(path)
		if not petal is CanvasItem:
			return {}
		colors.append(petal.modulate)
	var textures = drop.get("droplet_sprites")
	if not textures is Array:
		return {}
	var texture_index: int = textures.find(sprite.texture)
	if texture_index not in KINDS:
		return {}
	var data = _pose(drop)
	data.merge(
		{
			"kind": int(drop.droplet_type),
			"texture_index": texture_index,
			"sprite_rotation": sprite.rotation,
			"sprite_color": sprite.self_modulate,
			"sprite_flip_h": sprite.flip_h,
			"shadow_rotation": shadow.rotation,
			"shadow_visible": shadow.visible,
			"flower_rotation": flower.rotation,
			"flower_power": int(drop.flower_power),
			"flower_colors": colors,
			"charges": int(drop.charges),
			"direction": drop.dir,
			"held_ball_id":
			drop.ball_held.get_instance_id() if is_instance_valid(drop.ball_held) else 0,
			"launch_timer": float(drop.launch_timer)
		}
	)
	return data


static func _capture_energy(body: Node2D) -> Dictionary:
	var visuals = body.get_node_or_null("visuals")
	var transform = body.get_node_or_null("transform3d")
	var sphere = body.get_node_or_null("visuals/ball")
	if not visuals is Node2D or not transform is Node3D or not sphere is CanvasItem:
		return {}
	var trails: Array = []
	var lines = _energy_lines(body)
	if lines == null:
		return {}
	for index in lines.size():
		var line = lines[index]
		if line.get_point_count() > MAX_TRAIL_POINTS:
			return {}
		var points = PackedVector2Array()
		for point in line.points:
			points.append(line.to_global(point))
		trails.append(
			{
				"index": index,
				"points": points,
				"visible": line.visible,
				"color": line.modulate,
				"width": line.width
			}
		)
	var data = _pose(body)
	data.merge(
		{
			"velocity": body.linear_velocity,
			"visual_scale": visuals.scale,
			"spin": transform.rotation,
			"alive": body.alive,
			"spawned": body.spawned,
			"gone": body.gone,
			"sphere_visible": sphere.visible,
			"trails": trails
		}
	)
	return data


## Stable prefab traversal shared with the scriptless renderer. A null result is
## an unsupported oversized prefab, never a partially discovered visual layout.
static func line_nodes(root: Node):
	var lines: Array = []
	var pending: Array = [root]
	var visited = 0
	while not pending.is_empty():
		var node = pending.pop_back()
		visited += 1
		if visited > MAX_TRAIL_NODES:
			return null
		if node is Line2D:
			if lines.size() >= MAX_TRAILS:
				return null
			lines.append(node)
		var count = node.get_child_count()
		if count > MAX_TRAIL_NODES - visited - pending.size():
			return null
		for index in range(count - 1, -1, -1):
			pending.append(node.get_child(index))
	return lines


static func _energy_lines(body: Node):
	if not body.has_meta("together_effect_trails"):
		var found = line_nodes(body)
		if found == null:
			body.set_meta("together_effect_trails", false)
			return null
		var references: Array = []
		for line in found:
			references.append(weakref(line))
		body.set_meta("together_effect_trails", references)
	var stored = body.get_meta("together_effect_trails")
	if not stored is Array:
		return null
	var result: Array = []
	for reference in stored:
		var line = reference.get_ref()
		if not is_instance_valid(line):
			return null
		result.append(line)
	return result


static func _pose(node: Node2D) -> Dictionary:
	return {
		"id": node.get_instance_id(),
		"position": node.global_position,
		"rotation": node.rotation,
		"scale": node.scale,
		"color": node.modulate,
		"visible": node.visible
	}


static func _live(node) -> bool:
	return (
		is_instance_valid(node)
		and node is Node2D
		and node.is_inside_tree()
		and not node.is_queued_for_deletion()
	)


static func valid(data) -> bool:
	return problem(data) == ""


static func problem(data) -> String:
	if (
		not data is Dictionary
		or not _keys(data, ["version", "status", "reason", "droplets", "energy", "pockets"])
	):
		return "envelope"
	if typeof(data.version) != TYPE_INT or data.version != VERSION:
		return "version"
	if data.status not in ["complete", "overflow"] or not data.reason is String:
		return "status"
	for group in ["droplets", "energy", "pockets"]:
		if not data[group] is Array:
			return group + " type"
	if (
		data.droplets.size() > MAX_DROPLETS
		or data.energy.size() > MAX_ENERGY
		or data.pockets.size() > MAX_POCKETS
	):
		return "count"
	if data.status == "overflow":
		if (
			data.reason not in REASONS
			or not data.droplets.is_empty()
			or not data.energy.is_empty()
			or not data.pockets.is_empty()
		):
			return "overflow payload"
		return ""
	if data.reason != "":
		return "complete reason"
	var ids: Dictionary = {}
	for group in ["droplets", "energy", "pockets"]:
		for entry in data[group]:
			if not entry is Dictionary or not _id(entry.get("id")):
				return group + " id"
			if ids.has(entry.id):
				return "duplicate id"
			ids[entry.id] = true
			if group == "droplets" and not _droplet_valid(entry):
				return "droplet fields"
			if group == "energy" and not _energy_valid(entry):
				return "energy fields"
			if group == "pockets" and not _pocket_valid(entry):
				return "pocket fields"
	if var_to_bytes(data).size() > MAX_BYTES:
		return "encoded bytes"
	return ""


## Call only on validated effect state (or the absent legacy field {}).
## Motion/charge/color changes are disposable; identity, kind and overflow/recovery
## transitions force a reliable full table keyframe through the caller.
static func topology(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	var result = {"status": data.get("status", ""), "reason": data.get("reason", "")}
	for entry in data.get("droplets", []):
		result["d:%d" % entry.id] = entry.kind
	for entry in data.get("energy", []):
		result["e:%d" % entry.id] = true
	for entry in data.get("pockets", []):
		result["p:%d" % entry.id] = true
	return result


static func _droplet_valid(data: Dictionary) -> bool:
	if not _keys(data, COMMON + DROPLET_FIELDS) or not _pose_valid(data):
		return false
	if typeof(data.kind) != TYPE_INT or data.kind not in KINDS:
		return false
	if typeof(data.texture_index) != TYPE_INT or data.texture_index not in KINDS:
		return false
	if not _integer(data.flower_power, 1, 1000000) or not _integer(data.charges, 0, 1000000):
		return false
	if not _integer(data.held_ball_id, 0, 9223372036854775807):
		return false
	if not _vector(data.direction, 2.0) or not _number(data.launch_timer, -10.0, 10.0):
		return false
	for key in ["sprite_rotation", "shadow_rotation", "flower_rotation"]:
		if not _number(data[key], -1.0e6, 1.0e6):
			return false
	if typeof(data.sprite_flip_h) != TYPE_BOOL or typeof(data.shadow_visible) != TYPE_BOOL:
		return false
	if (
		not _color(data.sprite_color)
		or not data.flower_colors is Array
		or data.flower_colors.size() != 3
	):
		return false
	for color in data.flower_colors:
		if not _color(color):
			return false
	return true


static func _energy_valid(data: Dictionary) -> bool:
	if not _keys(data, COMMON + ENERGY_FIELDS) or not _pose_valid(data):
		return false
	if not _vector(data.velocity, 100000.0) or not _scale(data.visual_scale):
		return false
	if typeof(data.spin) != TYPE_VECTOR3 or not data.spin.is_finite() or data.spin.length() > 1.0e6:
		return false
	for key in ["alive", "spawned", "gone", "sphere_visible"]:
		if typeof(data[key]) != TYPE_BOOL:
			return false
	if not data.trails is Array or data.trails.size() > MAX_TRAILS:
		return false
	var indices: Dictionary = {}
	for trail in data.trails:
		if (
			not trail is Dictionary
			or not _keys(trail, ["index", "points", "visible", "color", "width"])
		):
			return false
		if not _integer(trail.index, 0, MAX_TRAILS - 1) or indices.has(trail.index):
			return false
		indices[trail.index] = true
		if (
			typeof(trail.points) != TYPE_PACKED_VECTOR2_ARRAY
			or trail.points.size() > MAX_TRAIL_POINTS
		):
			return false
		for point in trail.points:
			if not _vector(point, 100000.0):
				return false
		if (
			typeof(trail.visible) != TYPE_BOOL
			or not _color(trail.color)
			or not _number(trail.width, 0.0, 1024.0)
		):
			return false
	return true


static func capture_pocket_visuals(pocket: Node2D) -> Array:
	var nodes: Array = pocket.get_meta("together_pocket_visual_nodes", [])
	if nodes.is_empty():
		for path in POCKET_VISUAL_PATHS:
			nodes.append(pocket.get_node_or_null(path))
		pocket.set_meta("together_pocket_visual_nodes", nodes)
	var visuals: Array = []
	for index in nodes.size():
		var node = nodes[index]
		if not node is CanvasItem:
			return []
		# Root pose already belongs to the ordinary pocket state.
		visuals.append([
			Vector2.ZERO if index == 0 else node.position,
			0.0 if index == 0 else node.rotation,
			Vector2.ONE if index == 0 else node.scale,
			node.modulate, node.self_modulate, node.visible,
			node.text if node is Label else ""
		])
	return visuals


static func _pocket_valid(data: Dictionary) -> bool:
	# Protocol 10 durable effects use this exact legacy three-key shape. New
	# presentation belongs to the permissive ordinary pocket extension instead.
	return (
		_keys(data, ["id", "suction_scale", "suction_color"])
		and _scale(data.suction_scale, 1000000.0)
		and _color(data.suction_color)
	)


static func pocket_visual_valid(visuals) -> bool:
	if not visuals is Array or visuals.size() != POCKET_VISUAL_PATHS.size():
		return false
	for part in visuals:
		if not part is Array or part.size() != 7:
			return false
		if not _vector(part[0], 1024.0) or not _number(part[1], -1000.0, 1000.0) or not _vector(part[2], 16.0):
			return false
		if not _color(part[3]) or not _color(part[4]) or typeof(part[5]) != TYPE_BOOL:
			return false
		if not part[6] is String or part[6].length() > 64:
			return false
	return true

static func _pose_valid(data: Dictionary) -> bool:
	return (
		_id(data.id)
		and _vector(data.position, 100000.0)
		and _number(data.rotation, -1.0e6, 1.0e6)
		and _scale(data.scale)
		and _color(data.color)
		and typeof(data.visible) == TYPE_BOOL
	)


static func _keys(data: Dictionary, allowed: Array) -> bool:
	if data.size() != allowed.size():
		return false
	for key in allowed:
		if not data.has(key):
			return false
	return true


static func _id(value) -> bool:
	return typeof(value) == TYPE_INT and value > 0


static func _integer(value, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and value >= minimum and value <= maximum


static func _number(value, minimum: float, maximum: float) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and value >= minimum
		and value <= maximum
	)


static func _vector(value, maximum: float) -> bool:
	return typeof(value) == TYPE_VECTOR2 and value.is_finite() and value.length() <= maximum


static func _scale(value, maximum: float = 16.0) -> bool:
	return (
		typeof(value) == TYPE_VECTOR2
		and value.is_finite()
		and value.x >= 0.0
		and value.y >= 0.0
		and value.x <= maximum
		and value.y <= maximum
	)


static func _color(value) -> bool:
	if typeof(value) != TYPE_COLOR:
		return false
	return (
		_number(value.r, 0.0, 16.0)
		and _number(value.g, 0.0, 16.0)
		and _number(value.b, 0.0, 16.0)
		and _number(value.a, 0.0, 1.0)
	)

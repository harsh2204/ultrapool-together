extends Node
## GAP-007 / PERF-008/019: bounded native drawing, without gameplay replay.
## Paths below are an installed-scene allowlist; peers never choose resources.

const MAX_ITEMS = 192
const MAX_SCORES = 64
const MAX_BALLS = 128
const MAX_POINTS = 64
const MAX_BYTES = 32768
const MAX_CAPTURE_USEC = 4000
const RETAIN_MSEC = 250
const PATHS = {
	"pentagram": [".", "Lines", "Lines/Line2D", "Lines/Circle"],
	"tether": ["."],
	"trail": ["."],
	"prediction":
	[
		".",
		"PredictionLine",
		"collisionPoint",
		"collisionPoint/Sprite2D",
		"collisionPoint/collisionPointGauge"
	],
	"score":
	[
		".",
		"NumberPos",
		"NumberPos/Square",
		"NumberPos/Label_score",
		"NumberPos/Label_money",
		"NumberPos/PanelContainer",
		"NumberPos/PanelContainer/Label2"
	]
}
const LINES = {"pentagram": [2], "tether": [0], "trail": [0], "prediction": [1], "score": []}
const LABELS = {"pentagram": [], "tether": [], "trail": [], "prediction": [], "score": [3, 4, 6]}
const CONTROLS = {
	"pentagram": [], "tether": [], "trail": [], "prediction": [], "score": [3, 4, 5, 6]
}
const SHADERS = {
	"prediction": {3: ["charge_amount", "alpha", "color"]}, "score": {2: ["alpha", "color"]}
}

var _scores: Dictionary = {}
var _predictions: Dictionary = {}
var _epoch = ""
var _active = false
var _overflow_live = 0
var _overflow_until = 0
var capture_stats: Dictionary = {}


func _ready() -> void:
	get_tree().node_added.connect(_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_node_added):
		get_tree().node_added.disconnect(_node_added)
	clear()


func clear() -> void:
	_scores.clear()
	_predictions.clear()
	_epoch = ""
	_active = false
	_overflow_live = 0
	_overflow_until = 0


func has_pending_or_active_effects() -> bool:
	# Native creates LUNA prediction children at item setup. This bounded registry
	# catches the first idle aim before the next heartbeat has sampled visibility.
	var global_node = get_node_or_null("/root/Global")
	var game = global_node.gameManager if global_node != null else null
	if (
		not _predictions.is_empty()
		and is_instance_valid(game)
		and is_instance_valid(game.player_ball)
		and game.player_ball.preparing_shot
	):
		return true
	return (
		_active
		or not _scores.is_empty()
		or _overflow_live > 0
		or _overflow_until > Time.get_ticks_msec()
	)


func _node_added(node: Node) -> void:
	var prediction = node.scene_file_path == "res://prediction_small.tscn"
	var native_ball = node.scene_file_path == "res://ball.tscn"
	if not prediction and not native_ball and node.scene_file_path != "res://ui/score_display.tscn":
		return
	var global_node = get_node_or_null("/root/Global")
	var game = global_node.gameManager if global_node != null else null
	if not is_instance_valid(game) or game.has_method("apply_table") or game.in_shop:
		return
	var epoch = "%d:%d" % [game.get_instance_id(), game.rounds_played]
	if epoch != _epoch:
		clear()
		_epoch = epoch
	if native_ball:
		# Native _ready must finish before its optional presentation reference is
		# checked. This hook never instantiates a native script or invokes gameplay.
		call_deferred("_bind_native_tether", weakref(node))
		return
	if prediction:
		if _predictions.size() < MAX_BALLS:
			_predictions[node.get_instance_id()] = weakref(node)
			node.tree_exiting.connect(
				_prediction_exiting.bind(node.get_instance_id(), epoch), CONNECT_ONE_SHOT
			)
		return
	if _scores.size() >= MAX_SCORES:
		_overflow_live += 1
		_overflow_until = Time.get_ticks_msec() + RETAIN_MSEC
		node.tree_exiting.connect(_overflow_exiting.bind(epoch), CONNECT_ONE_SHOT)
		return
	var id = node.get_instance_id()
	_scores[id] = {"node": weakref(node), "last": {}, "until": 0}
	node.tree_exiting.connect(_score_exiting.bind(id), CONNECT_ONE_SHOT)
	call_deferred("_remember", id)


func _prediction_exiting(id: int, epoch: String) -> void:
	if _epoch == epoch:
		_predictions.erase(id)


func _bind_native_tether(reference: WeakRef) -> void:
	var body = reference.get_ref()
	if not is_instance_valid(body) or not body.is_inside_tree() or not body.is_node_ready():
		return
	var global_node = get_node_or_null("/root/Global")
	var game = global_node.gameManager if global_node != null else null
	if (
		not is_instance_valid(game)
		or game.has_method("apply_table")
		or not game.is_ancestor_of(body)
	):
		return
	if body.has_meta("together_native_tether_checked"):
		return
	body.set_meta("together_native_tether_checked", true)
	# Native 0.15.7 leaves this reference null even though its Line2D exists;
	# confirmed by the native fixture. Bind once, preserving valid native refs.
	# The native process still decides visibility/geometry from REAPER contact.
	if body.get("deathline") == null:
		var line = body.get_node_or_null("visuals/deathline")
		if line is Line2D:
			body.deathline = line


func _overflow_exiting(epoch: String) -> void:
	if _epoch == epoch:
		_overflow_live = maxi(0, _overflow_live - 1)


func _remember(id: int) -> void:
	if not _scores.has(id):
		return
	var node = _scores[id].node.get_ref()
	if is_instance_valid(node) and node.is_inside_tree():
		_scores[id].last = describe(node, "score")


func _score_exiting(id: int) -> void:
	if _scores.has(id):
		_scores[id].until = Time.get_ticks_msec() + RETAIN_MSEC


func capture(game: Node) -> Dictionary:
	var started = Time.get_ticks_usec()
	var epoch = "%d:%d" % [game.get_instance_id(), game.rounds_played]
	if epoch != _epoch or game.in_shop:
		clear()
		_epoch = epoch
	var data = {"version": 1, "status": "complete", "reason": "", "items": []}
	_active = false
	if game.in_shop:
		return data
	var pentagram = game.table.get_node_or_null("Pentagram")
	if is_instance_valid(pentagram) and (game.candles_pocketed > 0 or pentagram.value > 0):
		# Reset is represented by absence, clearing retained views without idle bytes.
		var state = describe(pentagram, "pentagram")
		state["candles"] = game.candles_pocketed
		state["strength"] = game.ritual_strength
		state["progress"] = pentagram.progress
		state["done"] = pentagram.done
		data.items.append(state)
		_active = (
			pentagram.value > 0
			and (
				pentagram.progress < 1.0
				or (pentagram.done and pentagram.get_node("Lines").modulate.a > 0.005)
			)
		)
	if game.balls.size() > MAX_BALLS:
		return _overflow("ball scan", started)
	var bodies: Array = game.balls.duplicate()
	if is_instance_valid(game.player_ball) and not bodies.has(game.player_ball):
		bodies.append(game.player_ball)
	if bodies.size() > MAX_BALLS:
		return _overflow("ball scan", started)
	for body in bodies:
		if Time.get_ticks_usec() - started > MAX_CAPTURE_USEC:
			return _overflow("capture budget", started)
		if (
			not is_instance_valid(body)
			or not body.is_inside_tree()
			or body.is_queued_for_deletion()
		):
			continue
		# Covers bodies already alive when this capture owner was attached. Only
		# the metadata check recurs; path discovery/binding happens once per body.
		if (
			body.scene_file_path == "res://ball.tscn"
			and not body.has_meta("together_native_tether_checked")
		):
			_bind_native_tether(weakref(body))
		for kind in ["tether", "trail", "prediction"]:
			var source = (
				body.get("prediction_sys")
				if kind == "prediction"
				else body.get_node_or_null("visuals/deathline" if kind == "tether" else "Trail")
			)
			if (
				not source is Node2D
				or not source.is_inside_tree()
				or source.is_queued_for_deletion()
				or not source.is_visible_in_tree()
			):
				continue
			var state = describe(source, kind)
			state["owner"] = body.get_instance_id()
			data.items.append(state)
			# Settled tethers and trail history do not justify permanent 10Hz traffic.
			# Ball motion already schedules their changing endpoints; prediction is
			# independent of ball velocity and follows the host's live aim.
			_active = _active or kind == "prediction"
	var now = Time.get_ticks_msec()
	for id in _scores.keys():
		if Time.get_ticks_usec() - started > MAX_CAPTURE_USEC:
			return _overflow("capture budget", started)
		var entry: Dictionary = _scores[id]
		if entry.until > 0 and entry.until <= now:
			_scores.erase(id)
			continue
		var node = entry.node.get_ref()
		if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion():
			entry.last = describe(node, "score")
		elif entry.until == 0:
			_scores.erase(id)
			continue
		if not entry.last.is_empty():
			data.items.append(entry.last)
	if _overflow_live > 0 or _overflow_until > now:
		return _overflow("score count", started)
	var invalid = problem(data)
	if not invalid.is_empty():
		return _overflow(invalid, started)
	capture_stats = {"usec": Time.get_ticks_usec() - started, "count": data.items.size()}
	return data


func _overflow(reason: String, started: int) -> Dictionary:
	capture_stats = {"usec": Time.get_ticks_usec() - started, "overflow": reason}
	return overflow(reason)


static func empty() -> Dictionary:
	return {"version": 1, "status": "complete", "reason": "", "items": []}


static func overflow(reason: String) -> Dictionary:
	return {"version": 1, "status": "overflow", "reason": reason, "items": []}


static func describe(node: Node2D, kind: String) -> Dictionary:
	var item = {"id": node.get_instance_id(), "kind": kind, "parts": []}
	if kind == "score":
		item["ttl"] = clampf(float(node.ttl), 0.0, 2.0)
	for index in PATHS[kind].size():
		var part = node.get_node_or_null(PATHS[kind][index])
		if not part is Node2D and not part is Control:
			continue
		var transform: Transform2D = part.transform if part is Node2D else part.get_transform()
		if part == node:
			transform = node.global_transform
		elif part.is_set_as_top_level() and part.get_parent() is Node2D:
			transform = part.get_parent().global_transform.affine_inverse() * part.global_transform
		var state = {
			"index": index,
			"position": transform.origin,
			"rotation": transform.get_rotation(),
			"scale": transform.get_scale(),
			"visible": part.visible,
			"modulate": part.modulate,
			"self_modulate": part.self_modulate,
			"z": part.z_index
		}
		if part is Line2D:
			state["points"] = part.points
			state["width"] = part.width
			state["color"] = part.default_color
			state["gradient_colors"] = (
				part.gradient.colors if part.gradient != null else PackedColorArray()
			)
			state["gradient_offsets"] = (
				part.gradient.offsets if part.gradient != null else PackedFloat32Array()
			)
		if part is Label:
			state["text"] = part.text
		if part is Control:
			state["size"] = part.size
		if SHADERS.get(kind, {}).has(index) and part.material is ShaderMaterial:
			state["shader"] = {}
			for key in SHADERS[kind][index]:
				state.shader[key] = part.material.get_shader_parameter(key)
		item.parts.append(state)
	return item


static func topology(data: Dictionary) -> Dictionary:
	var result = {"status": data.get("status", "complete")}
	for item in data.get("items", []):
		result[item.id] = item.kind
	return result


static func active(data: Dictionary) -> bool:
	for item in data.get("items", []):
		if item.kind in ["score", "prediction"]:
			return true
		if item.kind == "pentagram" and item.candles > 0:
			if item.progress < 1.0 or (item.done and item.parts[1].modulate.a > 0.005):
				return true
	return false


static func problem(data) -> String:
	if not data is Dictionary:
		return "native drawing type"
	if data.is_empty():
		return ""
	if (
		data.size() != 4
		or data.get("version") != 1
		or data.get("status") not in ["complete", "overflow"]
	):
		return "native drawing version/status"
	if not data.get("reason") is String or data.reason.length() > 64:
		return "native drawing reason"
	if not data.get("items") is Array or data.items.size() > MAX_ITEMS:
		return "native drawing count"
	if data.status == "overflow" and not data.items.is_empty():
		return "native drawing partial overflow"
	var ids: Dictionary = {}
	for item in data.items:
		if not item is Dictionary or not item.get("id") is int or item.id <= 0 or ids.has(item.id):
			return "native drawing identity"
		ids[item.id] = true
		if not item.get("kind") is String or not PATHS.has(item.kind):
			return "native drawing kind"
		if not item.get("parts") is Array or item.parts.size() != PATHS[item.kind].size():
			return "native drawing parts"
		var keys = ["id", "kind", "parts"]
		if item.kind == "pentagram":
			keys.append_array(["candles", "strength", "progress", "done"])
			if (
				not item.get("candles") is int
				or item.candles < 0
				or item.candles > 5
				or not item.get("strength") is int
				or item.strength < 0
				or item.strength > 1000000
				or not _number(item.get("progress"), 0, 1)
				or not item.get("done") is bool
			):
				return "native drawing ritual"
		elif item.kind == "score":
			keys.append("ttl")
			if not _number(item.get("ttl"), 0, 2):
				return "native drawing lifetime"
		else:
			keys.append("owner")
			if not item.get("owner") is int or item.owner <= 0:
				return "native drawing owner"
		if not _keys(item, keys):
			return "native drawing fields"
		for index in item.parts.size():
			var part = item.parts[index]
			if not part is Dictionary or not part.get("index") is int or part.index != index:
				return "native drawing part index"
			keys = [
				"index",
				"position",
				"rotation",
				"scale",
				"visible",
				"modulate",
				"self_modulate",
				"z"
			]
			if (
				not _vector(part.get("position"))
				or not _vector(part.get("scale"))
				or not _number(part.get("rotation"))
				or not part.get("visible") is bool
				or not part.get("z") is int
				or abs(part.z) > 4096
			):
				return "native drawing transform"
			if not _color(part.get("modulate")) or not _color(part.get("self_modulate")):
				return "native drawing tint"
			if index in LINES[item.kind]:
				keys.append_array(
					["points", "width", "color", "gradient_colors", "gradient_offsets"]
				)
				if (
					not part.get("points") is PackedVector2Array
					or part.points.size() > MAX_POINTS
					or not _number(part.get("width"), 0, 1024)
					or not _color(part.get("color"))
				):
					return "native drawing line"
				for point in part.points:
					if not _vector(point):
						return "native drawing point"
				if (
					not part.get("gradient_colors") is PackedColorArray
					or not part.get("gradient_offsets") is PackedFloat32Array
					or part.gradient_colors.size() > 16
					or part.gradient_colors.size() != part.gradient_offsets.size()
				):
					return "native drawing gradient"
				var previous = -1.0
				for g in part.gradient_colors.size():
					if (
						not _color(part.gradient_colors[g])
						or not _number(part.gradient_offsets[g], 0, 1)
						or part.gradient_offsets[g] < previous
					):
						return "native drawing gradient value"
					previous = part.gradient_offsets[g]
			if index in LABELS[item.kind]:
				keys.append("text")
				if not part.get("text") is String or part.text.length() > 256:
					return "native drawing label"
			if index in CONTROLS[item.kind]:
				keys.append("size")
				if not _vector(part.get("size")) or part.size.x < 0 or part.size.y < 0:
					return "native drawing control size"

			if SHADERS.get(item.kind, {}).has(index):
				keys.append("shader")
				if (
					not part.get("shader") is Dictionary
					or not _keys(part.shader, SHADERS[item.kind][index])
				):
					return "native drawing shader"
				for key in part.shader:
					if not (
						_color(part.shader[key])
						if key == "color"
						else _number(part.shader[key], 0, 1)
					):
						return "native drawing shader value"
			if not _keys(part, keys):
				return "native drawing part fields"
	# Shape/count checks precede encoding, so hostile nested values never ask the
	# serializer to walk arbitrary containers or unbounded native line history.
	if var_to_bytes(data).size() > MAX_BYTES:
		return "native drawing bytes"
	return ""


static func _keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in value:
		if key not in keys:
			return false
	return true


static func _number(value, low: float = -1.0e7, high: float = 1.0e7) -> bool:
	return (
		(value is float or value is int)
		and is_finite(float(value))
		and value >= low
		and value <= high
	)


static func _vector(value) -> bool:
	return value is Vector2 and _number(value.x) and _number(value.y)


static func _color(value) -> bool:
	return (
		value is Color
		and _number(value.r)
		and _number(value.g)
		and _number(value.b)
		and _number(value.a)
	)

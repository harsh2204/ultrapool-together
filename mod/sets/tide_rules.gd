extends RefCounted
## Host-authoritative TIDE rules. Height 0–3.

const CatalogUtil = preload("catalog_util.gd")
const DRIFTWOOD = "TIDE_DRIFTWOOD"
const BREAKER = "TIDE_BREAKER"
const BUOY = "TIDE_BUOY"
const RIPTIDE = "TIDE_RIPTIDE"
const MAELSTROM = "TIDE_MAELSTROM"
const UNDERTOW = "TIDE_UNDERTOW"
const HARBOR = "TIDE_HARBOR"
const TSUNAMI = "TIDE_TSUNAMI"
const KINDS = [DRIFTWOOD, BREAKER, BUOY, RIPTIDE, MAELSTROM, UNDERTOW, HARBOR, TSUNAMI]

var height = 0
var balls: Dictionary = {}
var pending = false
var shot_index = 0
var _utilities: Dictionary = {}
var _pocketed: Dictionary = {}
var _walls: Dictionary = {}
var _maelstrom_used = false
var _buoy_bonus = 0.0
var _round_key = ""


func reset_round(round_key: String) -> void:
	if round_key == _round_key:
		return
	_round_key = round_key
	height = 0
	balls.clear()
	_utilities.clear()
	pending = false
	_clear_shot()


func register_ball(id: int, kinds: Array) -> void:
	if id <= 0:
		return
	var registered: Array = []
	for kind in kinds:
		if kind in KINDS and kind not in registered:
			registered.append(kind)
	if registered.is_empty():
		return
	if not balls.has(id):
		balls[id] = {"kinds": [], "paid": {}}
	balls[id].kinds = registered


func begin_shot(accepted_index: int) -> bool:
	if pending or accepted_index <= shot_index:
		return false
	shot_index = accepted_index
	pending = true
	_clear_shot()
	return true


func mark_object_hit() -> void:
	pass


func hit(_ball_id: int, _ordinary_ids: Array) -> Dictionary:
	return CatalogUtil.empty_action()


func wall(ball_id: int) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0:
		return action
	_walls[ball_id] = true
	if balls.has(ball_id) and BREAKER in balls[ball_id].kinds:
		if height >= 3:
			action.temp.append({"id": ball_id, "amount": 1})
		else:
			_raise(1)
	if not _maelstrom_used and balls.has(ball_id) and MAELSTROM in balls[ball_id].kinds:
		_raise(1)
		_maelstrom_used = true
	elif not balls.has(ball_id) or BREAKER not in balls[ball_id].kinds:
		# Ordinary / other tide wall hits still raise pressure slightly via Breaker's peers only.
		pass
	# Any tide ball wall hit raises height once per ball per shot if not already raised by Breaker.
	if balls.has(ball_id) and not _walls.get("raised_%d" % ball_id, false):
		if BREAKER not in balls[ball_id].kinds:
			_raise(1)
		_walls["raised_%d" % ball_id] = true
	return action


func pocket(ball_id: int, kinds: Array, base_value: float, ordinary: bool) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or _pocketed.has(ball_id):
		return action
	_pocketed[ball_id] = true
	var value = maxf(0.0, base_value) if is_finite(base_value) else 0.0
	_raise(-1)
	if ordinary:
		if _buoy_bonus > 0.0:
			action.points += ceilf(value * _buoy_bonus)
			_buoy_bonus = 0.0
		return action
	register_ball(ball_id, kinds)
	if not balls.has(ball_id):
		return action
	var ball: Dictionary = balls[ball_id]
	for kind in ball.kinds:
		if ball.paid.has(kind):
			continue
		match kind:
			DRIFTWOOD:
				if height <= 1:
					action.points += ceilf(value * 0.5)
					ball.paid[kind] = true
			UNDERTOW:
				if height >= 2:
					action.points += ceilf(value * 0.25)
					ball.paid[kind] = true
			BUOY:
				if not _utilities.has(kind):
					height = 2
					_buoy_bonus = 0.25
					_utilities[kind] = true
				ball.paid[kind] = true
			RIPTIDE:
				if height >= 3:
					action.launch_nearest = true
				ball.paid[kind] = true
			HARBOR:
				if not _utilities.has(kind):
					_raise(-1)
					action.money = 1
					_utilities[kind] = true
				ball.paid[kind] = true
			TSUNAMI:
				if height >= 3:
					action.points += ceilf(value)
					ball.paid[kind] = true
			BREAKER, MAELSTROM:
				ball.paid[kind] = true
	return action


func finish_shot(_survivors: Array) -> void:
	if not pending:
		return
	pending = false
	_clear_shot()


func capture_shared() -> Dictionary:
	return {"height": height}


func display_fields() -> Array:
	return [height]


func _raise(delta: int) -> void:
	height = clampi(height + delta, 0, 3)


func _clear_shot() -> void:
	_walls.clear()
	_pocketed.clear()
	_maelstrom_used = false
	_buoy_bonus = 0.0

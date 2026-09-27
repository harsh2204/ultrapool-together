extends RefCounted
## Host-authoritative TAROT Spread. Drawn at round start from Arcana in the build.
## Upright = true; flipped on cushion hit. Pocket spends the card from the Spread.

const CatalogUtil = preload("catalog_util.gd")
const FOOL = "TAROT_FOOL"
const WHEEL = "TAROT_WHEEL"
const TOWER = "TAROT_TOWER"
const DEATH = "TAROT_DEATH"
const STAR = "TAROT_STAR"
const MAGICIAN = "TAROT_MAGICIAN"
const SUN = "TAROT_SUN"
const TEMPERANCE = "TAROT_TEMPERANCE"
const HANGED = "TAROT_HANGED"
const STRENGTH = "TAROT_STRENGTH"
const KINDS = [FOOL, WHEEL, TOWER, DEATH, STAR, MAGICIAN, SUN, TEMPERANCE, HANGED, STRENGTH]
const SPREAD_SIZE = 3
const WHEEL_BONUSES = [0.25, 0.5, 1.0]

var balls: Dictionary = {}
var spread: Array = []  # up to 3 kind ids currently in the Spread
var pending = false
var shot_index = 0
var _utilities: Dictionary = {}
var _pocketed: Dictionary = {}
var _walls: Dictionary = {}
var _hit_object = false
var _star_bonus_used = false
var _strength_used = false
var _next_ordinary = 0.0
var _round_key = ""
var _spread_drawn = false


func reset_round(round_key: String) -> void:
	if round_key == _round_key:
		return
	_round_key = round_key
	balls.clear()
	spread.clear()
	_utilities.clear()
	_spread_drawn = false
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
		balls[id] = {"kinds": [], "upright": true, "charge": 0, "paid": {}, "in_spread": false}
	balls[id].kinds = registered
	_ensure_spread()


func begin_shot(accepted_index: int) -> bool:
	if pending or accepted_index <= shot_index:
		return false
	shot_index = accepted_index
	pending = true
	_clear_shot()
	return true


func mark_object_hit() -> void:
	if pending:
		_hit_object = true


func hit(_ball_id: int, _ordinary_ids: Array) -> Dictionary:
	if pending:
		_hit_object = true
	return CatalogUtil.empty_action()


func wall(ball_id: int) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or not balls.has(ball_id):
		return action
	_walls[ball_id] = true
	var ball: Dictionary = balls[ball_id]
	ball.upright = not ball.upright
	if (
		not _strength_used
		and _spread_has(STRENGTH)
		and _orientation(STRENGTH)
		and ball.in_spread
	):
		action.temp.append({"id": ball_id, "amount": 1})
		_strength_used = true
	return action


func pocket(ball_id: int, kinds: Array, base_value: float, ordinary: bool) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or _pocketed.has(ball_id):
		return action
	_pocketed[ball_id] = true
	var value = maxf(0.0, base_value) if is_finite(base_value) else 0.0
	if ordinary:
		if (
			not _star_bonus_used
			and _spread_has(STAR)
			and _orientation(STAR)
		):
			action.points += ceilf(value * 0.25)
			_star_bonus_used = true
		if _next_ordinary > 0.0:
			action.points += ceilf(value * _next_ordinary)
			_next_ordinary = 0.0
		return action
	register_ball(ball_id, kinds)
	if not balls.has(ball_id):
		return action
	var ball: Dictionary = balls[ball_id]
	if not ball.in_spread and not spread.is_empty():
		# Only cards currently in the Spread pay orientation effects, then leave the Spread.
		pass
	for kind in ball.kinds:
		if ball.paid.has(kind):
			continue
		var upright: bool = ball.upright
		match kind:
			FOOL:
				if upright:
					action.points += ceilf(value)
				elif not _utilities.has(kind):
					action.points = 0.0
					action.money = 2
					_utilities[kind] = true
				ball.paid[kind] = true
			WHEEL:
				var pick = 0.25
				if upright:
					pick = WHEEL_BONUSES[
						absi(hash(str(ball_id) + str(shot_index))) % WHEEL_BONUSES.size()
					]
				action.points += ceilf(value * pick)
				ball.paid[kind] = true
			TOWER:
				if not _utilities.has(kind):
					if upright:
						action.clear_temps = true
						action.points += 3.0
					else:
						action.strip_and_spread = true
					_utilities[kind] = true
				ball.paid[kind] = true
			DEATH:
				if upright:
					action.consume_nearest = true
					action.consume_rate = 0.5
				else:
					action.shade_nearest = true
				ball.paid[kind] = true
			MAGICIAN:
				if upright:
					action.points += ceilf(value * 0.5)
				else:
					action.money = 1
				ball.paid[kind] = true
			SUN:
				if upright:
					action.points += ceilf(value)
				else:
					action.temp.append({"id": ball_id, "amount": -999})
				ball.paid[kind] = true
			TEMPERANCE:
				action.points += ceilf(value * 0.25)
				if upright:
					_next_ordinary = 0.25
				ball.paid[kind] = true
			HANGED:
				if upright and ball.charge > 0:
					action.points += ceilf(value * 0.5)
					ball.charge = 0
				elif not upright:
					action.points = 0.0
				ball.paid[kind] = true
			STAR, STRENGTH:
				ball.paid[kind] = true
		_spend_from_spread(kind)
	return action


func finish_shot(survivors: Array) -> void:
	if not pending:
		return
	if _hit_object:
		for id in survivors:
			if not balls.has(id) or _pocketed.has(id):
				continue
			var ball: Dictionary = balls[id]
			if HANGED in ball.kinds and ball.upright and ball.charge < 1:
				ball.charge = 1
	pending = false
	_clear_shot()


func capture_shared() -> Dictionary:
	return {"spread": spread.duplicate()}


func capture_ball(id: int) -> Dictionary:
	if not balls.has(id):
		return {}
	var ball: Dictionary = balls[id]
	return {
		"upright": ball.upright,
		"charge": ball.charge,
		"in_spread": ball.in_spread
	}


func display_fields() -> Array:
	var fields: Array = [spread.duplicate()]
	for id in balls:
		var ball: Dictionary = balls[id]
		fields.append([id, ball.upright, ball.charge, ball.in_spread])
	return fields


func _ensure_spread() -> void:
	if _spread_drawn:
		return
	var pool: Array = []
	for id in balls:
		for kind in balls[id].kinds:
			if kind not in pool:
				pool.append(kind)
	pool.sort()
	spread.clear()
	for i in range(mini(SPREAD_SIZE, pool.size())):
		spread.append(pool[i])
	_mark_spread_membership()
	_spread_drawn = true


func _mark_spread_membership() -> void:
	for id in balls:
		var ball: Dictionary = balls[id]
		ball.in_spread = false
		for kind in ball.kinds:
			if kind in spread:
				ball.in_spread = true
				break


func _spread_has(kind: String) -> bool:
	return kind in spread


func _orientation(kind: String) -> bool:
	for id in balls:
		if kind in balls[id].kinds:
			return balls[id].upright
	return true


func _spend_from_spread(kind: String) -> void:
	var index = spread.find(kind)
	if index >= 0:
		spread.remove_at(index)
	_mark_spread_membership()


func _clear_shot() -> void:
	_hit_object = false
	_walls.clear()
	_pocketed.clear()
	_star_bonus_used = false
	_strength_used = false
	_next_ordinary = 0.0

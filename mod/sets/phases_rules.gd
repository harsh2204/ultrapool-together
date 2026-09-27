extends RefCounted
## Host-authoritative PHASES rules. Phase 0 New → 1 Waxing → 2 Full → 3 Waning.

const CatalogUtil = preload("catalog_util.gd")
const CRESCENT = "PHASES_CRESCENT"
const FULL_MOON = "PHASES_FULL_MOON"
const NEW_MOON = "PHASES_NEW_MOON"
const ECLIPSE = "PHASES_ECLIPSE"
const APOGEE = "PHASES_APOGEE"
const GIBBOUS = "PHASES_GIBBOUS"
const UMBRA = "PHASES_UMBRA"
const PENUMBRA = "PHASES_PENUMBRA"
const KINDS = [CRESCENT, FULL_MOON, NEW_MOON, ECLIPSE, APOGEE, GIBBOUS, UMBRA, PENUMBRA]
const PHASE_NAMES = ["New", "Waxing", "Full", "Waning"]

var phase = 0
var silent_charges = 0
var balls: Dictionary = {}
var pending = false
var shot_index = 0
var _utilities: Dictionary = {}
var _pocketed: Dictionary = {}
var _walls: Dictionary = {}
var _hit_object = false
var _apogee_fired = false
var _penumbra_armed = false
var _ordinary_bonus = 0.0
var _round_key = ""


func reset_round(round_key: String) -> void:
	if round_key == _round_key:
		return
	_round_key = round_key
	phase = 0
	silent_charges = 0
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
		balls[id] = {"kinds": [], "paid": {}, "umbra_paid": false}
	balls[id].kinds = registered


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


func hit(ball_id: int, ordinary_ids: Array) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0:
		return action
	_hit_object = true
	if not balls.has(ball_id):
		return action
	var ball: Dictionary = balls[ball_id]
	if FULL_MOON in ball.kinds and phase == 2 and not ordinary_ids.is_empty():
		var pick = ordinary_ids[absi(hash(str(ball_id) + str(shot_index))) % ordinary_ids.size()]
		action.temp.append({"id": pick, "amount": 1})
	return action


func wall(ball_id: int) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or not balls.has(ball_id):
		return action
	_walls[ball_id] = true
	var ball: Dictionary = balls[ball_id]
	if UMBRA in ball.kinds and phase in [0, 3] and not ball.umbra_paid:
		ball.umbra_paid = true
		action.temp.append({"id": ball_id, "amount": 1})
	return action


func pocket(ball_id: int, kinds: Array, base_value: float, ordinary: bool) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or _pocketed.has(ball_id):
		return action
	_pocketed[ball_id] = true
	var value = maxf(0.0, base_value) if is_finite(base_value) else 0.0
	if ordinary:
		_advance_phase(1)
		if _ordinary_bonus > 0.0:
			action.points += ceilf(value * _ordinary_bonus)
			_ordinary_bonus = 0.0
		return action
	register_ball(ball_id, kinds)
	if not balls.has(ball_id):
		return action
	var ball: Dictionary = balls[ball_id]
	var is_phase = not ball.kinds.is_empty()
	if is_phase and silent_charges > 0 and not ball.paid.has("silent"):
		action.points += ceilf(value)
		silent_charges -= 1
		ball.paid["silent"] = true
	for kind in ball.kinds:
		if ball.paid.has(kind):
			continue
		match kind:
			CRESCENT:
				if phase in [1, 3]:
					action.points += ceilf(value * 0.5)
					ball.paid[kind] = true
			GIBBOUS:
				if phase in [1, 2]:
					action.points += ceilf(value * 0.25)
					ball.paid[kind] = true
			NEW_MOON:
				if phase == 0:
					silent_charges = mini(2, silent_charges + 1)
				ball.paid[kind] = true
			ECLIPSE:
				if not _utilities.has(kind):
					action.close_top_pocket = true
					_utilities[kind] = true
					action.money = 2
				ball.paid[kind] = true
			PENUMBRA:
				if phase in [0, 2] and not _utilities.has(kind):
					_ordinary_bonus = maxf(_ordinary_bonus, 0.5)
					_utilities[kind] = true
				ball.paid[kind] = true
			FULL_MOON, APOGEE, UMBRA:
				ball.paid[kind] = true
	return action


func finish_shot(survivors: Array) -> void:
	if not pending:
		return
	if _hit_object and not _apogee_fired:
		for id in survivors:
			if not balls.has(id) or _pocketed.has(id):
				continue
			if APOGEE in balls[id].kinds:
				_advance_phase(1)
				_apogee_fired = true
				break
	pending = false
	_clear_shot()


func capture_shared() -> Dictionary:
	return {"phase": phase, "silent": silent_charges}


func display_fields() -> Array:
	return [phase, silent_charges]


func _advance_phase(steps: int) -> void:
	phase = posmod(phase + steps, 4)


func _clear_shot() -> void:
	_hit_object = false
	_walls.clear()
	_pocketed.clear()
	_apogee_fired = false
	_penumbra_armed = false
	_ordinary_bonus = 0.0

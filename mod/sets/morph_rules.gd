extends RefCounted
## Host-authoritative MORPH rules. Forms cycle on cue-ball hits; pocket pays active form.

const CatalogUtil = preload("catalog_util.gd")
const VESSEL = "MORPH_VESSEL"
const HEAVY = "MORPH_HEAVY"
const PHASEFORM = "MORPH_PHASEFORM"
const SPLITTER = "MORPH_SPLITTER"
const PRIME = "MORPH_PRIME"
const SHIELD = "MORPH_SHIELD"
const CATALYST = "MORPH_CATALYST"
const FLUX = "MORPH_FLUX"
const KINDS = [VESSEL, HEAVY, PHASEFORM, SPLITTER, PRIME, SHIELD, CATALYST, FLUX]
# Forms: 0 Idle, 1 Active (Sprinter/Heavy/Splitter/Guard/Catalyst)
const FORM_IDLE = 0
const FORM_ACTIVE = 1

var balls: Dictionary = {}
var form_changes = 0
var pending = false
var shot_index = 0
var _utilities: Dictionary = {}
var _pocketed: Dictionary = {}
var _walls: Dictionary = {}
var _next_flat = 0
var _prime_ready = false
var _round_key = ""


func reset_round(round_key: String) -> void:
	if round_key == _round_key:
		return
	_round_key = round_key
	balls.clear()
	form_changes = 0
	_utilities.clear()
	_prime_ready = false
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
		balls[id] = {
			"kinds": [],
			"form": FORM_IDLE,
			"charge": 0,
			"marked": false,
			"paid": {},
			"weight_on": false
		}
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


func hit(ball_id: int, _ordinary_ids: Array) -> Dictionary:
	## Cue-ball hits only — form cycling is intentional, not collision noise.
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or not balls.has(ball_id):
		return action
	var ball: Dictionary = balls[ball_id]
	var before = ball.form
	ball.form = FORM_ACTIVE if ball.form == FORM_IDLE else FORM_IDLE
	var delta = 2 if FLUX in ball.kinds else 1
	if ball.form != before:
		form_changes += delta
		if form_changes >= 3:
			_prime_ready = true
	if HEAVY in ball.kinds:
		var want_weight = ball.form == FORM_ACTIVE
		if want_weight != ball.weight_on:
			ball.weight_on = want_weight
			action.weight.append({"id": ball_id, "delta": 1 if want_weight else -1})
	return action


func wall(ball_id: int) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or not balls.has(ball_id):
		return action
	_walls[ball_id] = true
	var ball: Dictionary = balls[ball_id]
	if VESSEL in ball.kinds and ball.form == FORM_ACTIVE and ball.charge < 1:
		ball.charge = 1
		ball.form = FORM_IDLE
	if PHASEFORM in ball.kinds and not ball.marked:
		ball.marked = true
	if SHIELD in ball.kinds and ball.form == FORM_ACTIVE and not ball.paid.has("shield_wall"):
		ball.paid["shield_wall"] = true
		action.temp.append({"id": ball_id, "amount": 1})
		ball.form = FORM_IDLE
	return action


func pocket(ball_id: int, kinds: Array, base_value: float, ordinary: bool) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or _pocketed.has(ball_id):
		return action
	_pocketed[ball_id] = true
	var value = maxf(0.0, base_value) if is_finite(base_value) else 0.0
	if _next_flat > 0:
		action.points += float(_next_flat)
		_next_flat = 0
	if ordinary:
		return action
	register_ball(ball_id, kinds)
	if not balls.has(ball_id):
		return action
	var ball: Dictionary = balls[ball_id]
	for kind in ball.kinds:
		if ball.paid.has(kind):
			continue
		match kind:
			VESSEL:
				if ball.charge > 0:
					action.points += ceilf(value * 0.25 * ball.charge)
					ball.charge = 0
				ball.paid[kind] = true
			HEAVY:
				if ball.form == FORM_ACTIVE:
					_next_flat = 1
				ball.paid[kind] = true
			PHASEFORM:
				if ball.marked:
					action.points += ceilf(value)
					ball.paid[kind] = true
			SPLITTER:
				if ball.form == FORM_ACTIVE and not _utilities.has(kind):
					action.spawn_echo = true
					_utilities[kind] = true
				ball.paid[kind] = true
			PRIME:
				if _prime_ready and not _utilities.has(kind):
					action.points += ceilf(value * 1.5)
					_prime_ready = false
					_utilities[kind] = true
				ball.paid[kind] = true
			CATALYST:
				if ball.form == FORM_ACTIVE and not _utilities.has(kind):
					for other_id in balls:
						action.temp.append({"id": other_id, "amount": 1})
					_utilities[kind] = true
				ball.paid[kind] = true
			SHIELD, FLUX:
				ball.paid[kind] = true
	return action


func finish_shot(_survivors: Array) -> void:
	if not pending:
		return
	pending = false
	_clear_shot()


func capture_ball(id: int) -> Dictionary:
	if not balls.has(id):
		return {}
	var ball: Dictionary = balls[id]
	return {"form": ball.form, "charge": ball.charge, "marked": ball.marked}


func capture_shared() -> Dictionary:
	return {"form_changes": form_changes, "prime": _prime_ready}


func display_fields() -> Array:
	var fields: Array = [form_changes, _prime_ready]
	for id in balls:
		var ball: Dictionary = balls[id]
		fields.append([id, ball.form, ball.charge, ball.marked])
	return fields


func _clear_shot() -> void:
	_walls.clear()
	_pocketed.clear()
	_next_flat = 0
	for id in balls:
		balls[id].marked = false

extends RefCounted
## Host-authoritative ZODIAC alignment rules.
## Alignment = count of that element's signs alive on table. 2=Aspect, 3+=Grand Trine.

const CatalogUtil = preload("catalog_util.gd")
const ARIES = "ZODIAC_ARIES"
const TAURUS = "ZODIAC_TAURUS"
const GEMINI = "ZODIAC_GEMINI"
const CANCER = "ZODIAC_CANCER"
const LEO = "ZODIAC_LEO"
const VIRGO = "ZODIAC_VIRGO"
const LIBRA = "ZODIAC_LIBRA"
const SCORPIO = "ZODIAC_SCORPIO"
const SAGITTARIUS = "ZODIAC_SAGITTARIUS"
const CAPRICORN = "ZODIAC_CAPRICORN"
const AQUARIUS = "ZODIAC_AQUARIUS"
const PISCES = "ZODIAC_PISCES"
const KINDS = [
	ARIES,
	TAURUS,
	GEMINI,
	CANCER,
	LEO,
	VIRGO,
	LIBRA,
	SCORPIO,
	SAGITTARIUS,
	CAPRICORN,
	AQUARIUS,
	PISCES
]
const ELEMENT = {
	ARIES: "fire",
	LEO: "fire",
	SAGITTARIUS: "fire",
	TAURUS: "earth",
	VIRGO: "earth",
	CAPRICORN: "earth",
	GEMINI: "air",
	LIBRA: "air",
	AQUARIUS: "air",
	CANCER: "water",
	SCORPIO: "water",
	PISCES: "water"
}

var balls: Dictionary = {}
var alive: Dictionary = {}  # id -> true while on table
var pending = false
var shot_index = 0
var _utilities: Dictionary = {}
var _pocketed: Dictionary = {}
var _walls: Dictionary = {}
var _hit_object = false
var _taurus_temps = 0
var _aries_bonus = 0.0
var _leo_used = false
var _libra_used = false
var _round_key = ""


func reset_round(round_key: String) -> void:
	if round_key == _round_key:
		return
	_round_key = round_key
	balls.clear()
	alive.clear()
	_utilities.clear()
	_taurus_temps = 0
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
		balls[id] = {"kinds": [], "charge": 0, "paid": {}, "weight_on": false}
	balls[id].kinds = registered
	alive[id] = true


func set_alive(id: int, is_alive: bool) -> void:
	if balls.has(id):
		alive[id] = is_alive


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


func hit(ball_id: int, _ordinary_ids: Array) -> Dictionary:
	## Cue-ball hits drive Taurus temps; mark_object_hit covers survival charges.
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or not balls.has(ball_id):
		return action
	var ball: Dictionary = balls[ball_id]
	if TAURUS in ball.kinds:
		var cap = 5 if _count("earth") >= 2 else 3
		if _taurus_temps < cap:
			_taurus_temps += 1
			action.temp.append({"id": ball_id, "amount": 1})
		if _count("earth") >= 3 and not ball.weight_on:
			ball.weight_on = true
			action.weight.append({"id": ball_id, "delta": 1})
	return action


func wall(ball_id: int) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or not balls.has(ball_id):
		return action
	if _walls.has(ball_id):
		return action
	_walls[ball_id] = true
	var ball: Dictionary = balls[ball_id]
	if LIBRA in ball.kinds and not _libra_used and _count("air") >= 2:
		action.temp.append({"id": ball_id, "amount": 1})
		_libra_used = true
	return action


func pocket(ball_id: int, kinds: Array, base_value: float, ordinary: bool) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or _pocketed.has(ball_id):
		return action
	_pocketed[ball_id] = true
	var value = maxf(0.0, base_value) if is_finite(base_value) else 0.0
	if ordinary:
		alive[ball_id] = false
		if _aries_bonus > 0.0:
			action.points += ceilf(value * _aries_bonus)
			_aries_bonus = 0.0
		return action
	register_ball(ball_id, kinds)
	if not balls.has(ball_id):
		alive[ball_id] = false
		return action
	var ball: Dictionary = balls[ball_id]
	for kind in ball.kinds:
		if ball.paid.has(kind):
			continue
		var element: String = ELEMENT.get(kind, "")
		var count = _count(element)
		match kind:
			ARIES:
				action.points += ceilf(value * 0.25)
				if count >= 3:
					_aries_bonus = maxf(_aries_bonus, 0.5)
				elif count >= 2:
					_aries_bonus = maxf(_aries_bonus, 0.25)
				ball.paid[kind] = true
			GEMINI:
				if count >= 2:
					var peers = _alive_of("air", ball_id)
					if not peers.is_empty():
						var pick = peers[absi(hash(str(ball_id) + str(shot_index))) % peers.size()]
						action.temp.append({"id": pick, "amount": maxi(1, int(ceilf(value * 0.25)))})
				ball.paid[kind] = true
			CANCER:
				action.points += ceilf(value * 0.5 * ball.charge)
				ball.charge = 0
				ball.paid[kind] = true
			LEO:
				if count >= 3 and not _leo_used and element == "fire":
					action.points += ceilf(value)
					_leo_used = true
				ball.paid[kind] = true
			VIRGO:
				if count >= 2:
					action.lock_random = true
				ball.paid[kind] = true
			SCORPIO:
				if count >= 2:
					action.consume_nearest = true
					action.consume_rate = 0.25
				ball.paid[kind] = true
			SAGITTARIUS:
				if count >= 2:
					action.launch_nearest = true
				ball.paid[kind] = true
			CAPRICORN:
				if count >= 2 and not _utilities.has(kind):
					action.money = 2
					_utilities[kind] = true
				ball.paid[kind] = true
			AQUARIUS:
				if count >= 2 and not _utilities.has(kind):
					action.spawn_echo = true
					_utilities[kind] = true
				ball.paid[kind] = true
			PISCES:
				if count >= 2 and not _utilities.has(kind):
					action.heal = 1
					_utilities[kind] = true
				ball.paid[kind] = true
			TAURUS, LIBRA:
				ball.paid[kind] = true
	alive[ball_id] = false
	return action


func finish_shot(survivors: Array) -> void:
	if not pending:
		return
	# Refresh alive map from survivors for alignment.
	for id in balls:
		alive[id] = id in survivors and not _pocketed.has(id)
	if _hit_object and _count("water") >= 2:
		for id in survivors:
			if not balls.has(id) or _pocketed.has(id):
				continue
			if CANCER in balls[id].kinds:
				balls[id].charge = mini(2, balls[id].charge + 1)
	pending = false
	_clear_shot()


func alignment_counts() -> Dictionary:
	return {
		"fire": _count("fire"),
		"earth": _count("earth"),
		"air": _count("air"),
		"water": _count("water")
	}


func capture_shared() -> Dictionary:
	return {"align": alignment_counts()}


func capture_ball(id: int) -> Dictionary:
	if not balls.has(id):
		return {}
	return {"charge": balls[id].charge}


func display_fields() -> Array:
	var fields: Array = [alignment_counts()]
	for id in balls:
		fields.append([id, balls[id].charge, alive.get(id, false)])
	return fields


func _count(element: String) -> int:
	var total = 0
	var seen_kinds: Dictionary = {}
	for id in balls:
		if not alive.get(id, false) or _pocketed.has(id):
			continue
		for kind in balls[id].kinds:
			if ELEMENT.get(kind, "") == element and not seen_kinds.has(kind):
				seen_kinds[kind] = true
				total += 1
	return total


func _alive_of(element: String, exclude_id: int) -> Array:
	var result: Array = []
	for id in balls:
		if id == exclude_id or not alive.get(id, false) or _pocketed.has(id):
			continue
		for kind in balls[id].kinds:
			if ELEMENT.get(kind, "") == element:
				result.append(id)
				break
	return result


func _clear_shot() -> void:
	_hit_object = false
	_walls.clear()
	_pocketed.clear()
	_aries_bonus = 0.0
	_leo_used = false
	_libra_used = false

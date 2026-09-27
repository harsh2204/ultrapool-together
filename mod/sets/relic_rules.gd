extends RefCounted
## Host-authoritative RELIC dig-charge rules.

const CatalogUtil = preload("catalog_util.gd")
const SHARD = "RELIC_SHARD"
const IDOL = "RELIC_IDOL"
const CHEST = "RELIC_CHEST"
const CURSE = "RELIC_CURSE"
const CROWN = "RELIC_CROWN"
const DUST = "RELIC_DUST"
const RELIQUARY = "RELIC_RELIQUARY"
const KEYSTONE = "RELIC_KEYSTONE"
const KINDS = [SHARD, IDOL, CHEST, CURSE, CROWN, DUST, RELIQUARY, KEYSTONE]
const MAX_DIG = 4

var balls: Dictionary = {}
var persist_digs = false
var idol_temps = 0
var pending = false
var shot_index = 0
var _utilities: Dictionary = {}
var _pocketed: Dictionary = {}
var _walls: Dictionary = {}
var _hit_object = false
var _round_key = ""


func reset_round(round_key: String) -> void:
	if round_key == _round_key:
		return
	_round_key = round_key
	balls.clear()
	persist_digs = false
	idol_temps = 0
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
		balls[id] = {"kinds": [], "dig": 0, "paid": {}}
	balls[id].kinds = registered
	if CROWN in registered:
		persist_digs = true


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
	if _walls.has(ball_id):
		return action
	_walls[ball_id] = true
	var ball: Dictionary = balls[ball_id]
	if DUST in ball.kinds:
		_gain_dig(ball_id, action)
	return action


func pocket(ball_id: int, kinds: Array, base_value: float, ordinary: bool) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending or ball_id <= 0 or _pocketed.has(ball_id):
		return action
	_pocketed[ball_id] = true
	if ordinary:
		return action
	register_ball(ball_id, kinds)
	if not balls.has(ball_id):
		return action
	var ball: Dictionary = balls[ball_id]
	var value = maxf(0.0, base_value) if is_finite(base_value) else 0.0
	var max_dig_anywhere = _max_dig()
	for kind in ball.kinds:
		if ball.paid.has(kind):
			continue
		match kind:
			SHARD:
				action.points += ceilf(value * 0.25 * ball.dig)
				ball.paid[kind] = true
			RELIQUARY:
				if max_dig_anywhere >= 3:
					action.points += ceilf(value * 0.5)
					ball.paid[kind] = true
			CHEST:
				if max_dig_anywhere >= 2 and not _utilities.has(kind):
					action.money = 2
					_spend_one_dig()
					_utilities[kind] = true
				ball.paid[kind] = true
			CURSE:
				action.lock_random = true
				ball.paid[kind] = true
			KEYSTONE:
				if ball.dig >= 1:
					for other_id in balls:
						balls[other_id].dig = mini(MAX_DIG, balls[other_id].dig + 1)
				ball.paid[kind] = true
			IDOL, CROWN, DUST:
				ball.paid[kind] = true
	if not persist_digs:
		ball.dig = 0
	return action


func finish_shot(survivors: Array) -> Dictionary:
	var action = CatalogUtil.empty_action()
	if not pending:
		return action
	if _hit_object:
		for id in survivors:
			if not balls.has(id) or _pocketed.has(id):
				continue
			if SHARD in balls[id].kinds:
				_gain_dig(id, action)
	pending = false
	_clear_shot()
	return action


func capture_ball(id: int) -> Dictionary:
	if not balls.has(id):
		return {}
	return {"dig": balls[id].dig}


func capture_shared() -> Dictionary:
	return {"persist": persist_digs, "idol_temps": idol_temps}


func display_fields() -> Array:
	var fields: Array = [persist_digs, idol_temps]
	for id in balls:
		fields.append([id, balls[id].dig])
	return fields


func _gain_dig(id: int, action: Dictionary) -> void:
	if not balls.has(id):
		return
	var ball: Dictionary = balls[id]
	var before = ball.dig
	ball.dig = mini(MAX_DIG, ball.dig + 1)
	if ball.dig > before:
		for other_id in balls:
			if IDOL in balls[other_id].kinds and idol_temps < 3:
				idol_temps += 1
				action.temp.append({"id": other_id, "amount": 1})


func _max_dig() -> int:
	var best = 0
	for id in balls:
		best = maxi(best, balls[id].dig)
	return best


func _spend_one_dig() -> void:
	for id in balls:
		if balls[id].dig >= 2:
			balls[id].dig -= 1
			return
	for id in balls:
		if balls[id].dig >= 1:
			balls[id].dig -= 1
			return


func _clear_shot() -> void:
	_hit_object = false
	_walls.clear()
	_pocketed.clear()
	if not persist_digs:
		for id in balls:
			# Digs from unfinished shots stay until pocket when Crown is absent;
			# Shard accrues across shots intentionally — only clear paid digs on pocket.
			pass

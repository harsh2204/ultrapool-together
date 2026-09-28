extends RefCounted
## Bounded host-owned cue perks. Refs PERF-010/034/035; no engine or frame work.
## Points use unmultiplied native base value, without upward rounding. One perk
## can fire per shot and each player's round budget follows them across cue swaps.

const CueModels = preload("cue_models.gd")
const MAX_PLAYERS = 8
const MAX_BALLS = 128

var pending = false
var shot_index = 0
var shot_pots = 0
var perk_used = false
var _round_key = ""
var _players: Dictionary = {}
var _balls: Dictionary = {}
var _potted: Dictionary = {}
var _actor = 0
var _profile: Dictionary = {}
var _power = 0.0
var _ordinary_count = 0
var _shots_in_round = 0
var _first_shot = false
var _comeback = false
var _relay = false
var _previous_actor = 0
var _previous_pots = 0


func reset_round(key: String) -> void:
	if key == _round_key:
		return
	_round_key = key
	_players.clear()
	_balls.clear()
	_potted.clear()
	_profile.clear()
	pending = false
	shot_index = 0
	shot_pots = 0
	perk_used = false
	_actor = 0
	_shots_in_round = 0
	_previous_actor = 0
	_previous_pots = 0


func begin_shot(
	index: int, actor: int, model: String, raw_power: float, ordinary_count: int, ball_ids: Array
) -> bool:
	if (
		pending or index <= shot_index or actor <= 0 or not CueModels.is_known(model)
		or not is_finite(raw_power) or raw_power <= 50.0 or raw_power > 200.1
		or ordinary_count < 0 or ordinary_count > ball_ids.size() or ball_ids.size() > MAX_BALLS
		or (not _players.has(actor) and _players.size() >= MAX_PLAYERS)
	):
		return false
	var registered: Dictionary = {}
	for id in ball_ids:
		if typeof(id) != TYPE_INT or id <= 0 or registered.has(id):
			return false
		registered[id] = {"walls": 0, "hits": {}}
	if not _players.has(actor):
		_players[actor] = {"bonus": 0.0, "previous_pots": 0, "has_previous": false}
	var history: Dictionary = _players[actor]
	_actor = actor
	_profile = CueModels.entry(model)
	_power = raw_power
	_ordinary_count = ordinary_count
	_first_shot = _shots_in_round == 0
	_comeback = history.has_previous and history.previous_pots == 0
	_relay = _previous_actor > 0 and _previous_actor != actor and _previous_pots > 0
	_shots_in_round += 1
	shot_index = index
	shot_pots = 0
	perk_used = false
	_balls = registered
	_potted.clear()
	pending = true
	return true


## Newly spawned native objects may join an active shot through node_added.
## Overflow makes the shot's remaining evidence unknown; never infer a dry shot
## from a partial object set or erase bonuses already paid from its round budget.
func register_ball(id: int) -> bool:
	if not pending or id <= 0:
		return false
	if _balls.has(id):
		return true
	if _balls.size() >= MAX_BALLS:
		invalidate_shot()
		return false
	_balls[id] = {"walls": 0, "hits": {}}
	return true


## Mid-shot overflow cannot undo score already awarded, so preserve spent budget
## and accepted-shot count. Missing pots invalidate only this shooter's personal
## predecessor and the table's immediate predecessor; other player history stays.
func invalidate_shot() -> void:
	if not pending:
		return
	_players[_actor].has_previous = false
	_players[_actor].previous_pots = 0
	_previous_actor = 0
	_previous_pots = 0
	_profile.clear()
	_balls.clear()
	_potted.clear()
	_first_shot = false
	_comeback = false
	_relay = false
	shot_pots = 0
	perk_used = true
	pending = false


## The native shot still plays when its board exceeds the supported cue bound.
## Missing contact/pot evidence must never reset spent budget or grant recovery/
## relay eligibility. Advancing round history also prevents a delayed Opener.
func skip_shot(index: int, actor: int) -> bool:
	if (
		index <= shot_index or actor <= 0
		or (not _players.has(actor) and _players.size() >= MAX_PLAYERS)
	):
		return false
	if pending and _players.has(_actor):
		_players[_actor].has_previous = false
		_players[_actor].previous_pots = 0
	if not _players.has(actor):
		_players[actor] = {"bonus": 0.0, "previous_pots": 0, "has_previous": false}
	_players[actor].has_previous = false
	_players[actor].previous_pots = 0
	_actor = actor
	_profile.clear()
	_balls.clear()
	_potted.clear()
	_previous_actor = 0
	_previous_pots = 0
	_first_shot = false
	_comeback = false
	_relay = false
	_shots_in_round += 1
	shot_index = index
	shot_pots = 0
	perk_used = true
	pending = false
	return true


func hit(first: int, second: int) -> void:
	if (
		not pending or first == second or not _balls.has(first) or not _balls.has(second)
		or _potted.has(first) or _potted.has(second)
	):
		return
	for pair in [[first, second], [second, first]]:
		var hits: Dictionary = _balls[pair[0]].hits
		if hits.size() < 2:
			hits[pair[1]] = true


func wall(id: int) -> void:
	if pending and _balls.has(id) and not _potted.has(id):
		_balls[id].walls = mini(2, int(_balls[id].walls) + 1)


## Only the adapter may call this after confirming a real, positive-scoring pot.
## Every eligible pot updates recovery/relay history, even for the House cue.
func pocket(id: int, base_value: float, pocket_kind: String) -> float:
	if (
		not pending or not _balls.has(id) or _potted.has(id)
		or not is_finite(base_value) or base_value <= 0.0
		or pocket_kind not in ["corner", "middle"]
	):
		return 0.0
	_potted[id] = true
	shot_pots += 1
	if perk_used or not _qualifies(id, pocket_kind):
		return 0.0
	# Consume even when the player's shared-across-models round cap is exhausted.
	perk_used = true
	var rate: float = _profile.bonus_rate
	var cap: float = _profile.bonus_cap
	var remaining: float = maxf(0.0, CueModels.ROUND_BONUS_CAP - _players[_actor].bonus)
	var points: float = minf(minf(base_value * rate, cap), remaining)
	_players[_actor].bonus += points
	return points


func finish_shot() -> void:
	if not pending:
		return
	_players[_actor].has_previous = true
	_players[_actor].previous_pots = shot_pots
	_previous_actor = _actor
	_previous_pots = shot_pots
	pending = false
	_balls.clear()
	_potted.clear()


func bonus_for(actor: int) -> float:
	return _players[actor].bonus if _players.has(actor) else 0.0


func _qualifies(id: int, pocket_kind: String) -> bool:
	var ball: Dictionary = _balls[id]
	match str(_profile.get("trigger", "")):
		"bankshot":
			return ball.walls >= 1
		"double_rail":
			return ball.walls >= 2
		"carom":
			return ball.hits.size() >= 2
		"silk":
			return _power <= 90.0
		"thunder":
			return _power >= 170.0
		"opener":
			return _first_shot
		"closer":
			return _ordinary_count <= 3
		"comeback":
			return _comeback
		"relay":
			return _relay
		"corner":
			return pocket_kind == "corner"
		"sidewinder":
			return pocket_kind == "middle"
		"clean":
			return ball.walls == 0
	return false

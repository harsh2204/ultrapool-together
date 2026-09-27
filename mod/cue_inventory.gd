extends RefCounted
## Authoritative, run-scoped personal cue racks. Refs PERF-010/034/035/037.
## The shop service owns actor/session/revision checks and the shared wallet.
## It must debit an accepted cost synchronously before handling another command.
## No disk writes, scene resources, or per-frame work live in this model.

const CueModels = preload("cue_models.gd")
const CueCatalog = preload("cue_catalog.gd")
const MAX_PLAYERS = 8

var _players: Dictionary = {}


## Call at match start/rematch or disconnect teardown, never on shop transitions.
## Disconnected members retain their rack until this reset; the controller rejects
## their commands. Malformed trusted roster input clears the old run and fails shut.
func reset(players: Array = []) -> bool:
	_players.clear()
	if players.size() > MAX_PLAYERS:
		return false
	var next: Dictionary = {}
	for member in players:
		if not member is Dictionary:
			return false
		var id = member.get("id")
		if typeof(id) != TYPE_INT or id <= 0 or next.has(id):
			return false
		var finish: String = CueCatalog.DEFAULT_ID
		if typeof(member.get("cue")) == TYPE_STRING:
			finish = CueCatalog.normalize(member.cue)
		next[id] = {
			"id": id,
			"owned": [CueModels.DEFAULT_ID],
			"equipped": CueModels.DEFAULT_ID,
			"finish": finish,
		}
	_players = next
	return true


func snapshot() -> Dictionary:
	var result: Array = []
	var ids: Array = _players.keys()
	ids.sort()
	for id in ids:
		result.append(_players[id].duplicate(true))
	return {"players": result}


static func valid_snapshot(value) -> bool:
	if not value is Dictionary or value.size() != 1:
		return false
	var players = value.get("players")
	if not players is Array or players.size() > MAX_PLAYERS:
		return false
	var seen: Dictionary = {}
	for member in players:
		if not member is Dictionary or member.size() != 4:
			return false
		var id = member.get("id")
		if typeof(id) != TYPE_INT or id <= 0 or seen.has(id):
			return false
		seen[id] = true
		var owned = member.get("owned")
		if not owned is Array or owned.is_empty() or owned.size() > CueModels.ids().size():
			return false
		var owned_ids: Dictionary = {}
		for model in owned:
			if typeof(model) != TYPE_STRING or not CueModels.is_known(model) or owned_ids.has(model):
				return false
			owned_ids[model] = true
		if not owned_ids.has(CueModels.DEFAULT_ID):
			return false
		var equipped = member.get("equipped")
		if typeof(equipped) != TYPE_STRING or not owned_ids.has(equipped):
			return false
		if not _valid_finish(member.get("finish")):
			return false
	return true


## Valid identical state is accepted without replacing retained records.
func apply_snapshot(value) -> bool:
	if not valid_snapshot(value):
		return false
	var next: Dictionary = {}
	for member in value.players:
		next[member.id] = member.duplicate(true)
	if next != _players:
		_players = next
	return true


func player(id: int) -> Dictionary:
	return _players[id].duplicate(true) if _players.has(id) else {}


func has_player(id: int) -> bool:
	return _players.has(id)


func model_for(id: int) -> String:
	return _players[id].equipped if _players.has(id) else CueModels.DEFAULT_ID


func finish_for(id: int) -> String:
	return _players[id].finish if _players.has(id) else CueCatalog.DEFAULT_ID


## A purchase equips its model; switching models and cosmetic finishes is free.
## Currency is deliberately external: the shared native shop wallet is the only
## balance. On accepted=true the caller subtracts cost before yielding or sending.
## Session, scene, revision, and replay protection belong to the shop boundary.
func transact(actor: int, action: String, model: String, finish: String, money: float) -> Dictionary:
	if not _players.has(actor):
		return _rejected("This player has no cue rack in the current run.")
	if action not in ["cue_buy", "cue_equip", "cue_finish"]:
		return _rejected("Unknown cue action.")
	if not CueModels.is_known(model) or not _valid_finish(finish):
		return _rejected("Choose a cue and finish from the rack.")
	if not is_finite(money) or money < 0.0:
		return _rejected("The shared wallet is unavailable.")
	var current: Dictionary = _players[actor]
	var cost = 0
	if action == "cue_buy":
		if model in current.owned:
			return _rejected("That cue is already in your rack.")
		cost = int(CueModels.entry(model).price)
		if money < cost:
			return _rejected("Not enough shared money for that cue.")
	elif model not in current.owned:
		return _rejected("Buy that cue before equipping it.")
	if action == "cue_finish" and model != current.equipped:
		return _rejected("The equipped cue changed. Choose its finish again.")
	var next: Dictionary = current.duplicate(true)
	if action == "cue_buy":
		next.owned.append(model)
	next.equipped = model
	next.finish = finish
	var changed: bool = next != current
	if changed:
		_players[actor] = next
	return {"accepted": true, "error": "", "cost": cost, "changed": changed}


static func _valid_finish(value) -> bool:
	return (
		typeof(value) == TYPE_STRING
		and CueCatalog.is_known(value)
		and CueCatalog.normalize(value) == value
	)


static func _rejected(message: String) -> Dictionary:
	return {"accepted": false, "error": message, "cost": 0, "changed": false}

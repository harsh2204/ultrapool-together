extends RefCounted

const REQUESTS = ["shot", "pass", "shop_request", "sync_request"]
const BROADCASTS = ["state", "snapshot", "shot_start", "shop_state", "checkpoint"]
const RESULTS = ["shot_result", "shop_result"]


func route(roster: Dictionary, actor: int, envelope: Dictionary) -> Dictionary:
	if (
		not roster.get("started") is bool
		or not roster.started
		or not roster.get("table_count") is int
		or roster.table_count < 1
		or roster.table_count > 8
		or not roster.get("players") is Array
		or roster.players.size() > 8
		or envelope.get("kind") != "table"
		or not envelope.get("table") is int
		or envelope.table < 0
		or envelope.table >= roster.table_count
		or not envelope.get("payload") is Dictionary
		or not envelope.get("reliable", true) is bool
	):
		return {}
	var payload: Dictionary = envelope.payload
	var kind = payload.get("kind")
	if kind not in REQUESTS and kind not in BROADCASTS and kind not in RESULTS:
		return {}
	var authority = _table_leader(roster, envelope.table)
	if authority.is_empty():
		return {}
	var leader: int = authority.id
	var members: Dictionary = {}
	var occupied: Dictionary = {}
	for player in roster.players:
		if not player is Dictionary or not player.get("table") is int:
			return {}
		if player.table != envelope.table:
			continue
		if (
			not player.get("id") is int
			or player.id <= 0
			or members.has(player.id)
			or not player.get("slot") is int
			or player.slot < 0
			or player.slot >= 8
			or occupied.has(player.slot)
			or not player.get("connected") is bool
		):
			return {}
		members[player.id] = player
		occupied[player.slot] = true
	if not members.has(leader) or not members.has(actor) or not members[actor].connected:
		return {}
	var target = 0
	if envelope.has("target"):
		if (
			not envelope.target is int
			or not members.has(envelope.target)
			or not members[envelope.target].connected
		):
			return {}
		target = envelope.target
	var recipients: Array = []
	if kind in REQUESTS:
		if not members[leader].connected or (target != 0 and target != leader):
			return {}
		recipients.append(leader)
	else:
		if actor != leader or envelope.get("epoch") != authority.epoch:
			return {}
		if kind in RESULTS:
			if target == 0:
				return {}
			recipients.append(target)
		elif target != 0:
			if target != actor:
				recipients.append(target)
		else:
			for player in members.values():
				if player.connected and player.id != actor:
					recipients.append(player.id)
	return {
		"recipients": recipients,
		"payload": payload.duplicate(true),
		"actor": actor,
		"table": envelope.table,
		"epoch": authority.epoch,
		"unreliable": kind == "snapshot" and not envelope.get("reliable", true)
	}


func _table_leader(roster: Dictionary, table: int) -> Dictionary:
	var leaders = roster.get("table_leaders")
	if not leaders is Array or leaders.size() > 8:
		return {}
	var found: Dictionary = {}
	for entry in leaders:
		if (
			not entry is Dictionary
			or not entry.get("table") is int
			or not entry.get("id") is int
			or entry.id <= 0
			or not entry.get("epoch") is int
			or entry.epoch < 1
		):
			return {}
		if entry.table == table:
			if not found.is_empty():
				return {}
			found = entry
	return found

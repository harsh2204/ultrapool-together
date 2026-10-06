extends RefCounted
## PERF-008/010/026: one immutable, bounded final build per table and match.
## The controller authenticates the leader and finalized summary before accept.

const Inventory = preload("player_inventory_sync.gd")
const CueInventory = preload("cue_inventory.gd")
const MAX_TABLES = 8
const MAX_RECORD_BYTES = 98304

var _match = 0
var _records: Dictionary = {}


func reset(match_id: int) -> void:
	_match = match_id
	_records = {}


func accept(record, database: Node) -> bool:
	if not validate_record(record, database) or record.match != _match:
		return false
	if _records.has(record.table):
		return _records[record.table] == record
	_records[record.table] = record.duplicate(true)
	return true


func has_table(table: int) -> bool:
	return _records.has(table)


func get_record(table: int) -> Dictionary:
	return _records.get(table, {}).duplicate(true)


static func validate_record(record, database: Node) -> bool:
	if not record is Dictionary or record.size() != 5 or database == null:
		return false
	for key in ["match", "table", "leader"]:
		if not record.get(key) is int:
			return false
	if record.match <= 0 or record.table < 0 or record.table >= MAX_TABLES or record.leader <= 0:
		return false
	if not Inventory.valid(record.get("inventory"), database):
		return false
	if not CueInventory.valid_snapshot(record.get("cues")):
		return false
	# Do not retain arbitrary extension fields, objects or unbounded nested data.
	var inventory: Dictionary = record.inventory
	if inventory.size() != 5:
		return false
	for group in Inventory.SLOT_LIMITS:
		for item in inventory[group]:
			if item == null:
				continue
			if (
				item.size()
				!= 2 + Inventory.NUMBERS.size() + Inventory.FLAGS.size() + int(item.has("copy_id"))
			):
				return false
	return var_to_bytes(record).size() <= MAX_RECORD_BYTES


static func complete(summaries: Array) -> bool:
	if summaries.is_empty() or summaries.size() > MAX_TABLES:
		return false
	var seen: Dictionary = {}
	for summary in summaries:
		if not summary is Dictionary or not summary.get("table") is int:
			return false
		if summary.table < 0 or summary.table >= MAX_TABLES or seen.has(summary.table):
			return false
		if not summary.get("finished") is bool or not summary.finished:
			return false
		seen[summary.table] = true
	return true


static func winner_tables(summaries: Array, mode: String) -> Array:
	if not complete(summaries):
		return []
	var winners: Array = []
	var best = -INF
	for summary in summaries:
		if summary.get("status") == "Table host disconnected":
			continue
		if mode == "coop":
			if summary.get("run_won") == true:
				winners.append(summary.table)
			continue
		var score = summary.get("score")
		if mode == "race":
			var order = summary.get("finish_order")
			if summary.get("run_won") != true or not order is int or order <= 0:
				continue
			score = -order
		elif mode != "score":
			return []
		if not (score is int or score is float) or not is_finite(float(score)):
			continue
		if score > best:
			best = score
			winners = [summary.table]
		elif score == best:
			winners.append(summary.table)
	winners.sort()
	return winners

extends Node

const RunCheckpoint = preload("run_checkpoint.gd")
const CHECKPOINT_INTERVAL_MS = 1000
const TAKEOVER_GRACE_MS = 15000
const REJOIN_PATH = "user://together_rejoin.cfg"
const REJOIN_MAX_AGE_SECONDS = 86400
const MAX_ROOM_CODE = 32

var database: Node
# Latest accepted checkpoint per table: {"epoch", "payload"}. One entry per table.
var _checkpoints: Dictionary = {}
# Room host only: table -> {"leader", "since"} while that table's leader is away.
var _lost_leaders: Dictionary = {}
var _sent_shop_revision = -1
var _last_run: Dictionary = {}
var _checkpoint_revision = 0
var _last_checkpoint_at = -CHECKPOINT_INTERVAL_MS
var _remembered_room = ""


func setup(catalog: Node) -> void:
	database = catalog
	_remembered_room = _load_room()


func clear() -> void:
	_checkpoints.clear()
	_lost_leaders.clear()
	reset_leader()


func reset_leader() -> void:
	_sent_shop_revision = -1
	_last_run.clear()
	_checkpoint_revision = 0
	_last_checkpoint_at = -CHECKPOINT_INTERVAL_MS


# Returns a checkpoint payload when the settled shop changed, at most once per interval.
# The native run state is only read once those cheaper checks pass.
func leader_checkpoint(shop_state: Dictionary, now: int, run_state_source: Callable) -> Dictionary:
	if not shop_state.get("open", false) or shop_state.get("busy", true):
		return {}
	var revision: int = shop_state.get("revision", -1)
	if revision == _sent_shop_revision or now - _last_checkpoint_at < CHECKPOINT_INTERVAL_MS:
		return {}
	_sent_shop_revision = revision
	var run = RunCheckpoint.capture(run_state_source.call())
	if run.is_empty() or run == _last_run:
		return {}
	_last_run = run
	_last_checkpoint_at = now
	_checkpoint_revision += 1
	return {"kind": "checkpoint", "revision": _checkpoint_revision, "run": run}


func store(table: int, epoch: int, payload) -> bool:
	if (
		epoch < 1
		or not payload is Dictionary
		or not payload.get("revision") is int
		or payload.revision < 1
		or not RunCheckpoint.valid(payload.get("run"), database)
	):
		return false
	var stored: Dictionary = _checkpoints.get(table, {})
	if (
		not stored.is_empty()
		and (
			epoch < stored.epoch
			or (epoch == stored.epoch and payload.revision <= stored.payload.revision)
		)
	):
		return false
	_checkpoints[table] = {"epoch": epoch, "payload": payload.duplicate(true)}
	return true


func checkpoint(table: int) -> Dictionary:
	return _checkpoints.get(table, {}).get("payload", {}).get("run", {}).duplicate(true)


func run_state_from(data) -> RunState:
	if not RunCheckpoint.valid(data, database):
		return null
	return RunCheckpoint.to_run_state(data, database)


static func valid_resume(resume) -> bool:
	return (
		resume is Dictionary
		and resume.get("checkpoint") is Dictionary
		and (resume.get("total_score") is float or resume.get("total_score") is int)
		and is_finite(float(resume.total_score))
		and float(resume.total_score) >= 0.0
		and resume.get("used_shots") is int
		and resume.used_shots >= 0
		and resume.used_shots <= 1000
	)


# Score PvP keeps spent shots and banked points: a shot in flight when the
# leader vanished counts as spent, and only the board rewinds to the checkpoint.
func resume_for(table: int, summary: Dictionary, score_match: bool) -> Dictionary:
	var used: int = summary.get("shots_used", 0)
	if score_match and summary.get("pending", false):
		used += 1
	return {
		"checkpoint": checkpoint(table),
		"total_score": float(summary.get("score", 0.0)),
		"used_shots": used
	}


func leader_left(table: int, leader: int, now: int) -> void:
	if not _lost_leaders.has(table):
		_lost_leaders[table] = {"leader": leader, "since": now}


func leader_returned(table: int) -> void:
	_lost_leaders.erase(table)


func is_waiting(table: int) -> bool:
	return _lost_leaders.has(table)


func lost_leader(table: int) -> int:
	return _lost_leaders.get(table, {}).get("leader", 0)


func takeover_in_ms(table: int, now: int) -> int:
	if not _lost_leaders.has(table):
		return -1
	return maxi(0, TAKEOVER_GRACE_MS - (now - _lost_leaders[table].since))


func due_takeovers(lobby: Dictionary, now: int) -> Array:
	var due: Array = []
	for table in _lost_leaders:
		var entry: Dictionary = _lost_leaders[table]
		if now - entry.since < TAKEOVER_GRACE_MS:
			continue
		var successor = successor_for(lobby, table, entry.leader)
		if successor != 0:
			due.append({"table": table, "successor": successor})
	return due


# The next connected seat after the departed leader, wrapping around the table.
static func successor_for(lobby: Dictionary, table: int, leader: int) -> int:
	var members: Array = lobby.get("players", []).filter(
		func(player): return player.get("table") == table
	)
	members.sort_custom(func(a, b): return a.slot < b.slot)
	var start = 0
	for index in members.size():
		if members[index].id == leader:
			start = index + 1
			break
	for offset in members.size():
		var player: Dictionary = members[(start + offset) % members.size()]
		if player.id != leader and player.connected:
			return player.id
	return 0


func remembered_room() -> String:
	return _remembered_room


func remember(room_code: String) -> void:
	if room_code.is_empty() or room_code.length() > MAX_ROOM_CODE:
		return
	var file = ConfigFile.new()
	file.set_value("rejoin", "room", room_code)
	file.set_value("rejoin", "saved_at", int(Time.get_unix_time_from_system()))
	if file.save(REJOIN_PATH) != OK:
		push_warning("[Together] Could not remember the match for rejoining.")
		return
	_remembered_room = room_code


func forget() -> void:
	_remembered_room = ""
	if FileAccess.file_exists(REJOIN_PATH):
		DirAccess.remove_absolute(REJOIN_PATH)


func _load_room() -> String:
	var file = ConfigFile.new()
	if file.load(REJOIN_PATH) != OK:
		return ""
	var room = file.get_value("rejoin", "room", "")
	var saved_at = file.get_value("rejoin", "saved_at", 0)
	if (
		not room is String
		or room.length() > MAX_ROOM_CODE
		or not saved_at is int
		or Time.get_unix_time_from_system() - saved_at > REJOIN_MAX_AGE_SECONDS
	):
		return ""
	return room

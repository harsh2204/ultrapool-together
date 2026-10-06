extends RefCounted
## UP12 / PERF-008/010/014/026: reversible presentation only. Original build
## indices (including empty slots) are identities; no BallItems or game callbacks.

const MAX_TABLES = 8
const MAX_SLOTS = 64
const MAX_COUNTER = 2147483647
const MOTION_INTERVAL_MSEC = 50
const MAX_STATE_BYTES = 4096

var match_id = 0
var _states: Dictionary = {}
var _occupied: Dictionary = {}
var _next_token = 0
var _motion_times: Dictionary = {}


func reset(generation: int) -> void:
	match_id = generation
	_states = {}
	_occupied = {}
	_next_token = 0
	_motion_times = {}


func ensure_table(table: int, build: Array) -> bool:
	if match_id <= 0 or table < 0 or table >= MAX_TABLES or build.size() < 16 or build.size() > MAX_SLOTS:
		return false
	if _states.has(table):
		return _states[table].order.size() == build.size()
	var order: Array = []
	var occupied: Array = []
	for slot in build.size():
		order.append(slot)
		occupied.append(build[slot] != null)
	_states[table] = {"revision": 0, "order": order, "drag": {}}
	_occupied[table] = occupied
	return true


func snapshot(table: int) -> Dictionary:
	return _states.get(table, {}).duplicate(true)


func transition(table: int, actor: int, request: Dictionary) -> Dictionary:
	if actor <= 0 or not _states.has(table):
		return _result(table, false, "The final rack is unavailable.")
	var state: Dictionary = _states[table]
	if not request.get("revision") is int or request.revision != state.revision:
		return _result(table, false, "The rack changed. Try again.")
	if state.revision >= MAX_COUNTER:
		return _result(table, false, "This rack cannot be changed again.")
	match request.get("action"):
		"begin":
			if state.revision >= MAX_COUNTER - 1:
				return _result(table, false, "This rack cannot be changed again.")
			if request.size() != 3 or not request.get("slot") is int or not _valid_slot(table, request.slot):
				return _result(table, false, "That ball is unavailable.")
			if not _occupied[table][request.slot]:
				return _result(table, false, "An empty slot cannot be picked up.")
			if not state.drag.is_empty():
				return _result(table, false, "Someone is already arranging this rack.")
			for other in _states.values():
				if other.drag.get("actor", 0) == actor:
					return _result(table, false, "Finish moving your other ball first.")
			if _next_token >= MAX_COUNTER:
				return _result(table, false, "This rack cannot be changed again.")
			_next_token += 1
			state.drag = {"actor": actor, "slot": request.slot, "token": _next_token,
				"position": Vector2.ZERO, "seq": 0}
		"drop", "cancel":
			var count = 4 if request.action == "drop" else 3
			if request.size() != count or not request.get("token") is int or state.drag.is_empty():
				return _result(table, false, "That move has already ended.")
			if state.drag.actor != actor or state.drag.token != request.token:
				return _result(table, false, "Only the player holding this ball can move it.")
			if request.action == "drop":
				if not request.get("target") is int or not _valid_slot(table, request.target):
					return _result(table, false, "Drop the ball into a rack slot.")
				var source: int = state.order.find(state.drag.slot)
				var displaced = state.order[request.target]
				state.order[request.target] = state.drag.slot
				state.order[source] = displaced
			state.drag = {}
		"reset":
			if request.size() != 2:
				return _result(table, false, "Invalid reset request.")
			if not state.drag.is_empty() and state.drag.actor != actor:
				return _result(table, false, "Someone is holding a ball. Try again when they finish.")
			for slot in state.order.size():
				state.order[slot] = slot
			state.drag = {}
		_:
			return _result(table, false, "Invalid rack action.")
	state.revision += 1
	_motion_times.erase(table)
	return _result(table, true, "")


func _result(table: int, accepted: bool, reason: String) -> Dictionary:
	return {"accepted": accepted, "changed": accepted, "reason": reason, "state": snapshot(table)}


## Host-only motion admission. No queue: excess samples are disposable. The
## next accepted sample replaces one position; reliable drop/cancel is separate.
func motion(table: int, actor: int, token: int, sequence: int, position: Vector2, now_msec: int) -> bool:
	if not _motion_matches(table, actor, token, sequence, position):
		return false
	if _motion_times.has(table) and now_msec - _motion_times[table] < MOTION_INTERVAL_MSEC:
		return false
	_motion_times[table] = now_msec
	return apply_motion(table, actor, token, sequence, position)


func apply_motion(table: int, actor: int, token: int, sequence: int, position: Vector2) -> bool:
	if not _motion_matches(table, actor, token, sequence, position):
		return false
	_states[table].drag.position = position.clamp(Vector2.ZERO, Vector2.ONE)
	_states[table].drag.seq = sequence
	return true


func _motion_matches(table: int, actor: int, token: int, sequence: int, position: Vector2) -> bool:
	if not _states.has(table) or not position.is_finite() or sequence <= 0 or sequence > MAX_COUNTER:
		return false
	var drag: Dictionary = _states[table].drag
	return (not drag.is_empty() and drag.actor == actor and drag.token == token and sequence > drag.seq)


func release_actor(actor: int) -> Array:
	var changed: Array = []
	for table in _states:
		var state: Dictionary = _states[table]
		if state.drag.get("actor", 0) == actor:
			state.drag = {}
			state.revision += 1
			_motion_times.erase(table)
			changed.append(table)
	return changed


## Coordinator snapshots are still checked against the archived slot identities.
## A resync/rejection at the same revision must not rewind newer lossy motion.
func apply_state(table: int, state: Dictionary) -> bool:
	if not _valid_state(table, state):
		return false
	var current: Dictionary = _states[table]
	if state.revision < current.revision:
		return false
	var incoming = state.duplicate(true)
	if state.revision == current.revision:
		if state.order != current.order or state.drag.is_empty() != current.drag.is_empty():
			return false
		if not state.drag.is_empty():
			for field in ["actor", "slot", "token"]:
				if state.drag[field] != current.drag[field]:
					return false
			if state.drag.seq < current.drag.seq:
				incoming.drag = current.drag.duplicate(true)
			elif state.drag.seq == current.drag.seq and state.drag.position != current.drag.position:
				return false
	_states[table] = incoming
	return true


func _valid_state(table: int, state: Dictionary) -> bool:
	if (not _states.has(table) or state.size() != 3 or not state.get("revision") is int
		or state.revision < 0 or state.revision > MAX_COUNTER or not state.get("order") is Array
		or state.order.size() != _occupied[table].size() or not state.get("drag") is Dictionary):
		return false
	var seen: Dictionary = {}
	for slot in state.order:
		if not slot is int or not _valid_slot(table, slot) or seen.has(slot):
			return false
		seen[slot] = true
	var drag: Dictionary = state.drag
	if not drag.is_empty():
		if drag.size() != 5 or state.revision >= MAX_COUNTER:
			return false
		for field in ["actor", "slot", "token", "seq"]:
			if not drag.get(field) is int:
				return false
		if (drag.actor <= 0 or not _valid_slot(table, drag.slot) or not _occupied[table][drag.slot]
			or drag.token <= 0 or drag.token > MAX_COUNTER or drag.seq < 0 or drag.seq > MAX_COUNTER
			or not drag.get("position") is Vector2 or not drag.position.is_finite()
			or drag.position != drag.position.clamp(Vector2.ZERO, Vector2.ONE)):
			return false
	return var_to_bytes(state).size() <= MAX_STATE_BYTES


func _valid_slot(table: int, slot: int) -> bool:
	return slot >= 0 and slot < _occupied[table].size()

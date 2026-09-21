extends RefCounted

var revision = 0
var last_error = ""
var _eligible: Array[int] = []
var _ready: Dictionary = {}
var _context


func configure(ids: Array, context = null) -> bool:
	var eligible: Array[int] = []
	for id in ids:
		if not id is int or id <= 0 or eligible.has(id):
			return _reject("The vote needs distinct player IDs.")
		eligible.append(id)
	eligible.sort()
	if eligible != _eligible or typeof(context) != typeof(_context) or context != _context:
		_eligible = eligible
		_context = context.duplicate(true) if context is Dictionary or context is Array else context
		_ready.clear()
		revision += 1
	last_error = ""
	return true


func set_ready(actor: int, value: bool, expected_revision: int = -1) -> bool:
	if not _eligible.has(actor):
		return _reject("Only connected members can vote.")
	if expected_revision >= 0 and expected_revision != revision:
		return _reject("The vote changed. Please choose again.")
	if is_ready(actor) != value:
		if value:
			_ready[actor] = true
		else:
			_ready.erase(actor)
	last_error = ""
	return true


func reset() -> void:
	_ready.clear()
	revision += 1
	last_error = ""


func is_ready(actor: int) -> bool:
	return _ready.has(actor)


func unanimous() -> bool:
	return not _eligible.is_empty() and _ready.size() == _eligible.size()


func snapshot() -> Dictionary:
	var ready: Array[int] = []
	for id in _eligible:
		if _ready.has(id):
			ready.append(id)
	return {"eligible": _eligible.duplicate(), "ready": ready, "revision": revision}


func _reject(reason: String) -> bool:
	last_error = reason
	return false

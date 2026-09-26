extends RefCounted

## Majority choice vote for set selection. Host breaks ties; timeout callers use
## `host_default()` (host's ballot, else the first option).

var revision = 0
var last_error = ""
var host_id = 0
var _eligible: Array[int] = []
var _options: Array[String] = []
var _votes: Dictionary = {}
var _context
var _deadline_msec = 0


func configure(
	ids: Array, options: Array, host: int, context = null, timeout_msec: int = 30000
) -> bool:
	var eligible: Array[int] = []
	for id in ids:
		if not id is int or id <= 0 or eligible.has(id):
			return _reject("The vote needs distinct player IDs.")
		eligible.append(id)
	eligible.sort()
	var cleaned: Array[String] = []
	for option in options:
		if not option is String or option.is_empty() or cleaned.has(option):
			return _reject("Set options must be distinct non-empty ids.")
		cleaned.append(option)
	if cleaned.size() < 2:
		return _reject("Set voting needs at least two options.")
	if host <= 0 or not eligible.has(host):
		return _reject("The table host must be eligible to vote.")
	var same_roster = eligible == _eligible
	var same_options = cleaned == _options
	var same_host = host == host_id
	var same_context = typeof(context) == typeof(_context) and context == _context
	if not (same_roster and same_options and same_host and same_context):
		_eligible = eligible
		_options = cleaned
		host_id = host
		_context = context.duplicate(true) if context is Dictionary or context is Array else context
		_votes.clear()
		revision += 1
		_deadline_msec = Time.get_ticks_msec() + maxi(1000, timeout_msec)
	last_error = ""
	return true


func cast(actor: int, option: String, expected_revision: int = -1) -> bool:
	if not _eligible.has(actor):
		return _reject("Only connected table members can vote.")
	if expected_revision >= 0 and expected_revision != revision:
		return _reject("The vote changed. Please choose again.")
	if not _options.has(option):
		return _reject("That set is not on the ballot.")
	_votes[actor] = option
	last_error = ""
	return true


func clear() -> void:
	_eligible.clear()
	_options.clear()
	_votes.clear()
	_context = null
	host_id = 0
	_deadline_msec = 0
	revision += 1
	last_error = ""


func active() -> bool:
	return not _eligible.is_empty() and not _options.is_empty()


func timed_out() -> bool:
	return active() and _deadline_msec > 0 and Time.get_ticks_msec() >= _deadline_msec


func remaining_msec() -> int:
	if not active():
		return 0
	return maxi(0, _deadline_msec - Time.get_ticks_msec())


func everyone_voted() -> bool:
	return active() and _votes.size() == _eligible.size()


func tally() -> Dictionary:
	var counts: Dictionary = {}
	for option in _options:
		counts[option] = 0
	for choice in _votes.values():
		counts[choice] = int(counts.get(choice, 0)) + 1
	return counts


## Majority wins. Ties break to the host's ballot when present, otherwise the
## earliest option id in ballot order.
func resolve() -> String:
	if not active():
		return ""
	var counts = tally()
	var best = -1
	var winners: Array[String] = []
	for option in _options:
		var count = int(counts.get(option, 0))
		if count > best:
			best = count
			winners = [option]
		elif count == best:
			winners.append(option)
	if winners.is_empty():
		return _options[0]
	if winners.size() == 1:
		return winners[0]
	var host_choice = str(_votes.get(host_id, ""))
	if winners.has(host_choice):
		return host_choice
	return winners[0]


func host_default() -> String:
	if not active():
		return ""
	var host_choice = str(_votes.get(host_id, ""))
	if _options.has(host_choice):
		return host_choice
	return _options[0]


func snapshot() -> Dictionary:
	return {
		"active": active(),
		"eligible": _eligible.duplicate(),
		"options": _options.duplicate(),
		"votes": _votes.duplicate(true),
		"revision": revision,
		"host_id": host_id,
		"deadline_msec": _deadline_msec,
		"remaining_msec": remaining_msec(),
		"tally": tally()
	}


func import_snapshot(data: Dictionary) -> bool:
	var options: Array = data.get("options", [])
	var eligible: Array = data.get("eligible", [])
	if options.size() < 2 or eligible.is_empty():
		return _reject("Invalid set-vote snapshot.")
	if not configure(
		eligible,
		options,
		int(data.get("host_id", 0)),
		{"remote": true, "revision": int(data.get("revision", 0))},
		maxi(1000, int(data.get("remaining_msec", TIMEOUT_DEFAULT)))
	):
		return false
	revision = int(data.get("revision", revision))
	_deadline_msec = int(data.get("deadline_msec", _deadline_msec))
	_votes.clear()
	var votes: Dictionary = data.get("votes", {})
	for actor in votes.keys():
		_votes[int(actor)] = str(votes[actor])
	last_error = ""
	return true


const TIMEOUT_DEFAULT = 30000


func _reject(reason: String) -> bool:
	last_error = reason
	return false

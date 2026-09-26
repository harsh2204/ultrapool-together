extends RefCounted

const CAPACITY = 8
const DEFAULT_SHOT_BUDGET = 6
const TeamVote = preload("team_vote.gd")
const RUN_FIELDS = ["deck", "difficulty", "match_mode"]
const MATCH_MODES = [{"id": "race", "label": "Race"}, {"id": "score", "label": "Score PvP"}]

var host_id = 0
var table_count = 1
var shot_budget = DEFAULT_SHOT_BUDGET
var match_mode = "race"
var revision = 0
var ready_generation = 0
var started = false
var last_error = ""
var _players: Dictionary = {}
var _return_vote = TeamVote.new()
var _return_proposer = 0
var _run_options: Dictionary = {}
var _run_defaults: Dictionary = {}
var _run_catalog_revision = 0
var _frozen_selection: Dictionary = {}


func setup(id: int, player_name: String) -> bool:
	if id <= 0:
		return _reject("A Steam host is required.")
	clear()
	host_id = id
	_players[id] = _player(id, player_name)
	_players[id].table = 0
	_players[id].slot = 0
	_changed()
	return true


func clear() -> void:
	host_id = 0
	table_count = 1
	shot_budget = DEFAULT_SHOT_BUDGET
	match_mode = "race"
	revision = 0
	ready_generation = 0
	started = false
	last_error = ""
	_players.clear()
	_run_options.clear()
	_run_defaults.clear()
	_run_catalog_revision = 0
	_frozen_selection.clear()
	_clear_return_vote()


func add_player(id: int, player_name: String) -> bool:
	if host_id == 0 or id <= 0:
		return _reject("Create a lobby before adding players.")
	if _players.has(id):
		var player: Dictionary = _players[id]
		var display_name = _display_name(player_name)
		if player.connected and player.name == display_name:
			last_error = ""
			return true
		var reconnected: bool = not player.connected
		player.connected = true
		player.name = display_name
		_refresh_return_vote()
		_changed(reconnected and not started)
		return true
	if started:
		return _reject("The match has started. Join the next lobby.")
	if _players.size() >= CAPACITY:
		return _reject("This lobby already has eight players.")
	_players[id] = _player(id, player_name)
	_changed(true)
	return true


func remove_player(id: int) -> bool:
	if not _players.has(id):
		return _reject("That player is not in the lobby.")
	if started:
		if not _players[id].connected:
			last_error = ""
			return true
		_players[id].connected = false
		_refresh_return_vote()
		_changed()
		return true
	_players.erase(id)
	_fit_tables()
	_changed(true)
	return true


func set_table_count(sender: int, count: int) -> bool:
	if not _is_host(sender):
		return _reject("Only the host can change the number of tables.")
	if started:
		return _reject("Table assignments are locked during a match.")
	if count < 1 or count > _players.size():
		return _reject("Choose between one table and one table per player.")
	if table_count == count:
		last_error = ""
		return true
	table_count = count
	_fit_tables()
	_changed(true)
	return true


func choose_slot(sender: int, table: int, slot: int) -> bool:
	if not _players.has(sender) or not _players[sender].connected:
		return _reject("Join the lobby before choosing a seat.")
	if started:
		return _reject("Seats are locked during a match.")
	var unseating = table == -1 and slot == -1
	if not unseating and (table < 0 or table >= table_count or slot < 0 or slot >= CAPACITY):
		return _reject("Choose a seat at one of the configured tables.")
	var player: Dictionary = _players[sender]
	if player.table == table and player.slot == slot:
		last_error = ""
		return true
	if not unseating:
		for other in _players.values():
			if other.table == table and other.slot == slot:
				return _reject("That seat is already taken.")
	player.table = table
	player.slot = slot
	_changed(true)
	return true


func set_shot_budget(sender: int, count: int) -> bool:
	if not _is_host(sender):
		return _reject("Only the host can change the shot budget.")
	if started:
		return _reject("The shot budget is locked during a match.")
	if count < 1 or count > 20:
		return _reject("Choose between one and twenty shots per table.")
	if shot_budget == count:
		last_error = ""
		return true
	shot_budget = count
	_changed(true)
	return true


func set_match_mode(sender: int, mode: String) -> bool:
	if not _is_host(sender):
		return _reject("Only the host can change the match mode.")
	if started:
		return _reject("The match mode is locked during a match.")
	if mode not in ["race", "score"]:
		return _reject("Choose Race or Score PvP.")
	if match_mode == mode:
		last_error = ""
		return true
	match_mode = mode
	_run_defaults.match_mode = mode
	for player in _players.values():
		player.run_votes.erase("match_mode")
	_changed(true)
	return true


func configure_run_options(sender: int, options: Dictionary, defaults: Dictionary = {}) -> bool:
	if not _is_host(sender):
		return _reject("Only the host can publish the available run choices.")
	if started:
		return _reject("Run choices are locked during a match.")
	var checked: Dictionary = {}
	var selected: Dictionary = {}
	for field in ["deck", "difficulty"]:
		var entries = options.get(field)
		if not entries is Array or entries.is_empty() or entries.size() > 64:
			return _reject("The host has no supported starting sets or difficulties available.")
		var ids: Array = []
		checked[field] = []
		for entry in entries:
			if (
				not entry is Dictionary
				or not entry.get("id") is String
				or entry.id.is_empty()
				or entry.id.length() > 128
				or not entry.get("label") is String
				or entry.label.is_empty()
				or entry.label.length() > 160
				or entry.id in ids
			):
				return _reject("The run choices contain an invalid or duplicate entry.")
			ids.append(entry.id)
			checked[field].append({"id": entry.id, "label": entry.label})
		selected[field] = defaults.get(field, ids[0])
		if selected[field] not in ids:
			selected[field] = ids[0]
	checked.match_mode = MATCH_MODES.duplicate(true)
	selected.match_mode = match_mode
	if _run_options == checked and _run_defaults == selected:
		last_error = ""
		return true
	_run_options = checked
	_run_defaults = selected
	_run_catalog_revision += 1
	for player in _players.values():
		player.run_votes.clear()
	_changed(true)
	return true


func set_run_vote(sender: int, field: String, choice: String, catalog_revision: int = -1) -> bool:
	if not _players.has(sender) or not _players[sender].connected:
		return _reject("Join the lobby before voting on the run.")
	if started:
		return _reject("Run votes are locked during a match.")
	if catalog_revision >= 0 and catalog_revision != _run_catalog_revision:
		return _reject("The available run choices changed. Vote again.")
	if field not in RUN_FIELDS or not _run_options.has(field):
		return _reject("Choose a starting set, difficulty, or match mode.")
	if (
		not choice.is_empty()
		and not _run_options[field].any(func(entry): return entry.id == choice)
	):
		return _reject("That run choice is not available in this lobby.")
	var votes: Dictionary = _players[sender].run_votes
	if votes.get(field, "") == choice:
		last_error = ""
		return true
	if choice.is_empty():
		votes.erase(field)
	else:
		votes[field] = choice
	_changed(true)
	return true


func resolved_run_selection() -> Dictionary:
	if started:
		return _frozen_selection.duplicate(true)
	var result: Dictionary = {}
	for field in RUN_FIELDS:
		if not _run_options.has(field):
			continue
		var counts = _run_vote_counts(field)
		var winner: String = _run_defaults.get(field, "")
		var highest = 0
		# Strictly greater preserves the published native-menu order for ties.
		for entry in _run_options[field]:
			var count: int = counts.get(entry.id, 0)
			if count > highest:
				highest = count
				winner = entry.id
		result[field] = winner
	return result


func _run_vote_counts(field: String) -> Dictionary:
	var counts: Dictionary = {}
	for player in _players.values():
		if player.connected:
			var choice: String = player.run_votes.get(field, "")
			if not choice.is_empty():
				counts[choice] = counts.get(choice, 0) + 1
	return counts


func _run_vote_snapshot() -> Dictionary:
	var counts: Dictionary = {}
	for field in RUN_FIELDS:
		counts[field] = _run_vote_counts(field)
	return {
		"catalog_revision": _run_catalog_revision,
		"options": _run_options.duplicate(true),
		"counts": counts,
		"selected": resolved_run_selection()
	}


func set_ready(sender: int, ready: bool, expected_generation: int = -1) -> bool:
	if not _players.has(sender) or not _players[sender].connected:
		return _reject("Join the lobby before readying up.")
	if started:
		return _reject("The match has already started.")
	if expected_generation >= 0 and expected_generation != ready_generation:
		return _reject("The lobby settings changed. Review the choices and ready up again.")
	var player: Dictionary = _players[sender]
	if ready and player.table < 0:
		return _reject("Choose a seat before readying up.")
	if player.ready == ready:
		last_error = ""
		return true
	player.ready = ready
	_changed()
	return true


func can_start() -> bool:
	if started or _players.size() < 2 or not _is_host(host_id) or _run_options.is_empty():
		return false
	var occupied: Dictionary = {}
	for player in _players.values():
		if not player.connected or not player.ready or player.table < 0:
			return false
		occupied[player.table] = true
	return occupied.size() == table_count


func start(sender: int) -> bool:
	if not _is_host(sender):
		return _reject("Only the host can start the match.")
	if not can_start():
		return _reject("Every player must choose a seat and ready up, with someone at each table.")
	_frozen_selection = resolved_run_selection()
	started = true
	_changed()
	return true


func request_return(sender: int) -> bool:
	if not _is_host(sender):
		return _reject("Only the host can propose returning to the lobby.")
	if not started:
		return _reject("There is no active match to end.")
	if _return_proposer != 0:
		last_error = ""
		return true
	_return_proposer = sender
	_refresh_return_vote()
	_changed()
	return true


func set_return_ready(sender: int, ready: bool, expected_revision: int = -1) -> bool:
	if _return_proposer == 0:
		return _reject("There is no return-to-lobby vote.")
	if not _return_vote.set_ready(sender, ready, expected_revision):
		return _reject(_return_vote.last_error)
	if not ready:
		_clear_return_vote()
	_changed()
	return true


func can_return() -> bool:
	return _return_proposer != 0 and _return_vote.unanimous()


func reset_lobby(sender: int, match_complete: bool = false) -> bool:
	if not _is_host(sender):
		return _reject("Only the host can reopen the lobby.")
	if started and not match_complete and not can_return():
		return _reject("Everyone still connected must approve ending the match.")
	started = false
	_frozen_selection.clear()
	_clear_return_vote()
	for id in _players.keys():
		if not _players[id].connected:
			_players.erase(id)
	_fit_tables()
	_changed(true)
	return true


func snapshot() -> Dictionary:
	var players = _players.values().duplicate(true)
	for player in players:
		player["leader"] = player.table >= 0 and leader_for_table(player.table) == player.id
	var return_vote = _return_vote.snapshot()
	return_vote["active"] = _return_proposer != 0
	return_vote["proposer"] = _return_proposer
	return {
		"revision": revision,
		"ready_generation": ready_generation,
		"host_id": host_id,
		"table_count": table_count,
		"shot_budget": shot_budget,
		"match_mode": match_mode,
		"return_vote": return_vote,
		"run_vote": _run_vote_snapshot(),
		"capacity": CAPACITY,
		"started": started,
		"can_start": can_start(),
		"players": players
	}


func members_for_table(table: int) -> Array:
	var members: Array = []
	if table < 0 or table >= table_count:
		return members
	for player in _players.values():
		if player.table == table:
			members.append(player.duplicate(true))
	members.sort_custom(func(a, b): return a.slot < b.slot)
	return members


func leader_for_table(table: int) -> int:
	var members = members_for_table(table)
	return members[0].id if not members.is_empty() else 0


func _player(id: int, player_name: String) -> Dictionary:
	return {
		"id": id,
		"name": _display_name(player_name),
		"table": -1,
		"slot": -1,
		"ready": false,
		"connected": true,
		"run_votes": {}
	}


func _display_name(value: String) -> String:
	var cleaned = value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	return cleaned.substr(0, 80) if cleaned != "" else "Player"


func _is_host(sender: int) -> bool:
	return sender == host_id and _players.has(host_id) and _players[host_id].connected


func _fit_tables() -> void:
	table_count = mini(table_count, maxi(1, _players.size()))
	for player in _players.values():
		if player.table >= table_count:
			player.table = -1
			player.slot = -1


func _refresh_return_vote() -> void:
	if _return_proposer == 0:
		return
	if not _is_host(_return_proposer):
		_clear_return_vote()
		return
	var connected: Array = []
	for player in _players.values():
		if player.connected:
			connected.append(player.id)
	_return_vote.configure(connected, _return_proposer)
	_return_vote.set_ready(_return_proposer, true)


func _clear_return_vote() -> void:
	_return_proposer = 0
	_return_vote.configure([])


func _changed(clear_ready: bool = false) -> void:
	if not _run_options.is_empty():
		match_mode = resolved_run_selection().get("match_mode", "race")
	if clear_ready:
		ready_generation += 1
		for player in _players.values():
			player.ready = false
	revision += 1
	last_error = ""


func _reject(reason: String) -> bool:
	last_error = reason
	return false

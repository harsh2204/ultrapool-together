extends RefCounted

const CAPACITY = 8
const DEFAULT_SHOT_BUDGET = 6
const TeamVote = preload("team_vote.gd")

var host_id = 0
var table_count = 1
var shot_budget = DEFAULT_SHOT_BUDGET
var match_mode = "race"
var revision = 0
var started = false
var last_error = ""
var _players: Dictionary = {}
var _return_vote = TeamVote.new()
var _return_proposer = 0


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
	started = false
	last_error = ""
	_players.clear()
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
	_changed(true)
	return true


func set_ready(sender: int, ready: bool) -> bool:
	if not _players.has(sender) or not _players[sender].connected:
		return _reject("Join the lobby before readying up.")
	if started:
		return _reject("The match has already started.")
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
	if started or _players.size() < 2 or not _is_host(host_id):
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
		"host_id": host_id,
		"table_count": table_count,
		"shot_budget": shot_budget,
		"match_mode": match_mode,
		"return_vote": return_vote,
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
			members.append(player.duplicate())
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
		"connected": true
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
	if clear_ready:
		for player in _players.values():
			player.ready = false
	revision += 1
	last_error = ""


func _reject(reason: String) -> bool:
	last_error = reason
	return false

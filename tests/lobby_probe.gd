extends SceneTree

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var model_script = load(
		get_script().resource_path.get_base_dir().path_join("../mod/lobby_state.gd")
	)
	var lobby = model_script.new()
	_check(not lobby.setup(0, "Host"), "invalid host rejected")
	_check(lobby.setup(10, "Host"), "host creates lobby")
	_check(
		_find(lobby, 10).table == 0 and _find(lobby, 10).slot == 0, "host starts in the first seat"
	)
	_check(
		lobby.set_ready(10, true) and not lobby.can_start(), "host alone cannot start multiplayer"
	)
	_check(lobby.add_player(20, "Partner"), "partner joins")
	_check(
		_find(lobby, 20).table == -1 and not _find(lobby, 20).ready,
		"joining player chooses their own seat"
	)
	_check(not _find(lobby, 10).ready, "joining invalidates earlier readiness")
	_check(not lobby.set_ready(20, true), "unseated player cannot ready")
	_check(not lobby.choose_slot(20, 0, 0), "occupied seat cannot be stolen")
	_check(not lobby.choose_slot(999, 0, 1), "unknown sender cannot choose a seat")
	_check(not lobby.set_table_count(20, 2), "guest cannot change table count")
	_check(not lobby.set_table_count(10, 3), "table count cannot exceed player count")
	_check(not lobby.choose_slot(20, 0, 8), "seat count is bounded")
	_check(lobby.choose_slot(20, 0, 1), "partner chooses a co-op seat")
	_ready_all(lobby)
	_check(lobby.can_start(), "ready co-op lobby can start")
	_check(not lobby.set_shot_budget(20, 3), "guest cannot change shot budget")
	_check(not lobby.set_shot_budget(10, 0), "zero shot budget rejected")
	_check(not lobby.set_shot_budget(10, 21), "excess shot budget rejected")
	_check(lobby.set_shot_budget(10, 7), "host changes shared table budget")
	_check(not lobby.can_start(), "budget change invalidates readiness")
	_check(lobby.set_shot_budget(10, 6), "host restores default shot budget")
	_ready_all(lobby)
	var revision: int = lobby.revision
	_check(lobby.choose_slot(20, 0, 1), "repeated selection is accepted")
	_check(
		lobby.revision == revision and lobby.can_start(), "repeated selection preserves readiness"
	)
	_check(not lobby.start(20), "guest cannot start match")
	_check(lobby.set_table_count(10, 2), "host enables two tables")
	_ready_all(lobby)
	_check(not lobby.can_start(), "empty configured table prevents start")
	_check(lobby.choose_slot(20, 1, 0), "partner chooses the other table")
	_check(not _find(lobby, 10).ready, "seat change clears all readiness")
	_ready_all(lobby)
	var copied = lobby.snapshot()
	copied.players[0].ready = false
	_check(lobby.can_start(), "snapshot cannot mutate lobby state")
	_check(lobby.start(10), "host starts fully ready lobby")
	_check(not lobby.choose_slot(20, 0, 1), "started match locks seating")
	_check(not lobby.set_table_count(10, 1), "started match locks tables")
	_check(not lobby.set_shot_budget(10, 4), "started match locks shot budget")
	_check(not lobby.set_ready(20, false), "started match locks ready state")
	_check(not lobby.add_player(30, "Late player"), "started match rejects new players")
	_check(lobby.remove_player(20), "match records a disconnected player")
	_check(
		not _find(lobby, 20).connected and _find(lobby, 20).table == 1,
		"disconnection preserves match seat"
	)
	_check(lobby.leader_for_table(1) == 20, "disconnected table leader stays authoritative")
	_check(lobby.add_player(20, "Partner"), "same player can reconnect")
	_check(
		_find(lobby, 20).connected and _find(lobby, 20).table == 1,
		"reconnection restores the existing seat"
	)
	_check(not lobby.reset_lobby(20), "guest cannot reset lobby")
	lobby.remove_player(20)
	_check(lobby.reset_lobby(10), "host reopens lobby")
	_check(
		lobby.snapshot().players.size() == 1 and lobby.table_count == 1,
		"reset prunes disconnected players and extra tables"
	)
	_check(not _find(lobby, 10).ready and not lobby.started, "reset requires fresh readiness")
	for id in range(20, 90, 10):
		_check(lobby.add_player(id, "Player %d" % id), "player fits within eight-person lobby")
	_check(not lobby.add_player(90, "Ninth"), "ninth player is rejected")
	_check(lobby.set_table_count(10, 4), "host configures four tables")
	var assignments = [
		[20, 1, 0], [30, 2, 0], [40, 3, 0], [50, 3, 1], [60, 3, 2], [70, 3, 3], [80, 3, 4]
	]
	for seat in assignments:
		_check(lobby.choose_slot(seat[0], seat[1], seat[2]), "unequal table groups are accepted")
	_ready_all(lobby)
	_check(lobby.can_start(), "one-versus-one-versus-one-versus-five is valid")
	_check(lobby.leader_for_table(3) == 40, "first occupied table seat leads")
	_check(
		lobby.members_for_table(3).map(func(player): return player.id) == [40, 50, 60, 70, 80],
		"table members are ordered by seat"
	)
	_check(
		_find(lobby, 40).leader and not _find(lobby, 50).leader, "snapshot badges the table leader"
	)
	_check(lobby.snapshot().shot_budget == 6, "table budget is independent of team size")
	_check(lobby.choose_slot(80, -1, -1), "player can leave their seat")
	_check(
		not lobby.set_ready(80, true) and not lobby.can_start(), "unseated player prevents start"
	)
	_check(not lobby.choose_slot(80, -1, 0), "partial unassigned seat is rejected")
	_check(lobby.remove_player(80), "pre-match departure removes player")
	_check(_find(lobby, 80).is_empty(), "departed player no longer occupies the lobby")
	_check(lobby.set_table_count(10, 2), "host reduces table count")
	_check(
		_find(lobby, 30).table == -1 and _find(lobby, 40).table == -1,
		"removed tables return players to unassigned"
	)
	lobby.clear()
	_check(
		lobby.snapshot().players.is_empty() and lobby.host_id == 0,
		"clear removes the entire session"
	)
	var uneven = model_script.new()
	uneven.setup(10, "Host")
	for id in [20, 30, 40, 50]:
		uneven.add_player(id, "Player %d" % id)
	uneven.set_table_count(10, 4)
	for seat in [[20, 1, 0], [30, 2, 0], [40, 3, 0], [50, 3, 1]]:
		uneven.choose_slot(seat[0], seat[1], seat[2])
	_ready_all(uneven)
	_check(uneven.can_start(), "one-versus-one-versus-one-versus-two can start")
	var before_attack = uneven.snapshot()
	_check(not uneven.choose_slot(999, 3, 2), "unregistered sender cannot claim a free seat")
	_check(not uneven.set_ready(999, true), "unregistered sender cannot ready another player")
	_check(not uneven.set_table_count(20, 1), "table member cannot impersonate host settings")
	_check(not uneven.set_shot_budget(20, 20), "table member cannot increase its budget")
	_check(uneven.snapshot() == before_attack, "rejected requests preserve the full ready roster")
	uneven.start(10)
	uneven.remove_player(40)
	_check(
		uneven.leader_for_table(3) == 40,
		"remaining teammate cannot take over a disconnected leader"
	)
	_check(
		uneven.members_for_table(3).size() == 2, "active roster preserves departed shooter identity"
	)
	uneven.reset_lobby(10)
	_check(
		uneven.leader_for_table(3) == 50, "reopened lobby can choose its next occupied-seat leader"
	)
	_check(uneven.add_player(40, "Returning player"), "departed player can join the reopened lobby")
	_check(
		_find(uneven, 40).table == -1 and not _find(uneven, 40).ready,
		"rejoin after reset requires a new seat and readiness"
	)
	uneven.choose_slot(40, 3, 0)
	_ready_all(uneven)
	_check(
		uneven.leader_for_table(3) == 40 and uneven.can_start(),
		"reconfigured lobby can approve a new leader"
	)
	var members = uneven.members_for_table(3)
	members[0].connected = false
	_check(_find(uneven, 40).connected, "membership helper cannot mutate the authoritative roster")
	print("LOBBY_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _find(lobby, id: int) -> Dictionary:
	for player in lobby.snapshot().players:
		if player.id == id:
			return player
	return {}


func _ready_all(lobby) -> void:
	for player in lobby.snapshot().players:
		lobby.set_ready(player.id, true)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

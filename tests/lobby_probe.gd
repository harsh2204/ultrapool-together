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
	_configure(lobby)
	_check(lobby.snapshot().match_mode == "race", "new lobbies default to a full-run race")
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
	_check(not lobby.set_match_mode(20, "score"), "guest cannot change match mode")
	_check(not lobby.set_match_mode(10, "coop"), "unknown match modes are rejected")
	_check(lobby.set_match_mode(10, "score"), "host can choose Score PvP")
	_check(not lobby.can_start(), "mode change invalidates readiness")
	_check(lobby.set_match_mode(10, "race"), "host can choose Race")
	_ready_all(lobby)
	var ready_revision: int = lobby.revision
	_check(lobby.set_match_mode(10, "race"), "repeating the same mode is accepted")
	_check(lobby.revision == ready_revision and lobby.can_start(), "same mode preserves readiness")
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
	_check(not lobby.set_match_mode(10, "score"), "started match locks mode")
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
	_check(not lobby.reset_lobby(10), "unfinished match cannot be reset without consent")
	_check(
		lobby.request_return(10) and lobby.can_return(), "only connected players need to approve"
	)
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
	_configure(uneven)
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
	uneven.request_return(10)
	for id in [20, 30, 50]:
		uneven.set_return_ready(id, true)
	_check(uneven.reset_lobby(10), "all remaining players approve returning to the lobby")
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
	_check_return_votes(model_script)
	_check_run_votes(model_script)
	print("LOBBY_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check_return_votes(model_script) -> void:
	var lobby = model_script.new()
	lobby.setup(10, "Host")
	_configure(lobby)
	for id in [20, 30]:
		lobby.add_player(id, "Player %d" % id)
		lobby.choose_slot(id, 0, id / 10 - 1)
	_ready_all(lobby)
	lobby.start(10)
	_check(not lobby.request_return(20), "guest cannot propose ending the match")
	_check(not lobby.set_return_ready(20, true), "approval requires a pending proposal")
	_check(lobby.request_return(10), "host proposes returning to the lobby")
	var vote: Dictionary = lobby.snapshot().return_vote
	_check(vote.active and vote.ready == [10], "proposal starts with the host's approval")
	_check(not lobby.can_return(), "host cannot end a three-player run alone")
	_check(not lobby.set_return_ready(999, true), "unknown actor cannot approve ending the run")
	_check(
		not lobby.set_return_ready(20, true, vote.revision - 1),
		"stale consent cannot approve a new vote"
	)
	_check(lobby.set_return_ready(20, true, vote.revision), "teammate can approve the current vote")
	_check(not lobby.reset_lobby(10), "partial approval cannot end the run")
	_check(lobby.request_return(10), "repeated host proposal is accepted")
	_check(lobby.snapshot().return_vote.ready == [10, 20], "repeated proposal preserves consent")
	_check(lobby.set_return_ready(30, false), "a teammate can cancel the proposal")
	_check(
		not lobby.snapshot().return_vote.active and not lobby.can_return(),
		"cancel removes all consent"
	)
	lobby.request_return(10)
	lobby.set_return_ready(20, true)
	var old_revision: int = lobby.snapshot().return_vote.revision
	lobby.remove_player(30)
	vote = lobby.snapshot().return_vote
	_check(
		vote.eligible == [10, 20] and vote.ready == [10],
		"roster change requires fresh teammate approval"
	)
	_check(not lobby.set_return_ready(20, true, old_revision), "old roster approval is rejected")
	lobby.set_return_ready(20, true)
	_check(lobby.can_return(), "remaining connected players can unanimously approve")
	lobby.add_player(30, "Player 30")
	_check(not lobby.can_return(), "reconnection cannot inherit previous consent")
	lobby.set_return_ready(20, true)
	lobby.set_return_ready(30, true)
	_check(lobby.can_return(), "all reconnected players can approve")
	var copied: Dictionary = lobby.snapshot().return_vote
	copied.ready.clear()
	_check(lobby.can_return(), "vote snapshots cannot mutate consent")
	_check(not lobby.reset_lobby(20), "unanimous approval still requires host execution")
	_check(lobby.reset_lobby(10), "unanimous approval permits host reset")
	_check(not lobby.snapshot().return_vote.active, "reset discards the finished vote")
	_ready_all(lobby)
	lobby.start(10)
	_check(lobby.reset_lobby(10, true), "completed matches return without an end-run vote")
	_check(not lobby.request_return(10), "pre-match lobby rejects end-run proposals")


func _configure(lobby) -> void:
	lobby.configure_run_options(
		10,
		{
			"deck":
			[{"id": "1_CLASSIC", "label": "Classic"}, {"id": "2_NATURE", "label": "Nature"}],
			"difficulty":
			[{"id": "diff_1", "label": "Chill Pool Night"}, {"id": "diff_2", "label": "Wine Mixer"}]
		},
		{"deck": "2_NATURE", "difficulty": "diff_2"}
	)


func _check_run_votes(model_script) -> void:
	var lobby = model_script.new()
	lobby.setup(10, "Host")
	lobby.add_player(20, "Partner")
	lobby.choose_slot(20, 0, 1)
	_ready_all(lobby)
	_check(not lobby.can_start(), "available run choices are required before starting")
	_configure(lobby)
	_check(not _find(lobby, 10).ready, "publishing run choices clears readiness")
	var catalog: int = lobby.snapshot().run_vote.catalog_revision
	_check(
		(
			lobby.resolved_run_selection().deck == "2_NATURE"
			and lobby.resolved_run_selection().difficulty == "diff_2"
		),
		"no votes preserves the initial native selection"
	)
	var options: Dictionary = lobby.snapshot().run_vote.options
	_check(not lobby.configure_run_options(20, options), "guest cannot publish its own unlocks")
	var malformed: Dictionary = options.duplicate(true)
	malformed.deck.append(malformed.deck[0])
	_check(not lobby.configure_run_options(10, malformed), "duplicate catalog IDs are rejected")
	malformed.deck = []
	_check(not lobby.configure_run_options(10, malformed), "empty starting sets are rejected")
	var before = lobby.snapshot()
	_check(not lobby.set_run_vote(999, "deck", "1_CLASSIC", catalog), "unknown actor cannot vote")
	_check(
		not lobby.set_run_vote(20, "seed", "1", catalog), "voters cannot choose arbitrary fields"
	)
	_check(
		not lobby.set_run_vote(20, "deck", "DAILY", catalog), "unpublished run choice is rejected"
	)
	_check(
		not lobby.set_run_vote(20, "difficulty", "diff_6", catalog),
		"locked difficulty cannot be voted"
	)
	_check(
		not lobby.set_run_vote(20, "deck", "1_CLASSIC", catalog - 1),
		"stale catalog vote is rejected"
	)
	_check(lobby.snapshot() == before, "invalid ballots preserve settings and readiness")
	_ready_all(lobby)
	var old_generation: int = lobby.snapshot().ready_generation
	_check(lobby.set_run_vote(20, "deck", "1_CLASSIC", catalog), "guest votes for starting set")
	_check(lobby.resolved_run_selection().deck == "1_CLASSIC", "guest vote resolves on host")
	_check(
		not _find(lobby, 10).ready and not _find(lobby, 20).ready,
		"ballot clears everyone's readiness"
	)
	_check(
		not lobby.set_ready(20, true, old_generation),
		"delayed ready cannot approve a changed ballot"
	)
	var generation: int = lobby.snapshot().ready_generation
	_check(lobby.set_ready(10, true, generation), "host readies for the current choices")
	_check(
		lobby.set_ready(20, true, generation),
		"concurrent ready accepts the same settings generation"
	)
	_check(
		lobby.snapshot().ready_generation == generation,
		"readiness alone does not invalidate others"
	)
	var previous: int = lobby.revision
	_check(lobby.set_run_vote(20, "deck", "1_CLASSIC", catalog), "duplicate ballot is accepted")
	_check(
		lobby.revision == previous and lobby.can_start(), "duplicate ballot cannot reset readiness"
	)
	_check(lobby.set_run_vote(10, "deck", "2_NATURE", catalog), "host has one equal vote")
	_check(lobby.resolved_run_selection().deck == "1_CLASSIC", "tie follows native menu order")
	_check(lobby.set_run_vote(20, "deck", "2_NATURE", catalog), "player can replace a ballot")
	_check(
		lobby.snapshot().run_vote.counts.deck == {"2_NATURE": 2},
		"replacement is one vote per player"
	)
	_check(
		lobby.set_run_vote(20, "difficulty", "diff_1", catalog), "difficulty has a separate ballot"
	)
	_check(lobby.set_run_vote(20, "match_mode", "score", catalog), "guest can vote Score PvP")
	_check(lobby.match_mode == "score", "resolved mode controls the match")
	_check(lobby.set_run_vote(10, "match_mode", "race", catalog), "host can vote Race")
	_check(lobby.match_mode == "race", "mode tie follows the same published rule")
	_check(lobby.set_run_vote(20, "deck", "", catalog), "no preference removes a ballot")
	_check(lobby.snapshot().run_vote.counts.deck == {"2_NATURE": 1}, "abstention removes its count")
	var copied = lobby.snapshot()
	copied.players[0].run_votes.clear()
	copied.run_vote.options.deck.clear()
	copied.run_vote.selected.deck = "DAILY"
	_check(
		lobby.snapshot().run_vote.counts.deck == {"2_NATURE": 1}, "snapshot cannot mutate ballots"
	)
	_check(lobby.snapshot().run_vote.options.deck.size() == 2, "snapshot cannot mutate choices")
	var members = lobby.members_for_table(0)
	members[0].run_votes.clear()
	_check(
		lobby.snapshot().run_vote.counts.deck == {"2_NATURE": 1},
		"membership snapshots isolate ballots"
	)
	_ready_all(lobby)
	var resolved: Dictionary = lobby.resolved_run_selection()
	_check(lobby.start(10), "fully ready voted match starts")
	_check(not lobby.set_run_vote(20, "deck", "1_CLASSIC", catalog), "started match locks ballots")
	_check(not lobby.configure_run_options(10, options), "started match locks catalog")
	lobby.remove_player(20)
	_check(lobby.resolved_run_selection() == resolved, "disconnect cannot change the frozen run")
	_check(lobby.match_mode == resolved.match_mode, "disconnect cannot change frozen mode")
	var frozen = lobby.resolved_run_selection()
	frozen.deck = "DAILY"
	_check(lobby.resolved_run_selection() == resolved, "callers cannot mutate frozen configuration")
	lobby.reset_lobby(10, true)
	_check(
		lobby.resolved_run_selection().difficulty == "diff_2",
		"departed voters do not vote in next lobby"
	)
	lobby.add_player(20, "Partner")
	_check(_find(lobby, 20).run_votes.is_empty(), "rejoined player does not inherit an old ballot")
	lobby.choose_slot(20, 0, 1)
	lobby.set_run_vote(20, "deck", "1_CLASSIC", catalog)
	lobby.remove_player(20)
	_check(
		lobby.resolved_run_selection().deck == "2_NATURE",
		"pre-match departures remove their ballots"
	)
	var replacement = {
		"deck": [{"id": "1_CLASSIC", "label": "Classic"}],
		"difficulty": [{"id": "diff_1", "label": "Chill Pool Night"}]
	}
	_check(lobby.configure_run_options(10, replacement), "host can refresh a changed catalog")
	_check(
		lobby.snapshot().run_vote.catalog_revision > catalog, "changed catalog advances generation"
	)
	_check(
		not lobby.set_run_vote(10, "deck", "1_CLASSIC", catalog),
		"old generation cannot vote after refresh"
	)
	_check(lobby.snapshot().run_vote.counts.deck.is_empty(), "new catalog requires fresh ballots")


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

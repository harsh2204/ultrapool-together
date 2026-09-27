extends SceneTree

const RunCheckpoint = preload("../mod/run_checkpoint.gd")
const TableRecovery = preload("../mod/table_recovery.gd")

var checks = 0
var failures: Array[String] = []
var _database: Node


func _initialize() -> void:
	_database = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("BallDatabase")
	if _database == null:
		_check(false, "recovery probe runs with the native catalogs")
		_finish()
		return
	_check_checkpoint_roundtrip()
	_check_checkpoint_validation()
	_check_storage_order()
	_check_leader_capture_gate()
	_check_successors_and_timers()
	_check_resume_rules()
	_check_rejoin_memory()
	_finish()


func _finish() -> void:
	print("RECOVERY_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _run_state() -> RunState:
	var state = RunState.new()
	state.money = 37
	state.hp = 3
	state.seed = 24681
	state.seed_text = "24681"
	state.rounds_played = 4
	state.level_number = 4
	state.chosen_deck_id = str(_database.id_to_deck.keys()[0])
	state.chosen_difficulty_id = str(_database.id_to_difficulty.keys()[0])
	state.chosen_sets = [_database.id_to_set.keys()[0]]
	state.snack_tickets = 1
	state.is_run_seeded = true
	state.game_time = 81.5
	state.run_id = "00000000-0000-4000-8000-000000000000"
	var build: Array[BallItem] = []
	var ordinary: Array = _database.id_to_ball.keys().filter(
		func(id): return str(id) != "PLAYER" and _database.id_to_ball[id].from_set != &"NEGATIVE"
	)
	for id in ordinary.slice(0, 3):
		var item = BallItem.new()
		item.data = _database.id_to_ball[id]
		item.level = 2
		build.append(item)
	build.append(null)
	state.current_build = build
	var passives: Array[BallItem] = [null, null, null, null]
	passives[1] = BallItem.new()
	passives[1].data = _database.id_to_passive.values()[0]
	state.current_passives = passives
	var offers: Array[BallItem] = [build[0].duplicate(true), null]
	state.shop_balls = offers
	var bar: Array[BallItem] = [null, null, null]
	state.cocktail_bar_items = bar
	return state


func _check_checkpoint_roundtrip() -> void:
	var data = RunCheckpoint.capture(_run_state())
	_check(RunCheckpoint.valid(data, _database), "captured native run state validates")
	var wire: Dictionary = bytes_to_var(var_to_bytes(data))
	_check(RunCheckpoint.valid(wire, _database), "checkpoint survives var_to_bytes encoding")
	var rebuilt = RunCheckpoint.to_run_state(wire, _database)
	_check(RunCheckpoint.capture(rebuilt) == data, "rebuilt run state captures identically")
	_check(
		rebuilt.current_passives[1].data == _database.id_to_passive.values()[0],
		"snacks rebuild from the passive catalog"
	)
	_check(rebuilt.current_build[3] == null, "empty build slots stay empty")
	var hatted = _run_state()
	hatted.current_build[0].hat = HatResource.new()
	_check(
		RunCheckpoint.capture(hatted).is_empty(), "items with uncatalogued hats are not captured"
	)
	var daily = _run_state()
	daily.chosen_deck_id = "DAILY"
	_check(RunCheckpoint.capture(daily).is_empty(), "daily runs are never checkpointed")


func _check_checkpoint_validation() -> void:
	var valid: Dictionary = RunCheckpoint.capture(_run_state())
	var cases = {
		"missing field": func(data): data.erase("money"),
		"float money": func(data): data.money = 3.5,
		"money out of range": func(data): data.money = 1000000000001,
		"negative health": func(data): data.hp = -1,
		"daily deck": func(data): data.chosen_deck_id = "DAILY",
		"unknown difficulty": func(data): data.chosen_difficulty_id = "NOT_A_DIFFICULTY",
		"unknown set": func(data): data.chosen_sets = ["NOT_A_SET"],
		"too many sets": func(data): data.chosen_sets.resize(33),
		"infinite game time": func(data): data.game_time = INF,
		"integer game time": func(data): data.game_time = 4,
		"oversized run id": func(data): data.run_id = "x".repeat(65),
		"unknown ball": func(data): data.current_build[0].data = "NOT_A_BALL",
		"ball in snack slot": func(data): data.current_passives[1] = data.current_build[0],
		"too many offers": func(data): data.shop_balls.resize(17),
		"resource path": func(data): data.current_build[0].data = "res://mod/main.gd",
		"invalid item level": func(data): data.current_build[0].level = 0,
		"non-negative cube": func(data): data.current_cubes = [data.current_build[0]],
		"array instead of dictionary": func(data): data.current_build[0] = [1],
	}
	for label in cases:
		var data: Dictionary = valid.duplicate(true)
		cases[label].call(data)
		_check(not RunCheckpoint.valid(data, _database), "checkpoint rejects " + label)
	_check(not RunCheckpoint.valid("checkpoint", _database), "checkpoint must be a dictionary")


func _recovery() -> Node:
	var recovery = TableRecovery.new()
	recovery.database = _database
	recovery.rejoin_path = "user://recovery_probe_rejoin.cfg"
	return recovery


func _payload(revision: int) -> Dictionary:
	return {"kind": "checkpoint", "revision": revision, "run": RunCheckpoint.capture(_run_state())}


func _check_storage_order() -> void:
	var recovery = _recovery()
	_check(recovery.store(1, 1, _payload(2)), "first checkpoint is stored")
	_check(not recovery.store(1, 1, _payload(2)), "duplicate revision is ignored")
	_check(not recovery.store(1, 1, _payload(1)), "older revision is ignored")
	_check(recovery.store(1, 2, _payload(1)), "new leader epoch restarts revisions")
	_check(not recovery.store(1, 1, _payload(9)), "replaced leader's checkpoint is ignored")
	_check(not recovery.store(1, 0, _payload(10)), "checkpoint requires an epoch")
	var invalid = _payload(11)
	invalid.run.money = "lots"
	_check(not recovery.store(1, 2, invalid), "invalid run data is rejected")
	_check(recovery.store(0, 1, _payload(1)), "tables keep independent checkpoints")
	var copy: Dictionary = recovery.checkpoint(1)
	copy.money = 0
	_check(recovery.checkpoint(1).money == 37, "checkpoint reads cannot mutate stored data")
	_check(recovery.checkpoint(5).is_empty(), "missing table has no checkpoint")
	recovery.clear()
	_check(recovery.checkpoint(1).is_empty(), "clear discards every checkpoint")
	recovery.free()


func _check_leader_capture_gate() -> void:
	var recovery = _recovery()
	var reads = [0]
	var source = func():
		reads[0] += 1
		return _run_state()
	var shop = {"open": true, "busy": false, "revision": 3}
	_check(
		recovery.leader_checkpoint({"open": false}, 5000, source).is_empty(),
		"closed shop does not checkpoint"
	)
	_check(
		(
			recovery
			. leader_checkpoint({"open": true, "busy": true, "revision": 3}, 5000, source)
			. is_empty()
		),
		"busy shop does not checkpoint"
	)
	_check(reads[0] == 0, "gated checkpoints never read native run state")
	var first = recovery.leader_checkpoint(shop, 5000, source)
	_check(first.get("revision") == 1 and not first.run.is_empty(), "settled shop checkpoints")
	_check(
		recovery.leader_checkpoint(shop, 9000, source).is_empty(), "unchanged shop is not resent"
	)
	shop.revision = 4
	_check(
		recovery.leader_checkpoint(shop, 5500, source).is_empty(),
		"checkpoints are limited to one per second"
	)
	_check(
		recovery.leader_checkpoint(shop, 6100, source).is_empty(),
		"identical run data after a shop change is not resent"
	)
	_check(reads[0] == 2, "native run state is read only for eligible changes")
	recovery.reset_leader()
	_check(
		recovery.leader_checkpoint(shop, 6200, source).get("revision") == 1,
		"reconnection republishes the current checkpoint"
	)
	recovery.free()


func _check_successors_and_timers() -> void:
	var lobby = {
		"players":
		[
			{"id": 10, "table": 0, "slot": 0, "connected": true},
			{"id": 20, "table": 1, "slot": 0, "connected": false},
			{"id": 30, "table": 1, "slot": 1, "connected": false},
			{"id": 40, "table": 1, "slot": 2, "connected": true},
			{"id": 50, "table": 2, "slot": 3, "connected": false}
		]
	}
	_check(TableRecovery.successor_for(lobby, 1, 20) == 40, "successor skips disconnected seats")
	_check(TableRecovery.successor_for(lobby, 1, 40) == 0, "no one else is connected to take over")
	lobby.players[1].connected = true
	_check(TableRecovery.successor_for(lobby, 1, 40) == 20, "successor wraps around seat order")
	_check(TableRecovery.successor_for(lobby, 2, 50) == 0, "solo table has no successor")
	var recovery = _recovery()
	lobby.players[1].connected = false
	recovery.leader_left(1, 20, 1000)
	recovery.leader_left(1, 20, 9000)
	_check(recovery.takeover_in_ms(1, 5000) == 11000, "repeated departure keeps the first deadline")
	_check(recovery.due_takeovers(lobby, 15999).is_empty(), "grace period delays takeover")
	_check(
		recovery.due_takeovers(lobby, 16000) == [{"table": 1, "successor": 40}],
		"expired grace hands the table to the next connected seat"
	)
	recovery.leader_left(2, 50, 0)
	_check(recovery.due_takeovers(lobby, 99999).size() == 1, "solo table waits for its player")
	_check(recovery.is_waiting(2) and recovery.lost_leader(2) == 50, "solo table stays paused")
	recovery.leader_returned(1)
	_check(not recovery.is_waiting(1) and recovery.takeover_in_ms(1, 0) == -1, "return cancels")
	recovery.free()


func _check_resume_rules() -> void:
	var recovery = _recovery()
	recovery.store(1, 1, _payload(1))
	var summary = {"score": 42.0, "shots_used": 3, "pending": true}
	var score = recovery.resume_for(1, summary, true)
	_check(score.used_shots == 4, "Score PvP counts the interrupted shot as spent")
	_check(score.total_score == 42.0, "Score PvP keeps banked points")
	_check(score.checkpoint.money == 37, "resume carries the latest checkpoint")
	_check(recovery.resume_for(1, summary, false).used_shots == 3, "other modes rewind the shot")
	_check(TableRecovery.valid_resume(score), "resume data validates")
	var empty = recovery.resume_for(3, {}, true)
	_check(
		empty.checkpoint.is_empty() and TableRecovery.valid_resume(empty),
		"table without a shop yet resumes from its first round"
	)
	for broken in [
		{},
		{"checkpoint": {}, "total_score": -1.0, "used_shots": 0},
		{"checkpoint": {}, "total_score": NAN, "used_shots": 0},
		{"checkpoint": [], "total_score": 0.0, "used_shots": 0},
		{"checkpoint": {}, "total_score": 0.0, "used_shots": -2}
	]:
		_check(not TableRecovery.valid_resume(broken), "malformed resume rejected %s" % [broken])
	recovery.free()


func _check_rejoin_memory() -> void:
	var recovery = _recovery()
	recovery.forget()
	recovery.setup(_database)
	_check(recovery.remembered_room().is_empty(), "no match is remembered by default")
	recovery.remember("UP9-12345")
	var reloaded = _recovery()
	reloaded.setup(_database)
	_check(reloaded.remembered_room() == "UP9-12345", "rejoin code survives a restart")
	recovery.remember("x".repeat(64))
	_check(recovery.remembered_room() == "UP9-12345", "oversized room codes are not stored")
	reloaded.forget()
	var cleared = _recovery()
	cleared.setup(_database)
	_check(cleared.remembered_room().is_empty(), "forgotten match is not offered again")
	for node in [recovery, reloaded, cleared]:
		node.free()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

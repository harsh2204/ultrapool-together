extends SceneTree


class TransportStub:
	extends Node
	var is_host = false
	var id = 20
	var coordinator = 10
	var room_code = "UP7-test"
	var sent: Array = []

	func local_id() -> int:
		return id

	func host_id() -> int:
		return coordinator

	func session_open() -> bool:
		return id != 0

	func invite_ready() -> bool:
		return false

	func participants() -> Array:
		return [
			{"id": 10, "name": "Room host"},
			{"id": 20, "name": "Table host"},
			{"id": 30, "name": "Teammate"}
		]

	func send(message: Dictionary):
		send_to(0, message)

	func send_to(recipient: int, message: Dictionary, unreliable = false):
		sent.append(
			{"recipient": recipient, "message": message.duplicate(true), "unreliable": unreliable}
		)

	func close():
		id = 0


class AdapterStub:
	extends Node
	var ended = 0
	var ready_to_shoot = false
	var state = {
		"available": false,
		"table_active": false,
		"can_shoot": false,
		"in_shop": false,
		"game_over": false,
		"run_won": false,
		"run_goal_rounds": 20,
		"round_finalized": false,
		"round": 0,
		"shots_left": 0,
		"score": 0.0
	}

	func game_data() -> Dictionary:
		return state.duplicate(true)

	func can_shoot() -> bool:
		return ready_to_shoot

	func shoot(_vector: Vector2, accepted: Callable = Callable()) -> bool:
		return ready_to_shoot and (not accepted.is_valid() or accepted.call())

	func score() -> float:
		return state.score

	func shot_score() -> float:
		return state.score

	func is_settled() -> bool:
		return false

	func end_session():
		ended += 1


class TableStub:
	extends Node
	var ended = 0
	var shots: Array[Vector2] = []

	func capture() -> Dictionary:
		return {"available": false}

	func end_guest():
		ended += 1

	func _valid_snapshot(data: Dictionary) -> bool:
		return data.get("available") is bool

	func apply_snapshot(data: Dictionary) -> bool:
		return _valid_snapshot(data)

	func begin_shot(vector: Vector2) -> bool:
		shots.append(vector)
		return true


class SpectatorStub:
	extends Node
	var watched_table = -1
	var states: Array = []
	var snapshots: Array = []

	func is_watching() -> bool:
		return watched_table >= 0

	func close():
		watched_table = -1

	func apply_state(table: int, state: Dictionary):
		states.append({"table": table, "state": state.duplicate(true)})

	func apply_snapshot(table: int, scene: Dictionary):
		snapshots.append({"table": table, "scene": scene.duplicate(true)})


class ShopStub:
	extends Node
	var ended = 0
	var state = {"open": false, "revision": 1}

	func capture() -> Dictionary:
		return state.duplicate(true)

	func is_open() -> bool:
		return state.open

	func end_session():
		ended += 1

	func apply_state(data: Dictionary) -> bool:
		state = data.duplicate(true)
		return true


class PresenceStub:
	extends Node
	var cleared = 0

	func clear():
		cleared += 1

	func receive(_sender: int, _message: Dictionary) -> bool:
		return false

	func tick(_delta: float, _active: bool, _can_aim: bool):
		pass


class MultiplayerBallsStub:
	extends Node
	var ended = 0
	var begin_calls = 0
	var rules: RefCounted

	func blocks_shot_input() -> bool:
		return false

	func end_session():
		ended += 1

	func prepare_shop():
		pass

	func begin_shot(index: int, actor: int) -> bool:
		begin_calls += 1
		return rules.begin_shot(index, actor, true, 2)

	func finish_shot():
		rules.finish_shot([])

	func capture() -> Dictionary:
		return {
			"last_shooter": rules.last_shooter,
			"pending": rules.pending,
			"bounty_shot": rules.bounty_shot,
			"call": rules.call_state.duplicate(),
			"balls": [],
			"pockets": []
		}

	func bounty_shot() -> int:
		return rules.bounty_shot

	func valid_state(data) -> bool:
		return rules.valid_state(data)


class RunStub:
	extends Node
	var validations = 0
	var starts = 0
	var cancelled = 0

	func at_main_menu() -> bool:
		return false

	func validate_config(_config: Dictionary) -> bool:
		validations += 1
		return true

	func ready_for_input() -> bool:
		return true

	func start(_config: Dictionary) -> Error:
		starts += 1
		return OK

	func cancel():
		cancelled += 1


class PanelStub:
	extends Control
	var status_text = ""

	func set_status(value: String):
		status_text = value

	func set_connection(_code: String, _open: bool, _invite: bool):
		pass

	func render(_lobby: Dictionary, _local_id: int, _host: bool):
		pass


var checks = 0
var failures: Array[String] = []
var _base: String


func _initialize() -> void:
	_base = get_script().resource_path.get_base_dir().get_base_dir().path_join("mod")
	_closed_transport_teardown()
	_abandoned_leader_rejoin()
	_run_closes_during_shot()
	_targeted_shop_sync()
	_rejected_shots_preserve_ability_state()
	_first_shot_phase_order()
	_race_and_score_limits()
	_race_finishes()
	_return_vote_lifecycle()
	_host_leave_requires_consent()
	_startup_failure_scope()
	_spectator_routes()
	print("CONTROLLER_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _controller():
	var controller = load(_base.path_join("main.gd")).new()
	controller.set_process(false)
	controller.transport = TransportStub.new()
	controller.adapter = AdapterStub.new()
	controller.table_sync = TableStub.new()
	controller.shop_sync = ShopStub.new()
	controller.presence = PresenceStub.new()
	controller.multiplayer_balls = MultiplayerBallsStub.new()
	controller.multiplayer_balls.rules = load(_base.path_join("multiplayer_ball_rules.gd")).new()
	controller.multiplayer_balls.rules.reset_round("fixture")
	controller.bounty_race = load(_base.path_join("bounty_race.gd"))
	controller.run_setup = RunStub.new()
	controller.panel = PanelStub.new()
	controller.panel.hide()
	controller.pass_button = Button.new()
	controller.turn_label = Label.new()
	controller.score_label = Label.new()
	for dependency in [
		controller.transport,
		controller.adapter,
		controller.table_sync,
		controller.shop_sync,
		controller.presence,
		controller.multiplayer_balls,
		controller.run_setup,
		controller.panel,
		controller.pass_button,
		controller.turn_label,
		controller.score_label
	]:
		controller.add_child(dependency)
	controller.lobby_model = load(_base.path_join("lobby_state.gd")).new()
	controller.router = load(_base.path_join("table_router.gd")).new()
	controller._local_id = 20
	controller.table_id = 1
	controller.table_leader_id = 20
	controller.turn_owner = 20
	controller.match_id = 5
	controller.lobby = {
		"started": true,
		"table_count": 2,
		"match_mode": "score",
		"shot_budget": 6,
		"players":
		[
			{"id": 10, "name": "Room host", "table": 0, "slot": 0, "connected": true},
			{"id": 20, "name": "Table host", "table": 1, "slot": 0, "connected": true},
			{"id": 30, "name": "Teammate", "table": 1, "slot": 1, "connected": true}
		]
	}
	return controller


func _closed_transport_teardown():
	var controller = _controller()
	controller.active = true
	controller.shot_pending = true
	controller.awaiting_shot_turn = 4
	controller.transport.close()
	_check(controller.transport.local_id() == 0, "fixture models transport already closed")
	controller._disconnected("Coordinator disconnected.")
	_check(controller._returning_to_menu, "cached leader identity schedules native menu return")
	_check(not controller.active and not controller.shot_pending, "disconnect cancels active shot")
	_check(controller.awaiting_shot_turn == -1, "disconnect clears pending submission")
	_check(
		(
			controller.adapter.ended == 1
			and controller.shop_sync.ended == 1
			and controller.table_sync.ended == 1
			and controller.multiplayer_balls.ended == 1
		),
		"disconnect tears down all table services"
	)
	_check(
		controller.match_id == 0 and controller._local_id == 0,
		"next room starts with a fresh match generation and identity"
	)
	_check(
		controller.lobby.is_empty() and controller.run_config.is_empty(),
		"disconnect clears previous room state"
	)
	controller.free()


func _abandoned_leader_rejoin():
	var host = _controller()
	host.transport.is_host = true
	host.transport.id = 10
	host._local_id = 10
	host.lobby_model.setup(10, "Room host")
	for id in [20, 30]:
		host.lobby_model.add_player(id, "Player %d" % id)
	host.lobby_model.set_table_count(10, 2)
	host.lobby_model.choose_slot(20, 1, 0)
	host.lobby_model.choose_slot(30, 1, 1)
	for id in [10, 20, 30]:
		host.lobby_model.set_ready(id, true)
	_check(host.lobby_model.start(10), "fixture starts two real lobby-model tables")
	host.table_summaries = [
		{
			"table": 0,
			"leader_id": 10,
			"score": 0.0,
			"base_score": 0.0,
			"bounty_shot": 0,
			"bounty_bonus": 0.0,
			"shots_used": 0,
			"shot_budget": 6,
			"finished": false,
			"status": "Playing"
		},
		{
			"table": 1,
			"leader_id": 20,
			"score": 18.0,
			"base_score": 18.0,
			"bounty_shot": 0,
			"bounty_bonus": 0.0,
			"shots_used": 2,
			"shot_budget": 6,
			"finished": false,
			"status": "Playing"
		}
	]
	host._broadcast_lobby()
	host._peer_left(20, "Connection lost.")
	_check(
		host.table_summaries[1].get("closed", false) and host.table_summaries[1].finished,
		"leader departure closes its table"
	)
	_check(host.table_summaries[1].score == 18.0, "leader departure preserves existing standings")
	_check(not host.table_summaries[0].finished, "another table keeps playing")
	host._peer_joined(20)
	_check(host.lobby_model.members_for_table(1)[0].connected, "reserved identity can reconnect")
	var returning = _controller()
	returning.lobby = host.lobby.duplicate(true)
	returning._received(10, {"kind": "match_start", "match": host.match_id, "config": {}})
	_check(
		not returning.active and returning.run_setup.starts == 0,
		"rejoining leader cannot start a fresh run in the old match"
	)
	_check(
		returning.run_setup.validations == 0, "closed-table check precedes native run preparation"
	)
	_check(
		returning.transport.sent.is_empty(),
		"closed-table rejoin does not reset healthy tables through match_failed"
	)
	host.transport.sent.clear()
	host._route_table(
		20,
		{
			"kind": "table",
			"match": host.match_id,
			"table": 1,
			"payload": {"kind": "snapshot", "id": 1, "scene": {"available": false}}
		}
	)
	_check(
		host.transport.sent.is_empty(),
		"reconnected closed leader cannot publish a restarted snapshot stream"
	)
	var follower = _controller()
	follower.transport.id = 30
	follower._local_id = 30
	follower.active = true
	follower.shot_pending = true
	follower.awaiting_shot_turn = 4
	follower.lobby = host.lobby.duplicate(true)
	follower._roster_changed()
	_check(
		follower.finished and not follower.shot_pending and follower.awaiting_shot_turn == -1,
		"closed table releases teammates from a pending shot"
	)
	host.table_summaries[1].closed = false
	host.table_summaries[1].status = "Finished"
	host._peer_left(20, "Left after finishing.")
	_check(
		(
			host.table_summaries[1].closed
			and host.table_summaries[1].status == "Finished"
			and host.table_summaries[1].score == 18.0
		),
		"completed result survives its leader leaving while the table still closes"
	)
	follower.free()
	returning.free()
	host.free()


func _run_closes_during_shot():
	var controller = _controller()
	controller.active = true
	controller.saw_table = true
	controller.shot_pending = true
	controller.total_score = 42.0
	controller.used_shots = 2
	controller._process(0.2)
	_check(
		controller.finished and not controller.shot_pending,
		"missing run terminates an unsettled shot"
	)
	_check(controller.finish_reason == "Run closed", "missing run reports its terminal reason")
	_check(
		controller.used_shots == 2 and controller.total_score == 42.0,
		"aborted shot does not invent score or shot completion"
	)
	var states: Array = controller.transport.sent.filter(
		func(frame): return frame.message.get("payload", {}).get("kind") == "state"
	)
	_check(
		(
			states.size() == 1
			and states[0].message.payload.finished
			and not states[0].message.payload.pending
		),
		"terminal state is sent to the coordinator"
	)
	controller.free()


func _targeted_shop_sync():
	var controller = _controller()
	controller.active = true
	controller.shop_sync.state = {"open": true, "revision": 2}
	controller.last_shop_state = {"open": true, "revision": 1}
	controller._publish_state(30)
	_check(
		controller.last_shop_state.revision == 1,
		"targeted reply preserves the previous broadcast cache"
	)
	var targeted: Array = controller.transport.sent.filter(
		func(frame): return frame.message.get("payload", {}).get("kind") == "shop_state"
	)
	_check(
		(
			targeted.size() == 1
			and targeted[0].message.target == 30
			and targeted[0].message.payload.shop.revision == 2
		),
		"rejoining teammate receives the current shop immediately"
	)
	controller._publish_state()
	_check(controller.last_shop_state.revision == 2, "normal broadcast advances the shop cache")
	var broadcast: Array = controller.transport.sent.filter(
		func(frame):
			return (
				frame.message.get("payload", {}).get("kind") == "shop_state"
				and not frame.message.has("target")
			)
	)
	_check(
		broadcast.size() == 1 and broadcast[0].message.payload.shop.revision == 2,
		"existing teammates still receive the pending shop change"
	)
	controller._publish_state()
	var repeated: Array = controller.transport.sent.filter(
		func(frame): return frame.message.get("payload", {}).get("kind") == "shop_state"
	)
	_check(repeated.size() == 2, "unchanged shop is not repeatedly broadcast")
	controller.free()


func _rejected_shots_preserve_ability_state():
	var controller = _controller()
	controller.active = true
	var rules = controller.multiplayer_balls.rules
	_check(
		not controller._take_shot(20, Vector2(100, 0), 0),
		"native adapter can reject an otherwise valid shot"
	)
	_check(
		rules.shot_index == 0 and controller.multiplayer_balls.begin_calls == 0,
		"native rejection cannot consume an accepted-shot index"
	)
	controller.adapter.ready_to_shoot = true
	_check(not controller._take_shot(30, Vector2(100, 0), 0), "nonowner shot is rejected")
	_check(not controller._take_shot(20, Vector2(100, 0), 1), "future turn is rejected")
	_check(not controller._take_shot(20, Vector2(20, 0), 0), "weak shot is rejected")
	_check(
		rules.shot_index == 0 and controller.multiplayer_balls.begin_calls == 0,
		"invalid requests cannot arm abilities"
	)
	_check(controller._pass(20, 0), "current player may pass before an accepted shot")
	_check(
		controller.shot_number == 1 and rules.shot_index == 0 and not rules.pending,
		"passing advances the turn without advancing ball abilities"
	)
	_check(controller._take_shot(30, Vector2(100, 0), 1), "new owner takes first accepted shot")
	_check(
		rules.shot_index == 1 and rules.shooter == 30 and rules.pending,
		"shot abilities record the actual accepted shooter"
	)
	_check(not controller._take_shot(30, Vector2(100, 0), 1), "duplicate active shot is rejected")
	_check(
		controller.multiplayer_balls.begin_calls == 1, "duplicate request cannot rearm abilities"
	)
	controller._finish_shot()
	_check(
		controller.used_shots == 1 and rules.last_shooter == 30 and not rules.pending,
		"settlement completes the same accepted shot in controller and rules"
	)
	_check(
		controller._take_shot(20, Vector2(100, 0), 2), "next accepted shot follows completed one"
	)
	_check(rules.shot_index == 2, "passing does not create a gap in accepted-shot indices")
	controller.free()


func _first_shot_phase_order():
	var host = _controller()
	host.active = true
	host.adapter.ready_to_shoot = true
	host.adapter.state.available = true
	host.adapter.state.table_active = true
	host.adapter.state.can_shoot = true
	var vector = Vector2(125, -50)
	_check(
		host._take_shot(20, vector, 0), "first shot is accepted before the first periodic update"
	)
	var phase_index = -1
	var shot_index = -1
	var baseline: Dictionary = {}
	var shot: Dictionary = {}
	for index in host.transport.sent.size():
		var frame: Dictionary = host.transport.sent[index]
		var payload: Dictionary = frame.message.get("payload", {})
		if payload.get("kind") == "snapshot" and payload.has("shop"):
			phase_index = index
			baseline = payload
			_check(not frame.unreliable, "first-shot phase baseline uses reliable delivery")
		if payload.get("kind") == "shot_start":
			shot_index = index
			shot = payload
			_check(not frame.unreliable, "first-shot vector uses reliable delivery")
	_check(
		phase_index >= 0 and shot_index > phase_index,
		"first-shot phase baseline is sent before the shot vector"
	)
	if baseline.is_empty() or shot.is_empty():
		host.free()
		return
	_check(shot.id > baseline.id, "first-shot vector has a newer sequence than its phase baseline")
	_check(
		shot.vector == vector and shot.turn == 0,
		"phase publication preserves the first shot vector and turn"
	)
	var guest = _controller()
	guest.active = true
	guest._local_id = 30
	guest.transport.id = 30
	guest._received_table(20, shot)
	_check(
		guest.last_started_turn == -1 and guest.table_sync.shots.is_empty(),
		"an early vector cannot consume the turn before its phase baseline"
	)
	guest._received_table(20, baseline)
	guest._received_table(20, shot)
	_check(
		guest.last_started_turn == 0 and guest.table_sync.shots == [vector],
		"the first vector starts after its phase baseline arrives"
	)
	guest._received_table(20, shot)
	_check(guest.table_sync.shots.size() == 1, "a repeated first-shot packet cannot launch twice")
	guest.free()
	host.free()


func _host_controller(mode: String):
	var host = _controller()
	host.transport.is_host = true
	host.transport.id = 10
	host._local_id = 10
	host.table_id = 0
	host.table_leader_id = 10
	host.turn_owner = 10
	host.lobby_model.setup(10, "Room host")
	for id in [20, 30]:
		host.lobby_model.add_player(id, "Player %d" % id)
	host.lobby_model.set_table_count(10, 2)
	host.lobby_model.set_match_mode(10, mode)
	host.lobby_model.choose_slot(20, 1, 0)
	host.lobby_model.choose_slot(30, 1, 1)
	for id in [10, 20, 30]:
		host.lobby_model.set_ready(id, true)
	host.lobby_model.start(10)
	host.table_summaries = [_summary(0, 10), _summary(1, 20)]
	host._broadcast_lobby()
	host.transport.sent.clear()
	return host


func _summary(table: int, leader: int) -> Dictionary:
	return {
		"table": table,
		"leader_id": leader,
		"score": 0.0,
		"base_score": 0.0,
		"bounty_shot": 0,
		"bounty_bonus": 0.0,
		"shots_used": 0,
		"shot_budget": 6,
		"finished": false,
		"run_won": false,
		"round": 1,
		"run_goal_rounds": 20,
		"elapsed_ms": 0,
		"finish_order": 0,
		"status": "Playing"
	}


func _state(controller, table: int, overrides: Dictionary = {}) -> Dictionary:
	var state: Dictionary = controller.adapter.game_data()
	state.merge(
		{
			"kind": "state",
			"available": true,
			"table_active": true,
			"turn_owner": controller._leader(table),
			"turn": 1,
			"pending": false,
			"round": 1,
			"total_score": 12.0,
			"used_shots": 1,
			"bounty_shot": 0,
			"multiplayer_balls": controller.multiplayer_balls.capture(),
			"finished": false,
			"finish_reason": ""
		},
		true
	)
	state.merge(overrides, true)
	return state


func _send_table(controller, actor: int, table: int, payload: Dictionary, match_value: int = -1):
	controller._route_table(
		actor,
		{
			"kind": "table",
			"match": controller.match_id if match_value < 0 else match_value,
			"table": table,
			"payload": payload
		}
	)


func _race_and_score_limits():
	for mode in ["race", "score"]:
		var controller = _controller()
		controller.active = true
		controller.lobby.match_mode = mode
		controller.used_shots = 5
		controller.shot_pending = true
		controller._finish_shot()
		_check(controller.used_shots == 6, "%s counts completed native shots" % mode)
		_check(controller.finished == (mode == "score"), "%s applies the correct shot limit" % mode)
		controller.free()
	var coop = _controller()
	coop.active = true
	coop.lobby.table_count = 1
	coop.lobby.match_mode = "score"
	coop.used_shots = 5
	coop._finish_shot()
	_check(not coop.finished, "one-table co-op ignores saved competitive mode and shot budget")
	coop.free()


func _race_finishes():
	var host = _host_controller("race")
	var win = _state(
		host,
		1,
		{
			"game_over": true,
			"run_won": true,
			"round": 20,
			"finished": true,
			"finish_reason": "Run completed"
		}
	)
	_check(host._valid_state(win, 1), "native final-round victory is a valid race finish")
	var premature: Dictionary = win.duplicate(true)
	premature.round = 19
	_check(not host._valid_state(premature, 1), "winning a nonfinal round cannot finish a race")
	var no_goal: Dictionary = win.duplicate(true)
	no_goal.round = 0
	no_goal.run_goal_rounds = 0
	_check(not host._valid_state(no_goal, 1), "empty run goal cannot count as race victory")
	var not_ended: Dictionary = win.duplicate(true)
	not_ended.game_over = false
	_check(not host._valid_state(not_ended, 1), "unfinished native run cannot claim victory")
	_send_table(host, 30, 1, win)
	_check(not host.table_summaries[1].finished, "teammate cannot publish a table leader's victory")
	_send_table(host, 20, 1, win, host.match_id - 1)
	_check(not host.table_summaries[1].finished, "previous-match victory is ignored")
	_send_table(host, 20, 1, win)
	_check(
		host.table_summaries[1].finish_order == 1, "first authenticated win receives first place"
	)
	var recorded: Dictionary = host.table_summaries[1].duplicate(true)
	_send_table(host, 20, 1, win)
	_check(
		host._finish_count == 1 and host.table_summaries[1] == recorded,
		"duplicate victory cannot change place or finish time"
	)
	var regressed = _state(host, 1)
	_send_table(host, 20, 1, regressed)
	_check(host.table_summaries[1] == recorded, "late playing state cannot reopen a finished table")
	var second = win.duplicate(true)
	second.turn_owner = 10
	_send_table(host, 10, 0, second)
	_check(host.table_summaries[0].finish_order == 2, "next table gets second place")
	_check(host._match_complete(), "all terminal tables complete the match")
	host.free()
	var losses = _host_controller("race")
	_send_table(
		losses,
		20,
		1,
		_state(
			losses,
			1,
			{"game_over": true, "finished": true, "finish_reason": "Run ended", "round": 20}
		)
	)
	_check(
		losses.table_summaries[1].finished and losses.table_summaries[1].finish_order == 0,
		"losing on the final round finishes without placing"
	)
	_check(losses._finish_count == 0, "loss does not consume first place")
	losses.free()


func _return_vote_lifecycle():
	var host = _host_controller("race")
	host.active = true
	var generation: int = host.match_id
	host._apply_lobby_request(20, {"action": "reset", "match": generation})
	_check(not host.lobby.return_vote.active, "guest cannot bypass vote by proposing a reset")
	host._apply_lobby_request(10, {"action": "reset", "match": generation - 1})
	_check(not host.lobby.return_vote.active, "stale reset request cannot open a new match vote")
	host._apply_lobby_request(10, {"action": "reset", "match": generation})
	_check(
		host.active and host.lobby.return_vote.active, "host proposal leaves the active run playing"
	)
	var revision: int = host.lobby.return_vote.revision
	host._apply_lobby_request(
		20, {"action": "return_ready", "match": generation, "revision": revision, "ready": true}
	)
	_check(
		host.active and host.match_id == generation, "partial consent preserves the active match"
	)
	host._apply_lobby_request(
		30, {"action": "return_ready", "match": generation - 1, "revision": revision, "ready": true}
	)
	_check(
		host.active and host.lobby.return_vote.ready == [10, 20],
		"old-match approval cannot complete the current vote"
	)
	host._apply_lobby_request(
		30, {"action": "return_ready", "match": generation, "revision": revision, "ready": true}
	)
	_check(
		not host.active and not host.lobby.started,
		"unanimous connected-player consent returns to lobby"
	)
	_check(
		host.match_id == generation + 1 and host.table_summaries.is_empty(),
		"approved reset advances the generation and clears results"
	)
	var stops = host.transport.sent.filter(
		func(frame): return frame.message.get("kind") == "match_stop"
	)
	_check(stops.size() == 1, "one approved vote publishes one match stop")
	host.free()


func _host_leave_requires_consent():
	var host = _host_controller("race")
	host.active = true
	host._leave_requested()
	_check(
		host.active and host.transport.session_open() and host.lobby.return_vote.active,
		"host Leave request keeps the room open and starts a unanimous return vote"
	)
	_check(host.panel.visible, "host Leave request opens the voting controls")
	host.free()
	var guest = _controller()
	guest.active = true
	guest._leave_requested()
	_check(not guest.active and not guest.transport.session_open(), "guest can leave voluntarily")
	guest.free()
	var completed = _host_controller("race")
	completed.active = true
	for summary in completed.table_summaries:
		summary.finished = true
	completed._leave_requested()
	_check(not completed.transport.session_open(), "host can leave once every table finishes")
	completed.free()


func _startup_failure_scope():
	var host = _host_controller("race")
	host.active = true
	host._starting_players = [20, 30]
	host._match_started_at = Time.get_ticks_msec()
	var generation: int = host.match_id
	host._received(20, {"kind": "match_ready", "match": generation - 1})
	_check(
		20 in host._starting_players, "stale startup acknowledgement cannot clear current startup"
	)
	host._received(20, {"kind": "match_ready", "match": generation})
	_check(
		not 20 in host._starting_players,
		"ready acknowledgement closes that player's startup window"
	)
	host._received(20, {"kind": "match_failed", "match": generation})
	_check(
		host.active and host.match_id == generation,
		"established player cannot bypass consent with a startup error"
	)
	host._received(30, {"kind": "match_failed", "match": generation - 1})
	_check(host.active, "previous-match startup failure cannot abort the current run")
	host._match_started_at = Time.get_ticks_msec() - 15001
	host._received(30, {"kind": "match_failed", "match": generation})
	_check(host.active, "expired startup error cannot bypass run-ending consent")
	host._match_started_at = Time.get_ticks_msec()
	host._received(30, {"kind": "match_failed", "match": generation})
	_check(
		not host.active and host.match_id == generation + 1,
		"genuine pending startup failure safely returns the room"
	)
	host.free()


func _spectator_routes():
	var host = _host_controller("race")
	host._set_watcher(999, {"match": host.match_id, "table": 0})
	_check(host._watchers.is_empty(), "unregistered actor cannot subscribe to a table")
	host._set_watcher(30, {"match": host.match_id - 1, "table": 0})
	host._set_watcher(30, {"match": host.match_id, "table": 1})
	_check(host._watchers.is_empty(), "old-match and own-table subscriptions are rejected")
	host._set_watcher(30, {"match": host.match_id, "table": 0})
	_check(host._watchers.get(30) == 0, "connected teammate can watch a different table")
	_send_table(host, 10, 0, _state(host, 0))
	var frames = host.transport.sent.filter(
		func(frame): return frame.message.get("kind") == "watch_state"
	)
	_check(
		frames.size() == 1 and frames[0].recipient == 30 and frames[0].message.table == 0,
		"host forwards only the subscribed table's state"
	)
	host.transport.sent.clear()
	host._set_watcher(30, {"match": host.match_id, "table": -1})
	_send_table(host, 10, 0, _state(host, 0))
	_check(
		not host.transport.sent.any(func(frame): return frame.message.get("kind") == "watch_state"),
		"leaving spectate stops its stream"
	)
	host.free()
	var viewer = _controller()
	viewer.active = true
	viewer.spectator = SpectatorStub.new()
	viewer.add_child(viewer.spectator)
	viewer.spectator.watched_table = 0
	_check(not viewer._turn_ready(), "spectating blocks local shot controls")
	var frame = {
		"kind": "watch_state", "match": viewer.match_id, "table": 0, "payload": _state(viewer, 0)
	}
	viewer._received(30, frame)
	_check(viewer.spectator.states.is_empty(), "peer cannot impersonate coordinator spectator feed")
	viewer._received(10, frame)
	_check(viewer.spectator.states.size() == 1, "coordinator can deliver the watched table")
	_check(
		viewer.turn_owner == 20 and viewer.table_id == 1 and viewer.latest_state.is_empty(),
		"spectator update cannot overwrite own-table authority"
	)
	frame.payload = {"kind": "snapshot", "id": 2, "scene": {"available": false}}
	viewer._received(10, frame)
	frame.payload.id = 1
	viewer._received(10, frame)
	_check(viewer.spectator.snapshots.size() == 1, "out-of-order spectator snapshots are ignored")
	frame.match -= 1
	frame.payload.id = 3
	viewer._received(10, frame)
	_check(viewer.spectator.snapshots.size() == 1, "previous-match spectator snapshots are ignored")
	viewer.free()


func _check(condition: bool, description: String):
	checks += 1
	if not condition:
		failures.append(description)

extends SceneTree


class TransportStub:
	extends Node
	var is_host = false
	var id = 20
	var coordinator = 10
	var room_code = "UP4-test"
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
	var state = {
		"available": false,
		"table_active": false,
		"can_shoot": false,
		"in_shop": false,
		"game_over": false,
		"round_finalized": false,
		"round": 0,
		"shots_left": 0,
		"score": 0.0
	}

	func game_data() -> Dictionary:
		return state.duplicate(true)

	func can_shoot() -> bool:
		return false

	func is_settled() -> bool:
		return false

	func end_session():
		ended += 1


class TableStub:
	extends Node
	var ended = 0

	func end_guest():
		ended += 1


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


class PresenceStub:
	extends Node
	var cleared = 0

	func clear():
		cleared += 1

	func receive(_sender: int, _message: Dictionary) -> bool:
		return false

	func tick(_delta: float, _active: bool, _can_aim: bool):
		pass


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
			"shots_used": 0,
			"shot_budget": 6,
			"finished": false,
			"status": "Playing"
		},
		{
			"table": 1,
			"leader_id": 20,
			"score": 18.0,
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


func _check(condition: bool, description: String):
	checks += 1
	if not condition:
		failures.append(description)

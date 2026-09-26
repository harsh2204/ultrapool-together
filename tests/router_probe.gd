extends SceneTree

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var base = get_script().resource_path.get_base_dir()
	var router = load(base.path_join("../mod/table_router.gd")).new()
	var roster = {
		"started": true,
		"table_count": 3,
		"players":
		[
			{"id": 10, "table": 0, "slot": 0, "connected": true},
			{"id": 20, "table": 0, "slot": 1, "connected": true},
			{"id": 30, "table": 1, "slot": 2, "connected": true},
			{"id": 40, "table": 1, "slot": 3, "connected": true},
			{"id": 50, "table": 2, "slot": 0, "connected": true}
		]
	}
	var message = _message(0, "shot")
	var routed = router.route(roster, 20, message)
	_check(routed.recipients == [10] and routed.actor == 20, "shot routes to its own table leader")
	_check(not routed.unreliable, "shot requests use reliable delivery")
	_check(router.route(roster, 30, message).is_empty(), "other table cannot submit a shot")
	_check(router.route(roster, 999, message).is_empty(), "unknown sender cannot submit a shot")
	message.payload["actor"] = 10
	message.payload["player"] = 10
	_check(
		router.route(roster, 20, message).actor == 20,
		"payload cannot impersonate the transport sender"
	)
	message["target"] = 30
	_check(router.route(roster, 20, message).is_empty(), "request cannot target another table")
	message.target = 20
	_check(router.route(roster, 20, message).is_empty(), "request cannot bypass its leader")
	for kind in ["shot", "pass", "shop_request", "sync_request"]:
		_check(
			router.route(roster, 40, _message(1, kind)).recipients == [30],
			"request finds first occupied seat even when slot zero is empty"
		)
	_check(
		router.route(roster, 40, _message(1, "ball_call")).is_empty(),
		"removed custom-ball requests cannot enter gameplay routing"
	)
	for kind in ["state", "snapshot", "shot_start", "shop_state"]:
		_check(
			router.route(roster, 20, _message(0, kind)).is_empty(),
			"nonleader cannot publish table authority"
		)
		_check(
			router.route(roster, 10, _message(0, kind)).recipients == [20],
			"leader broadcast stays within its table"
		)
	message = _message(0, "snapshot")
	message["reliable"] = false
	_check(
		router.route(roster, 10, message).unreliable, "live snapshot can use unreliable delivery"
	)
	message.reliable = true
	_check(not router.route(roster, 10, message).unreliable, "settled snapshot remains reliable")
	message = _message(0, "shot")
	message["reliable"] = false
	_check(
		not router.route(roster, 20, message).unreliable,
		"caller cannot downgrade an action's reliability"
	)
	for kind in ["shot_result", "shop_result"]:
		message = _message(0, kind)
		_check(
			router.route(roster, 10, message).is_empty(), "result requires an explicit recipient"
		)
		message["target"] = 20
		_check(
			router.route(roster, 10, message).recipients == [20],
			"result reaches its requesting player"
		)
		_check(router.route(roster, 20, message).is_empty(), "member cannot forge a leader result")
		message.target = 40
		_check(router.route(roster, 10, message).is_empty(), "result cannot cross table boundaries")
	message = _message(2, "state")
	routed = router.route(roster, 50, message)
	_check(
		not routed.is_empty() and routed.recipients.is_empty(),
		"solo leader state remains valid for room score tracking"
	)
	message = _message(0, "snapshot")
	message["target"] = 20
	_check(
		router.route(roster, 10, message).recipients == [20],
		"leader can target a same-table resynchronization"
	)
	message.target = 40
	_check(
		router.route(roster, 10, message).is_empty(), "resynchronization cannot reach another table"
	)
	var disconnected = roster.duplicate(true)
	disconnected.players[0].connected = false
	_check(
		router.route(disconnected, 20, _message(0, "shot")).is_empty(),
		"requests cannot reach a disconnected leader"
	)
	_check(
		router.route(disconnected, 20, _message(0, "state")).is_empty(),
		"leader disconnection cannot promote a replica"
	)
	_check(
		router.route(disconnected, 10, _message(0, "state")).is_empty(),
		"disconnected actor cannot publish"
	)
	disconnected = roster.duplicate(true)
	disconnected.players[1].connected = false
	_check(
		router.route(disconnected, 10, _message(0, "state")).recipients.is_empty(),
		"disconnected member is omitted from a valid broadcast"
	)
	var waiting = roster.duplicate(true)
	waiting.started = false
	_check(
		router.route(waiting, 20, _message(0, "shot")).is_empty(),
		"lobby cannot accept gameplay before start"
	)
	_check(
		router.route(roster, 20, _message(-1, "shot")).is_empty(), "negative table index rejected"
	)
	_check(router.route(roster, 20, _message(3, "shot")).is_empty(), "out-of-range table rejected")
	_check(
		router.route(roster, 20, _message(0, "presence")).is_empty(),
		"presence stays on its dedicated transport path"
	)
	_check(
		router.route(roster, 20, _message(0, "table_failed")).is_empty(),
		"room failure notification is not a table action"
	)
	message = _message(0, "state")
	message.payload["scores"] = [1, 2]
	routed = router.route(roster, 10, message)
	routed.payload.scores[0] = 99
	_check(message.payload.scores == [1, 2], "routing does not mutate the caller's payload")
	message.payload = "not a dictionary"
	_check(router.route(roster, 10, message).is_empty(), "malformed payload rejected")
	message = _message(0, "snapshot")
	message["reliable"] = "false"
	_check(router.route(roster, 10, message).is_empty(), "malformed reliability flag rejected")
	var invalid = roster.duplicate(true)
	invalid.started = 1
	_check(
		router.route(invalid, 10, _message(0, "state")).is_empty(),
		"nonboolean match state rejected"
	)
	invalid = roster.duplicate(true)
	invalid.table_count = 9
	_check(
		router.route(invalid, 10, _message(0, "state")).is_empty(), "table capacity remains bounded"
	)
	invalid = roster.duplicate(true)
	invalid.players[1].slot = 0
	_check(
		router.route(invalid, 10, _message(0, "state")).is_empty(),
		"ambiguous leader seats rejected"
	)
	print("ROUTER_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _message(table: int, kind: String) -> Dictionary:
	return {"kind": "table", "table": table, "payload": {"kind": kind}}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

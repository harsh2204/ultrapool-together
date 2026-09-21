extends SceneTree

const RELAY = "TOGETHER_RELAY"
const CALL = "TOGETHER_CALL"
const PATIENCE = "TOGETHER_PATIENCE"
const BOUNTY = "TOGETHER_BOUNTY"
const BANKROLL = "TOGETHER_BANKROLL"
const LIFELINE = "TOGETHER_LIFELINE"
const ENCORE = "TOGETHER_ENCORE"
const DOMINO = "TOGETHER_DOMINO"

var checks = 0
var failures: Array[String] = []
var rules_script: Script


func _initialize() -> void:
	rules_script = load(
		get_script().resource_path.get_base_dir().path_join("../mod/multiplayer_ball_rules.gd")
	)
	_relay_and_replay()
	_competitive_seat_counts()
	_race_table_balls()
	_patience()
	_calls()
	_utilities_and_mixed_balls()
	_domino_order()
	_bounty_and_round_reset()
	_multiplayer_state_validation()
	if failures.is_empty():
		print("PASS: %d multiplayer ball rules checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _new_rules():
	var model = rules_script.new()
	model.reset_round("round-1")
	return model


func _relay_and_replay() -> void:
	var model = _new_rules()
	model.register_ball(1, [RELAY])
	model.hit(1)
	_check(model.balls[1].marker == 0, "pre-shot contacts cannot mark Relay")
	_check(not model.begin_shot(0, 10, false, 2), "zero accepted-shot index is rejected")
	_check(model.begin_shot(1, 10, false, 2), "first accepted shot starts")
	model.hit(1)
	_check(not model.begin_shot(2, 20, false, 2), "overlapping shot cannot change shooter")
	_check(model.shooter == 10 and model.shot_index == 1, "active shot identity is frozen")
	_check(model.pocket(1, [RELAY], 9.0, 0, false).points == 0, "same-shot Relay has no bonus")
	model.finish_shot([1])
	_check(not model.begin_shot(1, 20, false, 2), "replayed accepted shot is rejected")
	_check(model.last_shooter == 10 and model.shot_index == 1, "replay cannot change turn state")
	model.begin_shot(2, 10, false, 2)
	model.hit(1)
	_check(model.pocket(1, [RELAY], 9.0, 0, false).points == 0, "same teammate cannot relay")
	model.finish_shot([1])
	model.begin_shot(3, 20, false, 2)
	model.hit(1)
	_check(model.balls[1].marker == 10, "later collision preserves the original assister")
	_check(model.pocket(1, [RELAY], 9.0, 0, false).points == 5, "handoff bonus rounds up")
	_check(model.pocket(1, [RELAY], 9.0, 0, false).points == 0, "duplicate pocket cannot pay")
	model.finish_shot([1])
	model.begin_shot(4, 10, false, 2)
	_check(model.pocket(1, [RELAY], 9.0, 0, false).points == 0, "respawn cannot farm Relay")
	model.finish_shot([])
	_check(model.pocket(2, [RELAY], 9.0, 0, false).points == 0, "out-of-shot pot has no effect")


func _competitive_seat_counts() -> void:
	var payouts: Array = []
	for seats in [1, 2, 8]:
		var model = _new_rules()
		model.register_ball(1, [RELAY])
		model.register_ball(2, [PATIENCE])
		model.begin_shot(1, 10, true, seats)
		model.hit(1)
		model.finish_shot([1, 2])
		model.begin_shot(2, 10, true, seats)
		payouts.append(
			[
				model.pocket(1, [RELAY], 20.0, 0, false).points,
				model.pocket(2, [PATIENCE], 20.0, 1, false).points
			]
		)
	_check(payouts == [[10.0, 5.0], [10.0, 5.0], [10.0, 5.0]], "seat count cannot improve bonuses")


func _race_table_balls() -> void:
	var solo = _new_rules()
	solo.register_ball(1, [RELAY])
	solo.begin_shot(1, 10, false, 1)
	solo.hit(1)
	_check(
		solo.pocket(1, [RELAY], 20.0, 0, false).points == 0, "solo Race Relay needs a later shot"
	)
	solo.finish_shot([1])
	solo.begin_shot(2, 10, false, 1)
	_check(
		solo.pocket(1, [RELAY], 20.0, 0, false).points == 10, "solo Race can complete its own Relay"
	)
	solo.finish_shot([1])
	solo.begin_shot(3, 10, false, 1)
	_check(
		solo.pocket(1, [RELAY], 20.0, 0, false).points == 0,
		"solo Race Relay still pays once per round"
	)
	for seats in [1, 2, 8]:
		var race = _new_rules()
		race.begin_shot(3, 10, false, seats)
		var bounty: Dictionary = race.pocket(1, [BOUNTY], 20.0, 0, false)
		_check(
			bounty.bounty and bounty.points == 10,
			"Race Bounty awards run points for every team size"
		)
		_check(
			not race.pocket(2, [BOUNTY], 20.0, 1, false).bounty,
			"Race Bounty remains once per match"
		)


func _patience() -> void:
	var model = _new_rules()
	model.register_ball(1, [PATIENCE])
	model.begin_shot(1, 10, false, 2)
	model.wall(1)
	model.finish_shot([1])
	_check(model.balls[1].charge == 0, "wall-only shot cannot charge Patience")
	for index in range(2, 6):
		model.begin_shot(index, 10, false, 2)
		model.hit(99)
		model.finish_shot([1])
	_check(model.balls[1].charge == 3, "Patience caps at three qualifying shots")
	model.finish_shot([1])
	_check(model.balls[1].charge == 3, "duplicate settlement cannot add a charge")
	model.begin_shot(6, 20, false, 2)
	model.hit(1)
	_check(model.pocket(1, [PATIENCE], 10.0, 0, false).points == 8, "three charges pay rounded 75%")
	model.finish_shot([1])
	_check(model.balls[1].charge == 3, "respawned pocket does not count as surviving the shot")
	model.begin_shot(7, 10, false, 2)
	_check(
		model.pocket(1, [PATIENCE], 10.0, 0, false).points == 0,
		"Patience cannot repay after respawn"
	)


func _calls() -> void:
	var model = _new_rules()
	model.register_ball(1, [CALL])
	_check(not model.call_ball(10, 1, 0), "call requires a completed shot")
	model.begin_shot(1, 10, false, 2)
	_check(not model.call_ball(10, 1, 0), "call cannot be made during shot")
	model.finish_shot([1])
	_check(not model.call_ball(20, 1, 0), "only previous shooter can call")
	_check(not model.call_ball(10, 1, 6), "invalid pocket cannot be called")
	_check(not model.call_ball(10, 99, 0), "unknown ball cannot be called")
	_check(model.call_ball(10, 1, 2), "previous shooter nominates next pocket")
	model.finish_shot([1])
	_check(model.call_state.get("pocket") == 2, "settlement without accepted shot preserves call")
	_check(not model.begin_shot(1, 20, false, 2), "old turn cannot consume a call")
	_check(model.call_state.get("actor") == 10, "replay preserves the nominated pocket")
	model.begin_shot(2, 20, false, 2)
	_check(not model.call_ball(10, 1, 3), "accepted shot locks the call")
	_check(model.pocket(1, [CALL], 12.0, 3, false).points == 0, "wrong pocket gives no call bonus")
	model.finish_shot([1])
	_check(model.call_state.is_empty(), "missed call expires at settlement")
	_check(model.call_ball(20, 1, 3), "next completed shooter may call again")
	model.begin_shot(3, 10, false, 2)
	_check(model.pocket(1, [CALL], 12.0, 3, false).points == 12, "correct pocket fulfills call")
	model.finish_shot([1])
	_check(not model.call_ball(10, 1, 3), "paid Called Shot cannot be farmed")
	var solo = _new_rules()
	solo.register_ball(1, [CALL])
	solo.begin_shot(1, 10, true, 1)
	solo.finish_shot([1])
	_check(solo.call_ball(10, 1, 5), "solo table can nominate its own next shot")
	solo.begin_shot(2, 10, true, 1)
	_check(solo.pocket(1, [CALL], 12.0, 5, false).points == 12, "solo call pays equally")


func _utilities_and_mixed_balls() -> void:
	var model = _new_rules()
	model.wall(1)
	model.begin_shot(1, 10, false, 2)
	_check(
		model.pocket(1, [BANKROLL], 10.0, 0, false).money == 0, "pre-shot wall contact cannot pay"
	)
	model.wall(2)
	var mixed: Dictionary = model.pocket(2, [BANKROLL, LIFELINE, ENCORE], 10.0, 0, false)
	_check(
		mixed.money == 2 and mixed.heal == 1 and mixed.encore,
		"mixed utility ball applies each effect"
	)
	_check(mixed.points == 0, "utility effects do not create point bonuses")
	model.wall(3)
	var duplicate: Dictionary = model.pocket(3, [BANKROLL, LIFELINE, ENCORE], 10.0, 0, false)
	_check(
		duplicate.money == 0 and duplicate.heal == 0 and not duplicate.encore,
		"utilities cap per table"
	)
	model.finish_shot([])
	model.begin_shot(2, 20, false, 2)
	model.wall(4)
	var later: Dictionary = model.pocket(4, [BANKROLL, LIFELINE, ENCORE], 10.0, 0, false)
	_check(
		later.money == 0 and later.heal == 0 and not later.encore,
		"changing shooter cannot refresh utilities"
	)
	model.finish_shot([])
	model.reset_round("round-2")
	model.begin_shot(3, 10, false, 2)
	model.wall(5)
	var refreshed: Dictionary = model.pocket(5, [BANKROLL, LIFELINE, ENCORE], 10.0, 0, false)
	_check(
		refreshed.money == 2 and refreshed.heal == 1 and refreshed.encore,
		"new round refreshes utilities"
	)
	var points = _new_rules()
	points.register_ball(1, [RELAY, PATIENCE, RELAY])
	points.begin_shot(1, 10, false, 2)
	points.hit(1)
	points.finish_shot([1])
	points.begin_shot(2, 20, false, 2)
	_check(
		points.pocket(1, [RELAY, PATIENCE, RELAY], 9.0, 0, false).points == 8,
		"mixed bonuses add ordinary values without compounding"
	)


func _domino_order() -> void:
	var model = _new_rules()
	model.begin_shot(1, 10, false, 2)
	_check(model.pocket(1, [], 10.0, 0, true).points == 0, "pot before Domino has no bonus")
	model.pocket(2, [DOMINO], 10.0, 0, false)
	_check(
		model.pocket(3, [DOMINO], 10.0, 0, false).points == 0,
		"another Domino neither consumes nor stacks"
	)
	model.pocket(4, [LIFELINE], 10.0, 0, false)
	_check(model.pocket(5, [], 11.0, 0, true).points == 11, "next ordinary pot consumes Domino")
	_check(
		model.pocket(6, [], 11.0, 0, true).points == 0, "second ordinary pot gets no Domino bonus"
	)
	model.finish_shot([])
	model.begin_shot(2, 20, false, 2)
	model.pocket(7, [DOMINO], 10.0, 0, false)
	_check(
		model.pocket(8, [], 11.0, 0, true).points == 0, "Domino charge is shared across the round"
	)
	model.finish_shot([])
	model.reset_round("round-2")
	model.begin_shot(3, 10, false, 2)
	model.pocket(9, [DOMINO], 10.0, 0, false)
	model.finish_shot([])
	model.begin_shot(4, 20, false, 2)
	_check(model.pocket(10, [], 11.0, 0, true).points == 0, "unused Domino expires with its shot")


func _bounty_and_round_reset() -> void:
	var model = _new_rules()
	model.register_ball(1, [RELAY, PATIENCE])
	model.begin_shot(1, 10, true, 8)
	model.hit(1)
	var competitive: Dictionary = model.pocket(2, [BOUNTY], 1000.0, 0, false)
	_check(
		competitive.bounty and competitive.points == 0,
		"competitive bounty reports completion without awarding locally"
	)
	_check(model.bounty_shot == 1, "bounty records accepted-shot index")
	model.finish_shot([1])
	model.reset_round("round-1")
	_check(
		model.balls[1].charge == 1 and model.balls[1].marker == 10, "same-round reset is idempotent"
	)
	model.reset_round("round-2")
	_check(
		model.balls.is_empty() and model.last_shooter == 0,
		"round reset clears marks and previous caller"
	)
	_check(
		model.shot_index == 1 and model.bounty_shot == 1,
		"round reset preserves match shot and bounty"
	)
	model.begin_shot(2, 20, true, 8)
	_check(
		not model.pocket(3, [BOUNTY], 1000.0, 0, false).bounty,
		"new round cannot repeat match bounty"
	)
	for index in [1, 3, 4]:
		var coop = _new_rules()
		coop.begin_shot(index, 10, false, 2)
		var result: Dictionary = coop.pocket(1, [BOUNTY], 1000.0, 0, false)
		var expected = 10.0 if index <= 3 else 0.0
		_check(
			result.bounty and result.points == expected,
			"co-op bounty has fixed three-shot deadline"
		)
		_check(
			not coop.pocket(2, [BOUNTY], 1000.0, 1, false).bounty,
			"multiple bounty balls cannot repay"
		)


func _multiplayer_state_validation():
	var service = rules_script
	var valid = {
		"last_shooter": 20,
		"pending": false,
		"bounty_shot": 1,
		"call": {"ball": 1, "pocket": 0, "actor": 20},
		"balls":
		[
			{
				"id": 1,
				"kinds": ["TOGETHER_CALL"],
				"name": "Called Shot",
				"position": Vector2(100, 200),
				"color": Color.WHITE,
				"marker": 0,
				"charge": 0,
				"callable": true,
				"alive": true
			}
		],
		"pockets": [{"index": 0, "position": Vector2(20, 20), "open": true}]
	}
	_check(service.valid_state(valid), "complete multiplayer display state is valid")
	_check(not service.valid_state(null), "missing multiplayer state is rejected")
	_check(not service.valid_state({}), "partial multiplayer state is rejected")
	var invalid = valid.duplicate(true)
	invalid.balls.append(invalid.balls[0].duplicate(true))
	_check(not service.valid_state(invalid), "duplicate ball identities are rejected")
	invalid = valid.duplicate(true)
	invalid.balls[0].kinds = ["TOGETHER_UNKNOWN"]
	_check(not service.valid_state(invalid), "unimplemented ability identifiers are rejected")
	invalid = valid.duplicate(true)
	invalid.balls[0].kinds = ["TOGETHER_CALL", "TOGETHER_CALL"]
	_check(not service.valid_state(invalid), "duplicate mixed ability identifiers are rejected")
	invalid = valid.duplicate(true)
	invalid.balls[0].position = Vector2(NAN, 0)
	_check(not service.valid_state(invalid), "nonfinite marker positions are rejected")
	invalid = valid.duplicate(true)
	invalid.balls[0].color = Color(NAN, 1, 1, 1)
	_check(not service.valid_state(invalid), "nonfinite colors are rejected")
	invalid = valid.duplicate(true)
	invalid.balls[0].charge = 4
	_check(not service.valid_state(invalid), "Patience charge limit is enforced")
	invalid = valid.duplicate(true)
	invalid.balls[0].marker = -1
	_check(not service.valid_state(invalid), "negative marker identities are rejected")
	invalid = valid.duplicate(true)
	invalid.balls[0].name = "x".repeat(161)
	_check(not service.valid_state(invalid), "unbounded ball labels are rejected")
	invalid = valid.duplicate(true)
	invalid.balls.clear()
	for id in range(1, 130):
		var ball: Dictionary = valid.balls[0].duplicate(true)
		ball.id = id
		invalid.balls.append(ball)
	_check(not service.valid_state(invalid), "oversized ball snapshots are rejected")
	invalid = valid.duplicate(true)
	invalid.pockets.append(invalid.pockets[0].duplicate(true))
	_check(not service.valid_state(invalid), "duplicate pocket identities are rejected")
	invalid = valid.duplicate(true)
	invalid.pockets[0].position = Vector2(0, INF)
	_check(not service.valid_state(invalid), "nonfinite pocket positions are rejected")
	for field in ["ball", "pocket"]:
		invalid = valid.duplicate(true)
		invalid.call[field] = 99
		_check(not service.valid_state(invalid), "call cannot reference an absent %s" % field)
	invalid = valid.duplicate(true)
	invalid.call.actor = 0
	_check(not service.valid_state(invalid), "call requires a real actor")
	invalid = valid.duplicate(true)
	invalid.pending = 1
	_check(not service.valid_state(invalid), "pending must be a boolean")
	invalid = valid.duplicate(true)
	invalid.balls[0].callable = "yes"
	_check(not service.valid_state(invalid), "call availability must be a boolean")
	invalid = valid.duplicate(true)
	invalid.call.actor = 30
	_check(not service.valid_state(invalid), "only the previous shooter can own a call")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

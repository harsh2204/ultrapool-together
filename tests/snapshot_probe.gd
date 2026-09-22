extends Node

signal completed

var checks = 0
var failed = false
var embedded = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not (
		OS.get_user_data_dir().contains("UltrapoolTogetherSnapshotTest")
		or (embedded and OS.get_user_data_dir().contains("UltrapoolTogetherRenderTest"))
	):
		push_error("SNAPSHOT_PROBE FAIL: isolated save directory required")
		get_tree().quit(1)
		return
	var sync = (
		load(get_script().resource_path.get_base_dir().path_join("../mod/table_sync.gd")).new()
	)
	add_child(sync)
	var item = {
		"data": "PLAYER",
		"mixed": "",
		"base_score": 1,
		"temp_extra_score": 0,
		"level": 1,
		"weight_state": 1,
		"flaming": false,
		"fleeting": false,
		"star_power": false,
		"shielded": false,
		"shield_broken": false,
		"locked": false
	}
	var cue = {
		"id": 1,
		"player": true,
		"item": item,
		"position": Vector2(300, 700),
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"linear_damp": 1.5,
		"angular_damp": 0.5,
		"force": Vector2.ZERO,
		"rotation": 0.0,
		"spin": Vector3.ZERO,
		"visual_scale": Vector2.ONE,
		"radius_scale": 1.0,
		"mass": 1.0,
		"color": Color.WHITE,
		"visible": true,
		"alive": true,
		"spawned": true,
		"falling": false,
		"gone": false,
		"passive": false
	}
	var state = {
		"available": true,
		"scene_id": 1,
		"round": 0,
		"rounds_played": 1,
		"ready": true,
		"in_menu": false,
		"in_shop": false,
		"round_ended": false,
		"game_over": false,
		"daily": false,
		"rotated": false,
		"table_position": Vector2.ZERO,
		"score": 0,
		"required_score": 50,
		"shots": 5,
		"money": 0,
		"hp": 3,
		"max_hp": 3,
		"inventory": {"build": [], "passives": [], "cubes": [], "snacks": 0, "cocktails": 0},
		"results":
		{
			"phase": "play",
			"won": false,
			"score": 0,
			"bonus_money": 0,
			"money_before": 0,
			"round_reward": 10,
			"balls_pocketed": 0,
			"money_earned": 0,
			"game_time": 0.0
		},
		"balls": [cue],
		"pockets": []
	}
	state.inventory.build.resize(16)
	state.inventory.passives.resize(4)
	for index in 6:
		state.pockets.append(
			{
				"id": index + 2,
				"base_index": index,
				"position": Vector2.ZERO,
				"rotation": 0.0,
				"scale": Vector2.ONE,
				"multiplier": 2.0,
				"score": 0,
				"closed": false,
				"shielded": false,
				"has_held_balls": false
			}
		)
	_check(sync._valid_snapshot(state), "native cue snapshot accepted")
	_check_inventory(sync, state)
	for invalid_result in [{}, {"phase": "unknown"}, {"phase": "payout", "won": "true"}]:
		var bad_result = state.duplicate(true)
		bad_result.results = invalid_result
		_check(not sync._valid_snapshot(bad_result), "invalid round presentation rejected")
	var nonfinite_result = state.duplicate(true)
	nonfinite_result.results.score = NAN
	_check(not sync._valid_snapshot(nonfinite_result), "nonfinite payout score rejected")
	_check(sync._valid_snapshot({"available": false}), "waiting snapshot accepted")
	_check(not sync._valid_snapshot({"available": "true"}), "wrong availability type rejected")
	var invalid = state.duplicate(true)
	invalid.balls[0].item.data = "res://injected.gd"
	_check(not sync._valid_snapshot(invalid), "network resource paths rejected")
	invalid = state.duplicate(true)
	invalid.balls[0].position = Vector2(NAN, 0)
	_check(not sync._valid_snapshot(invalid), "nonfinite position rejected")
	invalid = state.duplicate(true)
	invalid.balls[0].velocity = Vector2(INF, 0)
	_check(not sync._valid_snapshot(invalid), "nonfinite prediction velocity rejected")
	invalid = state.duplicate(true)
	invalid.balls[0].linear_damp = -1.0
	_check(not sync._valid_snapshot(invalid), "negative prediction damping rejected")
	invalid = state.duplicate(true)
	invalid.table_position = "0, 0"
	_check(not sync._valid_snapshot(invalid), "invalid table transform rejected")
	invalid = state.duplicate(true)
	invalid.balls[0].visual_scale = Vector2(100000, 100000)
	_check(not sync._valid_snapshot(invalid), "unbounded geometry rejected")
	invalid = state.duplicate(true)
	invalid.balls.append(cue.duplicate(true))
	_check(not sync._valid_snapshot(invalid), "duplicate identity rejected")
	invalid.balls[1].id = 2
	_check(not sync._valid_snapshot(invalid), "multiple cue balls rejected")
	invalid = state.duplicate(true)
	invalid.balls[0].mass = true
	_check(not sync._valid_snapshot(invalid), "boolean mass rejected")
	invalid = state.duplicate(true)
	invalid.balls[0].item.weight_state = 4
	_check(not sync._valid_snapshot(invalid), "invalid native enum rejected")
	invalid = state.duplicate(true)
	invalid.balls.resize(129)
	_check(not sync._valid_snapshot(invalid), "excess bodies rejected")
	invalid = state.duplicate(true)
	invalid.pockets[0].base_index = 6
	_check(not sync._valid_snapshot(invalid), "invalid base pocket index rejected")
	var with_hole = state.duplicate(true)
	var hole = state.pockets[0].duplicate(true)
	hole.id = 20
	hole.base_index = -1
	with_hole.pockets.append(hole)
	_check(sync._valid_snapshot(with_hole), "native dynamic hole accepted")
	invalid = with_hole.duplicate(true)
	invalid.pockets[6].scale = Vector2(INF, 1)
	_check(not sync._valid_snapshot(invalid), "nonfinite hole geometry rejected")
	var original_game = get_node("/root/Global").gameManager
	_check(not sync.apply_snapshot(state), "snapshot outside session rejected")
	_check(
		get_node("/root/Global").gameManager == original_game,
		"rejected packet has no scene side effects"
	)
	print("SNAPSHOT_PROBE %s: %d checks passed" % ["FAIL" if failed else "PASS", checks])
	completed.emit()
	if not embedded:
		get_tree().quit(1 if failed else 0)


func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error("SNAPSHOT_PROBE failed: " + description)
		failed = true
		return
	checks += 1


func _check_inventory(sync: Node, state: Dictionary) -> void:
	var inventory_sync = load(
		get_script().resource_path.get_base_dir().path_join("../mod/player_inventory_sync.gd")
	)
	var database = get_node("/root/BallDatabase")
	var info_script = load("res://player_info.gd")
	var info = info_script.new()
	var replica_info = info_script.new()
	var ball = BallItem.new()
	ball.data = database.id_to_ball["PLAYER"]
	ball.mixed_data = database.cubes[0]
	ball.base_score = 17
	ball.temp_extra_score = 9
	ball.level = 3
	ball.flaming = true
	ball.shielded = true
	var passive = BallItem.new()
	passive.data = database.id_to_passive.values()[0]
	var cube = BallItem.new()
	cube.data = database.cubes[0]
	info.build.assign([ball, null, ball.duplicate(true)])
	info.build.resize(16)
	info.passives.assign([null, passive, null, null])
	info.cubes.assign([cube])
	info.snack_tickets = 3
	info.cocktail_tickets = 2
	var payload = inventory_sync.capture(info)
	_check(inventory_sync.valid(payload, database), "complete native inventory accepted")
	inventory_sync.apply(replica_info, payload, database)
	_check(
		inventory_sync.capture(replica_info) == payload,
		"inventory roundtrip preserves slots, mixes, effects, reserves, passives, cubes, and tickets"
	)
	var with_inventory = state.duplicate(true)
	with_inventory.inventory = payload
	_check(sync._valid_snapshot(with_inventory), "table snapshot includes native inventory")
	for field in ["build", "passives", "cubes"]:
		var invalid = with_inventory.duplicate(true)
		invalid.inventory[field].resize(129)
		_check(not sync._valid_snapshot(invalid), "oversized inventory " + field + " rejected")
	var invalid = with_inventory.duplicate(true)
	invalid.inventory.build[0].data = "res://injected.tres"
	_check(not sync._valid_snapshot(invalid), "inventory resource paths rejected")
	invalid = with_inventory.duplicate(true)
	invalid.inventory.passives[1].data = "PLAYER"
	_check(not sync._valid_snapshot(invalid), "ball identity in passive inventory rejected")
	invalid = with_inventory.duplicate(true)
	invalid.inventory.cubes[0].data = "PLAYER"
	_check(not sync._valid_snapshot(invalid), "non-cube identity in cube inventory rejected")
	invalid = with_inventory.duplicate(true)
	invalid.inventory.build[0].mixed = "missing-ball"
	_check(not sync._valid_snapshot(invalid), "unknown inventory mixed ball rejected")
	invalid = with_inventory.duplicate(true)
	invalid.inventory.build[0].level = NAN
	_check(not sync._valid_snapshot(invalid), "nonfinite inventory level rejected")
	invalid = with_inventory.duplicate(true)
	invalid.inventory.build[0].flaming = "true"
	_check(not sync._valid_snapshot(invalid), "nonboolean inventory effect rejected")
	invalid = with_inventory.duplicate(true)
	invalid.inventory.snacks = -1
	_check(not sync._valid_snapshot(invalid), "negative inventory tickets rejected")
	invalid = with_inventory.duplicate(true)
	invalid.inventory.build.resize(2)
	_check(not sync._valid_snapshot(invalid), "missing required native inventory slots rejected")
	info.free()
	replica_info.free()

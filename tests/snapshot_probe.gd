extends Node

var checks = 0
var failed = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not OS.get_user_data_dir().contains("UltrapoolTogetherSnapshotTest"):
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
		"balls": [cue],
		"pockets": []
	}
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
	get_tree().quit(1 if failed else 0)


func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error("SNAPSHOT_PROBE failed: " + description)
		failed = true
		return
	checks += 1

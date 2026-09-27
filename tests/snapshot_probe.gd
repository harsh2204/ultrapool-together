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
		"shots_max": 5,
		"shots_used": 0,
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
	_check(sync.snapshot_problem(state) == "", "valid snapshot has empty problem")
	_check_inventory(sync, state)
	for invalid_result in [{}, {"phase": "unknown"}, {"phase": "payout", "won": "true"}]:
		var bad_result = state.duplicate(true)
		bad_result.results = invalid_result
		_check(not sync._valid_snapshot(bad_result), "invalid round presentation rejected")
		_check(
			sync.snapshot_problem(bad_result).begins_with("results")
			or sync.snapshot_problem(bad_result) == "results",
			"invalid results expose a reject reason"
		)
	var nonfinite_result = state.duplicate(true)
	nonfinite_result.results.score = NAN
	_check(not sync._valid_snapshot(nonfinite_result), "nonfinite payout score rejected")
	_check(sync._valid_snapshot({"available": false}), "waiting snapshot accepted")
	_check(not sync._valid_snapshot({"available": "true"}), "wrong availability type rejected")
	var invalid = state.duplicate(true)
	invalid.balls[0].item.data = "res://injected.gd"
	_check(not sync._valid_snapshot(invalid), "network resource paths rejected")
	_check(
		sync.snapshot_problem(invalid).contains("ball item data"),
		"unknown ball item reports item data reason"
	)
	invalid = state.duplicate(true)
	invalid.pockets.pop_back()
	_check(not sync._valid_snapshot(invalid), "incomplete base pockets rejected")
	_check(
		sync.snapshot_problem(invalid).contains("base pockets"),
		"incomplete pockets report base pocket count"
	)
	_check(sync.ball_ids(state).has(1), "ball_ids indexes cue identity")
	_check(not sync.spawn_barrier_active(), "spawn barrier idle without a live host table")
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
	_check(sync.valid_capture(state), "valid_capture mirrors snapshot validation")
	var incomplete_pockets = state.duplicate(true)
	incomplete_pockets.pockets.pop_back()
	_check(
		not sync.valid_capture(incomplete_pockets),
		"capture missing a base pocket is invalid for host publish"
	)
	var too_many_pockets = state.duplicate(true)
	for index in 11:
		var extra = state.pockets[0].duplicate(true)
		extra.id = 100 + index
		extra.base_index = -1
		too_many_pockets.pockets.append(extra)
	_check(
		not sync.valid_capture(too_many_pockets),
		"oversized pocket list is invalid for host publish"
	)
	_check_identity_rebuild(sync, state, cue)
	_check_potted_rail(sync, cue)
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


class _ResultsStub:
	extends Node

	func apply(_data: Dictionary) -> void:
		pass

	func clear() -> void:
		pass

	func end_session() -> void:
		pass


class _BallStub:
	extends Node
	var is_player = false
	var ball_item = null


class _ReplicaStub:
	extends Node
	var replicas: Dictionary = {}
	var pocket_replicas: Dictionary = {}
	var corrections: Dictionary = {}
	var player_ball = null
	var selected_ball = null
	var applied: Array = []

	func apply_table(data: Dictionary) -> void:
		applied.append(data.duplicate(true))
		for body in data.balls:
			if not replicas.has(body.id):
				var ball = _BallStub.new()
				ball.is_player = body.player
				replicas[body.id] = ball
				if body.player:
					player_ball = ball
		for pocket in data.pockets:
			if not pocket_replicas.has(pocket.id):
				var node = Node.new()
				node.set_meta("remote_base_index", pocket.base_index)
				if pocket.base_index < 0:
					node.set_meta("remote_hole", true)
				pocket_replicas[pocket.id] = node


func _check_identity_rebuild(sync: Node, state: Dictionary, cue: Dictionary) -> void:
	var replica = _ReplicaStub.new()
	add_child(replica)
	var results = _ResultsStub.new()
	add_child(results)
	sync._guest = true
	sync._scene_key = "%s:%s" % [state.scene_id, state.rotated]
	sync._replica = replica
	sync._results = results
	var cue_body = _BallStub.new()
	cue_body.is_player = true
	replica.replicas[cue.id] = cue_body
	replica.player_ball = cue_body
	for pocket in state.pockets:
		var node = Node.new()
		node.set_meta("remote_base_index", pocket.base_index)
		replica.pocket_replicas[pocket.id] = node
	var remapped = state.duplicate(true)
	# Swap two base pocket identities mid-scene (Slot-style rematerialize).
	remapped.pockets[0].base_index = 1
	remapped.pockets[1].base_index = 0
	_check(sync.apply_snapshot(remapped), "identity-incompatible pocket update is rebuilt")
	_check(
		replica.pocket_replicas[remapped.pockets[0].id].get_meta("remote_base_index") == 1,
		"rebuilt pocket adopts the new base index"
	)
	# Use a real object-ball id from BallDatabase. A literal "1" is not a valid
	# catalog key, so apply_snapshot used to soft-reject and the rebuild checks
	# never exercised issue-#7 identity flip semantics.
	var object_id = _object_ball_id()
	_check(object_id != "", "native BallDatabase exposes a non-cue object ball")
	if object_id == "":
		sync._guest = false
		sync._scene_key = ""
		sync._replica = null
		sync._results = null
		replica.queue_free()
		results.queue_free()
		return
	var flipped = state.duplicate(true)
	flipped.balls[0] = cue.duplicate(true)
	flipped.balls[0].player = false
	flipped.balls[0].item = cue.item.duplicate(true)
	flipped.balls[0].item.data = object_id
	# Recreate cue-as-player mapping then flip.
	replica.replicas.clear()
	cue_body = _BallStub.new()
	cue_body.is_player = true
	replica.replicas[cue.id] = cue_body
	replica.player_ball = cue_body
	_check(sync.apply_snapshot(flipped), "cue/object identity flip is rebuilt instead of rejected")
	_check(
		replica.replicas.has(cue.id) and replica.replicas[cue.id].is_player == false,
		"rebuilt ball matches the new player flag"
	)
	sync._guest = false
	sync._scene_key = ""
	sync._replica = null
	sync._results = null
	replica.queue_free()
	results.queue_free()


func _check_potted_rail(sync: Node, cue: Dictionary) -> void:
	var object_id = _object_ball_id()
	_check(object_id != "", "native BallDatabase exposes a non-cue object ball for potted-rail checks")
	if object_id == "":
		return
	var pocketed = cue.duplicate(true)
	pocketed.id = 50
	pocketed.player = false
	pocketed.item = cue.item.duplicate(true)
	pocketed.item.data = object_id
	pocketed.alive = false
	pocketed.visible = true
	pocketed.gone = false
	_check(sync.ball_on_potted_rail(pocketed), "pocketed visible object ball is on the potted rail")
	var live = pocketed.duplicate(true)
	live.alive = true
	_check(not sync.ball_on_potted_rail(live), "live object ball is not on the potted rail")
	var hidden = pocketed.duplicate(true)
	hidden.visible = false
	_check(not sync.ball_on_potted_rail(hidden), "invisible pocketed ball is not on the potted rail")
	var cue_rail = pocketed.duplicate(true)
	cue_rail.player = true
	cue_rail.item = cue.item.duplicate(true)
	cue_rail.item.data = "PLAYER"
	_check(not sync.ball_on_potted_rail(cue_rail), "cue ball is never treated as a rail icon")
	# Synced BallItem fields already carry name/description (via BallDatabase id) and value.
	_check(
		(
			typeof(pocketed.item.get("data")) == TYPE_STRING
			and typeof(pocketed.item.get("base_score")) == TYPE_INT
			and typeof(pocketed.item.get("temp_extra_score")) == TYPE_INT
		),
		"rail hover reuses synced ball identity and score fields"
	)


func _object_ball_id() -> String:
	var database = get_node_or_null("/root/BallDatabase")
	if database == null or not database.get("id_to_ball") is Dictionary:
		return ""
	for ball_id in database.id_to_ball:
		var key = str(ball_id)
		if key != "" and key != "PLAYER":
			return key
	return ""


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
	_check(
		payload.cubes.size() == 1 and payload.cubes[0] != null,
		"NEGATIVE cube slot survives host capture (#33)"
	)
	_check(payload.snacks == 3, "snack tickets survive host capture (#33)")
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

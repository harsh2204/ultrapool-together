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
	_check_pocket_capture(sync, state)
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
	_check_committed_readiness(sync, state)
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


class _PocketCaptureStub:
	extends Node2D
	var multiplier = 2.0
	var extra_score = 0
	var closed = false
	var shielded = false
	var held_balls: Array = []

	func _init() -> void:
		# Capture samples the native pocket's fixed presentation hierarchy. Keep
		# this logical stub inert, but give it the same visual node types/paths.
		var doors = Node2D.new()
		doors.name = "Doors"
		add_child(doors)
		for part_name in ["Left", "Right"]:
			var door = Sprite2D.new()
			door.name = part_name
			doors.add_child(door)
		for part_name in ["ShieldIndicator", "SkullIndicator"]:
			var indicator = Sprite2D.new()
			indicator.name = part_name
			add_child(indicator)
		var label = Label.new()
		label.name = "Label"
		add_child(label)
		var extra_score_pivot = Node2D.new()
		extra_score_pivot.name = "ExtraScoreLabelPivot"
		add_child(extra_score_pivot)

	func get_multiplier() -> float:
		return multiplier


class _PocketTableStub:
	extends Node2D
	var pockets: Array = []

	func get_pockets() -> Array:
		return pockets


class _PocketGameStub:
	extends Node
	var table: Node2D
	var pockets: Array = []


func _check_pocket_capture(sync: Node, state: Dictionary) -> void:
	var game = _PocketGameStub.new()
	game.table = _PocketTableStub.new()
	game.add_child(game.table)
	var pocket_parent = Node2D.new()
	pocket_parent.name = "Pockets"
	game.table.add_child(pocket_parent)
	for index in 6:
		var pocket = _PocketCaptureStub.new()
		pocket_parent.add_child(pocket)
		game.table.pockets.append(pocket)
	# Native Game aliases this array; a shallow/deep duplicate would miss the bug.
	game.pockets = game.table.get_pockets()
	add_child(game)
	var original = sync._capture_pockets(game)
	for index in 6:
		_check(original[index].base_index == index, "base pocket retains native scene order")
	var captured_base = state.duplicate(true)
	captured_base.pockets = original
	_check(sync.valid_capture(captured_base), "base pockets capture valid native presentation")
	var legacy_base = captured_base.duplicate(true)
	for pocket in legacy_base.pockets:
		pocket.erase("pocket_visual")
	_check(sync.valid_capture(legacy_base), "legacy pockets may omit optional presentation")
	var malformed_visual = captured_base.duplicate(true)
	malformed_visual.pockets[0].pocket_visual = []
	_check(not sync.valid_capture(malformed_visual), "present incomplete pocket presentation is rejected")
	var decoration = Node2D.new()
	pocket_parent.add_child(decoration)
	_check(
		sync._capture_pockets(game) == original,
		"unregistered scene child cannot shift the base pocket map"
	)
	var holes: Array = []
	for index in 10:
		var hole = _PocketCaptureStub.new()
		game.add_child(hole)
		hole.position = Vector2(120 + index * 10, 240)
		hole.scale = Vector2.ZERO if index == 0 else Vector2.ONE
		hole.multiplier = 4.0
		hole.extra_score = 17
		hole.shielded = true
		hole.held_balls.append(null)
		game.pockets.append(hole)
		holes.append(hole)
		if index == 0:
			_check(
				game.table.get_pockets().size() == 7,
				"blackhole fixture reproduces native table/game pocket Array alias"
			)
			var first_hole = state.duplicate(true)
			first_hole.pockets = sync._capture_pockets(game)
			_check(
				first_hole.pockets[6].base_index == -1 and sync.valid_capture(first_hole),
				"first blackhole captures as a valid dynamic pocket instead of base index six"
			)
	var expanded = state.duplicate(true)
	expanded.pockets = sync._capture_pockets(game)
	_check(sync.valid_capture(expanded), "all ten native blackholes preserve snapshot validity")
	_check(
		expanded.pockets.slice(0, 6) == original,
		"blackhole spawn never changes existing base pocket identities or state"
	)
	var layout = sync.pocket_ids(expanded)
	for index in 10:
		var captured = expanded.pockets[index + 6]
		var hole = holes[index]
		_check(
			(
				captured.id == hole.get_instance_id()
				and captured.base_index == -1
				and layout[captured.id] == -1
				and captured.position == hole.global_position
				and captured.scale == hole.scale
				and captured.multiplier == 4.0
				and captured.score == 17
				and captured.shielded
				and captured.has_held_balls
			),
			"blackhole retains authoritative identity, pose and pocket effects"
		)
	for hole in holes:
		game.pockets.erase(hole)
		hole.free()
	_check(
		sync._capture_pockets(game) == original and game.table.get_pockets().size() == 6,
		"native round cleanup returns capture to the six original pockets"
	)
	var remapped = state.duplicate(true)
	remapped.pockets = original.duplicate(true)
	remapped.pockets[0].base_index = 1
	remapped.pockets[1].base_index = 0
	_check(
		sync.pocket_ids(remapped) != sync.pocket_ids({"pockets": original}),
		"pocket topology identifies base role changes as well as new ids"
	)
	game.free()


class _ResultsStub:
	extends Node
	var during_apply: Callable

	func apply(_data: Dictionary) -> void:
		if during_apply.is_valid():
			during_apply.call()

	func clear() -> void:
		pass

	func end_session() -> void:
		pass


class _BallStub:
	extends Node
	var is_player = false
	var ball_item = null
	var visible = true
	var alive = true
	var spawned = true
	var falling = false


class _ReplicaStub:
	extends Node
	var replicas: Dictionary = {}
	var pocket_replicas: Dictionary = {}
	var corrections: Dictionary = {}
	var player_ball = null
	var selected_ball = null
	var applied: Array = []
	var native_ready = true
	var during_apply: Callable

	func can_shoot() -> bool:
		return native_ready

	func apply_table(data: Dictionary) -> void:
		if during_apply.is_valid():
			during_apply.call()
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


func _check_committed_readiness(sync: Node, state: Dictionary) -> void:
	var replica = _ReplicaStub.new()
	sync.add_child(replica)
	var results = _ResultsStub.new()
	sync.add_child(results)
	sync._guest = true
	sync._scene_key = "%s:%s" % [state.scene_id, state.rotated]
	sync._replica = replica
	sync._results = results
	sync._committed_context = {}
	var authority = {
		"available": true, "table_active": true, "can_shoot": true,
		"rounds_played": state.rounds_played, "round": state.round + 1
	}
	_check(not sync.ready_for_state(authority), "ready state waits for initial replica hydration")
	_check(sync.apply_snapshot(state) and sync.ready_for_state(authority), "complete play frame commits readiness for its matching one-based round")
	var mid_apply: Array = []
	replica.during_apply = func(): mid_apply.append(sync.ready_for_input())
	results.during_apply = func(): mid_apply.append(sync.ready_for_input())
	var next_round = state.duplicate(true)
	next_round.round += 1
	next_round.rounds_played += 1
	var next_authority = authority.duplicate(true)
	next_authority.round += 1
	next_authority.rounds_played += 1
	_check(not sync.ready_for_state(next_authority), "new reliable round cannot borrow the old native rack's readiness")
	_check(sync.apply_snapshot(next_round), "new ready round applies through production snapshot boundary")
	_check(mid_apply == [false, false], "table hydration and native results callbacks cannot observe half-committed readiness")
	_check(not sync.ready_for_state(authority) and sync.ready_for_state(next_authority), "only the fully committed round matches subsequent authority")
	for field in ["available", "table_active", "can_shoot"]:
		var blocked = next_authority.duplicate(true)
		blocked[field] = false
		_check(not sync.ready_for_state(blocked), "committed scene still obeys authoritative " + field)
	for field in ["in_menu", "in_shop", "round_ended", "game_over", "round_result_open", "pending", "finished"]:
		var blocked = next_authority.duplicate(true)
		blocked[field] = true
		_check(not sync.ready_for_state(blocked), "new authoritative phase closes readiness before scene arrival: " + field)
	var wrong_round = next_authority.duplicate(true)
	wrong_round.round = next_round.round
	_check(not sync.ready_for_state(wrong_round), "zero-based authority round is not mistaken for its one-based counterpart")
	var wrong_count = next_authority.duplicate(true)
	wrong_count.rounds_played += 1
	_check(not sync.ready_for_state(wrong_count), "same displayed level with another rounds-played epoch remains blocked")
	next_round.round += 5
	_check(sync.ready_for_state(next_authority), "committed readiness does not alias the caller's mutable snapshot")
	next_round.round -= 5
	for phase in ["payout", "shop", "ended"]:
		var transition = next_round.duplicate(true)
		transition.results.phase = phase
		_check(sync.apply_snapshot(transition) and not sync.ready_for_state(next_authority), "native-ready result frame never exposes aim during " + phase)
	_check(sync.apply_snapshot(next_round) and sync.ready_for_state(next_authority), "complete later play frame restores readiness without a timer")
	replica.native_ready = false
	_check(not sync.ready_for_state(next_authority), "native popup/settings readiness remains authoritative locally")
	replica.native_ready = true
	for field in ["visible", "alive", "spawned", "falling"]:
		replica.player_ball.set(field, field == "falling")
		_check(not sync.ready_for_state(next_authority), "cue must be physically eligible before input: " + field)
		replica.player_ball.set(field, field != "falling")
	for body in replica.replicas.values():
		if is_instance_valid(body):
			body.free()
	for pocket in replica.pocket_replicas.values():
		if is_instance_valid(pocket):
			pocket.free()
	var global_node = get_node("/root/Global")
	var original_game = global_node.gameManager
	sync._clear_replica()
	global_node.gameManager = original_game
	_check(sync._committed_context.is_empty() and not sync.ready_for_state(next_authority), "scene cleanup drops readiness and round context")
	sync._guest = false
	sync._results = null
	results.free()


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
	var brain = BallItem.new()
	brain.data = database.id_to_passive["GUMMY-BRAIN"]
	brain.set_copy_id("CRISPS")
	var cube = BallItem.new()
	cube.data = database.cubes[0]
	info.build.assign([ball, null, ball.duplicate(true)])
	info.build.resize(16)
	info.passives.assign([null, passive, brain, null])
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
	for value in [null, 17, false, "PLAYER", "res://injected.tres", "missing-passive", "A".repeat(129)]:
		var invalid_copy = with_inventory.duplicate(true)
		invalid_copy.inventory.passives[2].copy_id = value
		_check(not sync._valid_snapshot(invalid_copy), "invalid copied passive identity rejected: " + str(value))
	var invalid_copy = with_inventory.duplicate(true)
	invalid_copy.inventory.build[0]["copy_id"] = "CRISPS"
	_check(not sync._valid_snapshot(invalid_copy), "copied passive identity rejected on a ball inventory item")
	invalid_copy = with_inventory.duplicate(true)
	invalid_copy.inventory.passives[1].data = "CRISPS"
	invalid_copy.inventory.passives[1]["copy_id"] = "CRISPS"
	_check(not sync._valid_snapshot(invalid_copy), "copied identity rejected on a passive without native copy behavior")
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

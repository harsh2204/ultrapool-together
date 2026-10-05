extends Node

signal completed

const Effects = preload("../mod/table_effects_sync.gd")
const TableSync = preload("../mod/table_sync.gd")


class GameStub:
	extends Node
	var droplets: Array = []
	var energy_balls: Array = []
	var pockets: Array = []


class EnergyStub:
	extends Node2D
	var inited = true
	var linear_velocity = Vector2(120, -30)
	var alive = true
	var spawned = true
	var gone = false


class FxCaptureStub:
	extends Node
	var clears = 0

	func clear() -> void:
		clears += 1


var checks = 0
var failed = false
var embedded = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not embedded or not OS.get_user_data_dir().contains("UltrapoolTogetherRenderTest"):
		push_error("TABLE_EFFECTS_PROBE FAIL: embedded isolated render fixture required")
		get_tree().quit(1)
		return
	_check(Effects.valid(Effects.empty()), "empty authoritative effect state accepted")
	_check(not Effects.valid({}), "missing new envelope rejected at effect boundary")
	var state = Effects.empty()
	for kind in range(6):
		state.droplets.append(_drop(kind + 1, kind))
	state.energy.append(_energy(20))
	state.pockets.append(
		{"id": 30, "suction_scale": Vector2(4, 4), "suction_color": Color(0, 0, 0, 0.7)}
	)
	_check(Effects.valid(state), "all native floor families, energy trail, and wormhole accepted")
	_check(
		Effects.valid(bytes_to_var(var_to_bytes(state))),
		"wire roundtrip preserves typed effect state"
	)
	var changed = state.duplicate(true)
	changed.droplets[1].position += Vector2(1, 2)
	changed.droplets[1].charges = 0
	changed.energy[0].trails[0].points[0] += Vector2(4, 0)
	changed.pockets[0].suction_scale = Vector2.ONE
	_check(
		Effects.topology(changed) == Effects.topology(state),
		"motion and charges keep retained topology"
	)
	changed.droplets[1].kind = 4
	_check(
		Effects.topology(changed) != Effects.topology(state),
		"same identity changing kind forces reliable topology"
	)
	changed = state.duplicate(true)
	changed.energy.clear()
	_check(
		Effects.topology(changed) != Effects.topology(state),
		"projectile deletion forces reliable topology"
	)
	_check(Effects.topology({}).is_empty(), "legacy absent field has no effect topology")
	for reason in ["droplets", "bytes", "energy candidates"]:
		var over = Effects.overflow(reason)
		_check(Effects.valid(over), "explicit overflow accepted: " + reason)
		_check(
			Effects.topology(over) != Effects.topology(state),
			"overflow and recovery are reliable transitions: " + reason
		)
		_check(
			over.droplets.is_empty() and over.energy.is_empty(),
			"overflow carries no partial replacement: " + reason
		)
		var malformed = over.duplicate(true)
		malformed.droplets.append(_drop(1, 1))
		_check(not Effects.valid(malformed), "overflow cannot smuggle partial state: " + reason)
	_check_mutations(state)
	_check_capture_lifecycle()
	_check_bounded_layout()
	_check_combined_budget()
	_check_capture_epochs()
	_check_registry_overflow()
	_check_active_state(state)
	print("TABLE_EFFECTS_PROBE %s: %d checks passed" % ["FAIL" if failed else "PASS", checks])
	completed.emit()


func _check_mutations(state: Dictionary) -> void:
	for group in ["droplets", "energy", "pockets"]:
		var duplicate = state.duplicate(true)
		duplicate[group].append(duplicate[group][0].duplicate(true))
		_check(not Effects.valid(duplicate), "duplicate identity rejected in " + group)
	var bad = state.duplicate(true)
	bad.energy[0].id = bad.droplets[0].id
	_check(not Effects.valid(bad), "cross-family identity collision rejected")
	for mutation in [
		["kind", 6],
		["kind", 1.0],
		["texture_index", "res://injected.png"],
		["sprite_rotation", NAN],
		["scale", Vector2(INF, 1)],
		["visible", 1],
		["flower_power", 0],
		["flower_colors", [Color.WHITE]],
		["charges", -1],
		["direction", Vector2(INF, 0)],
		["held_ball_id", -1],
		["launch_timer", NAN],
		["script", "res://injected.gd"],
		["sprite_color", Color(1, 1, 1, 2)]
	]:
		bad = state.duplicate(true)
		bad.droplets[0][mutation[0]] = mutation[1]
		_check(not Effects.valid(bad), "malformed droplet rejected: " + str(mutation[0]))
	for mutation in [
		["index", 4],
		["points", [Vector2.ZERO]],
		["points", PackedVector2Array([Vector2(NAN, 0)])],
		["width", -1],
		["visible", "true"],
		["path", "../native_callback"]
	]:
		bad = state.duplicate(true)
		bad.energy[0].trails[0][mutation[0]] = mutation[1]
		_check(not Effects.valid(bad), "malformed trail rejected: " + str(mutation[0]))
	bad = state.duplicate(true)
	bad.energy[0].trails.append(bad.energy[0].trails[0].duplicate(true))
	_check(not Effects.valid(bad), "duplicate trail indices rejected")
	bad = state.duplicate(true)
	bad.energy[0].trails[0].points.resize(Effects.MAX_TRAIL_POINTS + 1)
	_check(not Effects.valid(bad), "oversized trail rejected")
	bad = state.duplicate(true)
	bad.pockets[0].suction_scale = Vector2(-1, 1)
	_check(not Effects.valid(bad), "negative wormhole suction scale rejected")
	for group in ["droplets", "energy", "pockets"]:
		bad = state.duplicate(true)
		bad[group].resize(257)
		_check(not Effects.valid(bad), "oversized collection rejected before traversal: " + group)
	bad = state.duplicate(true)
	bad.version = 2
	_check(not Effects.valid(bad), "unknown effect schema version rejected")
	bad = Effects.overflow("bytes")
	bad.reason = "unbounded external reason"
	_check(not Effects.valid(bad), "unrecognized overflow reason rejected")


func _check_capture_lifecycle() -> void:
	var game = GameStub.new()
	add_child(game)
	var body = EnergyStub.new()
	var visuals = Node2D.new()
	visuals.name = "visuals"
	body.add_child(visuals)
	var sphere = Sprite2D.new()
	sphere.name = "ball"
	sphere.visible = false
	visuals.add_child(sphere)
	var transform = Node3D.new()
	transform.name = "transform3d"
	body.add_child(transform)
	var trail = Line2D.new()
	trail.name = "Trail"
	trail.points = PackedVector2Array([Vector2(1, 2), Vector2(3, 4)])
	trail.modulate = Color(0.25, 0.5, 1, 0.75)
	body.add_child(trail)
	game.add_child(body)
	body.position = Vector2(100, 200)
	game.energy_balls.append(body)
	var first = Effects.capture(game)
	_check(
		Effects.valid(first) and first.energy.size() == 1,
		"capture registers a native-like projectile"
	)
	if first.energy.size() == 1:
		_check(not first.energy[0].sphere_visible, "capture preserves hidden native sphere")
		_check(
			first.energy[0].trails[0].points[0] == trail.to_global(Vector2(1, 2)),
			"trail coordinates are captured in host world space"
		)
		_check(first.energy[0].trails[0].color == trail.modulate, "trail preserves host modulation")
	body.alive = false
	body.spawned = false
	body.gone = true
	game.energy_balls.clear()
	var retired = Effects.capture(game)
	_check(
		retired.energy.size() == 1 and not retired.energy[0].alive,
		"native unalive array removal retains existing visual tail"
	)
	var dead_id = body.get_instance_id()
	body.free()
	var cleared = Effects.capture(game)
	_check(cleared.energy.is_empty(), "actual native deletion removes retained weak reference")
	_check(
		not Effects.topology(cleared).has("e:%d" % dead_id),
		"tail deletion removes topology identity"
	)
	game.droplets.resize(Effects.MAX_SCAN_DROPLETS + 1)
	var over = Effects.capture(game)
	_check(
		Effects.valid(over) and over.status == "overflow" and over.reason == "droplet candidates",
		"oversized candidate array yields explicit bounded recovery state"
	)
	game.droplets.clear()
	_check(
		Effects.capture(game).status == "complete",
		"capture recovers when candidate overflow clears"
	)
	game.free()
	var next_game = GameStub.new()
	add_child(next_game)
	_check(
		Effects.capture(next_game).energy.is_empty(),
		"new scene cannot inherit projectile identities"
	)
	next_game.free()


func _check_bounded_layout() -> void:
	var fixture = Node.new()
	var branch = Node2D.new()
	fixture.add_child(branch)
	var first = Line2D.new()
	branch.add_child(first)
	var second = Line2D.new()
	fixture.add_child(second)
	_check(
		Effects.line_nodes(fixture) == [first, second],
		"trail prefab indices use deterministic depth-first order"
	)
	for index in range(Effects.MAX_TRAILS):
		fixture.add_child(Line2D.new())
	_check(
		Effects.line_nodes(fixture) == null,
		"unsupported trail count never returns a partial layout"
	)
	fixture.free()
	fixture = Node.new()
	for index in range(Effects.MAX_TRAIL_NODES + 1):
		fixture.add_child(Node.new())
	_check(Effects.line_nodes(fixture) == null, "prefab discovery rejects oversized child fanout")
	fixture.free()


func _check_combined_budget() -> void:
	# Synthetic encoded payloads isolate aggregate envelope sizing from family
	# validation; the production caller builds descriptors before this boundary.
	var state = {
		"balls": ["rack"],
		"effects": Effects.empty(),
		"visual_fx": {"payload": "x".repeat(TableSync.MAX_TABLE_CAPTURE_BYTES)}
	}
	TableSync._limit_effect_payload(state)
	_check(
		state.visual_fx.status == "overflow" and state.effects.status == "complete",
		"combined packet pressure defers transient effects first"
	)
	_check(state.balls == ["rack"], "aggregate overflow preserves authoritative rack")
	state = {
		"balls": ["rack"],
		"effects": {"payload": "x".repeat(TableSync.MAX_TABLE_CAPTURE_BYTES)},
		"visual_fx": {}
	}
	TableSync._limit_effect_payload(state)
	_check(
		Effects.valid(state.effects) and state.effects.status == "overflow",
		"oversized durable payload becomes explicit overflow without losing table"
	)
	_check(
		var_to_bytes(state).size() < TableSync.MAX_TABLE_CAPTURE_BYTES,
		"effect budget fallback fits aggregate table budget"
	)


	state = {
		"balls": [{"id": 42, "item": {"data": "APPLE"}, "ball_visual": {"payload": "x".repeat(TableSync.MAX_TABLE_CAPTURE_BYTES)}}],
		"effects": Effects.empty(), "visual_fx": {}, "native_draw": {}
	}
	TableSync._limit_effect_payload(state)
	_check(state.get("ball_visual_status") == "overflow", "ball presentation overflow is explicit")
	_check(state.balls.size() == 1 and state.balls[0].id == 42 and state.balls[0].item.data == "APPLE", "ball presentation overflow preserves live identity and item")
	_check(not state.balls[0].has("ball_visual") and var_to_bytes(state).size() < TableSync.MAX_TABLE_CAPTURE_BYTES, "optional ball presentation yields before rack state")
	state = {
		"balls": [{"id": 42}],
		"pockets": [{"id": 9, "base_index": 0, "mult": 2.0, "pocket_visual": [{"payload": "x".repeat(TableSync.MAX_TABLE_CAPTURE_BYTES)}]}],
		"effects": Effects.empty(), "visual_fx": {}, "native_draw": {}
	}
	TableSync._limit_effect_payload(state)
	_check(state.get("pocket_visual_status") == "overflow", "pocket presentation overflow is explicit")
	_check(state.pockets[0].id == 9 and state.pockets[0].base_index == 0 and state.pockets[0].mult == 2.0, "pocket presentation overflow preserves identity and scoring")
	_check(not state.pockets[0].has("pocket_visual") and var_to_bytes(state).size() < TableSync.MAX_TABLE_CAPTURE_BYTES, "optional pocket presentation yields before authoritative state")
	_check(TableSync._active_effect_state(state), "pocket presentation overflow schedules recovery")


func _check_capture_epochs() -> void:
	var sync = TableSync.new()
	var visual = FxCaptureStub.new()
	sync._visual_fx_capture = visual
	var first = GameStub.new()
	var second = GameStub.new()
	first.set_meta("together_effect_energy", {})
	second.set_meta("together_effect_energy", {})
	sync._prepare_effect_capture(first)
	_check(
		visual.clears == 0, "first table capture preserves already-registered native visual effects"
	)
	sync._prepare_effect_capture(second)
	_check(
		not first.has_meta("together_effect_energy"),
		"new scene clears previous durable identity cache"
	)
	_check(
		visual.clears == 0,
		"scene change delegates visual epoch handling without erasing startup effects"
	)
	sync._effects_were_active = true
	sync.clear_effect_capture()
	_check(
		(
			visual.clears == 1
			and not sync._effects_were_active
			and not second.has_meta("together_effect_energy")
		),
		"explicit teardown clears both effect families and scheduler hint"
	)
	first.free()
	second.free()
	visual.free()
	sync.free()


func _check_registry_overflow() -> void:
	var game = GameStub.new()
	add_child(game)
	var container = Node2D.new()
	container.name = "Balls"
	game.add_child(container)
	for index in 33:
		var body = EnergyStub.new()
		body.inited = false
		container.add_child(body)
		game.energy_balls.append(body)
	_check(
		Effects.capture(game).status == "complete",
		"initial bounded registry captures initializing energy identities"
	)
	game.energy_balls.clear()
	for index in 32:
		var body = EnergyStub.new()
		body.inited = false
		container.add_child(body)
		game.energy_balls.append(body)
	_check(
		Effects.capture(game).status == "overflow",
		"active plus retiring energy exceeds bounded registry explicitly"
	)
	_check(
		game.get_meta("together_effect_energy").size() <= Effects.MAX_SCAN_ENERGY,
		"overflow does not grow or discard the bounded prior registry"
	)
	_check(
		Effects.capture(game).status == "overflow",
		"recovery cannot silently omit still-live retiring projectiles"
	)
	container.get_child(0).free()
	_check(
		Effects.capture(game).status == "complete",
		"bounded native container rebuild recovers after real removal"
	)
	_check(
		game.get_meta("together_effect_energy").size() == Effects.MAX_SCAN_ENERGY,
		"recovery retains every remaining known or active identity"
	)
	Effects.clear(game)
	_check(
		not game.has_meta("together_effect_energy_recovery"),
		"teardown clears overflow recovery latch"
	)
	game.free()


func _check_active_state(state: Dictionary) -> void:
	_check(
		TableSync._active_effect_state({"effects": state}),
		"settled table continues publishing live durable effects"
	)
	var empty = Effects.empty()
	empty.pockets.append(
		{"id": 1, "suction_scale": Vector2.ONE, "suction_color": Color.TRANSPARENT}
	)
	_check(
		not TableSync._active_effect_state({"effects": empty}),
		"final empty effect state releases fast scheduler hint"
	)
	empty.pockets[0].suction_scale = Vector2(2, 2)
	_check(
		TableSync._active_effect_state({"effects": empty}),
		"wormhole decay keeps settled-table presentation active"
	)
	_check(
		TableSync._active_effect_state({"visual_fx": {"items": [1]}}),
		"transient effects keep settled-table presentation active"
	)
	_check(
		TableSync._active_effect_state({"effects": Effects.overflow("bytes")}),
		"overflow keeps scheduler active for recovery"
	)


func _pose(id: int) -> Dictionary:
	return {
		"id": id,
		"position": Vector2(100, 200),
		"rotation": 0.2,
		"scale": Vector2.ONE,
		"color": Color.WHITE,
		"visible": true
	}


func _drop(id: int, kind: int) -> Dictionary:
	var value = _pose(id)
	value.merge(
		{
			"kind": kind,
			"texture_index": kind,
			"sprite_rotation": 0.3,
			"sprite_color": Color.WHITE,
			"sprite_flip_h": true,
			"shadow_rotation": 0.3,
			"shadow_visible": true,
			"flower_rotation": 0.7,
			"flower_power": 4,
			"flower_colors": [Color.RED, Color.GREEN, Color.BLUE],
			"charges": 4,
			"direction": Vector2.RIGHT,
			"held_ball_id": 0,
			"launch_timer": 0.8
		}
	)
	return value


func _energy(id: int) -> Dictionary:
	var value = _pose(id)
	value.merge(
		{
			"velocity": Vector2(100, -50),
			"visual_scale": Vector2.ONE,
			"spin": Vector3(0.2, 0.5, 0.7),
			"alive": true,
			"spawned": true,
			"gone": false,
			"sphere_visible": false,
			"trails":
			[
				{
					"index": 0,
					"points": PackedVector2Array([Vector2(100, 200), Vector2(99, 202)]),
					"visible": true,
					"color": Color.WHITE,
					"width": 4.0
				}
			]
		}
	)
	return value


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("TABLE_EFFECTS_PROBE PASS: " + description)
	else:
		failed = true
		push_error("TABLE_EFFECTS_PROBE FAIL: " + description)

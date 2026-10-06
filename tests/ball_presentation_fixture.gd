extends RefCounted
## Real native setters -> production capture -> production guest / watcher apply.
## Exercises removal and score thresholds without rebuilding the retained item.

const Visual = preload("../mod/ball_visual_state.gd")
const LevelFx = preload("../mod/ball_level_fx.gd")
const WatchFixture = preload("native_table_effects_fixture.gd")
var _active: Dictionary = {}
var _reset: Dictionary = {}
var _expected_active: Dictionary = {}
var _expected_reset: Dictionary = {}


func check_host(mod: Node, game: Node, record: Callable, capture: Callable) -> void:
	var settings = mod.get_node("/root/SettingsManager")
	var disabled: bool = settings.disable_particles
	settings.disable_particles = false
	var item = game.balls[0].ball_item.duplicate(true)
	item.set_data(mod.get_node("/root/BallDatabase").id_to_ball["SPIRIT"])
	var body = game.spawn_ball_from_item(item, "setup", Vector2(-100, 80), 0)
	if not record.call(is_instance_valid(body), "ball presentation: native donor spawns"):
		settings.disable_particles = disabled
		return
	body.freeze = true
	body.set_physics_process(false)
	body.set_process(false)
	body.ball_item.base_score = 45
	body.ball_item.temp_extra_score = 0
	body.update_score_label()
	body.set_star(true)
	body.set_flame(true)
	body.set_shield(true)
	body.set_level(3)
	body.set_weight(BallItem.WEIGHT_LEVEL.HEAVY)
	body.set_locked(true)
	body.set_fleeting()
	body.flash()
	body._process(0.01)
	body.size_process(1.0)
	body.set_process(false)
	_active = _captured_ball(mod, body)
	_expected_active = _inspect(body)
	record.call(not Visual._equal_value(Color.WHITE, Vector4(0.3, 0.3, 0.3, 1.0)) and Visual._equal_value(Color.WHITE, Vector4.ONE), "ball presentation: sparse shader comparison distinguishes changed native Color from packed vec4")
	record.call(not _active.is_empty(), "ball presentation: production capture includes donor")
	record.call(Visual.problem(_active.get("ball_visual", {})).is_empty(), "ball presentation: native sparse fields validate")
	record.call(_expected_active.fire and _expected_active.star and _expected_active.particles and _expected_active.outline, "ball presentation: native flame/star/high-score effects are active")
	record.call(_expected_active.spark and _expected_active.alpha == 0.75, "ball presentation: native upgrade and fleeting opacity are active")
	print("BALL_PRESENTATION_BYTES ", var_to_bytes(_active.get("ball_visual", {})).size())
	await capture.call("19-host-ball-presentation", "Host · native star, flame, high score, upgrade and fleeting ball")
	# Native has no inverse set_fleeting API. This production presentation inverse
	# clears exactly its edge/opacity changes while retaining the native item.
	LevelFx.set_fleeting(body, false)
	body.ball_item.base_score = 5
	body.update_score_label()
	body.set_flame(false)
	body.set_shield(false)
	body.set_shield_broken(true)
	body.set_locked(false)
	_reset = _captured_ball(mod, body)
	_expected_reset = _inspect(body)
	record.call(not _expected_reset.particles and not _expected_reset.outline and _expected_reset.alpha == 1.0, "ball presentation: native low score and fleeting cleanup captured")
	mod.get_node("/root/GlobalPhysics").unregister_ball(body)
	mod.get_node("/root/Global").eventManager.unregister_ball(body)
	for field in ["balls", "active_balls", "active_balls_include_untargetable", "pocketed_balls"]:
		game.get(field).erase(body)
	body.queue_free()
	settings.disable_particles = disabled
	await mod.get_tree().process_frame


func check_guest(mod: Node, baseline: Dictionary, record: Callable, capture: Callable) -> void:
	if not record.call(not _active.is_empty() and not _reset.is_empty(), "ball presentation: host captures available"):
		return
	var active = _packet(baseline, _active)
	var reset = _packet(baseline, _reset)
	var game = mod.get_node("/root/Global").gameManager
	var protected = [game.score, game.player_info.money]
	record.call(mod.table_sync.apply_snapshot(active), "ball presentation: guest accepts native state")
	var body = game.replicas[_active.id]
	body.set_process(false)
	_check_appearance(body, _expected_active, record, "guest active")
	var retained_item = body.ball_item
	var retained_material = body.ball.material
	var retained_body = body.get_instance_id()
	var full: int = game.apply_stats.full_items
	record.call(mod.table_sync.apply_snapshot(active), "ball presentation: duplicate accepted")
	record.call(game.apply_stats.full_items == full, "ball presentation: unchanged state avoids full item setup")
	await capture.call("37-guest-ball-presentation", "Guest · retained native ball presentation")
	record.call(mod.table_sync.apply_snapshot(reset), "ball presentation: removal and lower score accepted")
	_check_appearance(body, _expected_reset, record, "guest reset")
	record.call(body.ball_item == retained_item and body.ball.material == retained_material and body.get_instance_id() == retained_body and game.apply_stats.full_items == full, "ball presentation: score and fleeting removal retain body item and material")
	record.call(not body.ball_item.fleeting, "ball presentation: fleeting false reaches retained native item")
	record.call(not body.ball_item.locked and not body.is_locked(), "ball presentation: lock removal reaches native item without achievements")
	record.call(not body.ball_item.shielded and body.ball_item.shield_broken, "ball presentation: broken-shield setter guard cannot retain obsolete shield flag")
	var before_rejection = _inspect(body)
	var malformed = active.duplicate(true)
	malformed.balls.back().ball_visual.d.append([-1, NAN])
	record.call(not mod.table_sync.apply_snapshot(malformed), "ball presentation: malformed field rejected before mutation")
	record.call(_inspect(body) == before_rejection, "ball presentation: malformed state preserves current appearance")
	var wrong_color = _invalid_field(active, "visuals", "modulate", Vector4.ONE)
	record.call(not mod.table_sync.apply_snapshot(wrong_color), "ball presentation: typed CanvasItem color rejects shader-only vec4 compatibility")
	var excessive_particles = _invalid_field(active, "visuals/static/score_effects/score_particles", "amount", 11)
	record.call(not mod.table_sync.apply_snapshot(excessive_particles), "ball presentation: particle capacity cannot exceed native score cap")
	record.call(_inspect(body) == before_rejection, "ball presentation: rejected color and capacity retain appearance")
	record.call([game.score, game.player_info.money] == protected, "ball presentation: drawing does not award score or money")
	await _check_spectator(mod, active, reset, record, capture)
	mod.table_sync.apply_snapshot(baseline)
	record.call(not game.replicas.has(_active.id), "ball presentation: authoritative removal disposes donor")


func _check_spectator(mod: Node, active: Dictionary, reset: Dictionary, record: Callable, capture: Callable) -> void:
	var controller = WatchFixture.WatchController.new()
	controller.ui_root = mod.ui_root
	controller.skin = mod.skin
	mod.add_child(controller)
	var watcher = preload("../mod/table_spectator.gd").new()
	controller.add_child(watcher)
	watcher.setup(controller)
	watcher.watch(1)
	var displayed = active.duplicate(true)
	displayed.results.game_time = 125.0
	displayed.shots_max = 5
	displayed.shots_used = 3
	displayed.shots = 2
	watcher.apply_snapshot(1, displayed)
	watcher.tick(0.0)
	record.call(watcher._status.text.contains("2/5 shots") and watcher._status.text.contains("3 used") and watcher._status.text.contains("02:05"), "ball presentation: watcher shows remaining maximum spent and elapsed time")
	record.call(watcher._ui_nodes.pips.get_child_count() == 2, "ball presentation: watcher native pips match remaining shots")
	var pip_id = watcher._ui_nodes.pips.get_child(0).get_instance_id()
	watcher.apply_snapshot(1, displayed)
	watcher.tick(0.0)
	record.call(watcher._ui_nodes.pips.get_child(0).get_instance_id() == pip_id, "ball presentation: unchanged watcher HUD retains native shot pips")
	var body = watcher._balls[_active.id].node
	_check_appearance(body, _expected_active, record, "spectator active")
	record.call(body.get_script() == null, "ball presentation: spectator retains no native ball callbacks")
	record.call(body.get_node("visuals/static/StarEffect").can_process() and body.get_node("visuals/static/score_effects/score_particles").can_process(), "ball presentation: spectator particle ancestors allow actual emission")
	var node_id = body.get_instance_id()
	var material = watcher._balls[_active.id].sphere.material
	await capture.call("38-spectator-ball-presentation", "Spectator · native flame, particles, star, upgrade and fleeting opacity")
	watcher.apply_snapshot(1, reset)
	watcher._frames = [watcher._frames.back()]
	watcher.tick(0.0)
	_check_appearance(body, _expected_reset, record, "spectator reset")
	record.call(body.get_instance_id() == node_id and watcher._balls[_active.id].sphere.material == material, "ball presentation: spectator status removal retains nodes and material")
	watcher.watch(2)
	record.call(watcher._balls.is_empty(), "ball presentation: watcher switch clears all ball presentation")
	watcher.close()
	controller.queue_free()


func _captured_ball(mod: Node, body: Node) -> Dictionary:
	for state in mod.table_sync.capture().get("balls", []):
		if state.id == body.get_instance_id():
			return state.duplicate(true)
	return {}


func _packet(baseline: Dictionary, state: Dictionary) -> Dictionary:
	var result = baseline.duplicate(true)
	result.balls.append(state.duplicate(true))
	return result


func _inspect(body: Node) -> Dictionary:
	var visuals = body.get_node("visuals")
	var effects = visuals.get_node("static/score_effects")
	var particles = effects.get_node("score_particles")
	var outline = effects.get_node("outline")
	var edge = visuals.get_node("static/edge")
	var spark = visuals.get_node("static/spark")
	return {
		"fire": visuals.get_node("static/FireEffect").visible,
		"star": visuals.get_node("static/StarEffect").visible,
		"particles": particles.visible and particles.emitting and effects.visible,
		"amount": particles.amount,
		"outline": outline.visible and effects.visible,
		"radius": outline.material.get_shader_parameter("radius2"),
		"spark": spark.visible,
		"texture": spark.texture,
		"alpha": visuals.modulate.a,
		"edge_color": edge.material.get_shader_parameter("color"),
		"edge_selection": _shader_color(edge.material.get_shader_parameter("selout_color")),
		"shield": visuals.get_node("static/shield_indicator").visible,
		"broken": visuals.get_node("static/shield_broken_indicator").visible
	}


func _check_appearance(body: Node, expected: Dictionary, record: Callable, label: String) -> void:
	var actual = _inspect(body)
	for key in expected:
		if actual[key] != expected[key]:
			print("BALL_PRESENTATION_MISMATCH ", label, " ", key, " actual=", actual[key], " expected=", expected[key])
		record.call(actual[key] == expected[key], "ball presentation: " + label + " native " + key)


func _shader_color(value) -> Color:
	# Packed vec4 and native Color setter values describe the same RGBA uniform.
	return Color(value.x, value.y, value.z, value.w) if value is Vector4 else value


func _invalid_field(packet: Dictionary, path: String, property: String, value) -> Dictionary:
	var result = packet.duplicate(true)
	var state: Dictionary = result.balls.back().ball_visual
	var fields: Array = Visual._layouts[state.p]
	for index in fields.size():
		if fields[index][0] != path or fields[index][1] != property:
			continue
		var replaced = false
		for entry in state.d:
			if entry[0] == index:
				entry[1] = value
				replaced = true
		if not replaced:
			state.d.append([index, value])
		state.d.sort_custom(func(left, right): return left[0] < right[0])
		break
	return result

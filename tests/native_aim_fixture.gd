extends RefCounted

const CueCatalog = preload("../mod/cue_catalog.gd")

var _pointer_viewport: SubViewport

class AimPresence:
	extends Node
	var aim: Dictionary = {}

	func remote_aim(_actor: int) -> Dictionary:
		return aim


class LocalIdentity:
	extends Node

	func local_id() -> int:
		return 1


class ShotSink:
	extends Node
	var allowed = true
	var submitted: Array[Vector2] = []
	var presence: Node
	var transport: Node
	var turn_owner = 0

	func can_control() -> bool:
		return allowed

	func submit_shot(vector: Vector2) -> bool:
		submitted.append(vector)
		return true


## Exercise the inherited mouse-start path without spending a shot or moving balls.
## The sink replaces only controller authority/submission; native game.can_shoot()
## and the actual native_player input/process methods still run for host and guest.
func check(mod: Node, game: Node, role: String, record: Callable, capture: Callable) -> void:
	var ball = game.player_ball
	if not is_instance_valid(ball) or not ball.has_method("together_play_shot"):
		record.call(false, role + " mouse aim: hooked cue ball exists")
		return
	var settings = mod.get_node("/root/SettingsManager")
	var input_manager = mod.get_node("/root/InputManager")
	var saved = {
		"controller": ball.together_controller,
		"process": ball.is_processing(),
		"adapter_process": mod.adapter.is_processing(),
		"in_menu": game.in_menu,
		"playing": game.playing,
		"shot_mode": settings.shot_mode,
		"confirmation": settings.shoot_confirmation,
		"input_mode": input_manager.mode
	}
	var sink = ShotSink.new()
	var presence = AimPresence.new()
	var identity = LocalIdentity.new()
	sink.presence = presence
	sink.transport = identity
	var saved_cue: String = str(ball.get_meta("together_cue_id", "native"))
	mod.adapter.set_process(false)
	ball.set_process(false)
	ball.together_controller = sink
	settings.shot_mode = settings.SHOT_MODES.FAST
	settings.shoot_confirmation = false
	game.in_menu = false
	ball.pause_cancel_shot()
	# Window mouse queries read the desktop pointer even after push_input().
	# Use the same isolated SubViewport pointer seam as shop_input_fixture, while
	# keeping the real native cue ball, world and inherited input/process methods.
	var original_parent: Node = ball.get_parent()
	var original_index: int = ball.get_index()
	var original_transform: Transform2D = ball.transform
	var original_viewport: Viewport = ball.get_viewport()
	var resize_connections: Array = []
	for connection in original_viewport.size_changed.get_connections():
		var target_node = connection.callable.get_object()
		if target_node == ball or (target_node is Node and ball.is_ancestor_of(target_node)):
			resize_connections.append(connection)
	_pointer_viewport = SubViewport.new()
	_pointer_viewport.size = mod.get_viewport().get_visible_rect().size
	_pointer_viewport.world_2d = ball.get_world_2d()
	mod.add_child(_pointer_viewport)
	_pointer_viewport.canvas_transform = mod.get_viewport().get_canvas_transform()
	_reparent_ball(mod, ball, _pointer_viewport)
	# Native CustomButton disconnects on exit but connects only on first ready.
	# Transfer those existing bindings, just as the shop input fixture does.
	for connection in resize_connections:
		if not _pointer_viewport.size_changed.is_connected(connection.callable):
			_pointer_viewport.size_changed.connect(connection.callable, connection.flags)
	var start: Vector2 = ball.get_global_transform_with_canvas().origin
	var target = start - Vector2(120, 0)
	await _button(mod, start, false)
	await mod.get_tree().process_frame
	ball._process(1.0 / 30.0)
	var pivot = ball.get_node_or_null("CuePivot")
	var cue = ball.get_node_or_null("CuePivot/Cue")
	record.call(pivot != null and not pivot.visible, role + " mouse aim: idle cue stays hidden")
	var idle_alpha: float = pivot.modulate.a
	CueCatalog.apply(ball, "coral")
	record.call(
		not pivot.visible and is_zero_approx(cue.modulate.a)
		and is_equal_approx(pivot.modulate.a, idle_alpha),
		role + " mouse aim: idle cosmetic reconciliation cannot reveal cue"
	)
	record.call(game.can_shoot() and game.has_shots(), role + " mouse aim: native table ready")

	await _button(mod, start, true)
	ball._process(1.0 / 30.0)
	record.call(
		ball.holding_shot and ball.preparing_shot,
		role + " mouse aim: first click starts aiming from idle"
	)
	await mod.get_tree().process_frame
	_motion(mod, target)
	ball._process(1.0 / 30.0)
	record.call(
		_pointer_viewport.get_mouse_position().is_equal_approx(target),
		role + " mouse aim: injected pointer reaches native viewport polling"
	)
	record.call(
		ball.shot is Vector2 and ball.shot.length() > 50.0 and pivot.visible,
		role + " mouse aim: held pointer motion charges and reveals cue"
	)
	var short_pullback: float = cue.position.x
	_motion(mod, start - Vector2(160, 0))
	ball._process(1.0 / 30.0)
	record.call(
		cue.position.x < short_pullback,
		role + " mouse aim: stronger native charge pulls the cue farther back"
	)
	var aiming_alpha: float = pivot.modulate.a
	var aiming_pose: Transform2D = cue.transform
	CueCatalog.apply(ball, "gold")
	record.call(
		cue.transform == aiming_pose and is_equal_approx(pivot.modulate.a, aiming_alpha),
		role + " mouse aim: cosmetic reconciliation preserves native pose and fade"
	)
	await _button(mod, target, false)
	ball._process(1.0 / 30.0)
	await mod.get_tree().process_frame
	ball._process(1.0 / 30.0)
	record.call(
		sink.submitted.size() == 1 and sink.submitted[0].length() > 50.0,
		role + " mouse aim: release submits exactly one shot intent"
	)
	record.call(
		not ball.preparing_shot and not ball.holding_shot and not pivot.visible,
		role + " mouse aim: completed intent clears aiming and parked cue"
	)
	sink.allowed = false
	sink.turn_owner = 2
	presence.aim = {"aiming": true, "vector": Vector2(120, 0)}
	ball._process(1.0 / 30.0)
	record.call(
		pivot.visible and pivot.global_position.is_equal_approx(ball.global_position),
		role + " mouse aim: teammate cue remains attached to cue ball"
	)
	for frame in range(3):
		ball._process(1.0 / 30.0)
	record.call(
		pivot.modulate == Color.WHITE,
		role + " mouse aim: teammate cue keeps neutral parent color across native fades"
	)
	game.in_menu = true
	ball._process(1.0 / 30.0)
	record.call(not pivot.visible, role + " mouse aim: menu hides even a cached teammate aim")
	game.in_menu = false
	presence.aim = {}
	ball._process(1.0 / 30.0)
	record.call(not pivot.visible, role + " mouse aim: stale teammate aim leaves no parked cue")
	await _check_prediction(mod, game, ball, sink, role, record, capture)

	for blocked in ["off turn", "native menu"]:
		sink.allowed = blocked != "off turn"
		game.in_menu = blocked == "native menu"
		await _button(mod, start, true)
		ball._process(1.0 / 30.0)
		record.call(
			game.in_menu == (blocked == "native menu"),
			role + " mouse aim: " + blocked + " preserves native menu state"
		)
		record.call(
			not ball.holding_shot and not ball.preparing_shot,
			role + " mouse aim: " + blocked + " prevents aim startup"
		)
		await _button(mod, target, false)
		ball._process(1.0 / 30.0)
		record.call(sink.submitted.size() == 1, role + " mouse aim: " + blocked + " cannot submit")
	ball.pause_cancel_shot()
	CueCatalog.apply(ball, saved_cue)
	ball.together_controller = saved.controller
	game.in_menu = saved.in_menu
	game.playing = saved.playing
	settings.shot_mode = saved.shot_mode
	settings.shoot_confirmation = saved.confirmation
	input_manager._set_mode(saved.input_mode)
	_reparent_ball(mod, ball, original_parent)
	original_parent.move_child(ball, original_index)
	ball.transform = original_transform
	for connection in resize_connections:
		if not original_viewport.size_changed.is_connected(connection.callable):
			original_viewport.size_changed.connect(connection.callable, connection.flags)
	_pointer_viewport.queue_free()
	_pointer_viewport = null
	ball.set_process(saved.process)
	mod.adapter.set_process(saved.adapter_process)
	sink.free()
	presence.free()
	identity.free()


## PERF-027/029: use the installed raycaster and the current rack, then compare
## real local mouse aiming with the production off-turn predictor on that board.
## Freezing the existing bodies prevents incidental contacts during gallery waits;
## no balls, wall shapes, physics singleton or final line geometry are replaced.
func _check_prediction(
	mod: Node, game: Node, ball: Node, sink: ShotSink, role: String,
	record: Callable, capture: Callable
) -> void:
	var physics = mod.get_node("/root/GlobalPhysics")
	var bodies: Array = game.balls.duplicate()
	if not bodies.has(ball):
		bodies.append(ball)
	var frozen: Array = []
	for body in bodies:
		frozen.append({"body": body, "freeze": body.freeze, "physics": body.is_physics_processing()})
		body.freeze = true
		body.set_physics_process(false)
	var before: Dictionary = _gameplay_state(game, physics, bodies)
	var submissions: int = sink.submitted.size()
	var predictor: Node = ball.prediction
	var retained: Array = _prediction_ids(predictor)
	var cases: Array = _prediction_cases(game, physics, ball)
	record.call(cases.size() == 3, role + " native prediction: existing rack supplies direct, glancing and empty wall-bounce rays")
	for sample in cases:
		var label: String = role + " native prediction " + sample.name
		sink.presence.aim = {}
		sink.allowed = true
		sink.turn_owner = 1
		ball.pause_cancel_shot()
		await _aim_mouse(mod, ball, sample.vector)
		var vector: Vector2 = ball.shot if ball.shot is Vector2 else Vector2.ZERO
		var ray: Array = physics.raycast(ball.global_position, vector.normalized(), null)
		record.call(
			ball.holding_shot and ball.preparing_shot and vector.is_equal_approx(sample.vector),
			label + ": real mouse input owns the requested native aim"
		)
		record.call(ray[0] == sample.hit, label + ": native raycast reaches the expected ball or empty rail")
		var local: Dictionary = _prediction_state(predictor)
		record.call(local.visible and local.lines[0].visible, label + ": local native prediction is visible")
		if sample.hit != null:
			var hit_line: Dictionary = local.lines[3]
			record.call(
				local.lines[2].visible and hit_line.visible
				and hit_line.points[0].distance_to(hit_line.points[1]) > 1.0
				and float(hit_line.length) > 1.0,
				label + ": native collision produces a visible struck-ball direction"
			)
		else:
			record.call(
				ray[2].size() >= 3 and local.lines[1].visible
				and not local.lines[2].visible and not local.lines[3].visible,
				label + ": empty rail bounce keeps both primary segments and clears hit paths"
			)
		# A cached teammate vector must never override the local native drag.
		sink.presence.aim = {"aiming": true, "vector": -vector}
		ball._process(1.0 / 30.0)
		record.call(
			ball.holding_shot and ball.preparing_shot and ball.shot.is_equal_approx(vector),
			label + ": local owner retains input despite cached remote aim"
		)
		_compare_prediction(local, _prediction_state(predictor), record, label + " local ownership")
		if sample.name == "glancing hit":
			await capture.call(
				("10" if role == "host" else "31") + "-" + role + "-native-aim-hit",
				role.capitalize() + " local turn · native collision line and struck-ball direction from mouse input"
			)
		# Cancel before release: the real input path is exercised without spending
		# a native shot or using the authority sink to simulate gameplay.
		ball.pause_cancel_shot()
		sink.allowed = false
		sink.turn_owner = 2
		sink.presence.aim = {"aiming": true, "vector": vector}
		await _button(mod, _pointer_viewport.get_mouse_position(), false)
		ball._process(1.0 / 30.0)
		_compare_prediction(local, _prediction_state(predictor), record, label + " teammate parity")
		for frame in range(3):
			ball._process(1.0 / 30.0)
		_compare_prediction(local, _prediction_state(predictor), record, label + " retained parity")
		record.call(_prediction_ids(predictor) == retained, label + ": remote updates retain native nodes and materials")
		record.call(
			not ball.preparing_shot and not ball.holding_shot and ball.get_shot() == null
			and sink.submitted.size() == submissions,
			label + ": visual replay cannot own input or submit a shot"
		)
		if sample.name == "glancing hit":
			await capture.call(
				("10" if role == "host" else "31") + "-" + role + "-teammate-aim-hit",
				role.capitalize() + " off turn · the same native hit prediction from teammate presence"
			)
		game.in_menu = true
		ball._process(1.0 / 30.0)
		_check_prediction_hidden(ball, record, label + " menu")
		game.in_menu = false
		ball._process(1.0 / 30.0)
		_compare_prediction(local, _prediction_state(predictor), record, label + " menu recovery")
		sink.presence.aim = {}
		ball._process(1.0 / 30.0)
		_check_prediction_hidden(ball, record, label + " stale presence")
		sink.presence.aim = {"aiming": true, "vector": vector}
		ball._process(1.0 / 30.0)
		sink.turn_owner = 1
		ball._process(1.0 / 30.0)
		_check_prediction_hidden(ball, record, label + " turn ownership change")
		sink.turn_owner = 2
		ball._process(1.0 / 30.0)
		sink.allowed = true
		sink.turn_owner = 1
		ball._process(1.0 / 30.0)
		_check_prediction_hidden(ball, record, label + " local idle handoff")
	# The native predictor hides below its 50-unit threshold even while the
	# player holds the mouse. The mod must not revive its previous hit geometry.
	sink.allowed = true
	sink.turn_owner = 1
	sink.presence.aim = {}
	await _aim_mouse(mod, ball, Vector2(30, 0))
	record.call(
		ball.holding_shot and ball.preparing_shot and ball.shot.length() < 50.0,
		role + " native prediction: small mouse drag remains native input"
	)
	_check_prediction_hidden(ball, record, role + " native prediction below threshold")
	ball.pause_cancel_shot()
	sink.allowed = false
	await _button(mod, _pointer_viewport.get_mouse_position(), false)
	ball._process(1.0 / 30.0)
	record.call(
		_gameplay_state(game, physics, bodies) == before and sink.submitted.size() == submissions,
		role + " native prediction: input and replay preserve score, health, shots, economy and registered body physics"
	)
	for state in frozen:
		state.body.freeze = state.freeze
		state.body.set_physics_process(state.physics)


func _aim_mouse(mod: Node, ball: Node, vector: Vector2) -> void:
	ball.pause_cancel_shot()
	var start: Vector2 = ball.get_global_transform_with_canvas().origin
	await _button(mod, start, false)
	ball._process(1.0 / 30.0)
	await _button(mod, start, true)
	ball._process(1.0 / 30.0)
	# Native startup polls just_pressed; motion belongs to the following frame
	# or the second native process would reset its drag origin at the new point.
	await mod.get_tree().process_frame
	_motion(mod, start - _pointer_viewport.canvas_transform.basis_xform(vector))
	ball._process(1.0 / 30.0)


func _prediction_cases(game: Node, physics: Node, ball: Node) -> Array:
	var result: Array = []
	var origin: Vector2 = ball.global_position
	# Native direct/glancing intersections, selected from the existing real rack.
	for target in game.get_active_balls_include_untargetable():
		if target == ball or not target.alive:
			continue
		var delta: Vector2 = target.global_position - origin
		if delta.length() <= target.get_radius() + 20.0:
			continue
		var direct: Vector2 = delta.normalized() * 160.0
		var ray: Array = physics.raycast(origin, direct.normalized(), null)
		if ray[0] != target or ray[2].size() != 2:
			continue
		for sign_value in [-1.0, 1.0]:
			var offset: Vector2 = delta.orthogonal().normalized() * (target.get_radius() + 17.0) * 0.6 * sign_value
			var glance: Vector2 = (delta + offset).normalized() * 160.0
			var glancing_ray: Array = physics.raycast(origin, glance.normalized(), null)
			if glancing_ray[0] == target and glancing_ray[2].size() == 2:
				result.append({"name": "direct hit", "vector": direct, "hit": target})
				result.append({"name": "glancing hit", "vector": glance, "hit": target})
				break
		if result.size() == 2:
			break
	# At most 72 native queries, with no geometry/registration replacement.
	for index in range(72):
		var vector: Vector2 = Vector2.RIGHT.rotated(TAU * float(index) / 72.0) * 160.0
		var ray: Array = physics.raycast(origin, vector.normalized(), null)
		if ray[0] == null and ray[2].size() >= 3:
			result.append({"name": "empty wall bounce", "vector": vector, "hit": null})
			break
	return result


func _prediction_state(prediction: Node) -> Dictionary:
	var lines: Array = []
	for line in [prediction.line1, prediction.line2, prediction.secondary_lines[0], prediction.secondary_lines[1]]:
		var points: Array = []
		for point in line.points:
			points.append(line.to_global(point))
		lines.append({
			"visible": line.visible, "points": points, "color": line.modulate,
			"length": line.material.get_shader_parameter("line_length") if line in prediction.secondary_lines else 0.0
		})
	return {
		"visible": prediction.visible, "lines": lines,
		"collision_visible": prediction.collision_point.visible,
		"collision_position": prediction.collision_point.global_position,
		"bounce_visible": prediction.bounce_point.visible,
		"bounce_position": prediction.bounce_point.global_position,
		"charge_scale": prediction.collision_gauge.scale
	}


func _prediction_ids(prediction: Node) -> Array:
	var ids: Array = [prediction.get_instance_id()]
	for line in [prediction.line1, prediction.line2, prediction.secondary_lines[0], prediction.secondary_lines[1]]:
		ids.append([line.get_instance_id(), line.material.get_instance_id()])
	return ids


func _compare_prediction(expected: Dictionary, actual: Dictionary, record: Callable, label: String) -> void:
	for index in range(4):
		var wanted: Dictionary = expected.lines[index]
		var got: Dictionary = actual.lines[index]
		var same_points: bool = wanted.points.size() == got.points.size()
		for point_index in range(mini(wanted.points.size(), got.points.size())):
			same_points = same_points and wanted.points[point_index].is_equal_approx(got.points[point_index])
		record.call(
			got.visible == wanted.visible and same_points and got.color == wanted.color
			and is_equal_approx(float(got.length), float(wanted.length)),
			label + ": line %d preserves native points, visibility, color and shader length" % index
		)
	record.call(
		expected.visible == actual.visible
		and expected.collision_visible == actual.collision_visible
		and expected.collision_position.is_equal_approx(actual.collision_position)
		and expected.bounce_visible == actual.bounce_visible
		and expected.bounce_position.is_equal_approx(actual.bounce_position)
		and expected.charge_scale.is_equal_approx(actual.charge_scale),
		label + ": native collision marker, bounce marker and charge gauge match"
	)


func _check_prediction_hidden(ball: Node, record: Callable, label: String) -> void:
	record.call(
		not ball.prediction.visible and not ball.get_node("CuePivot").visible
		and not ball.prediction.collision_point.visible
		and not ball.prediction.secondary_lines[0].visible
		and not ball.prediction.secondary_lines[1].visible,
		label + ": native prediction and cue are fully hidden"
	)


func _gameplay_state(game: Node, physics: Node, bodies: Array) -> Dictionary:
	var body_states: Array = []
	for body in bodies:
		body_states.append([
			body.get_instance_id(), body.global_position, body.linear_velocity,
			body.angular_velocity, body.alive, body.spawned, body.falling
		])
	return {
		"score": game.score, "hp": game.player_info.hp, "money": game.player_info.money,
		"shots": game.get_shots_left(), "bodies": body_states,
		"registered_balls": physics.balls.duplicate(), "walls": physics.shapes.duplicate()
	}


func _reparent_ball(mod: Node, ball: Node, parent: Node) -> void:
	# This is an already-hooked player crossing fixture viewports. Reparenting does
	# not emit ready again, so do not add a second pending ready hook to the adapter.
	var added: Signal = mod.get_tree().node_added
	var callback: Callable = mod.adapter._node_added
	var connected = added.is_connected(callback)
	if connected:
		added.disconnect(callback)
	ball.reparent(parent, true)
	if connected:
		added.connect(callback)


func _button(mod: Node, position: Vector2, pressed: bool) -> void:
	await mod.get_tree().process_frame
	var event = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_pointer_viewport.push_input(event, true)


func _motion(_mod: Node, position: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - _pointer_viewport.get_mouse_position()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	_pointer_viewport.push_input(event, true)

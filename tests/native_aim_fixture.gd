extends RefCounted


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
func check(mod: Node, game: Node, role: String, record: Callable) -> void:
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
	mod.adapter.set_process(false)
	ball.set_process(false)
	ball.together_controller = sink
	settings.shot_mode = settings.SHOT_MODES.FAST
	settings.shoot_confirmation = false
	game.in_menu = false
	ball.pause_cancel_shot()
	var start: Vector2 = ball.get_global_transform_with_canvas().origin
	var target = start - Vector2(120, 0)
	await _button(mod, start, false)
	await mod.get_tree().process_frame
	ball._process(1.0 / 30.0)
	var pivot = ball.get_node_or_null("CuePivot")
	record.call(pivot != null and not pivot.visible, role + " mouse aim: idle cue stays hidden")
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
		ball.shot is Vector2 and ball.shot.length() > 50.0 and pivot.visible,
		role + " mouse aim: held pointer motion charges and reveals cue"
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
	ball.together_controller = saved.controller
	game.in_menu = saved.in_menu
	game.playing = saved.playing
	settings.shot_mode = saved.shot_mode
	settings.shoot_confirmation = saved.confirmation
	input_manager._set_mode(saved.input_mode)
	ball.set_process(saved.process)
	mod.adapter.set_process(saved.adapter_process)
	sink.free()


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
	mod.get_viewport().push_input(event, true)


func _motion(mod: Node, position: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	mod.get_viewport().push_input(event, true)

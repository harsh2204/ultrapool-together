extends RefCounted

const CueCatalog = preload("../mod/cue_catalog.gd")


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
	ball.set_process(saved.process)
	mod.adapter.set_process(saved.adapter_process)
	sink.free()
	presence.free()
	identity.free()


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

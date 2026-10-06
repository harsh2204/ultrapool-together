extends "res://player_ball.gd"

## Native cue rest pose: CuePivot/Cue defaults to position (-426, 0) at rotation 0 — a
## horizontal shaft whose tip sits on the ball. Leaving that visible while not aiming is
## the "floating stick at table mid-left" artifact. Hide unless actively aiming; when the
## local process loop is frozen (fixtures) or a teammate aims, drive pivot from the aim
## vector so the shaft stays attached to the cue ball (#18).

var together_controller: Node
var _remote_aim_active: bool = false


func _process(delta):
	var game = Global.gameManager
	if _can_control():
		# Ensure native cue stick / aim line / reticle path runs (#18).
		if is_instance_valid(game) and not game.playing:
			game.playing = true
		if _remote_aim_active:
			# A teammate pose must not survive the turn becoming local. The native
			# process below owns the new player's prediction (PERF-027/029).
			prediction.hide_prediction()
		_remote_aim_active = false
		# Native _process polls the initial click/controller aim and calls can_shoot().
		# Keep the real menu state here or an idle player can never start aiming.
		super._process(delta)
		# Hide the idle rest pose without changing gameplay input eligibility.
		_ensure_aim_chrome()
		return
	# Off-turn: cancel local input aim, then optionally mirror teammate presence aim (#18).
	pause_cancel_shot()
	var was_in_menu: bool = game.in_menu
	game.in_menu = true
	super._process(delta)
	game.in_menu = was_in_menu
	_apply_teammate_aim_chrome(delta)


func _input(event: InputEvent) -> void:
	if _can_control():
		super._input(event)
	else:
		pause_cancel_shot()


func shoot(vector: Vector2):
	if _can_control():
		together_controller.submit_shot(vector)
	pause_cancel_shot()


func together_play_shot(vector: Vector2) -> void:
	super.shoot(vector)


func hit(other):
	if not get_meta("together_replica", false):
		super.hit(other)


func hit_wall(normal):
	if not get_meta("together_replica", false):
		super.hit_wall(normal)


func _can_control() -> bool:
	return is_instance_valid(together_controller) and together_controller.can_control()


func _ensure_aim_chrome() -> void:
	# Native onready refs: keep aim UI discoverable while the local guest aims.
	var ui = get("shoot_ui")
	if ui is CanvasItem and preparing_shot:
		ui.visible = true
	# Native prediction decides visibility, including its minimum shot length.
	# Re-showing it here revives the collision marker below the native threshold.
	var gauge = get("chargeGauge")
	if gauge == null and get("visuals") != null:
		gauge = visuals.get_node_or_null("static/chargeGauge")
	if gauge is CanvasItem and preparing_shot:
		gauge.visible = true
	# Native processing owns the local aim pose, pullback and pivot fade (PERF-027).
	# Only undo our idle visibility guard; a fixed mod pose overwrites native charging.
	if preparing_shot and shot is Vector2 and shot.is_finite() and shot.length() > 50.0:
		_reveal_cue_pivot()
	else:
		_hide_cue_pivot()


## Non-controllers: present the turn owner's native cue and collision prediction.
## Presence validates current table/turn context; it never grants input authority.
## Reuse the installed predictor over this board's retained bodies (PERF-027/029).
func _apply_teammate_aim_chrome(delta: float = 0.0) -> void:
	var aim: Dictionary = {}
	var game = Global.gameManager
	if (
		is_instance_valid(game)
		and spawned
		and alive
		and not falling
		and game.can_shoot()
		and game.has_shots()
		and is_instance_valid(together_controller)
	):
		var presence = together_controller.get("presence")
		var turn_owner: int = int(together_controller.get("turn_owner"))
		var transport = together_controller.get("transport")
		var local_id: int = 0
		if is_instance_valid(transport) and transport.has_method("local_id"):
			local_id = int(transport.local_id())
		if (
			turn_owner != local_id
			and is_instance_valid(presence)
			and presence.has_method("remote_aim")
		):
			aim = presence.remote_aim(turn_owner)
	var vector = aim.get("vector", Vector2.ZERO) if aim is Dictionary else Vector2.ZERO
	var aiming: bool = (
		aim is Dictionary
		and bool(aim.get("aiming", false))
		and vector is Vector2
		and vector.is_finite()
		and vector.length() > 50.0
	)
	if not aiming:
		prediction.hide_prediction()
		_hide_cue_pivot()
		_remote_aim_active = false
		return
	vector = vector.limit_length(200.0)
	_show_cue_aim(vector)
	# This native helper changes only the prediction nodes. In particular, keep
	# preparing_shot false: get_shot(), input polling and shot submission stay local.
	prediction.predictive_stuff(vector, delta, null, true)
	prediction.set_charge_gauge(vector.length() / 200.0)
	_remote_aim_active = true


func _show_cue_aim(vector: Vector2) -> void:
	var pivot = get_node_or_null("CuePivot")
	if pivot == null:
		return
	_reveal_cue_pivot()
	# Glue the pivot to this ball in global space so a packed/animated offset cannot
	# leave the shaft floating at table mid-left (#18). Only remote/frozen aim uses
	# this pose; the live local owner retains the native process result.
	if pivot.global_position != global_position:
		pivot.global_position = global_position
	# Off-turn native processing fades toward transparent black. Remote aim needs
	# the whole neutral pivot color restored; the Cue child owns the selected finish.
	if pivot.modulate != Color.WHITE:
		pivot.modulate = Color.WHITE
	# Native packs Cue at (-426, 0) on local -X. rotation = aim.angle() puts -X behind
	# the ball (opposite the shot), matching the vanilla aim pose.
	if pivot.rotation != vector.angle():
		pivot.rotation = vector.angle()
	var cue = pivot.get_node_or_null("Cue")
	if cue is Node2D:
		var pullback = Vector2(-400.0 - clampf(vector.length(), 0.0, 200.0) * 0.4, 0.0)
		if cue.position != pullback:
			cue.position = pullback


func _reveal_cue_pivot() -> void:
	var pivot = get_node_or_null("CuePivot")
	if pivot == null:
		return
	if not pivot.visible:
		pivot.visible = true
	var cue = pivot.get_node_or_null("Cue")
	if cue is CanvasItem:
		if not cue.visible:
			cue.visible = true
		if cue.modulate.a != 1.0:
			cue.modulate.a = 1.0
		var shadow = cue.get_node_or_null("CueShadow")
		if shadow is CanvasItem and not shadow.visible:
			shadow.visible = true
	var anim = pivot.get_node_or_null("AnimationPlayer")
	if anim is AnimationPlayer and not anim.active:
		anim.active = true


func _hide_cue_pivot() -> void:
	var pivot = get_node_or_null("CuePivot")
	if pivot == null:
		return
	var anim = pivot.get_node_or_null("AnimationPlayer")
	if anim is AnimationPlayer and anim.is_playing():
		anim.stop()
	if anim is AnimationPlayer and anim.active:
		anim.active = false
	var cue = pivot.get_node_or_null("Cue")
	if cue is CanvasItem:
		if cue.visible:
			cue.visible = false
		if cue.modulate.a != 0.0:
			cue.modulate.a = 0.0
	if pivot.visible:
		pivot.visible = false

extends "res://player_ball.gd"

## Native cue rest pose: CuePivot/Cue defaults to position (-426, 0) at rotation 0 — a
## horizontal shaft whose tip sits on the ball. Leaving that visible while not aiming is
## the "floating stick at table mid-left" artifact. Hide unless actively aiming; when the
## local process loop is frozen (fixtures) or a teammate aims, drive pivot from the aim
## vector so the shaft stays attached to the cue ball (#18).

const CUE_REST_OFFSET := Vector2(-426, 0)

var together_controller: Node
var _remote_aim_active: bool = false


func _process(delta):
	var game = Global.gameManager
	if _can_control():
		# Ensure native cue stick / aim line / reticle path runs (#18).
		if is_instance_valid(game) and not game.playing:
			game.playing = true
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
	_apply_teammate_aim_chrome()


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
	var pred = get("prediction")
	if pred is CanvasItem and preparing_shot:
		pred.visible = true
	var gauge = get("chargeGauge")
	if gauge == null and get("visuals") != null:
		gauge = visuals.get_node_or_null("static/chargeGauge")
	if gauge is CanvasItem and preparing_shot:
		gauge.visible = true
	# Always pose CuePivot while preparing — fixtures freeze process, and live play can
	# leave the packed rest shaft visible until native aim writes a transform (#18).
	if preparing_shot and shot is Vector2 and shot.is_finite() and shot.length() > 1.0:
		_show_cue_aim(shot)
	elif not preparing_shot:
		_hide_cue_pivot()


## Non-controllers: drive CuePivot from the turn owner's presence aim vector (#18).
## Local input is already cancelled; this only sets visual transform.
func _apply_teammate_aim_chrome() -> void:
	var aim: Dictionary = {}
	if is_instance_valid(together_controller) and together_controller.has_method("get"):
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
		and vector.length() > 1.0
	)
	if not aiming:
		_hide_cue_pivot()
		_remote_aim_active = false
		return
	_show_cue_aim(vector)
	_remote_aim_active = true


func _show_cue_aim(vector: Vector2) -> void:
	var pivot = get_node_or_null("CuePivot")
	if pivot == null:
		return
	# Glue the pivot to this ball in global space so a packed/animated offset cannot
	# leave the shaft floating at table mid-left (#18).
	pivot.global_position = global_position
	pivot.visible = true
	# Native packs Cue at (-426, 0) on local -X. rotation = aim.angle() puts -X behind
	# the ball (opposite the shot), matching the vanilla aim pose.
	pivot.rotation = vector.angle()
	var cue = pivot.get_node_or_null("Cue")
	if cue is Node2D:
		# Aim pose uses the shoot-anim start offset, not the far RESET park.
		cue.position = Vector2(-350, 0)
		cue.visible = true
		cue.modulate.a = 1.0
		var shadow = cue.get_node_or_null("CueShadow")
		if shadow is CanvasItem:
			shadow.visible = true
	var anim = pivot.get_node_or_null("AnimationPlayer")
	if anim is AnimationPlayer:
		anim.active = true


func _hide_cue_pivot() -> void:
	var pivot = get_node_or_null("CuePivot")
	if pivot == null:
		return
	var anim = pivot.get_node_or_null("AnimationPlayer")
	if anim is AnimationPlayer and anim.is_playing():
		anim.stop()
	if anim is AnimationPlayer:
		anim.active = false
	var cue = pivot.get_node_or_null("Cue")
	if cue is CanvasItem:
		cue.visible = false
		cue.modulate.a = 0.0
	pivot.visible = false

extends "res://player_ball.gd"

var together_controller: Node
var _remote_aim_active: bool = false


func _process(delta):
	var game = Global.gameManager
	if _can_control():
		# Ensure native cue stick / aim line / reticle path runs (#18).
		if is_instance_valid(game) and not game.playing:
			game.playing = true
		_remote_aim_active = false
		super._process(delta)
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


## Non-controllers: drive CuePivot from the turn owner's presence aim vector (#18).
## Local input is already cancelled; this only sets visual transform.
func _apply_teammate_aim_chrome() -> void:
	var pivot = get_node_or_null("CuePivot")
	if pivot == null:
		return
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
		if _remote_aim_active:
			pivot.visible = false
			_remote_aim_active = false
		return
	pivot.visible = true
	pivot.rotation = vector.angle() + PI
	var cue = pivot.get_node_or_null("Cue")
	if cue is CanvasItem:
		cue.visible = true
	_remote_aim_active = true

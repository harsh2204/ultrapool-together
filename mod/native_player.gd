extends "res://player_ball.gd"

var together_controller: Node


func _process(delta):
	var game = Global.gameManager
	if _can_control():
		# Ensure native cue stick / aim line / reticle path runs (#18).
		if is_instance_valid(game) and not game.playing:
			game.playing = true
		super._process(delta)
		_ensure_aim_chrome()
		return
	pause_cancel_shot()
	var was_in_menu: bool = game.in_menu
	game.in_menu = true
	super._process(delta)
	game.in_menu = was_in_menu


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

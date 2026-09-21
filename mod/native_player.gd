extends "res://player_ball.gd"

var together_controller: Node


func _process(delta):
	if _can_control():
		super._process(delta)
		return
	pause_cancel_shot()
	var game = Global.gameManager
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

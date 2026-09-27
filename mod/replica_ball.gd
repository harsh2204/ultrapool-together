extends "res://ball.gd"

## Guest object-ball replica: suppress authoritative gameplay side effects, keep local SFX.
## Hit/cushion streams live on ball.tscn as BallOnBall / BallOnWall (PERF-019 disposable).

const MAX_IMPACT_SOUNDS = 4

var _impact_sounds: int = 0


func hit(_other: Ball):
	_play_impact("BallOnBall")


func hit_wall(_normal):
	_play_impact("BallOnWall")


func pocket(_which_pocket, _extra_multiplier = 1):
	pass


func _integrate_forces(_state):
	pass


func reset_impact_budget() -> void:
	_impact_sounds = 0


func _play_impact(node_name: String) -> void:
	if _impact_sounds >= MAX_IMPACT_SOUNDS:
		return
	var player = get_node_or_null(node_name)
	if player == null or not player.has_method("play"):
		return
	_impact_sounds += 1
	player.play()

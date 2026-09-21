extends "res://ball.gd"

var together_balls: Node


func hit(other: Ball):
	if is_instance_valid(together_balls):
		together_balls.record_hit(self, other)
	super.hit(other)


func hit_wall(normal):
	if not colliding_with_wall and not falling and is_instance_valid(together_balls):
		together_balls.record_wall(self)
	super.hit_wall(normal)


func pocket(which_pocket, extra_multiplier = 1):
	if not pocketed_this_frame and was_alive_one_frame_ago and is_instance_valid(together_balls):
		together_balls.record_pocket(self, which_pocket, extra_multiplier)
	super.pocket(which_pocket, extra_multiplier)

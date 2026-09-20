extends Control

var state: Dictionary = {}
var direction = Vector2.RIGHT * 140

func _draw():
	var cue = state.get("cue_screen", [0.0, 0.0])
	var viewport = state.get("viewport_size", [1.0, 1.0])
	var scale_info = state.get("aim_scale", [1.0, 1.0])
	if viewport[0] <= 0 or viewport[1] <= 0 or scale_info[0] <= 0 or scale_info[1] <= 0:
		return
	var ratio = size / Vector2(viewport[0], viewport[1])
	var start = Vector2(cue[0], cue[1]) * ratio
	var delta = direction / Vector2(scale_info[0], scale_info[1]) * ratio
	var end = start + delta
	draw_line(start, end, Color("a0ffe1"), 4.0, true)
	var tip = delta.normalized() * 16
	draw_line(end, end - tip.rotated(0.5), Color("a0ffe1"), 4.0, true)
	draw_line(end, end - tip.rotated(-0.5), Color("a0ffe1"), 4.0, true)
	draw_circle(start, 7, Color("f5e3a5"))

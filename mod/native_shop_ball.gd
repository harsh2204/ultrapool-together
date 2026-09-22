extends "res://shop_ball.gd"

var can_interact: Callable
var drag_started: Callable
var drop_requested: Callable
var drag_context: Dictionary = {}


func _process(delta: float) -> void:
	var was_interactable = interactable
	interactable = interactable and can_interact.is_valid() and can_interact.call(self)
	if not interactable:
		if Global.shopManager.is_grabbed(self):
			Global.shopManager.drop()
			Global.shopManager.hovered_slot = null
		drag_context.clear()
		select_logic(false)
	super._process(delta)
	interactable = was_interactable
	if Global.shopManager.is_grabbed(self):
		if drag_context.is_empty() and drag_started.is_valid():
			drag_context = drag_started.call(self)
	else:
		drag_context.clear()


func try_drop():
	AudioManager.play("drop_ball")
	var context = drag_context.duplicate()
	drag_context.clear()
	if drop_requested.is_valid():
		drop_requested.call(self, context)
	if is_instance_valid(slot):
		tpos = slot.global_position

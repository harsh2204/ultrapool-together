extends RefCounted

## Guest-only, fire-and-forget presentation for synced table edges.
## Disposable motion/presence: bounded per apply, no queues, cleared on rematch.
## PERF: keeps reliable state apply separate from FX (AGENTS.md / PERFORMANCE.md).

const MAX_SOUNDS_PER_APPLY = 4
const MAX_VISUALS_PER_APPLY = 8

var _alive: Dictionary = {}
var _star: Dictionary = {}
var _present: Dictionary = {}
var _rounds_played: int = -1
var _sounds: int = 0
var _visuals: int = 0


func clear() -> void:
	_alive.clear()
	_star.clear()
	_present.clear()
	_rounds_played = -1
	_sounds = 0
	_visuals = 0


func begin_apply() -> void:
	_sounds = 0
	_visuals = 0


func observe_round(table: Node, rounds_played: int, in_shop: bool) -> void:
	if _rounds_played < 0:
		_rounds_played = rounds_played
		return
	if rounds_played == _rounds_played:
		return
	_rounds_played = rounds_played
	if in_shop:
		return
	_play("drop_ball")
	if not is_instance_valid(table):
		return
	if table.has_method("show_start_animation"):
		table.show_start_animation()
	elif table.has_method("play_start"):
		table.play_start()
	var reminder = table.get_node_or_null("%AimReminder")
	if reminder is CanvasItem:
		reminder.visible = true


func observe_ball(body: Node, state: Dictionary, created: bool) -> void:
	var id: int = state.id
	var was_present: bool = _present.has(id)
	_present[id] = true
	if created or not was_present:
		_pulse_spawn(body)
		_play("drop_ball")
	var alive: bool = state.alive and not state.gone
	var was_alive = _alive.get(id, alive)
	if was_alive and not alive and not state.player:
		_pulse_pocket(body)
		_play("drop_ball")
	_alive[id] = alive
	var starred: bool = bool(state.item.get("star_power", false)) and not bool(state.get("player", false))
	var was_star: bool = bool(_star.get(id, false))
	if starred and not was_star:
		_pulse_spawn(body)
		if body.has_method("set_star"):
			body.set_star(true)
	elif not starred and was_star and not bool(state.get("player", false)):
		if body.has_method("set_star"):
			body.set_star(false)
	_star[id] = starred


func finish_apply(present_ids: Dictionary) -> void:
	for id in _present.keys():
		if not present_ids.has(id):
			_present.erase(id)
			_alive.erase(id)
			_star.erase(id)


func _pulse_spawn(body: Node) -> void:
	if _visuals >= MAX_VISUALS_PER_APPLY or not is_instance_valid(body):
		return
	_visuals += 1
	if body.get("flash_spr") is CanvasItem and body.flash_spr.material != null:
		body.flash_alpha = 1.0
		body.flash_spr.material.set_shader_parameter("alpha", 1.0)
	var spark = _effect_node(body, "static/spark")
	if spark is CanvasItem:
		spark.show()


func _pulse_pocket(body: Node) -> void:
	if _visuals >= MAX_VISUALS_PER_APPLY or not is_instance_valid(body):
		return
	_visuals += 1
	var spark = _effect_node(body, "static/spark")
	if spark is CanvasItem:
		spark.show()
	var score_fx = _effect_node(body, "static/score_effects")
	if score_fx is CanvasItem:
		score_fx.show()


func _effect_node(body: Node, path: String):
	var visuals = body.get("visuals")
	if not is_instance_valid(visuals):
		return null
	return visuals.get_node_or_null(path)


func _play(sound: String) -> void:
	if _sounds >= MAX_SOUNDS_PER_APPLY:
		return
	var audio = Engine.get_main_loop().root.get_node_or_null("/root/AudioManager")
	if audio == null or not audio.has_method("play"):
		return
	_sounds += 1
	audio.play(sound)

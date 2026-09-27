extends RefCounted

## Guest-only, fire-and-forget presentation for synced table edges.
## Disposable motion/presence: bounded per apply, no queues, cleared on rematch.
## PERF-019: keeps reliable state apply separate from FX (AGENTS.md / PERFORMANCE.md).

const MAX_SOUNDS_PER_APPLY = 4
const MAX_VISUALS_PER_APPLY = 8
const MAX_SPARK_TIMERS = 8
const SPARK_HIDE_SEC = 0.35

## Confirmed AudioManager SFX node names from native AudioManager.tscn (game.exe pack).
const SFX_SPAWN = "ball_spawn"
const SFX_POCKET = "ball_pocket"
const SFX_DROP = "drop_ball"
const SFX_SHOT = "player_ball_shoot"
const SFX_SCORE = "score"

var _alive: Dictionary = {}
var _star: Dictionary = {}
var _present: Dictionary = {}
var _speed: Dictionary = {}
var _rounds_played: int = -1
var _sounds: int = 0
var _visuals: int = 0
var _spark_timers: int = 0
var _missing_logged: Dictionary = {}


func clear() -> void:
	_alive.clear()
	_star.clear()
	_present.clear()
	_speed.clear()
	_rounds_played = -1
	_sounds = 0
	_visuals = 0
	_spark_timers = 0
	_missing_logged.clear()


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
	_play(SFX_SPAWN)
	_play_start_animation(table)
	var reminder = table.get_node_or_null("%AimReminder")
	if reminder is CanvasItem:
		reminder.visible = true


## Host→guest shot edge (shot_start / begin_shot). Disposable SFX only.
func observe_shot() -> void:
	_play(SFX_SHOT)


func observe_ball(body: Node, state: Dictionary, created: bool) -> void:
	var id: int = state.id
	var was_present: bool = _present.has(id)
	_present[id] = true
	# Cue-ball spark must never stick (#15/#31). Hide on every apply + on create.
	if state.player:
		_hide_spark(body)
	elif created:
		_hide_spark(body)
	if created or not was_present:
		_pulse_spawn(body)
		_play(SFX_SPAWN if created else SFX_DROP)
	var alive: bool = state.alive and not state.gone
	var was_alive = _alive.get(id, alive)
	if was_alive and not alive and not state.player:
		_pulse_pocket(body)
		_play(SFX_POCKET)
	_alive[id] = alive
	# Collision onset from synced speed drops (replica stubs native hit SFX). Rate-limited.
	if not state.player and alive and state.spawned and not state.falling:
		var speed: float = Vector2(state.velocity).length()
		var prev_speed: float = float(_speed.get(id, speed))
		if prev_speed > 80.0 and speed < prev_speed * 0.55 and speed < prev_speed - 40.0:
			_play_body_impact(body, prev_speed - speed)
		_speed[id] = speed
	elif not alive:
		_speed.erase(id)
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
			_speed.erase(id)


## Native round-start: Doors AnimationPlayer plays "open" (confirmed in table scene pack).
## show_start_animation / play_start do not exist in native scripts.
func _play_start_animation(table: Node) -> void:
	if not is_instance_valid(table):
		return
	var doors = table.get_node_or_null("Doors")
	if doors == null:
		_log_missing("table.Doors")
		return
	var anim = doors.get_node_or_null("AnimationPlayer")
	if anim == null:
		anim = doors.get_node_or_null("%AnimationPlayer")
	if anim == null or not anim.has_method("play"):
		_log_missing("Doors.AnimationPlayer")
		return
	# prepare_scene disables process on the table tree; re-enable for this one-shot.
	anim.set_process(true)
	anim.process_mode = Node.PROCESS_MODE_ALWAYS
	if anim.has_animation("open"):
		anim.play("open")
	elif anim.has_animation("RESET"):
		anim.play("RESET")
		_log_missing("Doors.AnimationPlayer.open")
	else:
		_log_missing("Doors.AnimationPlayer.open")


func _pulse_spawn(body: Node) -> void:
	if _visuals >= MAX_VISUALS_PER_APPLY or not is_instance_valid(body):
		return
	_visuals += 1
	if body.get("flash_spr") is CanvasItem and body.flash_spr.material != null:
		body.flash_alpha = 1.0
		body.flash_spr.material.set_shader_parameter("alpha", 1.0)
	var spark = _effect_node(body, "static/spark")
	if spark is CanvasItem:
		_flash_spark(spark)


func _pulse_pocket(body: Node) -> void:
	if _visuals >= MAX_VISUALS_PER_APPLY or not is_instance_valid(body):
		return
	_visuals += 1
	var spark = _effect_node(body, "static/spark")
	if spark is CanvasItem:
		_flash_spark(spark)
	var score_fx = _effect_node(body, "static/score_effects")
	if score_fx is CanvasItem:
		score_fx.show()
		_auto_hide(score_fx, SPARK_HIDE_SEC)


func _flash_spark(spark: CanvasItem) -> void:
	spark.show()
	_auto_hide(spark, SPARK_HIDE_SEC)


func _hide_spark(body: Node) -> void:
	var spark = _effect_node(body, "static/spark")
	if spark is CanvasItem and spark.visible:
		spark.hide()


func _auto_hide(node: CanvasItem, seconds: float) -> void:
	if _spark_timers >= MAX_SPARK_TIMERS:
		node.hide()
		return
	var tree = Engine.get_main_loop()
	if not tree is SceneTree:
		node.hide()
		return
	_spark_timers += 1
	var timer: SceneTreeTimer = tree.create_timer(seconds)
	timer.timeout.connect(
		func():
			_spark_timers = maxi(_spark_timers - 1, 0)
			if is_instance_valid(node):
				node.hide(),
		CONNECT_ONE_SHOT
	)


func _effect_node(body: Node, path: String):
	var visuals = body.get("visuals")
	if not is_instance_valid(visuals):
		return null
	return visuals.get_node_or_null(path)


func _play_body_impact(body: Node, delta_speed: float) -> void:
	if _sounds >= MAX_SOUNDS_PER_APPLY or not is_instance_valid(body):
		return
	# Native ball.tscn streams: BallOnBall / BallOnWall (AudioStreamPlayer2D), not AudioManager.
	var name = "BallOnBall" if delta_speed > 120.0 else "BallOnWall"
	var player = body.get_node_or_null(name)
	if player != null and player.has_method("play"):
		_sounds += 1
		player.play()
		return
	_play(SFX_SCORE if delta_speed > 120.0 else SFX_DROP)


func _play(sound: String) -> void:
	if _sounds >= MAX_SOUNDS_PER_APPLY:
		return
	var audio = Engine.get_main_loop().root.get_node_or_null("/root/AudioManager")
	if audio == null or not audio.has_method("play"):
		_log_missing("AudioManager.play")
		return
	# Guard: only call names confirmed as SFX children in native AudioManager.tscn.
	var sfx = audio.get_node_or_null("SFX/%s" % sound)
	if sfx == null:
		_log_missing("AudioManager.SFX.%s" % sound)
		return
	_sounds += 1
	audio.play(sound)


func _log_missing(key: String) -> void:
	if _missing_logged.has(key):
		return
	_missing_logged[key] = true
	push_warning("Together replica_fx: missing native entry %s" % key)

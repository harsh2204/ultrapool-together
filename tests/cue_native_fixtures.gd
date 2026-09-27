extends RefCounted
## Native cue compatibility checks inside the authorized, isolated screenshot run.
## No shots are fired and no native ball is actually potted. The callback fixture
## exercises the real score/HUD boundary synchronously below the round target.

const CueModels = preload("../mod/cue_models.gd")
const CueCatalog = preload("../mod/cue_catalog.gd")
const CueVisuals = preload("../mod/cue_visuals.gd")
const CueInventory = preload("../mod/cue_inventory.gd")
const CueEffects = preload("../mod/cue_effects.gd")
const SPRITE_FIELDS = [
	"texture", "transform", "offset", "centered", "flip_h", "flip_v", "hframes", "vframes",
	"frame", "region_enabled", "region_rect", "modulate", "self_modulate", "visible"
]


class SiblingService:
	extends Node
	var _active = true


func run(mod: Node, game: Node, capture: Callable, check: Callable) -> void:
	var player = game.player_ball
	var cue = player.get_node_or_null("CuePivot/Cue") if is_instance_valid(player) else null
	if not check.call(cue is Sprite2D, "native cues: real cue sprite is available"):
		return
	var pivot = player.get_node("CuePivot")
	var shadow = cue.get_node_or_null("CueShadow")
	var animation = pivot.get_node_or_null("AnimationPlayer")
	var saved = {
		"inventory": mod.cue_inventory,
		"adapter_process": mod.adapter.is_processing(),
		"player_process": player.is_processing(),
		"player_input": player.is_processing_input(),
		"player": _fields(player, ["preparing_shot", "holding_shot", "shot"]),
		"cue": _fields(cue, SPRITE_FIELDS),
		"pivot": _fields(pivot, ["transform", "modulate", "visible"]),
		"shadow": _fields(shadow, ["transform", "modulate", "visible"]),
		"animation_active": animation.active if animation is AnimationPlayer else false,
		"signature": cue.get_meta(CueVisuals.APPLIED_META, []),
	}
	mod.adapter.set_process(false)
	player.set_process(false)
	player.set_process_input(false)
	mod.cue_inventory = CueInventory.new()
	mod.cue_inventory.reset(mod._members(mod.table_id))
	CueVisuals.restore(player)
	var native_texture = cue.texture
	var native_transform: Transform2D = cue.transform
	var native_offset: Vector2 = cue.offset
	var native_tip = _tip(cue)
	var native_shadow: Transform2D = (
		cue.transform * shadow.transform if shadow is Node2D else Transform2D.IDENTITY
	)
	var native_self: Color = cue.self_modulate
	cue.modulate.a = 0.37
	pivot.modulate.a = 0.23
	for model in CueModels.entries():
		var art = CueVisuals.texture(model.id)
		check.call(
			art is Texture2D and art.get_width() > 0 and art.get_height() > 0,
			"native cues: %s asset decoded into the shared cache" % model.label
		)
		CueVisuals.apply(player, model.id, "gold")
		check.call(
			cue.texture == (native_texture if model.id == "house" else art),
			"native cues: %s selects its correct in-game texture" % model.label
		)
		check.call(
			_tip(cue).distance_to(native_tip) < 0.01,
			"native cues: %s preserves the tip anchor" % model.label
		)
		check.call(
			is_equal_approx(cue.modulate.a, 0.37) and is_equal_approx(pivot.modulate.a, 0.23),
			"native cues: %s preserves native aiming fade" % model.label
		)
		check.call(
			cue.self_modulate.is_equal_approx(native_self * CueCatalog.style("gold").modulate),
			"native cues: %s applies finish only to its sprite" % model.label
		)
		if shadow is Node2D:
			check.call(
				(cue.transform * shadow.transform).is_equal_approx(native_shadow),
				"native cues: %s preserves the native shadow transform" % model.label
			)
		if model.id != "house":
			check.call(cue.flip_h, "native cues: %s points its tip toward the ball" % model.label)
	CueVisuals.apply(player, "house", "native")
	check.call(
		cue.texture == native_texture and cue.transform.is_equal_approx(native_transform)
		and cue.offset.is_equal_approx(native_offset),
		"native cues: switching to House restores native geometry"
	)
	var bought: Dictionary = mod.cue_inventory.transact(1, "cue_buy", "bankshot", "native", 4.0)
	check.call(bought.accepted, "native cues: Bankshot is owned before the equipped preview")
	player.preparing_shot = true
	player.holding_shot = true
	player.shot = Vector2(145, -80)
	CueVisuals.apply(player, mod.cue_inventory.model_for(1), mod.cue_inventory.finish_for(1))
	if check.call(
		player.has_method("_show_cue_aim"), "native cues: native aiming helper is installed"
	):
		player._show_cue_aim(player.shot)
		pivot.modulate = Color.WHITE
		check.call(
			pivot.visible and pivot.global_position.is_equal_approx(player.global_position),
			"native cues: equipped Bankshot remains attached to its ball while aiming"
		)
		await capture.call(
			"cue-native-bankshot", "Bankshot equipped on the native table · aiming preview."
		)
	CueVisuals.restore(player)
	check.call(
		cue.texture == native_texture and cue.self_modulate.is_equal_approx(native_self),
		"native cues: teardown restores native texture and finish"
	)
	_restore_fields(player, saved.player)
	_restore_fields(cue, saved.cue)
	_restore_fields(pivot, saved.pivot)
	_restore_fields(shadow, saved.shadow)
	if animation is AnimationPlayer:
		animation.active = saved.animation_active
	if saved.signature.is_empty():
		if cue.has_meta(CueVisuals.APPLIED_META):
			cue.remove_meta(CueVisuals.APPLIED_META)
	else:
		cue.set_meta(CueVisuals.APPLIED_META, saved.signature)
	_check_callbacks(mod, game, check)
	mod.cue_inventory = saved.inventory
	player.set_process_input(saved.player_input)
	player.set_process(saved.player_process)
	mod.adapter.set_process(saved.adapter_process)


func _check_callbacks(mod: Node, game: Node, check: Callable) -> void:
	var body = _object_ball(game)
	if not check.call(body != null, "native cue effects: a live ordinary object ball is available"):
		return
	if not check.call(
		game.get_required_score() > 5.0, "native cue effects: scoring stays below target"
	):
		return
	var achievements = mod.get_node("/root/AchievementManager")
	var saved = {
		"score": game.score,
		"pitch": game.pitch_score,
		"combo": game.score_combo_time,
		"children": game.get_children(),
		"stats": achievements.stats.duplicate(true),
		"round_stats": achievements.round_stats.duplicate(true),
		"script": body.get_script(),
		"item": body.ball_item,
		"body": _fields(body, ["was_alive_one_frame_ago", "pocketed_this_frame", "alive"]),
		"together": body.get("together_balls"),
		"expansion": body.get("expansion_balls"),
	}
	var original_items: Dictionary = {}
	for candidate in game.balls:
		original_items[candidate.get_instance_id()] = candidate.ball_item
	var wrapper = load(mod.get_script().resource_path.get_base_dir().path_join("multiplayer_ball.gd"))
	var sibling = SiblingService.new()
	mod.add_child(sibling)
	mod.adapter._replace_script(body, wrapper)
	body.together_balls = sibling
	body.ball_item = saved.item.duplicate(true)
	body.ball_item.base_score = 3
	body.ball_item.temp_extra_score = 0
	body.was_alive_one_frame_ago = true
	body.pocketed_this_frame = false
	var effects = CueEffects.new()
	mod.add_child(effects)
	check.call(effects.setup(mod), "native cue effects: adapter connects to real game services")
	effects.begin_session()
	game.set_score(0.0)
	var admitted: bool = effects.begin_shot(1, 1, Vector2(125, 0))
	check.call(admitted and effects.rules.pending, "native cue effects: native shot boundary opens")
	var pocket = _fixed_pocket(effects)
	if check.call(pocket != null, "native cue effects: native fixed pockets are classified"):
		var points: float = minf(3.0 * CueModels.entry("bankshot").bonus_rate, 2.0)
		effects.record_wall(body)
		var award: Dictionary = effects.record_pocket(body, pocket, 1.0)
		check.call(
			not award.is_empty() and game.score == 0.0 and body.alive,
			"native cue effects: staged award cannot score while its source is alive"
		)
		check.call(
			award.get("position") == body.global_position,
			"native cue effects: staged award retains its pre-graveyard world position"
		)
		# Reproduce the native post-pocket flags without physically potting this
		# fixture's live ball. This isolates the real score/HUD commit boundary.
		body.alive = false
		body.pocketed_this_frame = true
		effects.commit_pocket(award)
		check.call(
			is_equal_approx(game.score, points) and points > 0.0 and points < 1.0,
			"native cue effects: real native score boundary preserves fractional Bankshot credit"
		)
		effects.commit_pocket(award)
		effects.commit_pocket(effects.record_pocket(body, pocket, 1.0))
		check.call(
			is_equal_approx(game.score, points), "native cue effects: repeated pot is deduplicated"
		)
		effects.finish_shot()
		body.alive = true
		body.pocketed_this_frame = false
		body.ball_item.base_score = 100
		check.call(effects.begin_shot(2, 1, Vector2(125, 0)), "native cue effects: next shot opens")
		effects.record_wall(body)
		award = effects.record_pocket(body, pocket, 1.0)
		body.alive = false
		body.pocketed_this_frame = true
		effects.commit_pocket(award)
		check.call(
			is_equal_approx(game.score, points + 2.0),
			"native cue effects: high native ball value respects the two-point shot cap"
		)
		effects.finish_shot()
		# A GAMEBALL poised just below target must not trigger REACH-SCORE while
		# staging. Its full native pot is deliberately outside this isolated seam.
		body.alive = true
		body.pocketed_this_frame = false
		var source_data = body.ball_item.data
		var database = mod.get_node("/root/BallDatabase")
		if check.call(database.id_to_ball.has("GAMEBALL"), "native cue effects: GAMEBALL data exists"):
			body.ball_item.data = database.id_to_ball["GAMEBALL"]
			body.ball_item.base_score = 3
			game.set_score(float(game.get_required_score()) - 0.05)
			var boundary_score: float = game.score
			check.call(effects.begin_shot(3, 1, Vector2(125, 0)), "GAMEBALL boundary shot opens")
			effects.record_wall(body)
			award = effects.record_pocket(body, pocket, 1.0)
			check.call(
				not award.is_empty() and game.score == boundary_score and body.alive,
				"GAMEBALL staging cannot cross the native score target before source removal"
			)
			# Incorrectly early commit is rejected rather than invoking a native
			# threshold event against a source that has not completed its pot.
			effects.commit_pocket(award)
			check.call(
				game.score == boundary_score and body.alive,
				"GAMEBALL award commit refuses a still-living source"
			)
			effects.finish_shot()
			game.set_score(0.0)
			body.ball_item.data = source_data
	effects.end_session()
	check.call(
		body.get_script() == wrapper and body.together_balls == sibling and body.cue_effects == null,
		"native cue effects: teardown preserves another active service's shared wrapper"
	)
	effects.free()
	body.together_balls = saved.together
	body.expansion_balls = saved.expansion
	body.ball_item = saved.item
	_restore_fields(body, saved.body)
	mod.adapter._replace_script(body, saved.script)
	sibling.free()
	game.set_score(saved.score)
	game.pitch_score = saved.pitch
	game.score_combo_time = saved.combo
	achievements.stats = saved.stats
	achievements.round_stats = saved.round_stats
	for child in game.get_children():
		if child is ScoreDisplay and child not in saved.children:
			child.queue_free()
	check.call(
		body.get_script() == saved.script and body.ball_item == saved.item
		and game.score == saved.score and body.alive and not body.gone,
		"native cue effects: fixture restores the native ball, score, and HUD without potting"
	)
	var references_preserved = true
	for candidate in game.balls:
		references_preserved = references_preserved and (
			candidate.ball_item == original_items.get(candidate.get_instance_id())
		)
	check.call(references_preserved, "native cue effects: all native item references survive hooks")


func _object_ball(game):
	for body in game.balls:
		if (
			is_instance_valid(body) and body is Ball and not body is PlayerBall
			and not body.is_passive and body.alive and not body.gone and not body.is_shielded()
			and not body.has_id("WEREWOLF") and not body.has_id("POT")
			and body.ball_item != null and body.get_score() > 0
		):
			return body
	return null


func _fixed_pocket(effects):
	for entry in effects._fixed_pockets.values():
		var pocket = entry.body.get_ref()
		if is_instance_valid(pocket) and not pocket.shielded and pocket.get_multiplier() > 0.0:
			return pocket
	return null


func _tip(cue: Sprite2D) -> Vector2:
	var rect: Rect2 = cue.get_rect()
	return cue.transform * Vector2(rect.end.x, rect.get_center().y)


func _fields(node, names: Array) -> Dictionary:
	var result: Dictionary = {}
	if is_instance_valid(node):
		for field in names:
			result[field] = node.get(field)
	return result


func _restore_fields(node, values: Dictionary) -> void:
	if is_instance_valid(node):
		for field in values:
			node.set(field, values[field])

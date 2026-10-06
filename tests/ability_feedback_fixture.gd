extends RefCounted
## MOD-04..06/12 / PERF-028: production model output rendered by the actual
## playing-table and spectator consumers. This is state replay, not native pot,
## HP, respawn, transport or cross-platform authority verification.

const BallRules = preload("../mod/multiplayer_ball_rules.gd")
const AbilityOverlay = preload("../mod/ability_overlay.gd")
const CueEffects = preload("../mod/cue_effects.gd")
const ZodiacRules = preload("../mod/sets/zodiac_rules.gd")
const WatchFixture = preload("native_table_effects_fixture.gd")


func check_guest(mod: Node, baseline: Dictionary, record: Callable, capture: Callable, cue_feedback: Dictionary = {}) -> void:
	if not record.call(not mod.is_table_host(), "ability feedback: replay runs on the guest consumer"):
		return
	var rules = BallRules.new()
	rules.reset_round("ability-replay")
	rules.begin_shot(2, 1, false, 2)
	rules.pocket(1, [BallRules.BOUNTY], 8.0, 0, false)
	rules.wall(2)
	rules.pocket(2, [BallRules.BANKROLL], 8.0, 0, false)
	rules.pocket(3, [BallRules.LIFELINE], 8.0, 0, false)
	rules.record_heal(3, 1)
	rules.pocket(4, [BallRules.DOMINO], 8.0, 0, false)
	rules.pocket(5, [], 12.0, 0, true)
	rules.pocket(6, [BallRules.ENCORE], 8.0, 0, false)
	rules.record_encore("returned")
	var balls = {"last_shooter": 0, "bounty_shot": 2, "pending": true,
		"call": {}, "balls": [], "pockets": [], "feedback": rules.capture_feedback()}
	var zodiac = ZodiacRules.new()
	zodiac.reset_round("ability-replay")
	for pair in [[1, "ZODIAC_ARIES"], [2, "ZODIAC_LEO"], [3, "ZODIAC_SAGITTARIUS"],
		[4, "ZODIAC_CANCER"], [5, "ZODIAC_PISCES"]]:
		zodiac.register_ball(pair[0], [pair[1]])
	var expansion = {"sets": {"ZODIAC": zodiac.capture_shared()}, "balls": []}
	if not record.call(mod.multiplayer_balls.valid_state(balls) and mod.expansion_balls.valid_state(expansion),
		"ability feedback: model captures validate at the production network boundary"):
		return
	record.call(not cue_feedback.is_empty() and CueEffects.valid_feedback(cue_feedback),
		"ability feedback: native committed cue award reaches the replay fixture")
	var game = mod.get_node("/root/Global").gameManager
	var before = [game.score, game.player_info.money, game.player_info.hp, game.replicas.keys()]
	var service = mod.multiplayer_balls
	var old_processing: bool = service.is_processing()
	var old_balls: Dictionary = service._remote.duplicate(true)
	var old_expansion: Dictionary = mod.expansion_balls._remote.duplicate(true)
	var old_state: Dictionary = mod.latest_state.duplicate(true)
	service.set_process(false)
	mod.latest_state.table_active = true
	mod.latest_state.in_shop = false
	mod.latest_state.cue_feedback = cue_feedback
	service.apply_state(balls)
	mod.expansion_balls.apply_state(expansion)
	service._ui.refresh(service.display_state(), mod.expansion_balls.display_state(), cue_feedback)
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	record.call(service._ui._overlay.is_visible_in_tree(), "ability feedback: guest overlay is rendered")
	_check_text_fit(service._ui._hint.get_theme_font("font"), service._ui._overlay, balls, expansion, cue_feedback, record, "guest")
	var signature: Array = service._ui._signature.duplicate(true)
	service.apply_state(balls)
	service._ui.refresh(service.display_state(), mod.expansion_balls.display_state(), cue_feedback)
	record.call(service._ui._signature == signature, "ability feedback: duplicate guest resync does not restart presentation")
	await capture.call("37-guest-ability-feedback", "Guest · Bounty, utilities, Encore and Zodiac alignment causes")
	var controller = WatchFixture.WatchController.new()
	controller.ui_root = mod.ui_root
	controller.skin = mod.skin
	mod.add_child(controller)
	var watcher = load(get_script().resource_path.get_base_dir().path_join("../mod/table_spectator.gd")).new()
	controller.add_child(watcher)
	watcher.setup(controller)
	watcher.watch(1)
	watcher.apply_snapshot(1, baseline)
	watcher.apply_state(1, {"multiplayer_balls": balls, "expansion_balls": expansion, "cue_feedback": cue_feedback})
	watcher.tick(0.0)
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	record.call(watcher._ability.is_visible_in_tree() and watcher._ability_states() == [balls, expansion],
		"ability feedback: watched table consumes the same authoritative outcomes")
	_check_text_fit(watcher._title.get_theme_font("font"), watcher._ability, balls, expansion, cue_feedback, record, "spectator")
	await capture.call("38-spectator-ability-feedback", "Spectator · matching ability outcomes and Aspect / Grand Trine labels")
	rules.reset_round("next-round")
	var cleared: Dictionary = balls.duplicate(true)
	cleared.feedback = rules.capture_feedback()
	watcher.apply_state(1, {"multiplayer_balls": cleared, "expansion_balls": {}})
	watcher.tick(0.0)
	record.call(AbilityOverlay.feedback_lines(watcher._ability_states()[0].feedback).is_empty(),
		"ability feedback: round generation replacement removes previous outcomes")
	watcher.watch(2)
	record.call(watcher._ability_states() == [{}, {}], "ability feedback: watched-table switch removes previous outcomes")
	watcher.close()
	controller.queue_free()
	service.apply_state(old_balls)
	mod.expansion_balls.apply_state(old_expansion)
	mod.latest_state = old_state
	service._ui.refresh(service.display_state(), mod.expansion_balls.display_state(), old_state.get("cue_feedback", {}))
	service.set_process(old_processing)
	record.call(before == [game.score, game.player_info.money, game.player_info.hp, game.replicas.keys()],
		"ability feedback: guest and spectator replay never execute rewards, healing or respawning")


func _check_text_fit(font: Font, canvas: CanvasItem, balls: Dictionary, expansion: Dictionary,
		cue_feedback: Dictionary, record: Callable, role: String) -> void:
	var lines: Array = AbilityOverlay.cue_feedback_lines(cue_feedback) + AbilityOverlay.feedback_lines(balls.feedback) + AbilityOverlay.shared_lines(expansion.sets)
	var fits = true
	for line in lines:
		fits = fits and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, AbilityOverlay.FONT_SIZE).x + 32 <= canvas.get_viewport_rect().size.x
	fits = fits and lines.size() * AbilityOverlay.PANEL_LINE + 82 <= canvas.get_viewport_rect().size.y
	record.call(fits and lines.size() == 7, "ability feedback: " + role + " rendered receipt text and panel fit the viewport")

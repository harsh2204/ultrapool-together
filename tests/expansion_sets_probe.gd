extends SceneTree
## Static rules probe for expansion sets. Does not launch Ultrapool.

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var base = get_script().resource_path.get_base_dir().path_join("../mod/sets")
	_phases(load(base.path_join("phases_rules.gd")))
	_morph(load(base.path_join("morph_rules.gd")))
	_tide(load(base.path_join("tide_rules.gd")))
	_relic(load(base.path_join("relic_rules.gd")))
	_tarot(load(base.path_join("tarot_rules.gd")))
	_zodiac(load(base.path_join("zodiac_rules.gd")))
	_registry(load(base.path_join("registry.gd")))
	_display_validation(base)
	if failures.is_empty():
		print("PASS: %d expansion set rules checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _phases(script: Script) -> void:
	var model = script.new()
	model.reset_round("r1")
	model.register_ball(1, ["PHASES_CRESCENT"])
	_check(model.begin_shot(1), "phases shot starts")
	model.phase = 1
	_check(model.pocket(1, ["PHASES_CRESCENT"], 8.0, false).points == 4, "crescent waxing +50%")
	model.finish_shot([])
	model.begin_shot(2)
	_check(model.pocket(2, [], 10.0, true).points == 0, "ordinary advances phase")
	_check(model.phase == 2, "phase advanced on ordinary pocket")


func _morph(script: Script) -> void:
	var model = script.new()
	model.reset_round("r1")
	model.register_ball(1, ["MORPH_VESSEL"])
	model.begin_shot(1)
	model.hit(1, [])
	_check(model.balls[1].form == 1, "vessel cycles to active on cue hit")
	model.wall(1)
	_check(model.balls[1].charge == 1, "sprinter stores wall charge")
	_check(model.pocket(1, ["MORPH_VESSEL"], 8.0, false).points == 2, "vessel pays +25%")


func _tide(script: Script) -> void:
	var model = script.new()
	model.reset_round("r1")
	model.register_ball(1, ["TIDE_DRIFTWOOD"])
	model.begin_shot(1)
	model.height = 0
	_check(model.pocket(1, ["TIDE_DRIFTWOOD"], 8.0, false).points == 4, "driftwood at low tide")


func _relic(script: Script) -> void:
	var model = script.new()
	model.reset_round("r1")
	model.register_ball(1, ["RELIC_SHARD"])
	model.begin_shot(1)
	model.mark_object_hit()
	model.finish_shot([1])
	_check(model.balls[1].dig == 1, "shard digs on survive")
	model.begin_shot(2)
	_check(model.pocket(1, ["RELIC_SHARD"], 8.0, false).points == 2, "shard pays dig")


func _tarot(script: Script) -> void:
	var model = script.new()
	model.reset_round("r1")
	model.register_ball(1, ["TAROT_FOOL"])
	_check(model.spread.size() == 1, "spread draws available arcana")
	model.begin_shot(1)
	model.balls[1].upright = true
	_check(model.pocket(1, ["TAROT_FOOL"], 8.0, false).points == 8, "fool upright +100%")
	_check(model.spread.is_empty(), "pocket spends spread card")


func _zodiac(script: Script) -> void:
	var model = script.new()
	model.reset_round("r1")
	model.register_ball(1, ["ZODIAC_ARIES"])
	model.register_ball(2, ["ZODIAC_LEO"])
	model.begin_shot(1)
	_check(model._count("fire") == 2, "fire aspect with two signs")
	var action = model.pocket(1, ["ZODIAC_ARIES"], 8.0, false)
	_check(action.points == 2, "aries base +25%")


func _display_validation(base: String) -> void:
	var overlay = load(base.path_join("../ability_overlay.gd"))
	var service = load(base.path_join("../expansion_balls.gd")).new()
	var state = {"sets": {}, "balls": []}
	var next_id = 1
	for set_id in ["PHASES", "MORPH", "TIDE", "RELIC", "TAROT", "ZODIAC"]:
		var model = load(base.path_join(set_id.to_lower() + "_rules.gd")).new()
		model.reset_round("display-round")
		for kind in model.KINDS:
			service._kind_to_set[kind] = set_id
		model.register_ball(next_id, [model.KINDS[0]])
		state.sets[set_id] = model.capture_shared()
		var extra: Dictionary = {}
		if model.has_method("capture_ball"):
			extra[set_id] = model.capture_ball(next_id)
		state.balls.append({"id": next_id, "kinds": [model.KINDS[0]], "name": "display",
			"position": Vector2.ZERO, "color": Color.WHITE, "alive": true, "extra": extra})
		next_id += 1
	_check(service.valid_state(state), "production capture schemas for all six expansion sets validate")
	var invalid: Dictionary = state.duplicate(true)
	invalid.sets.ZODIAC.align.fire = "three"
	_check(not service.valid_state(invalid), "Zodiac alignment rejects noninteger count before drawing")
	invalid = state.duplicate(true)
	invalid.sets.ZODIAC.align.fire = 4
	_check(not service.valid_state(invalid), "Zodiac alignment counts distinct native signs, capped at three")
	invalid = state.duplicate(true)
	invalid.sets.PHASES.silent = 3
	_check(not service.valid_state(invalid), "Phases shared charge respects its model cap")
	invalid = state.duplicate(true)
	invalid.sets.TIDE.height = -1
	_check(not service.valid_state(invalid), "Tide shared height rejects negative values")
	invalid = state.duplicate(true)
	invalid.sets.MORPH.prime = 1
	_check(not service.valid_state(invalid), "Morph Prime display rejects a nonboolean flag")
	invalid = state.duplicate(true)
	invalid.sets.RELIC.idol_temps = {"arbitrary": "nested"}
	_check(not service.valid_state(invalid), "Relic shared totals cannot smuggle a container into display state")
	invalid = state.duplicate(true)
	invalid.sets.TAROT.spread = ["TAROT_FOOL", "TAROT_FOOL"]
	_check(not service.valid_state(invalid), "Tarot spread rejects duplicate cards")
	invalid = state.duplicate(true)
	invalid.sets.TAROT.spread = ["ZODIAC_ARIES"]
	_check(not service.valid_state(invalid), "Tarot spread rejects a card from a different set")
	for index in range(state.balls.size()):
		var ball: Dictionary = state.balls[index]
		for set_id in ball.extra:
			invalid = state.duplicate(true)
			invalid.balls[index].extra[set_id] = "invalid"
			_check(not service.valid_state(invalid), "per-ball expansion display rejects non-Dictionary state")
	invalid = state.duplicate(true)
	invalid.balls[1].extra.MORPH.charge = 2
	_check(not service.valid_state(invalid), "Morph per-ball charge respects its one-charge model cap")
	invalid = state.duplicate(true)
	invalid.balls[3].extra.RELIC.dig = 4
	_check(service.valid_state(invalid), "Relic fourth dig remains valid and is not silently truncated")
	invalid.balls[3].extra.RELIC.dig = 5
	_check(not service.valid_state(invalid), "Relic per-ball dig rejects values beyond the model cap")
	invalid = state.duplicate(true)
	invalid.balls[4].extra.TAROT.upright = 1
	_check(not service.valid_state(invalid), "Tarot orientation rejects a nonboolean flag")
	invalid = state.duplicate(true)
	invalid.balls[5].extra.ZODIAC.charge = 3
	_check(not service.valid_state(invalid), "Zodiac per-ball survival charge respects its two-charge cap")
	invalid = state.duplicate(true)
	invalid.balls[5].extra.MORPH = {}
	_check(not service.valid_state(invalid), "per-ball extra cannot name an unrelated expansion set")
	var zodiac = load(base.path_join("zodiac_rules.gd")).new()
	zodiac.reset_round("alignment")
	zodiac.register_ball(1, ["ZODIAC_ARIES"])
	zodiac.register_ball(2, ["ZODIAC_ARIES"])
	_check(overlay.shared_lines({"ZODIAC": zodiac.capture_shared()}) == ["ZODIAC  Fire 1"],
		"duplicate Zodiac signs do not produce a false Aspect")
	zodiac.register_ball(3, ["ZODIAC_LEO"])
	_check(overlay.shared_lines({"ZODIAC": zodiac.capture_shared()}) == ["ZODIAC  Fire 2 Aspect"],
		"two distinct live signs display Aspect from authoritative alignment")
	zodiac.register_ball(4, ["ZODIAC_SAGITTARIUS"])
	_check(overlay.shared_lines({"ZODIAC": zodiac.capture_shared()}) == ["ZODIAC  Fire 3 Grand Trine"],
		"three distinct live signs display Grand Trine from authoritative alignment")
	zodiac.set_alive(4, false)
	_check(overlay.shared_lines({"ZODIAC": zodiac.capture_shared()}) == ["ZODIAC  Fire 2 Aspect"],
		"removal and resync downgrade the visible alignment without replaying an ability")
	service.free()


func _registry(script: Script) -> void:
	_check(script.SET_IDS.size() == 6, "six expansion set ids")
	_check(not script.any_enabled(script.default_flags()), "defaults are off")
	_check("PHASES" in script.shop_only_set_ids(), "phases excluded from vote pool")
	_check(script.is_native_lobby_deck("1_CLASSIC"), "classic deck is native lobby")
	_check(script.is_native_lobby_set("GACHA"), "gacha set is native lobby")
	_check(not script.is_native_lobby_deck("DAILY"), "daily excluded from lobby select")
	_check(not script.is_native_lobby_deck("TOGETHER"), "together excluded from lobby select")
	_check(not script.is_native_lobby_set("PHASES"), "expansion set excluded from lobby select")
	var stale = script.normalize_flags({"PHASES": true, "MORPH": true})
	_check(script.any_enabled(stale), "stale per-set flags can be on")
	_check(
		not script.any_enabled(script.effective_flags(false, stale)),
		"master-off forces every expansion inactive"
	)
	_check(
		script.any_enabled(script.effective_flags(true, stale)),
		"master-on restores per-set activation"
	)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

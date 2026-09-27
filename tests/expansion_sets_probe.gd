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

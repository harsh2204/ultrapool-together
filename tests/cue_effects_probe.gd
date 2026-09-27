extends SceneTree
## Pure cue-perk regression scenarios. Run only in the authorized capture harness.

var checks = 0
var failures: Array[String] = []


class HostFixture extends Node:
	func is_table_host() -> bool:
		return true


class TableFixture extends RefCounted:
	var table: Node


func _initialize() -> void:
	var base = get_script().resource_path.get_base_dir().path_join("../mod")
	var script = load(base.path_join("cue_effect_rules.gd"))
	_check_qualifying_pots(script)
	_check_contacts(script)
	_check_strength_and_pockets(script)
	_check_round_context(script)
	_check_personal_and_team_history(script)
	_check_budget_and_swaps(script)
	_check_rejection_and_bounds(script)
	_check_skipped_shots(script)
	_check_native_callback_guards(base)
	_check_pocket_geometry(base)
	_finish()


func _fresh(script):
	var rules = script.new()
	rules.reset_round("table:round:1")
	return rules


func _begin(rules, index: int, actor: int, model: String, power = 100.0, count = 4):
	_check(
		rules.begin_shot(index, actor, model, power, count, [1, 2, 3, 4]),
		"accepted %s shot %d starts for player %d" % [model, index, actor]
	)


func _check_qualifying_pots(script) -> void:
	var rules = _fresh(script)
	_begin(rules, 1, 10, "bankshot")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "an unbanked pot does not consume Bankshot")
	_check(not rules.perk_used and rules.shot_pots == 1, "nonqualifying pots still count for history")
	rules.wall(2)
	_check(is_equal_approx(rules.pocket(2, 50.0, "middle"), 2.0), "the first banked pot earns its cap")
	rules.wall(3)
	_check(rules.pocket(3, 50.0, "corner") == 0.0, "a second qualifying pot earns no extra perk")
	_check(rules.pocket(2, 50.0, "middle") == 0.0, "duplicate pocket callbacks cannot pay twice")
	_check(rules.shot_pots == 3, "duplicate pocket callbacks do not inflate history")
	rules.finish_shot()
	_check(rules.pocket(4, 50.0, "middle") == 0.0, "late events cannot pay after shot completion")
	for model in ["house", "finesse", "firm"]:
		rules = _fresh(script)
		_begin(rules, 1, 10, model)
		rules.wall(1)
		_check(rules.pocket(1, 100.0, "corner") == 0.0, "%s adds no bonus score" % model)
		_check(rules.shot_pots == 1, "%s pots still participate in teammate/recovery history" % model)


func _check_contacts(script) -> void:
	var rules = _fresh(script)
	_begin(rules, 1, 10, "double_rail")
	rules.wall(1)
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "one rail does not qualify Double Rail")
	rules.wall(2)
	rules.wall(2)
	_check(rules.pocket(2, 50.0, "corner") > 0.0, "two rails qualify Double Rail")
	rules = _fresh(script)
	_begin(rules, 1, 10, "carom")
	for attempt in range(10):
		rules.hit(1, 2)
		rules.hit(2, 1)
	rules.hit(1, 999)
	rules.hit(1, 1)
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "repeated same-object contact is not a carom")
	rules.hit(2, 3)
	_check(rules.pocket(2, 50.0, "corner") > 0.0, "two distinct object contacts qualify Carom")
	rules = _fresh(script)
	_begin(rules, 1, 10, "clean")
	rules.wall(1)
	_check(rules.pocket(1, 50.0, "middle") == 0.0, "an object rail disqualifies Clean")
	_check(rules.pocket(2, 50.0, "middle") > 0.0, "an unbanked object still qualifies Clean")
	_check(rules.register_ball(8), "a spawned object can join the active shot")
	_check(rules.register_ball(8), "repeated registration retains existing contact history")


func _check_strength_and_pockets(script) -> void:
	for sample in [
		["silk", 90.0, true], ["silk", 90.01, false],
		["thunder", 170.0, true], ["thunder", 169.99, false],
	]:
		var rules = _fresh(script)
		_begin(rules, 1, 10, sample[0], sample[1])
		_check(
			(rules.pocket(1, 50.0, "corner") > 0.0) == sample[2],
			"%s uses its inclusive raw-power boundary %.2f" % [sample[0], sample[1]]
		)
	var rules = _fresh(script)
	_begin(rules, 1, 10, "corner")
	_check(rules.pocket(1, 50.0, "middle") == 0.0, "Corner ignores middle pockets")
	_check(rules.pocket(2, 50.0, "corner") > 0.0, "Corner rewards a fixed corner")
	rules = _fresh(script)
	_begin(rules, 1, 10, "sidewinder")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "Sidewinder ignores corners")
	_check(rules.pocket(2, 50.0, "middle") > 0.0, "Sidewinder rewards a fixed middle pocket")
	rules = _fresh(script)
	_begin(rules, 1, 10, "clean")
	_check(is_equal_approx(rules.pocket(1, 1.0, "corner"), 0.02), "tiny bonuses stay fractional")
	_check(rules.bonus_for(10) < 1.0, "a low-value pot is never rounded upward to a full point")


func _check_round_context(script) -> void:
	var rules = _fresh(script)
	_begin(rules, 1, 10, "opener")
	_check(rules.pocket(1, 50.0, "corner") > 0.0, "Opener works on the first accepted round shot")
	rules.finish_shot()
	_begin(rules, 2, 20, "opener")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "Opener is round-wide, not each player's first shot")
	rules.finish_shot()
	rules.reset_round("table:round:2")
	_begin(rules, 3, 20, "opener")
	_check(rules.pocket(1, 50.0, "corner") > 0.0, "a new round restores the Opener condition")
	rules = _fresh(script)
	_begin(rules, 1, 10, "house")
	rules.finish_shot()
	_begin(rules, 2, 10, "opener")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "equipping Opener later cannot reset first-shot history")
	for count in [3, 4]:
		rules = _fresh(script)
		_begin(rules, 1, 10, "closer", 100.0, count)
		_check(
			(rules.pocket(1, 50.0, "corner") > 0.0) == (count <= 3),
			"Closer freezes the ordinary-object count at shot start"
		)
		_check(rules.pocket(2, 50.0, "corner") == 0.0, "pots during the shot cannot newly enable Closer")


func _check_personal_and_team_history(script) -> void:
	var rules = _fresh(script)
	_begin(rules, 1, 10, "comeback")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "Comeback cannot reward a player's first-ever shot")
	rules.finish_shot()
	_begin(rules, 2, 10, "house")
	rules.finish_shot()
	_begin(rules, 3, 20, "house")
	rules.pocket(1, 50.0, "corner")
	rules.finish_shot()
	_begin(rules, 4, 10, "comeback")
	_check(rules.pocket(1, 50.0, "corner") > 0.0, "Comeback uses the player's own previous dry shot")
	rules.finish_shot()
	_begin(rules, 5, 10, "comeback")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "a successful personal shot clears recovery eligibility")
	rules = _fresh(script)
	_begin(rules, 1, 10, "house")
	rules.pocket(1, 50.0, "corner")
	rules.finish_shot()
	_begin(rules, 2, 10, "relay")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "Relay excludes the same player's previous pot")
	rules.finish_shot()
	_begin(rules, 3, 20, "relay")
	_check(rules.pocket(1, 50.0, "corner") > 0.0, "Relay rewards a different teammate's previous pot")
	rules.finish_shot()
	_begin(rules, 4, 10, "house")
	rules.finish_shot()
	_begin(rules, 5, 20, "relay")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "a dry intervening shot expires Relay")
	rules.finish_shot()
	rules.reset_round("table:round:2")
	_begin(rules, 6, 20, "relay")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "Relay history does not cross a round boundary")


func _check_budget_and_swaps(script) -> void:
	var rules = _fresh(script)
	for index in [1, 2]:
		_begin(rules, index, 10, "bankshot")
		rules.wall(1)
		_check(is_equal_approx(rules.pocket(1, 100.0, "corner"), 2.0), "a large pot respects its shot cap")
		rules.finish_shot()
	_check(is_equal_approx(rules.bonus_for(10), 4.0), "two capped pots exhaust the personal round budget")
	_begin(rules, 3, 10, "corner")
	_check(rules.pocket(1, 100.0, "corner") == 0.0, "switching models cannot replenish the round budget")
	_check(rules.perk_used, "a qualifying pot consumes the perk even with no budget remaining")
	rules.finish_shot()
	rules.reset_round("table:round:1")
	_check(is_equal_approx(rules.bonus_for(10), 4.0), "refreshing the same round cannot reset its budget")
	_begin(rules, 4, 20, "corner")
	_check(rules.pocket(1, 100.0, "corner") > 0.0, "one player's budget cannot consume a teammate's")
	rules.finish_shot()
	rules.reset_round("table:round:2")
	_check(rules.bonus_for(10) == 0.0, "a new round clears personal budgets")
	_begin(rules, 5, 10, "bankshot")
	rules.wall(1)
	_check(rules.pocket(1, 100.0, "corner") > 0.0, "the next round allows a fresh earned bonus")
	rules.finish_shot()
	rules.reset_round("table:round:3")
	for index in [6, 7]:
		_begin(rules, index, 10, "silk", 75.0)
		rules.pocket(1, 100.0, "corner")
		rules.finish_shot()
	_begin(rules, 8, 10, "bankshot")
	rules.wall(1)
	_check(is_equal_approx(rules.pocket(1, 100.0, "corner"), 1.0), "the last reward clips to remaining budget")


func _check_rejection_and_bounds(script) -> void:
	var rules = _fresh(script)
	for invalid in [NAN, INF, -INF, 0.0, 50.0, 201.0]:
		_check(not rules.begin_shot(1, 10, "clean", invalid, 1, [1]), "invalid raw strength cannot open a shot")
	_check(not rules.begin_shot(1, 0, "clean", 100.0, 1, [1]), "invalid actors cannot open a shot")
	_check(not rules.begin_shot(1, 10, "unknown", 100.0, 1, [1]), "unknown models cannot open a shot")
	_check(not rules.begin_shot(1, 10, "clean", 100.0, 2, [1]), "impossible live counts reject")
	_check(not rules.begin_shot(1, 10, "clean", 100.0, 1, [1, 1]), "duplicate bodies reject initial hydration")
	_check(not rules.begin_shot(1, 10, "clean", 100.0, 1, ["1"]), "string body identities reject")
	_check(not rules.pending and rules.shot_index == 0, "rejected begins do not consume a shot")
	_begin(rules, 1, 10, "clean")
	_check(not rules.begin_shot(2, 20, "corner", 100.0, 1, [1]), "pending shots reject overlap")
	for invalid in [NAN, INF, -INF, 0.0, -2.0]:
		_check(rules.pocket(1, invalid, "corner") == 0.0, "invalid native scores cannot reward a pot")
	_check(rules.pocket(999, 50.0, "corner") == 0.0, "unregistered callbacks cannot create objects")
	_check(rules.pocket(1, 50.0, "virtual") == 0.0, "virtual pockets cannot qualify")
	_check(rules.shot_pots == 0 and not rules.perk_used, "malformed pots cannot consume history or perks")
	_check(rules.pocket(1, 50.0, "corner") > 0.0, "a valid pot remains eligible after malformed callbacks")
	rules.finish_shot()
	_check(not rules.begin_shot(1, 10, "corner", 100.0, 1, [1]), "replayed accepted indices reject")
	var ids: Array = []
	for id in range(1, 129):
		ids.append(id)
	_check(rules.begin_shot(2, 10, "carom", 100.0, 128, ids), "the full supported object bound fits")
	_check(not rules.register_ball(129), "spawn overflow cannot exceed the shot's bound")
	for id in range(2, 129):
		rules.hit(1, id)
		rules.wall(1)
	_check(rules.pocket(1, 50.0, "corner") > 0.0, "bounded contact saturation preserves qualification")
	rules.finish_shot()
	ids.append(129)
	_check(not rules.begin_shot(3, 10, "clean", 100.0, 129, ids), "oversized initial object lists reject")
	for actor in range(11, 18):
		_check(rules.begin_shot(actor, actor, "house", 100.0, 1, [1]), "up to eight player histories fit")
		rules.finish_shot()
	_check(not rules.begin_shot(18, 18, "house", 100.0, 1, [1]), "a ninth actor cannot create unbounded history")


func _check_skipped_shots(script) -> void:
	var rules = _fresh(script)
	_begin(rules, 1, 10, "bankshot")
	rules.wall(1)
	rules.pocket(1, 100.0, "corner")
	# An unsupported new shot may also recover a stale pending perk attempt.
	_check(rules.skip_shot(2, 10), "an unsupported board can admit its native shot without perks")
	_check(not rules.pending and rules.shot_index == 2, "skip closes pending state and advances admission")
	_check(is_equal_approx(rules.bonus_for(10), 2.0), "skip preserves already spent round budget")
	_check(rules.pocket(1, 100.0, "corner") == 0.0, "skipped-shot callbacks cannot award bonus points")
	_check(not rules.register_ball(5), "late spawned objects cannot reopen a skipped shot")
	_begin(rules, 3, 10, "bankshot")
	rules.wall(1)
	_check(is_equal_approx(rules.pocket(1, 100.0, "corner"), 2.0), "supported play resumes with remaining budget")
	rules.finish_shot()
	_check(rules.skip_shot(4, 20), "a teammate's unsupported shot can also proceed")
	_begin(rules, 5, 10, "corner")
	_check(rules.pocket(1, 100.0, "corner") == 0.0, "skipping another actor cannot replenish an exhausted budget")
	rules = _fresh(script)
	var oversized: Array = []
	for id in range(1, 130):
		oversized.append(id)
	_check(
		not rules.begin_shot(1, 10, "opener", 100.0, 129, oversized),
		"an oversized initial board cannot create unbounded perk tracking"
	)
	_check(rules.skip_shot(1, 10), "rejected perk hydration still records native shot admission")
	_begin(rules, 2, 20, "opener")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "a skipped first shot cannot defer Opener to the next shot")
	_check(not rules.skip_shot(2, 20), "duplicate skip indices cannot close a valid pending shot")
	_check(rules.pending, "a rejected duplicate skip preserves pending state")
	rules = _fresh(script)
	_begin(rules, 1, 10, "house")
	rules.finish_shot()
	rules.skip_shot(2, 10)
	_begin(rules, 3, 10, "comeback")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "unknown skipped pot history cannot enable Comeback")
	rules = _fresh(script)
	_begin(rules, 1, 10, "house")
	rules.pocket(1, 50.0, "corner")
	rules.finish_shot()
	rules.skip_shot(2, 20)
	_begin(rules, 3, 10, "relay")
	_check(rules.pocket(1, 50.0, "corner") == 0.0, "unknown skipped teammate history cannot enable Relay")
	rules.finish_shot()
	_begin(rules, 4, 20, "relay")
	_check(rules.pocket(1, 50.0, "corner") > 0.0, "known successful history resumes Relay after a skip")


func _check_native_callback_guards(base: String) -> void:
	var service = load(base.path_join("cue_effects.gd")).new()
	var controller = HostFixture.new()
	service._controller = controller
	service.begin_session()
	# No accepted shot exists, so detached/malformed callback traffic must be inert.
	service.record_hit(null, null)
	service.record_wall(null)
	service.record_pocket(null, null, NAN)
	_check(not service.rules.pending, "callbacks without an accepted shot remain inert")
	_begin(service.rules, 1, 10, "clean")
	var foreign = Node2D.new()
	service.record_hit(foreign, foreign)
	service.record_wall(foreign)
	service.record_pocket(foreign, null, 1.0)
	service.record_pocket(null, foreign, 1.0)
	_check(service.rules.shot_pots == 0, "foreign native callbacks cannot record an eligible pot")
	_check(service.rules.bonus_for(10) == 0.0, "malformed active callbacks cannot award bonus score")
	service.end_session()
	_check(service.rules == null, "session teardown clears all perk history")
	foreign.free()
	service.free()
	controller.free()


func _check_pocket_geometry(base: String) -> void:
	var service = load(base.path_join("cue_effects.gd")).new()
	var game = TableFixture.new()
	game.table = Node2D.new()
	var container = Node2D.new()
	container.name = "Pockets"
	game.table.add_child(container)
	# Deliberately scramble child order: native indices are not pocket geometry.
	for position in [
		Vector2(100, 0), Vector2(-100, -200), Vector2(100, 200),
		Vector2(-100, 0), Vector2(100, -200), Vector2(-100, 200),
	]:
		var pocket = Pocket.new()
		pocket.position = position
		container.add_child(pocket)
	service._cache_pockets(game)
	for pocket in container.get_children():
		var expected = "middle" if pocket.position.y == 0.0 else "corner"
		_check(
			service._fixed_pockets[pocket.get_instance_id()].kind == expected,
			"fixed pocket role follows local geometry instead of child index"
		)
	game.table.free()
	service.free()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("CUE_EFFECTS_PROBE PASS (%d checks)" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("CUE_EFFECTS_PROBE FAIL: ", failure)
		print("CUE_EFFECTS_PROBE FAIL (%d/%d)" % [failures.size(), checks])
		quit(1)

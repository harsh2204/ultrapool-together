extends RefCounted
## MOD-04 / PERF-028: final competitive award comes from the real room summary
## resolver. Both presentation consumers read it without changing native score.

const BountyRace = preload("../mod/bounty_race.gd")
const WatchFixture = preload("native_table_effects_fixture.gd")


func check_guest(mod: Node, baseline: Dictionary, record: Callable, capture: Callable) -> void:
	var summaries: Array = [
		_summary(0, 80.0, 2, true), _summary(1, 50.0, 2, false), _summary(2, 70.0, 3, true)
	]
	BountyRace.resolve(summaries, true)
	record.call(summaries.all(func(item): return BountyRace.award_text(item).is_empty()),
		"Bounty feedback: pending competitive standings cannot announce a final award")
	var pending: Array = summaries.duplicate(true)
	summaries[1].finished = true
	BountyRace.resolve(summaries, true)
	record.call(summaries[0].score == 105.0 and summaries[1].score == 75.0 and summaries[2].score == 70.0,
		"Bounty feedback: real resolver awards both earliest-shot ties and excludes a later claim")
	record.call(BountyRace.award_text(summaries[0]) == "Bounty +25 points"
		and BountyRace.award_text(summaries[1]) == "Bounty +25 points"
		and BountyRace.award_text(summaries[2]).is_empty(),
		"Bounty feedback: cause text follows finalized award ownership, including ties")
	var resolved: Array = summaries.duplicate(true)
	BountyRace.resolve(summaries, true)
	record.call(summaries == resolved, "Bounty feedback: repeated resolution never adds the award twice")
	_check_validation(summaries[0], record)
	var game = mod.get_node("/root/Global").gameManager
	var before: Array = [game.score, game.player_info.money, game.player_info.hp, game.replicas.keys()]
	var saved = {"lobby": mod.lobby, "finished": mod.finished, "finish_reason": mod.finish_reason,
		"table_id": mod.table_id, "spectator": mod.spectator,
		"total_score": mod.total_score, "used_shots": mod.used_shots}
	mod.lobby = mod.lobby.duplicate(true)
	mod.lobby.table_count = 3
	mod.lobby.match_mode = "score"
	# The surrounding capture may use a named cooperative budget. This fixture
	# switches to Score mode, whose live protocol/HUD contract requires an integer.
	mod.lobby.shot_budget = 6
	mod.total_score = float(summaries[0].base_score)
	mod.used_shots = 6
	mod.lobby.table_summaries = pending
	mod.table_id = 0
	mod.finished = true
	mod.finish_reason = "Run ended"
	record.call(not "Bounty" in mod._result_text(), "Bounty feedback: own-table result waits for final standings")
	mod.lobby.table_summaries = summaries
	var own_text: String = mod._result_text()
	record.call(own_text == "Your table won · Bounty +25 points",
		"Bounty feedback: real own-table result names its final competitive award")
	mod.table_id = 1
	record.call("Bounty +25 points" in mod._result_text(),
		"Bounty feedback: tied Bounty winner retains its award even when another table wins the score match")
	mod.table_id = 2
	record.call(not "Bounty" in mod._result_text(), "Bounty feedback: losing later claimant cannot display the reward")
	mod.table_id = 0
	mod._update_hud()
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	record.call(mod.turn_label.text == own_text and mod.turn_label.is_visible_in_tree(),
		"Bounty feedback: actual playing-table result control presents the cause")
	record.call(mod.score_label.text == "Table 1 · 80 points · 6/6 shots",
		"Bounty feedback: own-table score control formats real numeric score and budget values")
	_check_fit(mod.turn_label, record, "own-table result")
	_check_fit(mod.score_label, record, "own-table score")
	await capture.call("39-guest-bounty-award", "Guest result · finalized competitive Bounty reward")
	var controller = WatchFixture.WatchController.new()
	controller.ui_root = mod.ui_root
	controller.skin = mod.skin
	controller.lobby = {"table_count": 3, "match_mode": "score", "table_summaries": pending}
	mod.add_child(controller)
	var watcher = load(get_script().resource_path.get_base_dir().path_join("../mod/table_spectator.gd")).new()
	controller.add_child(watcher)
	watcher.setup(controller)
	watcher.watch(1)
	watcher.apply_snapshot(1, baseline)
	watcher.apply_state(1, {"finished": true})
	watcher.tick(0.0)
	record.call(not "Bounty" in watcher._status.text,
		"Bounty feedback: finished watcher waits while another table has not completed")
	# Deliver only the final room summaries. There is deliberately no subsequent
	# table snapshot/state: roster reconciliation must refresh this finished view.
	controller.lobby.table_summaries = summaries
	mod.spectator = watcher
	mod._roster_changed()
	# The capture harness pauses the controller's per-frame HUD refresh. Exercise
	# that actual presentation boundary explicitly after entering the watched view.
	mod._update_hud()
	record.call(not mod.turn_label.visible and not mod.score_label.visible,
		"Bounty feedback: spectator result hides the unrelated own-table HUD")
	record.call("Bounty +25 points" in watcher._status.text,
		"Bounty feedback: lobby-only finalization updates the finished watched table")
	var watched_text: String = watcher._status.text
	mod._roster_changed()
	record.call(watcher._status.text == watched_text and watched_text.count("Bounty +25 points") == 1,
		"Bounty feedback: duplicate room summaries do not append a second cause label")
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	_check_fit(watcher._status, record, "spectator result")
	await capture.call("39-spectator-bounty-award", "Spectator result · tied earliest-shot Bounty award")
	watcher.watch(2)
	watcher.apply_snapshot(2, baseline)
	watcher.apply_state(2, {"finished": true})
	watcher.tick(0.0)
	record.call(not "Bounty" in watcher._status.text,
		"Bounty feedback: switching to a later claimant clears the previous table's award")
	var reset: Array = summaries.duplicate(true)
	BountyRace.resolve(reset, false)
	record.call(reset.all(func(item): return item.score == item.base_score and BountyRace.award_text(item).is_empty()),
		"Bounty feedback: noncompetitive/reset standings discard previous competitive bonuses")
	controller.lobby.table_summaries = reset
	mod.lobby.table_summaries = reset
	watcher.watch(1)
	watcher.apply_snapshot(1, baseline)
	watcher.apply_state(1, {"finished": true})
	watcher.refresh_summary()
	record.call(not "Bounty" in watcher._status.text and not "Bounty" in mod._result_text(),
		"Bounty feedback: reset standings clear both presentation consumers")
	watcher.close()
	controller.queue_free()
	mod.spectator = saved.spectator
	mod.lobby = saved.lobby
	mod.finished = saved.finished
	mod.finish_reason = saved.finish_reason
	mod.table_id = saved.table_id
	mod.total_score = saved.total_score
	mod.used_shots = saved.used_shots
	mod._update_hud()
	record.call(before == [game.score, game.player_info.money, game.player_info.hp, game.replicas.keys()],
		"Bounty feedback: resolution display never awards native score, economy, health or balls")
	record.call(summaries == resolved, "Bounty feedback: result rendering preserves authoritative resolved summaries")


func _summary(table: int, score: float, shot: int, finished: bool) -> Dictionary:
	return {"table": table, "score": score, "base_score": score, "bounty_shot": shot,
		"bounty_bonus": 0.0, "finished": finished, "status": "Run ended"}


func _check_validation(winner: Dictionary, record: Callable) -> void:
	for value in [0.0, 24.0, 26.0, INF, NAN, "25"]:
		var invalid: Dictionary = winner.duplicate(true)
		invalid.bounty_bonus = value
		record.call(BountyRace.award_text(invalid).is_empty(), "Bounty feedback: malformed or unawarded bonus produces no text")
	for value in [0, -1, "2"]:
		var invalid: Dictionary = winner.duplicate(true)
		invalid.bounty_shot = value
		record.call(BountyRace.award_text(invalid).is_empty(), "Bounty feedback: invalid claim shot produces no text")
	for value in [false, 1, "true"]:
		var invalid: Dictionary = winner.duplicate(true)
		invalid.finished = value
		record.call(BountyRace.award_text(invalid).is_empty(), "Bounty feedback: only a finished authoritative summary can announce reward")


func _check_fit(label: Label, record: Callable, role: String) -> void:
	var font: Font = label.get_theme_font("font")
	var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.get_theme_font_size("font_size")).x
	var style: StyleBox = label.get_theme_stylebox("normal")
	var padding: float = style.get_minimum_size().x if style != null else 0.0
	var rect: Rect2 = label.get_global_rect()
	record.call(width + padding <= label.size.x + 1.0
		and rect.position.x >= -1.0 and rect.end.x <= label.get_viewport_rect().size.x + 1.0,
		"Bounty feedback: " + role + " rendered award text fits its control and viewport")

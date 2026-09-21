extends SceneTree

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var race = load(get_script().resource_path.get_base_dir().path_join("../mod/bounty_race.gd"))
	var summaries = [_summary(0, 40.0, 2, true, [10]), _summary(1, 80.0, 0, false, [20, 30])]
	race.resolve(summaries, true)
	_check(summaries[0].score == 40.0, "unfinished competitor prevents early award")
	_check(summaries[0].bounty_bonus == 0.0, "unresolved race has no bonus")
	summaries[1].finished = true
	summaries[1].bounty_shot = 3
	race.resolve(summaries, true)
	_check(summaries[0].score == 65.0, "lower accepted shot wins after every table finishes")
	_check(summaries[1].score == 80.0, "later claim receives no reward")
	_check(summaries[0].base_score == 40.0, "base score remains unchanged")
	for iteration in 4:
		race.resolve(summaries, true)
	_check(summaries[0].score == 65.0, "repeated summaries never stack rewards")
	_check(summaries[0].bounty_bonus == 25.0, "one table can earn only one fixed reward")

	summaries = [
		_summary(0, 12.0, 2, true, [100]),
		_summary(1, 18.0, 2, true, [1, 2, 3, 4, 5]),
		_summary(2, 24.0, 4, true, [6]),
		_summary(3, 30.0, 0, true, [7])
	]
	race.resolve(summaries, true)
	_check(summaries[0].score == 37.0, "solo table receives full tied reward")
	_check(summaries[1].score == 43.0, "five-player table receives the same full tied reward")
	_check(summaries[2].score == 24.0, "later shot does not share an earlier tie")
	_check(summaries[3].score == 30.0, "zero means no claim")
	summaries.reverse()
	race.resolve(summaries, true)
	_check(summaries[2].score == 43.0, "table order and user IDs do not break ties")

	summaries = [_summary(0, 15.0, 3, true, [10]), _summary(1, 20.0, 1, true, [20])]
	summaries[1].status = "Table host disconnected"
	race.resolve(summaries, true)
	_check(summaries[1].score == 45.0, "terminal disconnect preserves an accepted claim")
	_check(summaries[0].bounty_bonus == 0.0, "disconnect does not manufacture a later winner")
	summaries[1].finished = false
	race.resolve(summaries, true)
	_check(summaries[1].score == 20.0, "incomplete reevaluation removes a stale award")
	_check(summaries[1].bounty_bonus == 0.0, "incomplete reevaluation clears the bonus field")

	summaries = [_summary(0, 15.0, 1, true, [10, 20])]
	race.resolve(summaries, false)
	_check(summaries[0].score == 15.0, "co-op does not receive the competitive race reward")
	_check(summaries[0].bounty_bonus == 0.0, "co-op bonus field stays zero")
	summaries = [_summary(0, 15.0, 0, true, [10]), _summary(1, 20.0, 0, true, [20])]
	race.resolve(summaries, true)
	_check(summaries[0].score == 15.0 and summaries[1].score == 20.0, "no claims means no reward")
	race.resolve([], true)
	print("BOUNTY_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _summary(table: int, score: float, shot: int, finished: bool, members: Array) -> Dictionary:
	return {
		"table": table,
		"base_score": score,
		"score": score,
		"bounty_shot": shot,
		"finished": finished,
		"members": members,
		"status": "Finished" if finished else "Playing"
	}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

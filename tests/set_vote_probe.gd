extends SceneTree

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var SetVote = load(get_script().resource_path.get_base_dir().path_join("../mod/set_vote.gd"))
	var DifficultyCatalog = load(
		get_script().resource_path.get_base_dir().path_join("../mod/difficulty_catalog.gd")
	)
	_check(
		DifficultyCatalog.forces_single_table(DifficultyCatalog.together_nighter_id()),
		"Together All Nighter is marked single-table"
	)
	_check(
		not DifficultyCatalog.forces_single_table("diff_6"),
		"native All Nighter stays multi-table capable in the lobby"
	)
	_check(
		DifficultyCatalog.together_nighter_id() == "diff_together_nighter",
		"Together All Nighter uses a stable mod difficulty id"
	)
	_check(
		DifficultyCatalog.NATIVE_ALL_NIGHTER_ID == "diff_6",
		"native All Nighter clones from diff_6"
	)

	var vote = SetVote.new()
	_check(not vote.active(), "empty set vote is inactive")
	_check(not vote.configure([10], ["A", "B"], 10), "solo tables cannot open a set vote")
	_check(
		vote.configure([20, 10], ["NATURE", "SPOOKY", "SPACE"], 10),
		"table members open a set ballot"
	)
	_check(vote.snapshot().options == ["NATURE", "SPOOKY", "SPACE"], "ballot options stay ordered")
	_check(not vote.cast(30, "NATURE"), "outsiders cannot cast a set vote")
	_check(not vote.cast(10, "MISSING"), "unknown set options are rejected")
	var revision = vote.revision
	_check(vote.cast(10, "SPOOKY", revision), "host can ballot for a set")
	_check(not vote.everyone_voted(), "partial ballots leave the vote open")
	_check(vote.cast(20, "NATURE", revision), "teammate can ballot for another set")
	_check(vote.everyone_voted(), "full table completes the set vote")
	_check(vote.resolve() == "NATURE" or vote.resolve() == "SPOOKY", "resolve returns a ballot option")
	# Tie of 1-1: host voted SPOOKY, guest NATURE — host breaks ties.
	_check(vote.resolve() == "SPOOKY", "host ballot breaks a tied set vote")

	vote.configure([10, 20, 30], ["A", "B", "C"], 10)
	vote.cast(20, "B")
	vote.cast(30, "B")
	vote.cast(10, "A")
	_check(vote.resolve() == "B", "majority wins over the host preference")

	vote.configure([10, 20], ["A", "B"], 10, "round-2", 1)
	vote.cast(10, "B")
	_check(vote.host_default() == "B", "timeout fallback prefers the host ballot")
	vote.clear()
	_check(not vote.active(), "clearing ends the set vote")

	print("SET_VOTE_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

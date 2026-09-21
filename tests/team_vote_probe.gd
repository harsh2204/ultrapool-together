extends SceneTree

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var model = load(get_script().resource_path.get_base_dir().path_join("../mod/team_vote.gd"))
	var vote = model.new()
	_check(not vote.unanimous(), "an empty team never approves an action")
	_check(not vote.configure([10, 10]), "duplicate identities cannot inflate the team")
	_check(not vote.configure([0]), "invalid identities are rejected")
	_check(not vote.configure(["10"]), "string identities are rejected")
	_check(vote.configure([20, 10], "shop:1"), "a connected team opens a vote")
	_check(vote.snapshot().eligible == [10, 20], "eligible identities have stable order")
	_check(not vote.set_ready(30, true), "outsiders cannot consent for the team")
	var initial: int = vote.revision
	_check(vote.set_ready(10, true, initial), "first teammate readies")
	_check(not vote.unanimous(), "one teammate cannot commit a shared action")
	var after_first: int = vote.revision
	_check(vote.set_ready(10, true), "duplicate consent is accepted")
	_check(vote.revision == after_first, "duplicate consent does not change the vote")
	_check(vote.set_ready(20, true, initial), "simultaneous teammate consent uses the same context")
	_check(vote.unanimous(), "simultaneous consent completes the vote")
	_check(vote.revision == initial, "consent does not invalidate other teammates' requests")
	_check(vote.set_ready(10, true, initial), "replayed explicit consent remains idempotent")
	_check(vote.set_ready(10, false), "teammates can withdraw consent")
	_check(not vote.is_ready(10), "withdrawing removes the ready state")
	vote.set_ready(10, true)
	_check(vote.configure([10, 20], "shop:1"), "unchanged context can be refreshed")
	_check(vote.is_ready(10), "unchanged roster and context preserve consent")
	_check(vote.set_ready(20, true), "second teammate readies")
	_check(vote.unanimous(), "every connected teammate approves")
	var snapshot: Dictionary = vote.snapshot()
	snapshot.eligible.clear()
	snapshot.ready.clear()
	_check(vote.unanimous(), "snapshots cannot mutate the vote")
	_check(vote.configure([10], "shop:1"), "disconnect removes the absent teammate")
	_check(not vote.unanimous(), "disconnect resets consent instead of committing silently")
	_check(not vote.set_ready(10, true, initial), "old-roster consent cannot approve the new team")
	_check(not vote.set_ready(20, true), "disconnected teammates cannot vote")
	_check(vote.set_ready(10, true) and vote.unanimous(), "remaining teammate can approve anew")
	vote.configure([10, 20], "shop:1")
	_check(not vote.is_ready(10), "reconnection invalidates earlier consent")
	vote.set_ready(10, true)
	vote.configure([10, 20], "shop:2")
	_check(not vote.is_ready(10), "a new shop requires fresh consent")
	var context = {"money": 92, "slots": [1, 2]}
	vote.set_ready(10, true)
	var before_dictionary: int = vote.revision
	vote.configure([10, 20], context)
	_check(
		vote.revision > before_dictionary and not vote.is_ready(10),
		"changing a scalar context to a dictionary invalidates consent"
	)
	var inventory_generation: int = vote.revision
	vote.set_ready(10, true)
	context.slots[0] = 3
	_check(
		vote._context is Dictionary and vote._context.get("slots") == [1, 2],
		"nested context is copied independently from its caller"
	)
	vote.configure([10, 20], context)
	_check(not vote.is_ready(10), "inventory changes invalidate consent")
	_check(vote.revision > inventory_generation, "inventory changes advance the consent generation")
	vote.set_ready(10, true)
	context.money = 80
	vote.configure([10, 20], context)
	_check(not vote.is_ready(10), "shared spending invalidates consent")
	vote.set_ready(10, true)
	vote.configure([10, 20], ["round", 2])
	_check(not vote.is_ready(10), "changing a dictionary context to an array invalidates consent")
	vote.set_ready(10, true)
	vote.configure([10, 20], "next-shop")
	_check(not vote.is_ready(10), "changing an array context to a scalar invalidates consent")
	vote.set_ready(10, true)
	var before_reset: int = vote.revision
	vote.reset()
	_check(not vote.is_ready(10), "reset clears consent")
	_check(not vote.set_ready(10, true, before_reset), "reset prevents old-vote replay")
	print("TEAM_VOTE_PROBE ", "PASS" if failures.is_empty() else "FAIL", " ", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures.append(label)
		push_error("TEAM_VOTE_PROBE: " + label)

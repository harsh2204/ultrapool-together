extends SceneTree
## Model coverage; embedded in the authorized Capture-Screens
## harness. Catalog fixtures isolate wire/archive rules from native presentation.

const EndRun = preload("../mod/end_run_state.gd")
const Discussion = preload("../mod/end_run_discussion.gd")
const CueInventory = preload("../mod/cue_inventory.gd")


class ItemData:
	extends RefCounted
	var from_set = "CLASSIC"


class Database:
	extends Node
	var id_to_ball: Dictionary = {}
	var id_to_passive: Dictionary = {}


var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var database = Database.new()
	var ordinary = ItemData.new()
	var negative = ItemData.new()
	negative.from_set = "NEGATIVE"
	database.id_to_ball = {"ORB": ordinary, "NEGATIVE-ORB": negative}
	database.id_to_passive = {"SNACK": ItemData.new(), "GUMMY-BRAIN": ItemData.new()}
	_record_validation(database)
	_archive_lifetime(database)
	_completion()
	_winners()
	_discussion_slots(database)
	_discussion_ownership()
	_discussion_motion()
	_discussion_reconciliation()
	_discussion_validation()
	_discussion_counter_boundaries()
	database.free()
	print("END_RUN_PROBE ", "PASS" if failures.is_empty() else "FAIL", " ", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)


func _record_validation(database: Node) -> void:
	var record = _record()
	_check(EndRun.validate_record(record, database), "a complete final build passes validation")
	for value in [null, [], true, "record"]:
		_check(
			not EndRun.validate_record(value, database), "final build requires a record dictionary"
		)
	for field in ["match", "table", "leader", "inventory", "cues"]:
		var missing = record.duplicate(true)
		missing.erase(field)
		_check(not EndRun.validate_record(missing, database), "missing " + field + " is rejected")
	var invalid = record.duplicate(true)
	invalid["extra"] = "untrusted metadata"
	_check(not EndRun.validate_record(invalid, database), "unknown outer fields are rejected")
	for field in ["match", "leader"]:
		for value in [0, -1, "1", 1.0, true]:
			invalid = record.duplicate(true)
			invalid[field] = value
			_check(
				not EndRun.validate_record(invalid, database),
				field + " requires a positive identity"
			)
	for value in [-1, 8, "0", 0.0, false]:
		invalid = record.duplicate(true)
		invalid.table = value
		_check(not EndRun.validate_record(invalid, database), "invalid table identity is rejected")
	for field in ["inventory", "cues"]:
		for value in [null, [], "payload"]:
			invalid = record.duplicate(true)
			invalid[field] = value
			_check(
				not EndRun.validate_record(invalid, database), "malformed " + field + " is rejected"
			)
	for group in ["build", "passives", "cubes"]:
		invalid = record.duplicate(true)
		invalid.inventory[group] = []
		invalid.inventory[group].resize(65)
		_check(not EndRun.validate_record(invalid, database), "overfull " + group + " is rejected")
	invalid = record.duplicate(true)
	invalid.inventory.build.resize(15)
	_check(
		not EndRun.validate_record(invalid, database), "truncated native build slots are rejected"
	)
	invalid = record.duplicate(true)
	invalid.inventory.passives.resize(3)
	_check(
		not EndRun.validate_record(invalid, database), "truncated native passive slots are rejected"
	)
	for field in ["data", "mixed"]:
		invalid = record.duplicate(true)
		invalid.inventory.build[0][field] = "missing-resource"
		_check(
			not EndRun.validate_record(invalid, database), "unknown item " + field + " is rejected"
		)
	invalid = record.duplicate(true)
	invalid.inventory.passives[0] = _item("ORB")
	_check(
		not EndRun.validate_record(invalid, database), "ball identity cannot occupy a passive slot"
	)
	invalid = record.duplicate(true)
	invalid.inventory.cubes[0] = _item("ORB")
	_check(not EndRun.validate_record(invalid, database), "ordinary ball cannot occupy a cube slot")
	for value in [0, 1.0, "1"]:
		invalid = record.duplicate(true)
		invalid.inventory.build[0].level = value
		_check(not EndRun.validate_record(invalid, database), "invalid item level is rejected")
	invalid = record.duplicate(true)
	invalid.inventory.build[0].flaming = 1
	_check(not EndRun.validate_record(invalid, database), "item effect flags require booleans")
	invalid = record.duplicate(true)
	invalid.inventory.snacks = -1
	_check(not EndRun.validate_record(invalid, database), "invalid ticket count is rejected")
	invalid = record.duplicate(true)
	invalid.cues.players[0].finish = "missing-finish"
	_check(not EndRun.validate_record(invalid, database), "unknown cue finish is rejected")
	invalid = record.duplicate(true)
	invalid.cues.players[0].equipped = "bankshot"
	_check(not EndRun.validate_record(invalid, database), "unowned equipped cue is rejected")
	invalid = record.duplicate(true)
	invalid.cues.players.append(invalid.cues.players[0].duplicate(true))
	_check(not EndRun.validate_record(invalid, database), "duplicate cue owners are rejected")
	invalid = record.duplicate(true)
	invalid.inventory["oversized"] = "x".repeat(100000)
	_check(
		not EndRun.validate_record(invalid, database), "arbitrary inventory extension is rejected"
	)
	invalid = record.duplicate(true)
	invalid.inventory.build[0]["extra"] = "untrusted item metadata"
	_check(not EndRun.validate_record(invalid, database), "arbitrary item extension is rejected")
	# The IDs remain known to the fixture catalog and every slot is otherwise
	# valid. This reaches the encoded-byte boundary, not a count/schema rejection.
	var long_id = "ORB".repeat(1000)
	database.id_to_ball[long_id] = database.id_to_ball.ORB
	invalid = record.duplicate(true)
	invalid.inventory.build.clear()
	for _slot in range(64):
		invalid.inventory.build.append(_item(long_id))
	_check(not EndRun.validate_record(invalid, database), "oversized encoded record is rejected")
	database.id_to_ball.erase(long_id)


func _archive_lifetime(database: Node) -> void:
	var archive = EndRun.new()
	var record = _record()
	_check(not archive.accept(record, database), "an unconfigured archive rejects a run record")
	archive.reset(41)
	_check(archive.accept(record, database), "current-match final build enters the archive")
	_check(
		archive.has_table(0) and not archive.has_table(1), "archive tracks each table separately"
	)
	_check(archive.get_record(7).is_empty(), "missing build does not expose another table")
	var accepted = record.duplicate(true)
	record.inventory.build[0].level = 7
	record.cues.players[0].finish = "gold"
	_check(archive.get_record(0) == accepted, "retained record owns inventory and cue containers")
	var exposed = archive.get_record(0)
	exposed.inventory.build.clear()
	exposed.cues.players.clear()
	_check(archive.get_record(0) == accepted, "review reads cannot mutate the archived build")
	_check(archive.accept(accepted, database), "identical reliable replay is accepted")
	_check(not archive.accept(record, database), "conflicting replay cannot replace a final build")
	_check(archive.get_record(0) == accepted, "rejected replay leaves the first final build intact")
	var other = _record(1)
	other.leader = 20
	_check(archive.accept(other, database), "another table retains an independent final build")
	_check(archive.get_record(0) == accepted, "another table cannot overwrite the first build")
	var stale = _record(2)
	stale.match = 40
	_check(not archive.accept(stale, database), "late previous-match build is rejected")
	stale.match = 42
	_check(not archive.accept(stale, database), "unannounced future-match build is rejected")
	_check(not archive.has_table(2), "wrong-epoch delivery cannot reserve a table archive slot")
	archive.reset(42)
	_check(
		not archive.has_table(0) and not archive.has_table(1) and archive.get_record(0).is_empty(),
		"rematch removes every previous build"
	)
	_check(not archive.accept(accepted, database), "rematch rejects delayed completed-run data")
	_check(archive.accept(stale, database), "new-match record is accepted after explicit reset")
	archive.reset(0)
	_check(not archive.has_table(2), "disconnect teardown clears the retained archive")
	_check(not archive.accept(stale, database), "closed archive rejects late incoming records")


func _completion() -> void:
	_check(not EndRun.complete([]), "an empty room cannot complete a run")
	var summaries = [_summary(0), _summary(1)]
	_check(EndRun.complete(summaries), "every completed table resolves the room")
	summaries[1].finished = false
	_check(not EndRun.complete(summaries), "one active table keeps results pending")
	summaries[1].finished = true
	summaries[1].closed = true
	summaries[1].status = "Table host disconnected"
	_check(EndRun.complete(summaries), "closed table does not strand other completed tables")
	_check(not EndRun.complete([_summary(0), _summary(0)]), "duplicate table identity is rejected")
	_check(not EndRun.complete([null]), "malformed summary is rejected")
	for value in [-1, 8, "0", 0.0, false]:
		var invalid = _summary(0)
		invalid.table = value
		_check(
			not EndRun.complete([invalid]), "completion requires a bounded integer table identity"
		)
	for value in [null, 1, "true"]:
		var invalid = _summary(0)
		invalid.finished = value
		_check(not EndRun.complete([invalid]), "completion requires an explicit finished boolean")
	var oversized: Array = []
	for table in range(9):
		oversized.append(_summary(table))
	_check(not EndRun.complete(oversized), "an over-capacity result cannot complete the room")


func _winners() -> void:
	var summaries = [_summary(0, 20.0), _summary(1, 45.0)]
	_check(EndRun.winner_tables(summaries, "score") == [1], "highest final score wins")
	summaries[0].base_score = 20.0
	summaries[0].bounty_bonus = 25.0
	summaries[0].score = 45.0
	_check(
		EndRun.winner_tables(summaries, "score") == [0, 1], "final bounty award can create a tie"
	)
	summaries[1].finished = false
	for mode in ["score", "race", "coop"]:
		_check(
			EndRun.winner_tables(summaries, mode).is_empty(),
			"no " + mode + " award before all finish"
		)
	summaries = [_summary(0, 100.0), _summary(1, 5.0)]
	summaries[0].run_won = true
	summaries[0].finish_order = 2
	summaries[1].run_won = true
	summaries[1].finish_order = 1
	_check(
		EndRun.winner_tables(summaries, "race") == [1],
		"race awards first finish independently of score"
	)
	summaries[0].finish_order = 1
	_check(
		EndRun.winner_tables(summaries, "race") == [0, 1],
		"equal valid finish places share the spotlight"
	)
	summaries[0].run_won = false
	_check(
		EndRun.winner_tables(summaries, "race") == [1], "defeated table cannot claim a race place"
	)
	summaries[1].finish_order = 0
	_check(
		EndRun.winner_tables(summaries, "race").is_empty(), "unplaced race finish is not a winner"
	)
	summaries[1].run_won = false
	_check(
		EndRun.winner_tables(summaries, "coop").is_empty(),
		"all-defeat co-op has no false celebration"
	)
	summaries[0].run_won = true
	_check(
		EndRun.winner_tables(summaries, "coop") == [0],
		"co-op victory follows authoritative run outcome"
	)
	summaries[1].run_won = true
	_check(
		EndRun.winner_tables(summaries, "coop") == [0, 1],
		"co-op can celebrate every victorious table"
	)
	summaries = [_summary(0, 100.0), _summary(1, 5.0)]
	summaries[0].status = "Table host disconnected"
	summaries[0].closed = true
	_check(
		EndRun.winner_tables(summaries, "score") == [1],
		"disconnect before finish cannot win on partial score"
	)
	summaries[0].status = "Finished"
	_check(
		EndRun.winner_tables(summaries, "score") == [0],
		"disconnect after a valid finish preserves the winner"
	)
	summaries[0].status = "Table host disconnected"
	summaries[1].status = "Table host disconnected"
	_check(
		EndRun.winner_tables(summaries, "score").is_empty(),
		"all disconnected tables produce no winner"
	)


func _discussion_slots(database: Node) -> void:
	var discussion = Discussion.new()
	var build = _discussion_build()
	_check(not discussion.ensure_table(0, build), "closed discussion cannot create a rack")
	discussion.reset(41)
	for table in [-1, 8]:
		_check(not discussion.ensure_table(table, build), "discussion rejects an unavailable table")
	for count in [15, 65]:
		var invalid: Array = []
		invalid.resize(count)
		_check(not discussion.ensure_table(0, invalid), "discussion rejects invalid slot capacity")
	_check(discussion.snapshot(0).is_empty(), "failed initialization does not reserve a rack")
	var archive = EndRun.new()
	archive.reset(41)
	var record = _record()
	record.inventory.build = build
	_check(archive.accept(record, database), "discussion fixture retains a valid final archive")
	var original = archive.get_record(0)
	_check(
		discussion.ensure_table(0, original.inventory.build), "final build initializes discussion"
	)
	var initial = discussion.snapshot(0)
	_check(
		initial.order == range(16), "rack includes every original duplicate and empty slot identity"
	)
	_check(initial.revision == 0 and initial.drag.is_empty(), "new discussion has no held item")
	var exposed = discussion.snapshot(0)
	exposed.order.reverse()
	exposed.drag["actor"] = 999
	_check(discussion.snapshot(0) == initial, "discussion snapshots own their returned containers")
	var began = discussion.transition(0, 10, {"revision": 0, "action": "begin", "slot": 0})
	_check(
		began.accepted and began.changed and began.reason.is_empty(),
		"picking up a ball commits a transition"
	)
	_check(
		began.state.revision == 1 and began.state.drag.slot == 0,
		"pickup holds the original item identity"
	)
	var token: int = began.state.drag.token
	var dropped = discussion.transition(
		0, 10, {"revision": 1, "action": "drop", "token": token, "target": 1}
	)
	var empty_swap: Array = range(16)
	empty_swap[0] = 1
	empty_swap[1] = 0
	_check(
		dropped.accepted and dropped.state.order == empty_swap,
		"dropping into an empty slot swaps its original identity"
	)
	_check(
		dropped.state.revision == 2 and dropped.state.drag.is_empty(),
		"drop releases ownership and advances revision"
	)
	_reject_discussion_request(
		discussion,
		0,
		10,
		{"revision": 2, "action": "begin", "slot": 1},
		"empty identity stays empty after moving to an occupied position"
	)
	began = discussion.transition(0, 10, {"revision": 2, "action": "begin", "slot": 0})
	token = began.state.drag.token
	dropped = discussion.transition(
		0, 10, {"revision": 3, "action": "drop", "token": token, "target": 3}
	)
	var duplicate_swap = empty_swap.duplicate()
	duplicate_swap[1] = 3
	duplicate_swap[3] = 0
	_check(
		dropped.accepted and dropped.state.order == duplicate_swap,
		"equal-looking balls retain distinct identities when swapped"
	)
	_check(
		archive.get_record(0) == original and build == original.inventory.build,
		"discussion rearrangement never mutates archived or source inventory"
	)
	_check(
		discussion.ensure_table(0, build) and discussion.snapshot(0) == dropped.state,
		"repeated rack setup preserves the current arrangement"
	)
	var changed_build = build.duplicate(true)
	changed_build[0] = null
	changed_build[1] = _item("ORB")
	_check(
		discussion.ensure_table(0, changed_build),
		"same-capacity setup leaves archived occupancy authoritative"
	)
	_reject_discussion_request(
		discussion,
		0,
		10,
		{"revision": 4, "action": "begin", "slot": 1},
		"later caller data cannot turn an original empty slot into a ball"
	)
	began = discussion.transition(0, 10, {"revision": 4, "action": "begin", "slot": 0})
	_check(began.accepted, "later caller data cannot erase an original ball")
	var large: Array = []
	large.resize(64)
	large[63] = _item("ORB")
	_check(discussion.ensure_table(7, large), "expanded final rack retains its highest slot")
	_check(
		discussion.snapshot(7).order == range(64),
		"expanded rack keeps every slot without truncation"
	)
	_check(discussion.snapshot(6).is_empty(), "missing discussion table exposes no other rack")
	var returned = began.state
	returned.order.clear()
	returned.drag.clear()
	_check(
		(
			discussion.snapshot(0).order == duplicate_swap
			and not discussion.snapshot(0).drag.is_empty()
		),
		"transition responses cannot mutate retained discussion state"
	)


func _discussion_ownership() -> void:
	var discussion = _new_discussion()
	_check(discussion.ensure_table(1, _discussion_build()), "second rack initializes independently")
	var first = discussion.transition(0, 10, {"revision": 0, "action": "begin", "slot": 0})
	var token: int = first.state.drag.token
	_reject_discussion_request(
		discussion,
		0,
		20,
		{"revision": 0, "action": "begin", "slot": 3},
		"simultaneous stale pickup returns the accepted holder for rollback"
	)
	_reject_discussion_request(
		discussion,
		0,
		20,
		{"revision": 1, "action": "begin", "slot": 3},
		"one table cannot admit two holders"
	)
	_reject_discussion_request(
		discussion,
		1,
		10,
		{"revision": 0, "action": "begin", "slot": 3},
		"one actor cannot hold balls across two tables"
	)
	var other = discussion.transition(1, 20, {"revision": 0, "action": "begin", "slot": 3})
	_check(
		other.accepted and other.state.drag.token != token,
		"different actors can arrange separate racks with distinct tokens"
	)
	_reject_discussion_request(
		discussion,
		0,
		20,
		{"revision": 1, "action": "drop", "token": token, "target": 1},
		"a different actor cannot drop a held ball"
	)
	_reject_discussion_request(
		discussion,
		0,
		20,
		{"revision": 1, "action": "cancel", "token": token},
		"a different actor cannot cancel a hold"
	)
	_reject_discussion_request(
		discussion,
		0,
		20,
		{"revision": 1, "action": "reset"},
		"reset cannot interrupt another actor's hold"
	)
	_reject_discussion_request(
		discussion,
		0,
		10,
		{"revision": 1, "action": "drop", "token": token + 100, "target": 1},
		"a forged token cannot end the active hold"
	)
	var cancelled = discussion.transition(
		0, 10, {"revision": 1, "action": "cancel", "token": token}
	)
	_check(
		cancelled.accepted and cancelled.state.revision == 2 and cancelled.state.order == range(16),
		"cancel releases the ball without rearranging its rack"
	)
	_check(
		not discussion.apply_motion(0, 10, token, 1, Vector2(0.4, 0.5)),
		"motion after cancellation cannot resurrect a hold"
	)
	first = discussion.transition(0, 10, {"revision": 2, "action": "begin", "slot": 3})
	_check(first.state.drag.token > token, "new hold gets a newer token within the match")
	token = first.state.drag.token
	var reset_result = discussion.transition(0, 10, {"revision": 3, "action": "reset"})
	_check(
		(
			reset_result.accepted
			and reset_result.state.revision == 4
			and reset_result.state.drag.is_empty()
		),
		"holder can reset and release its rack"
	)
	_check(
		not discussion.apply_motion(0, 10, token, 1, Vector2.ONE),
		"motion after rack reset cannot restore an old hold"
	)
	first = discussion.transition(0, 10, {"revision": 4, "action": "begin", "slot": 0})
	var before_release = discussion.snapshot(0)
	_check(discussion.release_actor(10) == [0], "disconnect releases only the actor's held table")
	var released = discussion.snapshot(0)
	_check(
		(
			released.revision == before_release.revision + 1
			and released.drag.is_empty()
			and released.order == before_release.order
		),
		"disconnect commits release without changing arrangement"
	)
	_check(
		discussion.snapshot(1) == other.state,
		"disconnect preserves another actor's independent hold"
	)
	_check(discussion.release_actor(10).is_empty(), "repeated disconnect has no further transition")
	_check(
		not discussion.apply_motion(0, 10, first.state.drag.token, 1, Vector2.ONE),
		"motion after disconnect cannot resurrect the released ball"
	)
	_check(discussion.release_actor(20) == [1], "second actor disconnect releases its own rack")
	discussion.reset(42)
	_check(
		discussion.snapshot(0).is_empty() and discussion.snapshot(1).is_empty(),
		"rematch clears every arrangement and hold"
	)
	_check(
		not discussion.apply_motion(0, 10, first.state.drag.token, 2, Vector2.ONE),
		"no motion applies before a new-match archive initializes its rack"
	)
	_check(
		(
			discussion.ensure_table(0, _discussion_build())
			and discussion.snapshot(0).order == range(16)
		),
		"new match starts from original archive order"
	)
	discussion.reset(0)
	_check(
		discussion.snapshot(0).is_empty() and not discussion.ensure_table(0, _discussion_build()),
		"session teardown disables discussion until the next match"
	)


func _discussion_motion() -> void:
	var discussion = _new_discussion()
	var began = discussion.transition(0, 10, {"revision": 0, "action": "begin", "slot": 0})
	var token: int = began.state.drag.token
	_check(
		discussion.motion(0, 10, token, 1, Vector2(0.2, 0.3), 1000),
		"first owner motion is admitted immediately"
	)
	var first = discussion.snapshot(0)
	_check(
		(
			first.revision == 1
			and first.order == range(16)
			and first.drag.position == Vector2(0.2, 0.3)
		),
		"lossy motion changes presentation without a reliable revision or rearrangement"
	)
	for sequence in [2, 3, 4]:
		_check(
			not discussion.motion(0, 10, token, sequence, Vector2.ONE, 1000),
			"same-instant motion burst is discarded"
		)
	_check(
		discussion.snapshot(0) == first,
		"discarded motion does not advance sequence or overwrite position"
	)
	_check(
		discussion.motion(0, 10, token, 5, Vector2(0.5, 0.6), 2000),
		"later motion skips dropped samples without waiting for a queue"
	)
	var latest = discussion.snapshot(0)
	_check(
		not discussion.motion(0, 10, token, 4, Vector2.ZERO, 3000),
		"reordered motion cannot rewind a newer sample"
	)
	_check(
		not discussion.apply_motion(0, 10, token, 5, Vector2.ZERO),
		"duplicate motion cannot overwrite its accepted position"
	)
	_check(
		not discussion.motion(0, 20, token, 6, Vector2.ZERO, 3000),
		"motion requires the holder's actor identity"
	)
	_check(
		not discussion.motion(0, 10, token + 100, 6, Vector2.ZERO, 3000),
		"motion requires the active hold token"
	)
	_check(
		discussion.snapshot(0) == latest,
		"rejected ownership and replay samples preserve the current drag"
	)
	_check(
		discussion.motion(0, 10, token, 6, Vector2(-1.0, 2.0), 3000),
		"finite pointer coordinates can move beyond the rack before clamping"
	)
	_check(
		discussion.snapshot(0).drag.position == Vector2(0.0, 1.0),
		"admitted pointer position stays within normalized rack bounds"
	)
	latest = discussion.snapshot(0)
	for point in [Vector2(INF, 0.0), Vector2(0.0, -INF), Vector2(NAN, 0.0)]:
		_check(
			not discussion.motion(0, 10, token, 7, point, 4000),
			"nonfinite pointer coordinates are rejected"
		)
	for sequence in [0, -1, 2147483648]:
		_check(
			not discussion.motion(0, 10, token, sequence, Vector2.ZERO, 4000),
			"invalid motion sequence is rejected"
		)
	_check(discussion.snapshot(0) == latest, "invalid motion never changes the held item")
	_check(
		discussion.motion(0, 10, token, 7, Vector2(0.8, 0.9), 4000),
		"invalid packets do not consume the next valid motion admission"
	)
	var dropped = discussion.transition(
		0, 10, {"revision": 1, "action": "drop", "token": token, "target": 1}
	)
	_check(dropped.accepted, "reliable drop does not wait for the motion rate limit")
	_check(
		not discussion.motion(0, 10, token, 8, Vector2.ONE, 5000),
		"late motion after drop cannot move a released ball"
	)
	began = discussion.transition(0, 10, {"revision": 2, "action": "begin", "slot": 3})
	_check(
		not discussion.motion(0, 10, token, 8, Vector2.ONE, 4000),
		"previous hold token cannot move a new held ball"
	)
	_check(
		discussion.motion(0, 10, began.state.drag.token, 1, Vector2(0.1, 0.2), 4000),
		"new hold gets immediate motion despite the previous hold's admission time"
	)
	_check(
		not discussion.apply_motion(7, 10, token, 9, Vector2.ONE),
		"motion cannot create an unknown rack"
	)


func _discussion_reconciliation() -> void:
	var host = _new_discussion()
	var client = _new_discussion()
	var initial = host.snapshot(0)
	var began = host.transition(0, 10, {"revision": 0, "action": "begin", "slot": 0})
	var token: int = began.state.drag.token
	_check(client.apply_state(0, began.state), "client accepts the coordinator's reliable pickup")
	_check(
		client.apply_motion(0, 10, token, 7, Vector2(0.7, 0.6)),
		"client accepts newer disposable drag motion"
	)
	var moved = client.snapshot(0)
	_check(
		client.apply_state(0, began.state) and client.snapshot(0) == moved,
		"delayed reliable acknowledgement cannot rewind newer motion"
	)
	_check(
		client.apply_state(0, moved) and client.snapshot(0) == moved,
		"same-sequence same-position reliable replay is idempotent"
	)
	var foreign_position = moved.duplicate(true)
	foreign_position.drag.position = Vector2(0.1, 0.2)
	_reject_discussion_state(
		client,
		foreign_position,
		"same-sequence reliable reply cannot substitute a different position"
	)
	_check(
		not client.apply_state(0, initial) and client.snapshot(0) == moved,
		"stale reliable revision cannot undo an accepted hold"
	)
	for field in ["actor", "slot", "token"]:
		var conflicting = began.state.duplicate(true)
		conflicting.drag[field] = 20 if field == "actor" else (3 if field == "slot" else token + 1)
		_reject_discussion_state(
			client,
			conflicting,
			"same-revision " + field + " conflict cannot replace active ownership"
		)
	var conflicting = began.state.duplicate(true)
	conflicting.order[0] = 1
	conflicting.order[1] = 0
	_reject_discussion_state(
		client, conflicting, "same-revision permutation cannot rearrange the rack"
	)
	conflicting = began.state.duplicate(true)
	conflicting.drag = {}
	_reject_discussion_state(
		client, conflicting, "same-revision release cannot clear the active hold"
	)
	_check(
		host.motion(0, 10, token, 8, Vector2(0.8, 0.9), 1000),
		"coordinator can retain a later motion sample for resync"
	)
	_check(
		client.apply_state(0, host.snapshot(0)) and client.snapshot(0).drag.seq == 8,
		"same-revision resync accepts genuinely newer motion"
	)
	var dropped = host.transition(
		0, 10, {"revision": 1, "action": "drop", "token": token, "target": 1}
	)
	_check(client.apply_state(0, dropped.state), "newer reliable drop supersedes lossy motion")
	_check(
		client.snapshot(0) == dropped.state and client.snapshot(0).drag.is_empty(),
		"client converges to released authoritative arrangement"
	)
	_check(
		not client.apply_motion(0, 10, token, 8, Vector2.ONE),
		"motion crossing reliable release cannot restore the drag"
	)
	_reject_discussion_state(
		client, began.state, "late pickup reply cannot resurrect a finished move"
	)
	var exposed = dropped.state.duplicate(true)
	_check(client.apply_state(0, exposed), "identical reliable replay is idempotent")
	exposed.order.reverse()
	exposed.drag["actor"] = 999
	_check(
		client.snapshot(0) == dropped.state, "accepted coordinator state owns its copied containers"
	)
	var reset_result = host.transition(0, 20, {"revision": 2, "action": "reset"})
	_check(
		client.apply_state(0, reset_result.state) and client.snapshot(0).order == range(16),
		"reset restores original archive order for every client"
	)
	_reject_discussion_state(
		client, dropped.state, "late pre-reset arrangement cannot undo rack reset"
	)


func _discussion_validation() -> void:
	var discussion = _new_discussion()
	for request in [
		{},
		{"revision": 0, "action": "unknown"},
		{"revision": 0, "action": 1},
		{"revision": "0", "action": "reset"},
		{"revision": 0.0, "action": "reset"},
		{"revision": false, "action": "reset"},
		{"revision": -1, "action": "reset"},
		{"revision": 1, "action": "reset"},
		{"revision": 0, "action": "reset", "extra": true},
		{"revision": 0, "action": "begin"},
		{"revision": 0, "action": "begin", "slot": -1},
		{"revision": 0, "action": "begin", "slot": 16},
		{"revision": 0, "action": "begin", "slot": "0"},
		{"revision": 0, "action": "begin", "slot": 0.0},
		{"revision": 0, "action": "begin", "slot": false},
		{"revision": 0, "action": "begin", "slot": 0, "extra": true},
		{"revision": 0, "action": "drop", "token": 1, "target": 1},
		{"revision": 0, "action": "cancel", "token": 1}
	]:
		_reject_discussion_request(
			discussion, 0, 10, request, "malformed or inapplicable rack request is rejected"
		)
	_reject_discussion_request(
		discussion,
		0,
		0,
		{"revision": 0, "action": "begin", "slot": 0},
		"unidentified actor cannot acquire a ball"
	)
	_reject_discussion_request(
		discussion,
		7,
		10,
		{"revision": 0, "action": "begin", "slot": 0},
		"request cannot initialize a missing rack"
	)
	var began = discussion.transition(0, 10, {"revision": 0, "action": "begin", "slot": 0})
	var token: int = began.state.drag.token
	for target in [-1, 16, "1", 1.0, false]:
		_reject_discussion_request(
			discussion,
			0,
			10,
			{"revision": 1, "action": "drop", "token": token, "target": target},
			"invalid drop target preserves the active hold"
		)
	for action in ["drop", "cancel"]:
		var request = {"revision": 1, "action": action, "token": str(token)}
		if action == "drop":
			request["target"] = 1
		_reject_discussion_request(
			discussion, 0, 10, request, "hold token requires an integer identity"
		)
		request.token = token
		request["extra"] = true
		_reject_discussion_request(
			discussion, 0, 10, request, "unknown release fields are rejected"
		)
	var client = _new_discussion()
	var state = began.state
	for field in ["revision", "order", "drag"]:
		var invalid = state.duplicate(true)
		invalid.erase(field)
		_reject_discussion_state(client, invalid, "missing reliable " + field + " is rejected")
	var invalid = state.duplicate(true)
	invalid["extra"] = true
	_reject_discussion_state(client, invalid, "unknown reliable state field is rejected")
	for revision in [-1, 2147483648, "1", 1.0, true]:
		invalid = state.duplicate(true)
		invalid.revision = revision
		_reject_discussion_state(client, invalid, "invalid reliable revision is rejected")
	for order in [null, {}, "order", [], [0]]:
		invalid = state.duplicate(true)
		invalid.order = order
		_reject_discussion_state(
			client, invalid, "reliable order must cover the archived slot count"
		)
	for slot in [-1, 16, 1, "0", 0.0, false]:
		invalid = state.duplicate(true)
		invalid.order[0] = slot
		_reject_discussion_state(
			client, invalid, "invalid or duplicate original slot identity is rejected"
		)
	for drag in [null, [], "drag", {"actor": 10}]:
		invalid = state.duplicate(true)
		invalid.drag = drag
		_reject_discussion_state(client, invalid, "malformed reliable hold is rejected")
	for field in ["actor", "slot", "token", "position", "seq"]:
		invalid = state.duplicate(true)
		invalid.drag.erase(field)
		_reject_discussion_state(client, invalid, "missing hold " + field + " is rejected")
	invalid = state.duplicate(true)
	invalid.drag["extra"] = true
	_reject_discussion_state(client, invalid, "unknown hold field is rejected")
	for field in ["actor", "slot", "token", "seq"]:
		for value in [null, "1", 1.0, true]:
			invalid = state.duplicate(true)
			invalid.drag[field] = value
			_reject_discussion_state(client, invalid, "hold " + field + " requires an integer")
	for field in ["actor", "token"]:
		for value in [0, -1]:
			invalid = state.duplicate(true)
			invalid.drag[field] = value
			_reject_discussion_state(
				client, invalid, "hold " + field + " requires a positive identity"
			)
	for slot in [-1, 1, 16]:
		invalid = state.duplicate(true)
		invalid.drag.slot = slot
		_reject_discussion_state(client, invalid, "hold must identify an occupied original slot")
	for field in ["token", "seq"]:
		invalid = state.duplicate(true)
		invalid.drag[field] = 2147483648
		_reject_discussion_state(client, invalid, "over-limit hold counter is rejected")
	invalid = state.duplicate(true)
	invalid.drag.seq = -1
	_reject_discussion_state(client, invalid, "negative hold motion sequence is rejected")
	invalid = state.duplicate(true)
	invalid.revision = 2147483647
	_reject_discussion_state(
		client, invalid, "reliable hold must leave revision capacity for its eventual release"
	)
	for point in [
		null, [], Vector2(-0.1, 0.5), Vector2(0.5, 1.1), Vector2(INF, 0.0), Vector2(0.0, NAN)
	]:
		invalid = state.duplicate(true)
		invalid.drag.position = point
		_reject_discussion_state(
			client, invalid, "reliable hold position must be finite and normalized"
		)
	_check(
		not client.apply_state(7, state),
		"coordinator state cannot create a rack without archived slot identities"
	)
	_check(
		client.apply_state(0, state),
		"valid state remains accepted after malformed-state rejections"
	)


func _discussion_counter_boundaries() -> void:
	var discussion = _new_discussion()
	var state = discussion.snapshot(0)
	state.revision = 2147483645
	_check(discussion.apply_state(0, state), "near-limit revision can resync an idle rack")
	var began = discussion.transition(0, 10, {"revision": 2147483645, "action": "begin", "slot": 0})
	_check(
		began.accepted and began.state.revision == 2147483646,
		"last safe pickup reserves capacity for release"
	)
	var cancelled = discussion.transition(
		0, 10, {"revision": 2147483646, "action": "cancel", "token": began.state.drag.token}
	)
	_check(
		(
			cancelled.accepted
			and cancelled.state.revision == 2147483647
			and cancelled.state.drag.is_empty()
		),
		"final cancellation stays within the wire counter range"
	)
	var client = _new_discussion()
	_check(client.apply_state(0, cancelled.state), "client can apply the last reliable release")
	_reject_discussion_request(
		discussion,
		0,
		10,
		{"revision": 2147483647, "action": "begin", "slot": 0},
		"exhausted revision cannot create an unreleasable hold"
	)
	discussion = _new_discussion()
	state = discussion.snapshot(0)
	state.revision = 2147483646
	_check(discussion.apply_state(0, state), "penultimate idle revision can be restored")
	_reject_discussion_request(
		discussion,
		0,
		10,
		{"revision": 2147483646, "action": "begin", "slot": 0},
		"pickup rejects when no later release revision is available"
	)
	discussion = _new_discussion()
	state.revision = 2147483645
	discussion.apply_state(0, state)
	discussion.transition(0, 10, {"revision": 2147483645, "action": "begin", "slot": 0})
	_check(
		discussion.release_actor(10) == [0], "disconnect releases a hold at the last safe revision"
	)
	var released = discussion.snapshot(0)
	_check(
		released.revision == 2147483647 and released.drag.is_empty(),
		"disconnect release cannot overflow the reliable counter"
	)
	client = _new_discussion()
	_check(client.apply_state(0, released), "last disconnect release remains valid for clients")


func _new_discussion():
	var discussion = Discussion.new()
	discussion.reset(41)
	discussion.ensure_table(0, _discussion_build())
	return discussion


func _discussion_build() -> Array:
	var build: Array = []
	build.resize(16)
	build[0] = _item("ORB")
	build[3] = _item("ORB")
	return build


func _reject_discussion_request(
	discussion, table: int, actor: int, request: Dictionary, description: String
) -> void:
	var before = discussion.snapshot(table)
	var result = discussion.transition(table, actor, request)
	_check(not result.accepted and not result.changed and not result.reason.is_empty(), description)
	_check(
		result.state == before and discussion.snapshot(table) == before,
		"rejected request returns canonical rollback state without mutation"
	)


func _reject_discussion_state(discussion, state: Dictionary, description: String) -> void:
	var before = discussion.snapshot(0)
	_check(not discussion.apply_state(0, state), description)
	_check(
		discussion.snapshot(0) == before,
		"invalid coordinator state leaves the current rack untouched"
	)


func _record(table: int = 0) -> Dictionary:
	var build: Array = []
	build.resize(16)
	build[0] = _item("ORB")
	var cues = CueInventory.new()
	cues.reset([{"id": 10, "cue": "emerald"}])
	return {
		"match": 41,
		"table": table,
		"leader": 10,
		"inventory":
		{
			"build": build,
			"passives": [_item("SNACK"), null, null, null],
			"cubes": [_item("NEGATIVE-ORB")],
			"snacks": 2,
			"cocktails": 1
		},
		"cues": cues.snapshot()
	}


func _item(id: String) -> Dictionary:
	return {
		"data": id,
		"mixed": "",
		"base_score": 5,
		"temp_extra_score": 0,
		"level": 1,
		"weight_state": 0,
		"flaming": false,
		"fleeting": false,
		"star_power": false,
		"shielded": false,
		"shield_broken": false,
		"locked": false
	}


func _summary(table: int, score: float = 0.0) -> Dictionary:
	return {
		"table": table,
		"score": score,
		"finished": true,
		"run_won": false,
		"finish_order": 0,
		"status": "Finished",
		"closed": false
	}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("END_RUN_PROBE: " + description)

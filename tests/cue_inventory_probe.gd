extends SceneTree
## Run only inside the explicitly authorized capture harness. This probe exercises
## pure cue ownership, shared-budget sequencing, and rejected/isolated snapshots.

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var script = load(get_script().resource_path.get_base_dir().path_join("../mod/cue_inventory.gd"))
	var rack = script.new()
	_check(rack.snapshot() == {"revision": 0, "players": []}, "new inventory has no stale run members")
	_check(rack.model_for(99) == "house", "missing actors fall back to native handling")
	_check(rack.finish_for(99) == "native", "missing actors fall back to the native finish")
	var roster = [{"id": 20, "cue": "emerald"}, {"id": 10, "cue": "coral"}]
	_check(rack.reset(roster), "a new run creates a personal rack for each member")
	_check(rack.snapshot().players[0].id == 10, "snapshot order is stable by player identity")
	_check(rack.player(20).owned == ["house"], "every player begins with only the free House cue")
	_check(rack.model_for(20) == "house", "House is equipped for a fresh run")
	_check(rack.finish_for(20) == "emerald", "a fresh run imports the existing cue preference")
	roster[0].cue = "violet"
	_check(rack.finish_for(20) == "emerald", "roster changes cannot mutate the run rack")
	var before: Dictionary = rack.snapshot()
	_reject(rack, 99, "cue_buy", "finesse", "gold", 50.0, "outsiders cannot acquire a cue")
	_reject(rack, 20, "buy", "finesse", "gold", 50.0, "unknown actions fail closed")
	_reject(rack, 20, "cue_buy", "unknown", "gold", 50.0, "unknown models fail closed")
	_reject(rack, 20, "cue_buy", "finesse", "unknown", 50.0, "unknown finishes fail closed")
	_reject(rack, 20, "cue_buy", "finesse", " GOLD ", 50.0, "wire finishes must be canonical")
	_reject(rack, 20, "cue_equip", "finesse", "gold", 50.0, "unowned cues cannot be equipped")
	_reject(rack, 20, "cue_finish", "finesse", "gold", 50.0, "finishes cannot unlock a model")
	_reject(rack, 20, "cue_buy", "finesse", "gold", 3.99, "insufficient shared money rejects")
	for invalid_money in [-1.0, NAN, INF, -INF]:
		_reject(rack, 20, "cue_buy", "finesse", "gold", invalid_money, "invalid money rejects")
	_check(rack.snapshot() == before, "rejected commands leave all ownership and finishes intact")
	var money = 6.0
	var purchase: Dictionary = rack.transact(20, "cue_buy", "finesse", "gold", money)
	_check(purchase.accepted and purchase.changed, "a valid purchase succeeds and changes the rack")
	_check(purchase.cost > 0 and purchase.cost <= money, "purchase returns its bounded shared cost")
	money -= purchase.cost
	_check(rack.model_for(20) == "finesse", "a purchased cue is immediately equipped")
	_check(rack.finish_for(20) == "gold", "the purchase adopts the selected cosmetic finish")
	_check(rack.player(20).owned == ["house", "finesse"], "purchase retains the free House cue")
	_reject(rack, 20, "cue_buy", "finesse", "gold", 50.0, "duplicate purchase cannot debit again")
	_reject(rack, 10, "cue_buy", "firm", "rose", money, "the next player sees spent shared money")
	_check(rack.model_for(10) == "house", "failed simultaneous spending preserves the other rack")
	var equip: Dictionary = rack.transact(20, "cue_equip", "house", "ice", money)
	_check(equip.accepted and equip.changed and equip.cost == 0, "returning to House is free")
	_check(rack.player(20).owned.has("finesse"), "switching cues retains purchases within the run")
	_reject(rack, 20, "cue_finish", "finesse", "amber", money, "stale model finish requests reject")
	var cosmetic: Dictionary = rack.transact(20, "cue_finish", "house", "amber", money)
	_check(cosmetic.accepted and cosmetic.changed and cosmetic.cost == 0, "finish changes are free")
	var unchanged: Dictionary = rack.transact(20, "cue_finish", "house", "amber", money)
	_check(unchanged.accepted and not unchanged.changed, "identical finish is an accepted no-op")
	unchanged = rack.transact(20, "cue_equip", "house", "amber", money)
	_check(unchanged.accepted and not unchanged.changed, "identical equipment is an accepted no-op")
	var saved: Dictionary = rack.snapshot()
	_check(script.valid_snapshot(saved), "the complete authoritative rack passes wire validation")
	var guest = script.new()
	_check(guest.apply_snapshot(saved), "a guest hydrates all run racks from one snapshot")
	_check(guest.snapshot() == rack.snapshot(), "initial sync reproduces ownership and presentation")
	_check(guest.apply_snapshot(saved), "an equal snapshot remains a valid no-op")
	saved.players[0].owned.append("firm")
	saved.players[1].finish = "rose"
	_check(guest.snapshot() == rack.snapshot(), "applied snapshots cannot be mutated by the sender")
	var exposed: Dictionary = guest.player(20)
	exposed.owned.clear()
	exposed.finish = "rose"
	_check(guest.snapshot() == rack.snapshot(), "individual player reads cannot mutate inventory")
	var exported: Dictionary = guest.snapshot()
	exported.players.clear()
	_check(guest.snapshot() == rack.snapshot(), "exported snapshot arrays are isolated")
	_check_bad_snapshots(script, guest)
	_check_reordered_snapshots(script)
	_check_reset(rack)
	_finish()


func _check_bad_snapshots(script, rack) -> void:
	var valid: Dictionary = rack.snapshot()
	var cases: Array = [
		null, [], {}, {"players": []}, {"revision": 0, "players": {}},
		{"revision": 0, "players": [], "extra": true},
	]
	for revision in [-1, 1.0, "1", null, true]:
		var invalid_revision: Dictionary = valid.duplicate(true)
		invalid_revision.revision = revision
		cases.append(invalid_revision)
	for field in ["id", "owned", "equipped", "finish"]:
		var missing: Dictionary = valid.duplicate(true)
		missing.players[0].erase(field)
		cases.append(missing)
	for field_and_value in [
		["id", "10"], ["id", 10.0], ["id", 0], ["id", -10],
		["owned", "house"], ["owned", []], ["owned", ["house", "house"]],
		["owned", ["house", "unknown"]], ["owned", ["finesse"]], ["owned", ["house", 3]],
		["equipped", "firm"], ["equipped", 2], ["finish", "GOLD"], ["finish", "unknown"],
		["finish", 2],
	]:
		var malformed: Dictionary = valid.duplicate(true)
		malformed.players[0][field_and_value[0]] = field_and_value[1]
		cases.append(malformed)
	var extra_field: Dictionary = valid.duplicate(true)
	extra_field.players[0].hidden = true
	cases.append(extra_field)
	var duplicate_actor: Dictionary = valid.duplicate(true)
	duplicate_actor.players.append(duplicate_actor.players[0].duplicate(true))
	cases.append(duplicate_actor)
	var too_many = {"revision": valid.revision, "players": []}
	for id in range(1, 10):
		too_many.players.append({"id": id, "owned": ["house"], "equipped": "house", "finish": "native"})
	cases.append(too_many)
	for malformed in cases:
		_check(not script.valid_snapshot(malformed), "malformed cue snapshots are rejected at the boundary")
		_check(not rack.apply_snapshot(malformed), "malformed cue snapshots cannot hydrate")
		_check(rack.snapshot() == valid, "rejected snapshots preserve the last complete state")
	_check(
		rack.apply_snapshot({"revision": valid.revision + 1, "players": []}),
		"newer empty authoritative state clears stale run racks"
	)
	_check(rack.player(20).is_empty(), "disconnected-session racks do not survive explicit clear")


func _check_reordered_snapshots(script) -> void:
	var host = script.new()
	var guest = script.new()
	host.reset([{"id": 20, "cue": "native"}])
	guest.reset([{"id": 20, "cue": "native"}])
	var initial: Dictionary = host.snapshot()
	host.transact(20, "cue_buy", "finesse", "gold", 50.0)
	var bought: Dictionary = host.snapshot()
	_check(bought.revision > initial.revision, "ownership changes advance the inventory revision")
	_check(guest.apply_snapshot(bought), "a shop result imports the confirmed purchase revision")
	_check(guest.apply_snapshot(initial), "a delayed initial table state is safely ignored")
	_check(guest.snapshot() == bought, "delayed initial state cannot revoke a purchased cue")
	host.transact(20, "cue_equip", "house", "ice", 50.0)
	var equipped: Dictionary = host.snapshot()
	_check(equipped.revision > bought.revision, "equipment changes advance the inventory revision")
	guest.apply_snapshot(equipped)
	guest.apply_snapshot(bought)
	_check(guest.snapshot() == equipped, "delayed purchase state cannot rewind newer equipment")
	host.transact(20, "cue_finish", "house", "amber", 50.0)
	var finished: Dictionary = host.snapshot()
	_check(finished.revision > equipped.revision, "finish changes advance the inventory revision")
	guest.apply_snapshot(finished)
	guest.apply_snapshot(equipped)
	_check(guest.snapshot() == finished, "delayed equipment state cannot rewind a newer finish")
	host.transact(20, "cue_finish", "house", "amber", 50.0)
	host.transact(20, "cue_equip", "house", "amber", 50.0)
	host.transact(20, "cue_buy", "finesse", "gold", 50.0)
	_check(host.snapshot() == finished, "unchanged and rejected actions never advance inventory revision")
	host.transact(20, "cue_equip", "finesse", "gold", 50.0)
	var restored: Dictionary = host.snapshot()
	_check(guest.apply_snapshot(restored), "newer state may deliberately return to an earlier appearance")
	_check(guest.snapshot() == restored, "higher revision imports even when it resembles older state")
	var newer_identical: Dictionary = restored.duplicate(true)
	newer_identical.revision += 2
	_check(guest.apply_snapshot(newer_identical), "newer identical rows still advance the accepted version")
	guest.apply_snapshot(finished)
	_check(guest.snapshot() == newer_identical, "an identical-row import still protects against later stale state")
	_check(guest.apply_snapshot(newer_identical), "equal authoritative snapshots remain accepted no-ops")
	_check(guest.snapshot() == newer_identical, "equal snapshots retain their revision and data")


func _check_reset(rack) -> void:
	_check(rack.reset([{"id": 20, "cue": "emerald"}]), "rematch resets with the current roster")
	_check(rack.snapshot().revision == 0, "a new match starts its own inventory revision epoch")
	_check(rack.player(20).owned == ["house"], "paid cues do not survive a rematch")
	_check(rack.model_for(20) == "house", "rematch restores native handling")
	_check(rack.finish_for(20) == "emerald", "rematch preserves only the cosmetic preference")
	_check(rack.player(10).is_empty(), "old members are absent after reset")
	_check(rack.reset([{"id": 20, "cue": "invalid"}]), "unknown saved cosmetics recover safely")
	_check(rack.finish_for(20) == "native", "unknown saved cosmetics restore native appearance")
	_check(not rack.reset([{"id": 20}, {"id": 20}]), "duplicate run identities reject reset")
	_check(rack.snapshot() == {"revision": 0, "players": []}, "a rejected reset cannot retain a previous run")
	var roster: Array = []
	for id in range(1, 9):
		roster.append({"id": id})
	_check(rack.reset(roster), "a full eight-player roster fits the bounded inventory")
	_check(rack.snapshot().players.size() == 8, "all eight player racks are retained")
	roster.append({"id": 9})
	_check(not rack.reset(roster), "oversized rosters fail closed")
	_check(rack.snapshot().players.is_empty(), "overflow cannot leave a partial roster")
	_check(rack.reset(), "disconnect teardown can clear the rack without a roster")


func _reject(rack, actor: int, action: String, model: String, finish: String, money: float, label: String):
	var before: Dictionary = rack.snapshot()
	var result: Dictionary = rack.transact(actor, action, model, finish, money)
	_check(not result.accepted and not result.changed and result.cost == 0, label)
	_check(not result.error.is_empty() and rack.snapshot() == before, label + " without mutation")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("CUE_INVENTORY_PROBE PASS (%d checks)" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("CUE_INVENTORY_PROBE FAIL: ", failure)
		print("CUE_INVENTORY_PROBE FAIL (%d/%d)" % [failures.size(), checks])
		quit(1)

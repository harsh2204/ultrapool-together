extends SceneTree

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var clone = load(get_script().resource_path.get_base_dir().path_join("../mod/clone_round.gd"))
	_check(not clone.enabled({}), "clone rounds off by default")
	_check(
		not clone.enabled({"clone_rounds": true}),
		"clone flag alone is not enough without Together All Nighter"
	)
	_check(
		clone.enabled({"clone_rounds": true, "difficulty": "diff_together_nighter"}),
		"Together All Nighter with the flag enables clone rounds"
	)
	_check(
		not clone.enabled({"clone_rounds": true, "difficulty": "diff_6"}),
		"native All Nighter does not unlock clone rounds"
	)
	_check(
		not clone.should_run({"clone_rounds": true, "difficulty": "diff_together_nighter"}, [10]),
		"solo tables skip clone rounds"
	)
	_check(
		clone.should_run(
			{"clone_rounds": true, "difficulty": "diff_together_nighter"}, [10, 20]
		),
		"shared Together All Nighter tables with the flag run clone rounds"
	)
	_check(
		not clone.should_run({"clone_rounds": true, "difficulty": "diff_2"}, [10, 20]),
		"other difficulties cannot run clone rounds even with the flag"
	)

	var instances = clone.assign_instances([20, 10, 30])
	_check(instances.size() == 3, "each seated player gets a clone instance")
	_check(
		instances[0].player_id == 10 and instances[0].instance_id == 0,
		"clone instances are ordered by player id"
	)
	_check(clone.has_instance(instances, 20), "assigned players own a clone instance")
	_check(not clone.has_instance(instances, 99), "outsiders do not receive a clone instance")

	clone.record_score(instances, 10, 40.0)
	clone.record_score(instances, 20, 55.0)
	clone.record_score(instances, 30, 55.0)
	_check(clone.pick_winner(instances) == 0, "unfinished clones cannot crown a winner yet")
	clone.mark_finished(instances, 10, 40.0)
	clone.mark_finished(instances, 20, 55.0)
	clone.mark_finished(instances, 30, 55.0)
	_check(clone.all_finished(instances), "every clone can finish")
	_check(
		clone.pick_winner(instances) == 20,
		"highest score wins; ties break to the lowest player id"
	)

	var snap = clone.snapshot(instances, false, 20, true)
	_check(
		snap.active == false and snap.winner_id == 20 and snap.shop_armed,
		"snapshot carries winner-shop arming for guests"
	)

	# Winner-only shop gate: reject non-winners, then clear after one shop.
	var shop = load(get_script().resource_path.get_base_dir().path_join("../mod/shop_sync.gd")).new()
	var host = ShopHost.new()
	host.table_id = 0
	host.finished = false
	host.panel = Control.new()
	host.transport = ShopTransport.new()
	add_child(host)
	add_child(shop)
	shop.begin_session(host)
	shop.set_exclusive_shopper(20)
	_check(shop.exclusive_shopper() == 20, "shop records the exclusive winner")
	_check(
		not shop.handle_request({"action": "reroll", "revision": 1}, 10),
		"non-winner shop actions are rejected during the winner shop"
	)
	_check(
		shop.last_error.findn("winner") >= 0,
		"non-winner rejection names the winner-only rule"
	)
	shop.clear_exclusive_shopper()
	_check(shop.exclusive_shopper() == 0, "clearing the gate restores shared shopping")

	print("CLONE_ROUND_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


class ShopHost:
	extends Node
	var finished = false
	var panel: Control
	var table_id = 0
	var transport

	func is_table_host() -> bool:
		return true

	func is_spectating() -> bool:
		return false

	func _members(_table: int) -> Array:
		return [{"id": 10}, {"id": 20}, {"id": 30}]


class ShopTransport:
	extends RefCounted

	func local_id() -> int:
		return 20


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

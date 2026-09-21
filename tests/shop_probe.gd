extends Node

var failures: Array[String] = []
var controller: Node


class ShopController:
	extends Node
	var finished = false
	var panel: Control

	func is_table_host() -> bool:
		return true


func _ready():
	_run.call_deferred()


func _run():
	if not OS.get_user_data_dir().contains("UltrapoolTogetherShopTest"):
		get_tree().quit(2)
		return
	var mod = get_node("/root/UltrapoolTogether")
	mod.set_process(false)
	mod.transport.close()
	mod._set_panel(false)
	get_node("/root/SettingsManager").use_analytics = false
	get_node("/root/AnalyticsManager").state = 0
	get_node("/root/CloudSaveManager").backend = null
	var global_node = get_node("/root/Global")
	var database = get_node("/root/BallDatabase")
	global_node.chosen_deck = database.id_to_deck["1_CLASSIC"]
	global_node.chosen_difficulty = database.id_to_difficulty["diff_1"]
	global_node.chosen_run_state = null
	var sync = mod.shop_sync
	controller = ShopController.new()
	controller.panel = mod.panel
	add_child(controller)
	sync.begin_session(controller)
	global_node.go_to_game()
	if not await _wait(
		func():
			return (
				is_instance_valid(global_node.gameManager) and global_node.gameManager.balls_spawned
			)
	):
		_check(false, "native game starts")
		_finish(sync)
		return
	var game = global_node.gameManager
	game.player_info.money = 92.0
	game.open_shop(false)
	if not await _wait(
		func(): return sync.capture().get("open", false) and not sync.capture().get("busy", true)
	):
		_check(false, "native shop finishes opening")
		_finish(sync)
		return
	var state: Dictionary = sync.capture()
	_check(sync._valid_state(state), "native floating-point currency is accepted")
	var offer: Dictionary = {}
	var empty: Dictionary = {}
	for slot in state.slots:
		if slot.group == "offer" and slot.id != 0:
			offer = slot
		if slot.group == "build" and slot.id == 0:
			empty = slot
	if offer.is_empty() or empty.is_empty():
		_check(false, "fixture has an offer and an empty build slot")
		_finish(sync)
		return
	var purchase = {
		"action": "move",
		"revision": state.revision,
		"source": offer.key,
		"item_id": offer.id,
		"target": empty.key,
		"target_id": 0
	}
	_check(
		sync.handle_request(purchase),
		"either participant can buy through the shared action handler"
	)
	var after: Dictionary = sync.capture()
	_check(after.revision > state.revision, "purchase advances shared revision")
	var money_after = game.player_info.money
	_check(
		not sync.handle_request(purchase),
		"second simultaneous purchase with old revision is rejected"
	)
	_check(
		game.player_info.money == money_after, "stale purchase does not spend shared money twice"
	)
	var wrong_identity = purchase.duplicate()
	wrong_identity.revision = after.revision
	_check(
		not sync.handle_request(wrong_identity),
		"moved item cannot be bought again at the new revision"
	)
	_check(game.player_info.money == money_after, "wrong item identity does not spend money")
	var source: Dictionary = {}
	var destination: Dictionary = {}
	for slot in after.slots:
		if slot.key == empty.key:
			source = slot
		if slot.group == "build" and slot.id == 0:
			destination = slot
	if not source.is_empty() and not destination.is_empty():
		var move = {
			"action": "move",
			"revision": after.revision,
			"source": source.key,
			"item_id": source.id,
			"target": destination.key,
			"target_id": 0
		}
		_check(sync.handle_request(move), "shared build rearrangement succeeds")
		_check(game.player_info.money == money_after, "rearranging does not charge money")
		_check(not sync.handle_request(move), "replayed rearrangement is rejected")
	var invalid = sync.capture().duplicate(true)
	for slot in invalid.slots:
		if slot.id != 0:
			slot.data = "res://invalid-network-resource"
			break
	_check(not sync._valid_state(invalid), "unknown item resource is rejected")
	get_tree().paused = true
	var paused: Dictionary = sync.capture()
	_check(
		not sync.handle_request({"action": "reroll", "revision": paused.revision}),
		"paused host blocks guest transactions"
	)
	get_tree().paused = false
	controller.finished = true
	var completed: Dictionary = sync.capture()
	var completed_money = game.player_info.money
	_check(
		not sync.handle_request({"action": "reroll", "revision": completed.revision}),
		"completed tables reject shop transactions"
	)
	_check(game.player_info.money == completed_money, "completed table cannot spend money")
	_finish(sync)


func _finish(sync):
	sync.end_session()
	print("SHOP_PROBE_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(condition: bool, label: String):
	if not condition:
		failures.append(label)
		push_error("SHOP_PROBE: " + label)


func _wait(condition: Callable) -> bool:
	for _attempt in 200:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return false

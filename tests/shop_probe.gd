extends Node

var failures: Array[String] = []
var controller: Node


class ShopController:
	extends Node
	var finished = false
	var panel: Control
	var table_id = 0
	var transport = ShopTransport.new()

	func is_table_host() -> bool:
		return true

	func is_spectating() -> bool:
		return false

	func _members(_table: int) -> Array:
		return [{"id": 1}, {"id": 2}]


class ShopTransport:
	extends RefCounted

	func local_id() -> int:
		return 1


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
	await _check_rendered_slots(sync, state)
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
	_check_predictions(sync, state, offer, empty)
	var purchase = {
		"action": "move",
		"revision": state.revision,
		"source": offer.key,
		"item_id": offer.id,
		"target": empty.key,
		"target_id": 0
	}
	_check(
		not sync.handle_request(purchase, 999),
		"players from another table cannot use the shared shop"
	)
	_check(
		sync.handle_request(_ready_request(state, true), 1),
		"one teammate can ready without leaving the shop"
	)
	state = sync.capture()
	_check(state.open and state.ready_vote.ready == [1], "shop publishes partial team readiness")
	purchase.revision = state.revision
	_check(
		sync.handle_request(purchase),
		"either participant can buy through the shared action handler"
	)
	var after: Dictionary = sync.capture()
	_check(after.revision > state.revision, "purchase advances shared revision")
	_check(after.ready_vote.ready.is_empty(), "buying clears consent for the previous inventory")
	_check(
		not sync.handle_request(_ready_request(state, true), 2),
		"pre-purchase consent cannot approve the new inventory"
	)
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
	await _check_inspected_sale(sync)
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
	controller.finished = false
	_check_ready_departure(sync)
	_finish(sync)


func _check_ready_departure(sync):
	var state: Dictionary = sync.capture()
	var ready = _ready_request(state, true)
	_check(sync.handle_request(ready, 1), "first teammate readies for the next round")
	_check(sync.handle_request(ready, 1), "replayed explicit shop readiness is idempotent")
	state = sync.capture()
	_check(state.ready_vote.ready == [1], "replayed consent never counts as another teammate")
	_check(
		sync.handle_request(_ready_request(state, false), 1),
		"ready teammate can withdraw before everyone consents"
	)
	state = sync.capture()
	_check(state.ready_vote.ready.is_empty() and state.open, "withdrawing keeps the shop open")
	_check(sync.handle_request(_ready_request(state, true), 1), "teammate can ready again")
	_check(
		sync.handle_request(ready, 2),
		"simultaneous last teammate's consent starts the next round at the same generation"
	)
	_check(not sync.capture().open, "unanimous readiness closes the native shop")
	_check(not sync.handle_request(ready, 2), "duplicate final vote cannot start another round")


func _ready_request(state: Dictionary, value: bool) -> Dictionary:
	return {
		"action": "ready",
		"ready": value,
		"revision": state.revision,
		"ready_generation": state.ready_vote.revision
	}


func _check_predictions(sync, state: Dictionary, offer: Dictionary, empty: Dictionary):
	var original = state.duplicate(true)
	var purchase = {
		"action": "move",
		"source": offer.key,
		"item_id": offer.id,
		"target": empty.key,
		"target_id": 0
	}
	var predicted: Dictionary = sync._predict_state(state, purchase)
	_check(predicted.money == state.money - offer.price, "purchase prediction updates local money")
	_check(state == original, "optimistic purchase leaves the authoritative state untouched")
	var from: Dictionary = predicted.slots.filter(func(slot): return slot.key == offer.key)[0]
	var to: Dictionary = predicted.slots.filter(func(slot): return slot.key == empty.key)[0]
	_check(
		from.id == 0 and to.id == offer.id, "purchase prediction preserves the moved item identity"
	)
	var ready: Dictionary = sync._predict_state(state, _ready_request(state, true))
	_check(ready.ready_vote.ready == [1], "ready prediction updates the teammate count immediately")
	var replay: Dictionary = sync._predict_state(ready, _ready_request(state, true))
	_check(replay.ready_vote.ready == [1], "predicting the same approval never doubles the count")
	var stale = _ready_request(state, true)
	stale.ready_generation -= 1
	_check(sync._predict_state(state, stale) == state, "stale ready generation is never predicted")
	var insufficient = state.duplicate(true)
	insufficient.money = -1
	_check(
		sync._predict_state(insufficient, purchase) == insufficient,
		"unaffordable purchase does not create a local item"
	)
	var target = sync._buttons[offer.key]
	sync._render()
	_check(sync._buttons[offer.key] == target, "redrawing preserves native drag targets")


func _check_inspected_sale(sync):
	var state: Dictionary = sync.capture()
	for slot in state.slots:
		if slot.group != "build" or slot.id == 0:
			continue
		var body = sync.slot_item(slot.key)
		_check(sync.inspect_slot(slot.key), "sale fixture inspects a native build ball")
		_check(
			sync.handle_request(
				{
					"action": "sell",
					"revision": state.revision,
					"source": slot.key,
					"item_id": slot.id
				}
			),
			"inspected build ball can be sold"
		)
		_check(
			sync.native_shop().selected_ball == null,
			"selling clears native selection before freeing the ball"
		)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(
			not is_instance_valid(body),
			"sold inspected ball is freed without a stale shop reference"
		)
		return
	_check(false, "sale fixture has an occupied build slot")


func _check_rendered_slots(sync, state: Dictionary):
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		sync.native_shop() == get_node("/root/Global").gameManager.shop,
		"shared controls use the original native shop"
	)
	_check(not sync._panel is PanelContainer, "shared controls do not cover the native scene")
	for slot in state.slots:
		var native_slot = sync._native_slots[slot.key]
		var object = native_slot.item if slot.group in ["snack", "passive"] else native_slot.ball
		if not is_instance_valid(object) or object.is_queued_for_deletion():
			_check(slot.id == 0, "empty native slot retains zero identity: " + slot.key)
			continue
		_check(
			slot.id == object.get_instance_id(),
			"occupied slot preserves native identity: " + slot.key
		)
		_check(sync.slot_item(slot.key) == object, "native item remains visible: " + slot.key)
		_check(
			not object.interactable, "native item cannot bypass shared transactions: " + slot.key
		)
		var button = sync._buttons[slot.key]
		_check(
			(
				button.get_global_rect().get_center().distance_to(
					sync.slot_screen_position(slot.key)
				)
				< 1
			),
			"shared hit target follows its native slot: " + slot.key
		)
		if object is ShopBall:
			_check(
				object.ball.material.get_shader_parameter("tex") == object.get_item().data.texture,
				"native shop sphere uses its item texture: " + slot.key
			)
	for slot in state.slots:
		if slot.group != "build" or slot.id == 0:
			continue
		_check(sync.inspect_slot(slot.key), "native shop ball can be inspected")
		sync.show_section("balls")
		_check(
			(
				sync.native_shop().selected_ball == null
				and sync.native_shop().selected_passive == null
			),
			"changing native sections clears item inspection and upgrade arrows"
		)
		await _wait(func(): return not sync.native_shop().moving())
		break


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

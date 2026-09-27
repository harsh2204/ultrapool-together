extends Node

var failures: Array[String] = []
var controller: Node
var _transaction_record: Callable


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
	if not await check_native_transactions(sync):
		_finish(sync)
		return
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
	sync.set_exclusive_shopper(1)
	_check(
		not sync.handle_request({"action": "reroll", "revision": sync.capture().revision}, 2),
		"non-winner cannot act during the winner-only shop"
	)
	_check(sync.last_error.findn("winner") >= 0, "winner-only rejection is explicit")
	sync.clear_exclusive_shopper()
	var reopened: Dictionary = sync.capture()
	_check(
		sync.handle_request({"action": "reroll", "revision": reopened.revision}, 2)
		or sync.last_error.findn("money") >= 0
		or sync.last_error.findn("changed") >= 0,
		"shared shopping resumes after the winner-only shop clears"
	)
	_check_ready_departure(sync)
	_finish(sync)


## Reusable in Capture-Screens: instantiate this script without adding it to the
## tree, then call this method with the existing open host shop and result sink.
## All mutations use production shop handlers. Fixtures grant tickets, purchase one
## passive, and replace two build balls with one mixer result; mix slots end empty.
func check_native_transactions(sync: Node, record: Callable = Callable()) -> bool:
	_transaction_record = record
	var before_failures = failures.size()
	var shop = sync.native_shop()
	if not _transaction_check(
		is_instance_valid(shop) and sync.capture().get("open", false),
		"native transactions: host shop is open"
	):
		_transaction_record = Callable()
		return false
	var info = shop.player_info
	var bar = shop.cocktail_bar
	var saved = {
		"snacks": info.snack_tickets,
		"cocktails": info.cocktail_tickets,
		"bar_visible": bar.visible,
		"bar_process": bar.process_mode
	}
	info.snack_tickets = 2
	info.cocktail_tickets = 2
	bar.visible = true
	bar.process_mode = Node.PROCESS_MODE_INHERIT
	bar.update_state()
	if _transaction_slots(sync.capture(), "snack", true).is_empty():
		shop.tapas_bar.update_passives()
	await sync.get_tree().process_frame
	await sync.get_tree().process_frame
	var snack_ok: bool = await _check_snack_transactions(sync)
	var mix_ok: bool = await _check_mixer_transactions(sync)
	info.snack_tickets = saved.snacks
	info.cocktail_tickets = saved.cocktails
	shop.update_snack_tickets()
	shop.update_cocktail_tickets()
	bar.update_state()
	bar.visible = saved.bar_visible
	bar.process_mode = saved.bar_process
	sync.capture()
	_transaction_record = Callable()
	return snack_ok and mix_ok and failures.size() == before_failures


func _check_snack_transactions(sync: Node) -> bool:
	var shop = sync.native_shop()
	var state: Dictionary = sync.capture()
	var offers = _transaction_slots(state, "snack", true)
	var empty = _transaction_slots(state, "passive", false)
	if not _transaction_check(
		not offers.is_empty() and not empty.is_empty(),
		"native snack: offer and empty passive slot exist"
	):
		return false
	var source: String = offers[0].key
	var target: String = empty[0].key
	shop.player_info.snack_tickets = 0
	_transaction_reject(sync, _transaction_move(sync, source, target), "native snack: no ticket")
	shop.player_info.snack_tickets = 2
	state = sync.capture()
	var before_owned = _transaction_slots(state, "passive", true).size()
	var purchase = _transaction_move(sync, source, target)
	var identity: int = purchase.item_id
	if not _transaction_check(
		sync.handle_request(purchase, 1), "native snack: purchase accepted through shared handler"
	):
		return false
	await sync.get_tree().process_frame
	await sync.get_tree().process_frame
	var after: Dictionary = sync.capture()
	var owned = _transaction_slot(after, target)
	_transaction_check(
		after.snacks == state.snacks - 1 and after.money == state.money,
		"native snack: purchase spends exactly one ticket and no money"
	)
	_transaction_check(
		owned.id == identity
		and _transaction_slots(after, "passive", true).size() == before_owned + 1
		and _transaction_identity_count(after, identity) == 1,
		"native snack: purchased identity moves once into owned inventory"
	)
	_transaction_check(
		is_instance_valid(sync.slot_item(target))
		and sync.slot_item(target).get_instance_id() == identity,
		"native snack: captured ownership matches the actual native passive"
	)
	_transaction_reject(sync, purchase, "native snack: replayed purchase")
	var refreshed_replay = purchase.duplicate()
	refreshed_replay.revision = sync.capture().revision
	_transaction_reject(sync, refreshed_replay, "native snack: old item at current revision")
	offers = _transaction_slots(sync.capture(), "snack", true)
	if not _transaction_check(not offers.is_empty(), "native snack: remaining ticket restocks offers"):
		return false
	_transaction_reject(
		sync, _transaction_move(sync, offers[0].key, target), "native snack: occupied passive slot"
	)
	return true


func _check_mixer_transactions(sync: Node) -> bool:
	var shop = sync.native_shop()
	var bar = shop.cocktail_bar
	var state: Dictionary = sync.capture()
	var inputs: Array = []
	for slot in _transaction_slots(state, "build", true):
		if slot.mixed != "":
			continue
		if inputs.is_empty() or inputs[0].data != slot.data:
			inputs.append(slot)
		if inputs.size() == 2:
			break
	if not _transaction_check(
		inputs.size() == 2 and _transaction_slots(state, "mix", true).is_empty(),
		"native mixer: two distinct unmixed build balls and empty mixer exist"
	):
		return false
	var left: Dictionary = inputs[0]
	var right: Dictionary = inputs[1]
	var before_count = _transaction_slots(state, "build", true).size()
	var before_money = state.money
	var expected_score: int = (
		sync.slot_item(left.key).get_item().get_score()
		+ sync.slot_item(right.key).get_item().get_score()
	)
	shop.player_info.cocktail_tickets = 0
	_transaction_reject(
		sync, _transaction_move(sync, left.key, "mix:0"), "native mixer: input without ticket"
	)
	shop.player_info.cocktail_tickets = 2
	bar.update_state()
	_transaction_reject(
		sync, _transaction_move(sync, left.key, "mix:2"), "native mixer: direct drop into output"
	)
	var move_left = _transaction_move(sync, left.key, "mix:0")
	if not _transaction_check(
		sync.handle_request(move_left, 1), "native mixer: first native input accepted"
	):
		return false
	_transaction_reject(sync, move_left, "native mixer: replayed first input")
	_transaction_reject(
		sync, _transaction_move(sync, right.key, "mix:0"), "native mixer: occupied input slot"
	)
	_transaction_reject(
		sync,
		{"action": "mix", "revision": sync.capture().revision},
		"native mixer: incomplete recipe"
	)
	var offers = _transaction_slots(sync.capture(), "offer", true)
	if _transaction_check(not offers.is_empty(), "native mixer: unowned offer fixture exists"):
		_transaction_reject(
			sync, _transaction_move(sync, offers[0].key, "mix:1"),
			"native mixer: unowned offer cannot be an ingredient"
		)
	if not _transaction_check(
		sync.handle_request(_transaction_move(sync, right.key, "mix:1"), 1),
		"native mixer: second native input accepted"
	):
		return false
	state = sync.capture()
	_transaction_check(
		state.can_mix and state.cocktails == 2
		and _transaction_slot(state, "mix:0").id == left.id
		and _transaction_slot(state, "mix:1").id == right.id,
		"native mixer: inputs preserve identities and do not spend a ticket"
	)
	shop.player_info.cocktail_tickets = 0
	_transaction_reject(
		sync, {"action": "mix", "revision": sync.capture().revision},
		"native mixer: complete recipe without ticket"
	)
	shop.player_info.cocktail_tickets = 2
	state = sync.capture()
	var mix = {"action": "mix", "revision": state.revision}
	if not _transaction_check(
		sync.handle_request(mix, 1), "native mixer: shared handler starts actual native mix"
	):
		return false
	_transaction_check(
		bar.mix_animation.is_processing() and sync.capture().busy,
		"native mixer: native animation keeps transactions busy"
	)
	_transaction_reject(sync, mix, "native mixer: replayed mix request")
	_transaction_reject(
		sync, {"action": "mix", "revision": sync.capture().revision},
		"native mixer: second mix during native animation"
	)
	# Await the native animation and its real completion callback; do not invoke
	# finish manually or replace it with a state-only simulation.
	var deadline = Time.get_ticks_msec() + 6000
	while bar.mix_animation.is_processing() and Time.get_ticks_msec() < deadline:
		await sync.get_tree().process_frame
	if not _transaction_check(
		not bar.mix_animation.is_processing(), "native mixer: animation completes within six seconds"
	):
		return false
	await sync.get_tree().process_frame
	state = sync.capture()
	var output = _transaction_slot(state, "mix:2")
	if not _transaction_check(
		output.get("id", 0) != 0 and _transaction_slots(state, "mix", true).size() == 1,
		"native mixer: completion consumes both inputs and leaves one output"
	):
		return false
	_transaction_check(
		_transaction_identity_count(state, left.id) == 0
		and _transaction_identity_count(state, right.id) == 0
		and _transaction_identity_count(state, output.id) == 1
		and _transaction_slots(state, "build", true).size() + 1 == before_count - 1,
		"native mixer: exactly two original identities become one new item"
	)
	_transaction_check(
		state.cocktails == 1 and state.money == before_money and output.score == expected_score,
		"native mixer: one ticket spent, shared money unchanged, input score conserved"
	)
	_transaction_check(
		sync._valid_state(state) and sync.slot_item("mix:2").visible
		and not sync.slot_item("mix:2").slot.disabled_slot,
		"native mixer: completed native output is visible, collectible and valid on the wire"
	)
	var occupied = _transaction_slots(state, "build", true)
	if _transaction_check(not occupied.is_empty(), "native mixer: occupied build fixture exists"):
		_transaction_reject(
			sync, _transaction_move(sync, "mix:2", occupied[0].key),
			"native mixer: output cannot replace an occupied build slot"
		)
		_transaction_reject(
			sync, _transaction_move(sync, occupied[0].key, "mix:0"),
			"native mixer: collect output before adding another input"
		)
	_transaction_reject(
		sync, {"action": "mix", "revision": sync.capture().revision},
		"native mixer: occupied output cannot mix again"
	)
	var collect = _transaction_move(sync, "mix:2", left.key)
	if not _transaction_check(
		sync.handle_request(collect, 1), "native mixer: collect output through shared handler"
	):
		return false
	state = sync.capture()
	_transaction_check(
		_transaction_slot(state, left.key).id == output.id
		and _transaction_slots(state, "mix", true).is_empty()
		and _transaction_slots(state, "build", true).size() == before_count - 1
		and state.cocktails == 1 and state.can_continue,
		"native mixer: output enters build once and empty mixer permits continuation"
	)
	_transaction_reject(sync, collect, "native mixer: replayed output collection")
	return true


func _transaction_move(sync: Node, source: String, target: String) -> Dictionary:
	var state: Dictionary = sync.capture()
	return {
		"action": "move", "revision": state.revision,
		"source": source, "item_id": _transaction_slot(state, source).get("id", 0),
		"target": target, "target_id": _transaction_slot(state, target).get("id", 0)
	}


func _transaction_slot(state: Dictionary, key: String) -> Dictionary:
	for slot in state.slots:
		if slot.key == key:
			return slot
	return {}


func _transaction_slots(state: Dictionary, group: String, occupied: bool) -> Array:
	return state.slots.filter(func(slot): return slot.group == group and (slot.id != 0) == occupied)


func _transaction_identity_count(state: Dictionary, identity: int) -> int:
	return state.slots.filter(func(slot): return slot.id == identity).size()


func _transaction_reject(sync: Node, request: Dictionary, label: String) -> void:
	var before: Dictionary = sync.capture()
	_transaction_check(not sync.handle_request(request, 1), label + " is rejected")
	var after: Dictionary = sync.capture()
	_transaction_check(
		before.money == after.money and before.snacks == after.snacks
		and before.cocktails == after.cocktails and before.slots == after.slots,
		label + " preserves shared money, tickets and item identities"
	)


func _transaction_check(condition: bool, label: String) -> bool:
	if _transaction_record.is_valid():
		_transaction_record.call(condition, label)
	if not condition:
		failures.append(label)
		if not _transaction_record.is_valid():
			push_error("SHOP_PROBE: " + label)
	return condition


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
	var item = sync.slot_item(offer.key)
	sync._render()
	_check(sync.slot_item(offer.key) == item, "redrawing preserves the native draggable item")
	_check(item.can_interact.call(item), "redrawing preserves native item interaction")


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
		_check(object.interactable, "native item retains its own input: " + slot.key)
		_check(
			object.drop_requested.is_valid() and object.can_interact.is_valid(),
			"native item routes drops through shared transactions: " + slot.key
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

extends RefCounted

const PlayerInventory = preload("../mod/player_inventory_sync.gd")
const CONTROLLER_FIELDS = [
	"active",
	"_local_id",
	"table_id",
	"table_leader_id",
	"match_id",
	"lobby",
	"turn_owner",
	"snapshot_id",
	"last_guest_snapshot",
	"_last_phase",
	"_guest_phase",
	"finished",
	"finish_reason",
	"saw_table",
	"latest_state",
	"last_shop_state",
	"table_summaries"
]


class Wire:
	extends Node
	var is_host = true
	var id = 1
	var room_code = "UP8-ROUND-FLOW"
	var packets: Array = []

	func local_id() -> int:
		return id

	func host_id() -> int:
		return 1

	func session_open() -> bool:
		return true

	func invite_ready() -> bool:
		return false

	func close():
		id = 0

	func send(message: Dictionary):
		send_to(2 if is_host else 1, message)

	func send_to(recipient: int, message: Dictionary, unreliable = false):
		packets.append(
			{"recipient": recipient, "bytes": var_to_bytes(message), "unreliable": unreliable}
		)

	func drain() -> Array:
		var result = packets.duplicate()
		packets.clear()
		return result


var checks: Array[Dictionary] = []
var phases: Dictionary = {}
var purchase: Dictionary = {}
var payout: Dictionary = {}
var endings: Dictionary = {}
var run_config: Dictionary = {}
var ready_request: Dictionary = {}
var _mod: Node
var _wire: Wire


func check_host_shop_drag(mod: Node, capture: Callable):
	_mod = mod
	var sync = mod.shop_sync
	var state: Dictionary = sync.capture()
	var offer: Dictionary = {}
	var empty: Dictionary = {}
	for slot in state.slots:
		if slot.group == "offer" and slot.id != 0 and slot.price <= state.money:
			offer = slot
		if slot.group == "build" and slot.id == 0:
			empty = slot
	if not _check(not offer.is_empty() and not empty.is_empty(), "host drag: purchase available"):
		return
	var previous_transport = mod.transport
	var transport = Wire.new()
	mod.transport = transport
	await _begin_shop_input()
	await _cancel_drag(offer.key, "host")
	var body = await _grab_item(offer.key, "host")
	var target_position = sync.slot_screen_position(empty.key)
	await _move_held_item(body, target_position + Vector2(0, -90), "host")
	await capture.call("22-host-native-drag", "Host · native shop ball follows the pointer")
	await _release_at(target_position)
	_check(sync.slot_item(empty.key) == body, "host drag: release purchases the native ball")
	var purchased: Dictionary = sync.capture()
	_check(purchased.revision > state.revision, "host drag: purchase advances shop revision")
	_check(purchased.money == state.money - offer.price, "host drag: purchase spends money once")
	var duplicate = {
		"action": "move",
		"revision": state.revision,
		"source": offer.key,
		"item_id": offer.id,
		"target": empty.key,
		"target_id": 0
	}
	_check(
		purchased.revision > state.revision and not sync.handle_request(duplicate, 1),
		"host drag: duplicate purchase is rejected"
	)
	_check(sync.capture().money == purchased.money, "host drag: duplicate preserves money")
	_input_fixture().finish()
	mod.transport = previous_transport
	transport.free()


func check_guest_snack_drag(mod: Node, capture: Callable):
	_mod = mod
	var sync = mod.shop_sync
	await _delay(0.7)
	var key = ""
	for entry in sync._state.slots:
		if entry.group == "snack" and entry.id != 0:
			key = entry.key
			break
	if not _check(key != "", "guest snack drag: native offer exists"):
		return
	await _begin_shop_input()
	var body = await _grab_item(key, "guest snack")
	await _move_held_item(body, Vector2(940, 500), "guest snack")
	var retracted = 0
	for slot in sync.native_shop().tapas_bar.slots:
		if is_instance_valid(slot.item) and slot.item != body and slot.item.retracted:
			retracted += 1
	_check(retracted > 0, "guest snack drag: native neighboring offers retract while held")
	await capture.call(
		"52-guest-native-snack-drag", "Guest · native snack drag and offer retraction"
	)
	await _release_at(Vector2(24, 96))
	_check(sync.native_shop().grabbed_passive == null, "guest snack drag: cancellation clears grab")
	_check(sync.slot_item(key) == body, "guest snack drag: cancelled snack returns to its slot")
	var restored = true
	for slot in sync.native_shop().tapas_bar.slots:
		if is_instance_valid(slot.item):
			restored = restored and not slot.item.retracted
	_check(restored, "guest snack drag: cancellation restores every retracted offer")
	_input_fixture().finish()


func record_host(mod: Node, capture: Callable):
	_mod = mod
	var saved = _save()
	_setup(1)
	var global_node = mod.get_node("/root/Global")
	var game = global_node.gameManager
	run_config = {
		"deck": str(global_node.chosen_deck.id),
		"difficulty": str(global_node.chosen_difficulty.id),
		"seed": 24681
	}
	if not _check(
		await _wait(func(): return game.balls_spawned and not game.round_ended),
		"round flow: native first round is playable"
	):
		_restore(saved)
		return
	_phase("playing")
	var before = game.player_info.money
	game.debug_round_end(true)
	var menu = mod.get_node("/root/UIManager").round_over_menu
	if not _check(await _wait(func(): return menu.is_open), "round flow: native payout opens"):
		_restore(saved)
		return
	await _delay(0.5)
	payout = {
		"score": menu.score_label.text,
		"money": menu.money_gained_label.text,
		"balance": game.player_info.money,
		"round": game.level_number,
		"rounds_played": game.rounds_played
	}
	_check(payout.balance > before, "round flow: native completion pays the table")
	_phase("payout")
	await capture.call("60-host-payout", "Host · native round completion and payout")
	_check(
		_press_callback(menu, "_on_continue_button_pressed"),
		"round flow: native payout Continue enters the shop"
	)
	if not _check(await _wait(_shop_ready), "round flow: shared shop finishes opening"):
		_restore(saved)
		return
	_check(game.rounds_played > payout.rounds_played, "round flow: shop advances the round counter")
	_phase("shop")
	await capture.call("61-host-round-shop", "Host · shared shop reached through round payout")
	var state = mod.shop_sync.capture()
	var offer: Dictionary = {}
	var empty: Dictionary = {}
	for slot in state.slots:
		if slot.group == "offer" and slot.id != 0 and slot.price <= state.money:
			offer = slot
		if slot.group == "build" and slot.id == 0:
			empty = slot
	if not _check(
		not offer.is_empty() and not empty.is_empty(), "round flow: affordable offer exists"
	):
		_restore(saved)
		return
	purchase = {
		"kind": "shop_request",
		"action": "move",
		"revision": state.revision,
		"source": offer.key,
		"item_id": offer.id,
		"target": empty.key,
		"target_id": 0,
		"request_id": 1
	}
	_deliver_request(2, purchase)
	var purchase_result = _request_result(1)
	_check(purchase_result.get("accepted", false), "round flow: host accepts routed guest purchase")
	if not purchase_result.get("accepted", false):
		print("ROUND_FLOW_REJECTION ", purchase_result.get("error", "No routed result"))
	_check(
		mod.shop_sync.capture().money == state.money - offer.price,
		"round flow: routed guest purchase spends shared money once"
	)
	_phase("purchase")
	state = mod.shop_sync.capture()
	ready_request = {
		"kind": "shop_request",
		"action": "ready",
		"ready": true,
		"revision": state.revision,
		"ready_generation": state.ready_vote.revision,
		"request_id": 3
	}
	var play = mod.shop_sync.native_shop().play_button
	_check(not play.disabled, "round flow: native host Ready is enabled")
	play.pressed.emit()
	state = mod.shop_sync.capture()
	_check(state.open and state.ready_vote.ready == [1], "round flow: host Ready waits for guest")
	_phase("host_ready")
	_deliver_request(
		2,
		{
			"kind": "shop_request",
			"action": "sell",
			"revision": ready_request.revision,
			"source": purchase.target,
			"item_id": purchase.item_id,
			"request_id": 2
		}
	)
	_check(_request_result(2).get("accepted") == false, "round flow: host rejects the stale sale")
	_check(
		mod.shop_sync.capture().money == state.money,
		"round flow: stale sale cannot alter the authoritative balance"
	)
	_phase("rejected_sale")
	_deliver_request(2, ready_request)
	_check(not mod.shop_sync.capture().open, "round flow: simultaneous approvals leave the shop")
	_phase("leaving")
	_check(
		await _wait(
			func(): return game.balls_spawned and not game.round_ended and not game.in_shop
		),
		"round flow: native next round spawns after unanimous Ready"
	)
	_phase("next")
	await capture.call("62-host-next-round", "Host · next round after both teammates ready")
	await _record_endings(capture)
	_restore(saved)


func replay_guest(mod: Node, capture: Callable) -> Array[Dictionary]:
	_mod = mod
	if not phases.has("next"):
		_check(false, "round flow: complete host traffic is available for guest replay")
		return checks
	var saved = _save()
	var menu_scene = mod.get_tree().current_scene
	var menu_visible = menu_scene.visible
	var menu_process = menu_scene.process_mode
	var ui_process = mod.get_node("/root/UIManager").process_mode
	_setup(2)
	_check(
		mod.table_sync.begin_guest(run_config),
		"round flow: guest starts with the host run configuration"
	)
	mod.shop_sync.begin_session(mod)
	mod.adapter.begin_session(mod)
	_replay(phases.playing, ["shop_state"])
	_check(mod.active, "round flow: closed shop update before first replica is accepted")
	_replay(phases.playing, ["state", "snapshot"])
	await _delay(0.3)
	var global_node = mod.get_node("/root/Global")
	_check(
		is_instance_valid(global_node.gameManager),
		"round flow: routed first snapshot creates guest"
	)
	var last_playing_snapshot = mod.last_guest_snapshot
	for packet in phases.payout:
		var payload: Dictionary = bytes_to_var(packet.bytes).get("payload", {})
		if payload.get("kind") == "snapshot" and not payload.has("shop"):
			_replay([packet])
	_check(
		mod.last_guest_snapshot == last_playing_snapshot,
		"round flow: faster physics packet waits for the reliable payout transition"
	)
	_replay(phases.payout)
	await _delay(0.6)
	var menu = mod.get_node("/root/UIManager").round_over_menu
	_check(menu.is_open and menu.canvas.visible, "round flow: guest sees native payout")
	_check(menu.score_label.text == payout.score, "round flow: guest payout score matches host")
	_check(
		menu.money_gained_label.text == payout.money, "round flow: guest payout earnings match host"
	)
	_check(
		global_node.gameManager.player_info.money == payout.balance,
		"round flow: guest receives payout balance"
	)
	await capture.call(
		"63-guest-payout", "Guest · payout received through serialized table messages"
	)
	var old_game = global_node.gameManager.get_instance_id()
	_replay(phases.shop, ["state", "shop_state"])
	await _delay(0.1)
	_replay(phases.shop, ["snapshot"])
	await _delay(0.8)
	var game = global_node.gameManager
	_check(
		(
			game.get_node("UI/ShopFloor").is_visible_in_tree()
			and game.get_node("UI/ShopFloor").texture != null
		),
		"round flow: guest retains the configured native floor"
	)
	_check(
		game.get_node("UI/FloatingUI").is_visible_in_tree(),
		"round flow: guest retains the native floating UI"
	)
	_check(
		game.get_instance_id() == old_game, "round flow: shop transition preserves the guest scene"
	)
	_check(menu.is_open, "round flow: guest can finish reading payout after the host enters shop")
	var shop = mod.shop_sync.native_shop()
	if _check(
		is_instance_valid(shop), "round flow: shop data before the phase snapshot stays usable"
	):
		_check(shop.play_button.disabled, "round flow: Ready is blocked while guest reads payout")
		_wire.drain()
		var rounds_before_continue = game.rounds_played
		_check(
			_press_callback(menu, "_dismiss_round"),
			"round flow: native guest Continue dismisses its payout"
		)
		await _delay(0.2)
		_check(
			(
				not menu.is_open
				and game.rounds_played == rounds_before_continue
				and _wire.packets.is_empty()
			),
			"round flow: guest Continue cannot advance or mutate the shared run"
		)
		_check(
			game.shop == shop and shop.is_visible_in_tree(),
			"round flow: shop belongs to the current guest scene"
		)
		_check(
			shop.is_open and shop.remote_slots_cover(shop.remote_slots, mod.shop_sync._state.slots),
			"round flow: guest remote slots cover the shared shop layout"
		)
		_check(
			global_node.camera.move_position == shop.get_camera_target(),
			"round flow: guest camera reaches native shop"
		)
		_check(
			mod.shop_sync._panel.visible, "round flow: native shop input is visible after payout"
		)
		await capture.call(
			"64-guest-round-shop", "Guest · native shared shop after the round payout"
		)
		await _guest_purchase(capture)
		await _guest_rejected_sale()
		_replay(phases.host_ready)
		await _delay(0.1)
		_check(
			not shop.play_button.disabled,
			"round flow: guest Ready remains enabled after host approves"
		)
		_wire.drain()
		shop.play_button.pressed.emit()
		var ready_frames = _wire.drain()
		_check(
			_has_request(ready_frames, "ready"),
			"round flow: native guest Ready sends a routed request"
		)
		_check(
			mod.shop_sync._state.ready_vote.ready.has(2),
			"round flow: guest Ready shows its approval before the delayed response"
		)
		await capture.call(
			"65-guest-ready-pending",
			"Guest · Ready responds immediately while host confirmation is delayed"
		)
	_replay(phases.leaving, ["shop_result", "shop_state", "state"])
	var waiting_snapshot = mod.last_guest_snapshot
	_replay(phases.next, ["snapshot"])
	_check(
		mod.last_guest_snapshot == waiting_snapshot,
		"round flow: next-round physics waits for the reliable leave-shop transition"
	)
	_replay(phases.leaving, ["snapshot"])
	_replay(phases.next)
	await _delay(0.5)
	game = global_node.gameManager
	_check(
		not game.in_shop and not mod.shop_sync.is_open(),
		"round flow: guest leaves shop after unanimous Ready"
	)
	_check(
		not menu.is_open and not mod.get_tree().paused,
		"round flow: payout cannot soft-lock the next round"
	)
	_check(mod.table_sync.ready_for_input(), "round flow: next round guest aiming is enabled")
	var next_id = game.get_instance_id()
	var last_snapshot = mod.last_guest_snapshot
	_replay(phases.payout, ["snapshot"])
	_replay(phases.shop, ["shop_state", "snapshot"])
	await _delay(0.2)
	_check(
		game.get_instance_id() == next_id and mod.last_guest_snapshot == last_snapshot,
		"round flow: delayed old snapshots cannot replace the next round"
	)
	_check(
		not mod.shop_sync.is_open() and not menu.is_open,
		"round flow: delayed old shop cannot reopen after Ready"
	)
	await capture.call(
		"66-guest-next-round", "Guest · next round remains playable after delayed old shop messages"
	)
	var ui = mod.get_node("/root/UIManager")
	ui.open_settings()
	await _delay(0.3)
	_check(
		ui.settings_menu.is_open and ui.settings_menu.can_process(),
		"round flow: guest native settings open and process"
	)
	_check(
		(
			ui.settings_menu.main_menu_restart_group.is_visible_in_tree()
			and ui.settings_menu.continue_button.is_visible_in_tree()
		),
		"round flow: guest settings retain native in-run actions"
	)
	_check(not mod.table_sync.ready_for_input(), "round flow: guest settings block shot input")
	ui.settings_menu.just_opened_or_closed = false
	ui.settings_menu.instant_close_menu()
	ui.update_pause()
	await _delay(0.1)
	_check(mod.table_sync.ready_for_input(), "round flow: closing guest settings restores aiming")
	for phase in ["win", "loss"]:
		if not phases.has(phase):
			_check(false, "round flow: native " + phase + " traffic is available")
			continue
		_replay(phases[phase])
		await _delay(0.6)
		var ending = mod.get_node("/root/UIManager").game_over_menu
		_check(ending.is_open and ending.canvas.visible, "round flow: guest sees native " + phase)
		_check(
			ending.win == endings[phase].won and ending.score_label.text == endings[phase].score,
			"round flow: guest " + phase + " result matches the host"
		)
		_check(
			(
				ending.money_earned_label.text == endings[phase].money
				and ending.balls_pocketed_label.text == endings[phase].balls
			),
			"round flow: guest " + phase + " statistics match the host"
		)
		_check(
			not mod.table_sync.ready_for_input(),
			"round flow: terminal " + phase + " disables shots"
		)
		_check(
			(
				PlayerInventory.capture(global_node.gameManager.player_info)
				== endings[phase].inventory
			),
			"round flow: guest " + phase + " inventory exactly matches the host"
		)
		var card = ending.get_node("%ContinueRunInfo")
		_check(
			(
				card.get_node("%Balls").get_child_count() == endings[phase].balls_rendered
				and endings[phase].balls_rendered > 0
			),
			"round flow: guest " + phase + " native summary renders the host build"
		)
		_check(
			card.get_node("%Passives").get_child_count() == endings[phase].passives_rendered,
			"round flow: guest " + phase + " native summary renders the host passives"
		)
		await capture.call("69-guest-" + phase, "Guest · native run " + phase + " result")
	ui.game_over_menu.just_opened_or_closed = false
	ui.game_over_menu.instant_close_menu()
	ui.update_pause()
	ui.open_settings()
	await _delay(0.2)
	_check(ui.settings_menu.is_open, "round flow: teardown starts with native settings open")
	mod.shop_sync.end_session()
	mod.adapter.end_session()
	mod.table_sync.end_guest()
	await _delay(0.1)
	_check(
		menu_scene.visible == menu_visible and menu_scene.process_mode == menu_process,
		"round flow: ending guest session restores the main menu"
	)
	_check(
		mod.get_node("/root/UIManager").process_mode == ui_process and not mod.get_tree().paused,
		"round flow: ending guest session restores UI processing and pause state"
	)
	_check(not ui.settings_menu.is_open, "round flow: teardown closes guest native settings")
	await _guest_removed_drag()
	await _cold_loss(capture)
	_restore(saved)
	return checks


func _cold_loss(capture: Callable):
	var global_node = _mod.get_node("/root/Global")
	var previous_shop = (
		global_node.shopManager if is_instance_valid(global_node.shopManager) else null
	)
	global_node.shopManager = null
	_mod._guest_phase = []
	_mod.last_guest_snapshot = 0
	_mod.finished = false
	_check(
		_mod.table_sync.begin_guest(run_config),
		"round flow: cold guest starts without a previous native shop"
	)
	_mod.shop_sync.begin_session(_mod)
	_mod.adapter.begin_session(_mod)
	_replay(phases.loss)
	await _delay(0.6)
	var game = global_node.gameManager
	var ending = _mod.get_node("/root/UIManager").game_over_menu
	_check(
		global_node.shopManager == game.shop and not game.shop.is_open and not game.shop.visible,
		"round flow: cold replica retains an initialized closed native shop"
	)
	_check(game.rounds_played == 0, "round flow: cold defeat happens before the first shop")
	_check(
		ending.is_open and ending.canvas.visible,
		"round flow: cold guest sees the native defeat card without visiting shop"
	)
	_check(
		PlayerInventory.capture(game.player_info) == endings.loss.inventory,
		"round flow: cold defeat restores the starting inventory"
	)
	_check(
		(
			ending.get_node("%ContinueRunInfo").get_node("%Balls").get_child_count()
			== endings.loss.balls_rendered
		),
		"round flow: cold defeat card renders the starting balls"
	)
	_check(
		(
			ending.get_node("%ContinueRunInfo").get_node("%Passives").get_child_count()
			== endings.loss.passives_rendered
		),
		"round flow: cold defeat card renders the starting passives"
	)
	await capture.call(
		"70-guest-cold-loss", "Guest · first-round defeat before any shop has opened"
	)
	_mod.shop_sync.end_session()
	_mod.adapter.end_session()
	_mod.table_sync.end_guest()
	_check(
		global_node.shopManager == null,
		"round flow: cold guest teardown restores the missing shop reference"
	)
	global_node.shopManager = previous_shop if is_instance_valid(previous_shop) else null


func _record_endings(capture: Callable):
	var global_node = _mod.get_node("/root/Global")
	var game = global_node.gameManager
	game.level_number = game.get_target_round() - 1
	game.debug_round_end(true)
	await _record_ending("win", capture)
	_mod.run_controls.end_session()
	_mod.shop_sync.end_session()
	_mod.adapter.end_session()
	_mod.run_setup.return_menu()
	if not _check(
		await _wait(_mod.run_setup.at_main_menu), "round flow: finished host returns to menu"
	):
		return
	var config = {
		"deck": str(global_node.chosen_deck.id),
		"difficulty": str(global_node.chosen_difficulty.id),
		"seed": 24681
	}
	_mod.finished = false
	_mod.finish_reason = ""
	_mod.adapter.begin_session(_mod)
	_mod.shop_sync.begin_session(_mod)
	_mod.run_controls.begin_session()
	if not _check(
		_mod.run_setup.start(config) == OK,
		"round flow: host starts a fresh native run for defeat coverage"
	):
		return
	if not _check(await _wait(_fresh_game_ready), "round flow: fresh defeat table spawns"):
		return
	game = global_node.gameManager
	game.player_info.hp = 1
	game.debug_round_end(false)
	await _record_ending("loss", capture)


func _record_ending(phase: String, capture: Callable):
	var menu = _mod.get_node("/root/UIManager").game_over_menu
	if not _check(
		await _wait(func(): return menu.is_open), "round flow: native " + phase + " opens"
	):
		return
	await _delay(0.4)
	_mod.saw_table = true
	_mod._process(0.0)
	var card = menu.get_node("%ContinueRunInfo")
	endings[phase] = {
		"won": menu.win,
		"score": menu.score_label.text,
		"money": menu.money_earned_label.text,
		"balls": menu.balls_pocketed_label.text,
		"inventory": PlayerInventory.capture(_mod.get_node("/root/Global").gameManager.player_info),
		"balls_rendered": card.get_node("%Balls").get_child_count(),
		"passives_rendered": card.get_node("%Passives").get_child_count()
	}
	_phase(phase)
	await capture.call("68-host-" + phase, "Host · native run " + phase + " result")


func _guest_purchase(capture: Callable):
	var sync = _mod.shop_sync
	var source = sync.slot_item(purchase.source)
	var source_id = source.get_instance_id()
	var original_money = sync._state.money
	var target_slot = sync._view_slots[purchase.target]
	await _begin_shop_input()
	await _cancel_drag(purchase.source, "guest")
	_wire.drain()
	await _grab_item(purchase.source, "guest")
	var target_position = sync.slot_screen_position(purchase.target)
	await _move_held_item(source, target_position + Vector2(0, -90), "guest")
	_replay(phases.shop)
	_check(
		sync.native_shop().is_grabbed(source),
		"guest drag: unchanged host inventory preserves the native grab"
	)
	await capture.call("67-guest-native-drag", "Guest · native shop ball follows the pointer")
	await _release_at(target_position)
	var requests = _wire.drain()
	_check(
		_has_request(requests, "move"),
		"round flow: guest purchase sends a serialized routed request"
	)
	_check(
		sync.slot_item(purchase.target) == source,
		"round flow: purchase moves the same native item immediately"
	)
	_check(
		sync._state.money < original_money,
		"round flow: shared balance updates before the delayed response"
	)
	_check(
		sync._view_slots[purchase.target] == target_slot,
		"round flow: optimistic move preserves the native inventory slot"
	)
	var predicted_money = sync._state.money
	_replay(phases.shop)
	_check(
		sync.slot_item(purchase.target) == source and sync._state.money == predicted_money,
		"round flow: unchanged host traffic preserves an unconfirmed purchase"
	)
	await _delay(0.35)
	await capture.call(
		"67-guest-purchase-pending",
		"Guest · purchase appears immediately during a simulated network delay"
	)
	_replay(phases.purchase)
	await _delay(0.1)
	var confirmed = sync.slot_item(purchase.target)
	_check(
		is_instance_valid(confirmed) and confirmed.get_instance_id() == source_id,
		"round flow: confirmed purchase keeps the same native item"
	)
	_check(not sync._pending, "round flow: host acknowledgement clears the pending purchase")
	_check(
		sync._view_slots[purchase.target] == target_slot,
		"round flow: host update preserves native inventory slots"
	)
	_input_fixture().finish()


func _guest_removed_drag():
	_mod._guest_phase = []
	_mod.last_guest_snapshot = 0
	_mod.finished = false
	_mod.table_sync.begin_guest(run_config)
	_mod.shop_sync.begin_session(_mod)
	_mod.adapter.begin_session(_mod)
	_replay(phases.shop)
	await _delay(0.6)
	var sync = _mod.shop_sync
	var shop = sync.native_shop()
	await _begin_shop_input()
	var body = await _grab_item(purchase.source, "guest interrupted")
	await _move_held_item(body, Vector2(24, 96), "guest interrupted")
	var removed = sync._authoritative_state.duplicate(true)
	removed.revision += 1
	for slot in removed.slots:
		if slot.key == purchase.source:
			for field in ["data", "mixed", "level", "score", "price", "sell"]:
				slot.erase(field)
			slot.id = 0
	_wire.drain()
	_deliver_request(1, {"kind": "shop_state", "shop": removed})
	await _delay(0.1)
	_check(shop.grabbed_ball == null, "guest drag: authoritative removal clears the native grab")
	await _release_at(Vector2(24, 96))
	var requests = _wire.drain()
	_check(
		not _has_request(requests, "move") and not _has_request(requests, "sell"),
		"guest drag: releasing a removed item cannot send a stale transaction"
	)
	_check(
		not is_instance_valid(sync.slot_item(purchase.source)),
		"guest drag: releasing a removed item cannot restore it"
	)
	_input_fixture().finish()
	_mod.shop_sync.end_session()
	_mod.adapter.end_session()
	_mod.table_sync.end_guest()


func _grab_item(key: String, role: String):
	var sync = _mod.shop_sync
	var body = sync.slot_item(key)
	await _input_fixture().hover(body)
	var position = body.get_global_transform_with_canvas().origin
	if not _check(
		_input_fixture().viewport.get_mouse_position().distance_to(position) < 2,
		role + " drag: pointer reaches the native item"
	):
		await _abort_input()
	_check(
		body.can_interact.call(body) and body.interactable, role + " drag: native input is allowed"
	)
	await _mouse_button(position, true)
	await _delay(0.1)
	if not _check(
		sync.native_shop().is_grabbed(body), role + " drag: mouse press grabs the native item"
	):
		print(
			"NATIVE_DRAG_INPUT ",
			{
				"role": role,
				"requested": position,
				"viewport_pointer": _input_fixture().viewport.get_mouse_position(),
				"world_pointer": body.get_global_mouse_position(),
				"body_position": body.global_position,
				"canvas": _mod.get_viewport().get_canvas_transform(),
				"final": _mod.get_viewport().get_final_transform(),
				"interactable": body.interactable,
				"allowed": body.can_interact.call(body),
				"pressed": Input.is_action_pressed("click")
			}
		)
		await _abort_input()
	return body


func hover_shop_item(mod: Node, key: String) -> bool:
	_mod = mod
	await _input_fixture().hover(mod.shop_sync.slot_item(key))
	return mod.shop_sync.native_shop().selected_ball == mod.shop_sync.slot_item(key)


func _input_fixture():
	return _mod.get_node("/root/RenderProbe").shop_input


func _begin_shop_input():
	var shop = _mod.shop_sync.native_shop()
	await _wait(func(): return absf(shop.camera.position.x - shop.target_camera_x) < 0.1)
	_input_fixture().begin(shop)
	await _mod.get_tree().process_frame


func _abort_input():
	_input_fixture().finish()
	_mod.get_node("/root/RenderProbe").abort_input(checks)
	await _mod.get_tree().process_frame


func _move_held_item(body: Node2D, position: Vector2, role: String):
	var original_position = body.global_position
	var started_at = Time.get_ticks_msec()
	var start_process_frame = Engine.get_process_frames()
	var start_drawn_frame = Engine.get_frames_drawn()
	var start_canvas = body.get_viewport().get_canvas_transform()
	_mouse_motion(position, true)
	await _delay(0.4)
	_check(
		body.global_position.distance_to(original_position) > 30,
		role + " drag: the native item itself moves with the pointer"
	)
	var pointer_distance = body.global_position.distance_to(body.get_global_mouse_position())
	if pointer_distance >= 4:
		var shop = _mod.shop_sync.native_shop()
		print(
			"NATIVE_DRAG_MOTION ",
			{
				"role": role,
				"elapsed_ms": Time.get_ticks_msec() - started_at,
				"process_frames": Engine.get_process_frames() - start_process_frame,
				"drawn_frames": Engine.get_frames_drawn() - start_drawn_frame,
				"last_process_delta": body.get_process_delta_time(),
				"body_type": "ShopPassive" if body is ShopPassive else body.get_class(),
				"script": body.get_script().resource_path,
				"body_processing": body.is_processing() and body.can_process(),
				"start_world": original_position,
				"end_world": body.global_position,
				"target_screen": position,
				"pointer_screen": body.get_viewport().get_mouse_position(),
				"pointer_world": body.get_global_mouse_position(),
				"native_target_world": body.tpos,
				"slot_world": body.slot.global_position,
				"pointer_distance": pointer_distance,
				"grabbed": shop.is_grabbed(body),
				"shop_moving": shop.moving(),
				"shop_camera_position": shop.camera.position,
				"shop_camera_target_x": shop.target_camera_x,
				"start_canvas": start_canvas,
				"end_canvas": body.get_viewport().get_canvas_transform(),
				"root_canvas": _mod.get_viewport().get_canvas_transform()
			}
		)
	_check(pointer_distance < 4, role + " drag: native movement reaches the pointer")
	_check(body.z_index == 200, role + " drag: native item renders above its shop slot")
	if body is ShopBall:
		_check(
			body.ball.material.get_shader_parameter("tex") == body.ball_item.data.texture,
			role + " drag: the native sphere shader stays on the held ball"
		)


func _cancel_drag(key: String, role: String):
	var sync = _mod.shop_sync
	var original_state = sync._state.duplicate(true)
	var body = await _grab_item(key, role + " cancel")
	await _move_held_item(body, Vector2(24, 96), role + " cancel")
	_check(
		(
			sync.native_shop().get_hovered_slot() == null
			and not sync.native_shop().is_hovering_sell_area()
		),
		role + " drag: cancellation releases outside native drop targets"
	)
	await _release_at(Vector2(24, 96))
	_check(not sync.native_shop().is_grabbed(body), role + " drag: cancelled item is released")
	_check(sync.slot_item(key) == body, role + " drag: cancellation retains the original item")
	_check(
		body.global_position.distance_to(body.slot.global_position) < 4,
		role + " drag: cancelled native ball returns to its slot"
	)
	_check(
		sync._state == original_state, role + " drag: cancellation leaves shared state unchanged"
	)


func _release_at(position: Vector2):
	_mouse_motion(position, true)
	await _delay(0.1)
	await _mouse_button(position, false)
	await _delay(0.45)


func _mouse_motion(position: Vector2, held: bool):
	_input_fixture().motion(position, held)


func _mouse_button(position: Vector2, pressed: bool):
	await _input_fixture().button(position, pressed)
	_check(
		(
			Input.is_action_just_pressed("click")
			if pressed
			else Input.is_action_just_released("click")
		),
		"native mouse event reaches the click action: " + ("press" if pressed else "release")
	)


func _guest_rejected_sale():
	var sync = _mod.shop_sync
	var balance = sync._state.money
	_wire.drain()
	sync._submit_item("sell", purchase.target)
	_check(
		_has_request(_wire.drain(), "sell"), "round flow: conflicting sale reaches the host route"
	)
	_check(
		not is_instance_valid(sync.slot_item(purchase.target)),
		"round flow: pending sale responds immediately"
	)
	await _delay(0.2)
	_replay(phases.rejected_sale)
	_check(
		(
			is_instance_valid(sync.slot_item(purchase.target))
			and sync._find_slot(purchase.target).id == purchase.item_id
		),
		"round flow: rejected sale restores the authoritative item"
	)
	_check(sync._state.money == balance, "round flow: rejected sale restores the shared balance")
	_check(not sync._pending, "round flow: rejected sale unlocks further shop actions")


func _has_request(packets: Array, action: String) -> bool:
	for packet in packets:
		var message = bytes_to_var(packet.bytes)
		if (
			packet.recipient == 1
			and message.get("kind") == "table"
			and message.get("payload", {}).get("action") == action
		):
			return true
	return false


func _setup(id: int):
	_wire = Wire.new()
	_wire.id = id
	_wire.is_host = id == 1
	_mod.transport = _wire
	_mod.active = true
	_mod._local_id = id
	_mod.table_id = 0
	_mod.table_leader_id = 1
	_mod.turn_owner = 2
	_mod.match_id = 41
	_mod.snapshot_id = 0
	_mod.last_guest_snapshot = 0
	_mod.last_shop_state = {}
	_mod._last_phase = []
	_mod._guest_phase = []
	_mod.finished = false
	_mod.finish_reason = ""
	_mod.table_summaries = []
	_mod.lobby = {
		"started": true,
		"table_count": 1,
		"match_mode": "race",
		"shot_budget": 12,
		"players":
		[
			{"id": 1, "name": "Host", "table": 0, "slot": 0, "connected": true},
			{"id": 2, "name": "Guest", "table": 0, "slot": 1, "connected": true}
		]
	}
	_mod._set_panel(false)


func _save() -> Dictionary:
	var saved = {"transport": _mod.transport}
	for key in CONTROLLER_FIELDS:
		var value = _mod.get(key)
		saved[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return saved


func _restore(saved: Dictionary):
	for key in saved:
		_mod.set(key, saved[key])
	_wire.free()
	_wire = null


func _phase(name: String):
	_mod._publish_state()
	_mod._publish_snapshot(true)
	_mod._update_hud()
	phases[name] = _wire.drain()
	_check(
		phases[name].any(func(packet): return bytes_to_var(packet.bytes).get("kind") == "table"),
		"round flow: recorded routed host " + name
	)


func _deliver_request(actor: int, request: Dictionary):
	var envelope = {
		"kind": "table",
		"match": _mod.match_id,
		"table": _mod.table_id,
		"actor": actor,
		"payload": request,
		"reliable": true
	}
	_mod._received(actor, bytes_to_var(var_to_bytes(envelope)))


func _replay(packets: Array, kinds: Array = []):
	for packet in packets:
		if packet.recipient != 2:
			continue
		var message = bytes_to_var(packet.bytes)
		if not kinds.is_empty() and message.get("payload", {}).get("kind") not in kinds:
			continue
		_mod._received(1, message)
	_mod._update_hud()


func _shop_ready() -> bool:
	var state = _mod.shop_sync.capture()
	return state.get("open", false) and not state.get("busy", true)


func _press_callback(menu: Node, method: String) -> bool:
	for button in menu.find_children("*", "Control", true, false):
		if not button.has_signal("pressed"):
			continue
		for connection in button.get_signal_connection_list("pressed"):
			if connection.callable.get_method() == method:
				button.emit_signal("pressed")
				return true
	return false


func _request_result(id: int) -> Dictionary:
	for packet in _wire.packets:
		var payload: Dictionary = bytes_to_var(packet.bytes).get("payload", {})
		if payload.get("kind") == "shop_result" and payload.get("request_id") == id:
			return payload
	return {}


func _fresh_game_ready() -> bool:
	var game = _mod.get_node("/root/Global").gameManager
	return is_instance_valid(game) and game.balls_spawned


func _wait(condition: Callable) -> bool:
	for _attempt in 120:
		if condition.call():
			return true
		await _delay(0.1)
	return false


func _delay(seconds: float):
	await _mod.get_tree().create_timer(seconds).timeout


func _check(passed: bool, name: String) -> bool:
	checks.append({"passed": passed, "name": name})
	print("ROUND_FLOW_CHECK ", "PASS " if passed else "FAIL ", name)
	return passed

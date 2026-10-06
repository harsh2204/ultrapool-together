extends RefCounted

const PlayerInventory = preload("../mod/player_inventory_sync.gd")
const EndRunState = preload("../mod/end_run_state.gd")
const EndRunDiscussion = preload("../mod/end_run_discussion.gd")
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
	"_last_state_sig",
	"_guest_phase",
	"finished",
	"finish_reason",
	"saw_table",
	"latest_state",
	"last_shop_state",
	"table_summaries",
	"final_builds",
	"end_discussion",
	"_end_motion_sent",
	"_final_build_sent",
	"cue_inventory",
	"lobby_model"
]


class ReviewLobby:
	extends RefCounted
	var state: Dictionary = {}

	func snapshot() -> Dictionary:
		return state.duplicate(true)


class Wire:
	extends Node
	var is_host = true
	var id = 1
	var room_code = "UP12-ROUND-FLOW"
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
var snack_fixture: RefCounted
var _mod: Node
var _wire: Wire
var _trace_count = 0


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
	if snack_fixture != null:
		await snack_fixture.record_host_round(mod, _check, capture)
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
	if snack_fixture != null:
		await snack_fixture.check_routed_guest_round(mod, _check, capture)
	var ui = mod.get_node("/root/UIManager")
	_trace_stage("guest-settings-before-open")
	ui.open_settings()
	_trace_stage("guest-settings-after-open-before-delay")
	await _delay(0.3)
	_trace_stage("guest-settings-after-open-delay")
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
	_trace_stage("guest-settings-before-close")
	ui.settings_menu.just_opened_or_closed = false
	ui.settings_menu.instant_close_menu()
	ui.update_pause()
	_trace_stage("guest-settings-after-close-before-delay")
	await _delay(0.1)
	_trace_stage("guest-settings-after-close-delay")
	_check(mod.table_sync.ready_for_input(), "round flow: closing guest settings restores aiming")
	for phase in ["win", "loss"]:
		if not phases.has(phase):
			_check(false, "round flow: native " + phase + " traffic is available")
			continue
		_mod.final_builds.reset(_mod.match_id)
		_mod.end_discussion.reset(_mod.match_id)
		_trace_stage("guest-" + phase + "-before-review-session")
		_mod.end_run_review.begin_session()
		_trace_stage("guest-" + phase + "-before-terminal-replay")
		_replay(phases[phase])
		_trace_stage("guest-" + phase + "-after-terminal-replay-before-delay")
		await _delay(0.6)
		_trace_stage("guest-" + phase + "-after-terminal-delay")
		var ending = mod.get_node("/root/UIManager").game_over_menu
		await _check_review("guest-" + phase, endings[phase].inventory, capture)
		_trace_stage("guest-" + phase + "-before-continue")
		mod.end_run_review._continue.pressed.emit()
		_trace_stage("guest-" + phase + "-after-continue")
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
	_trace_stage("guest-before-staggered-review")
	await _check_staggered_review(capture)
	_trace_stage("guest-after-staggered-review")
	ui.game_over_menu.just_opened_or_closed = false
	ui.game_over_menu.instant_close_menu()
	ui.update_pause()
	mod.end_run_review.end_session()
	_trace_stage("guest-teardown-settings-before-open")
	ui.open_settings()
	_trace_stage("guest-teardown-settings-after-open-before-delay")
	await _delay(0.2)
	_trace_stage("guest-teardown-settings-after-open-delay")
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
	_mod.final_builds.reset(_mod.match_id)
	_mod.end_discussion.reset(_mod.match_id)
	_mod.end_run_review.begin_session()
	_check(
		_mod.table_sync.begin_guest(run_config),
		"round flow: cold guest starts without a previous native shop"
	)
	_mod.shop_sync.begin_session(_mod)
	_mod.adapter.begin_session(_mod)
	_trace_stage("guest-cold-loss-before-terminal-replay")
	_replay(phases.loss)
	_trace_stage("guest-cold-loss-after-terminal-replay-before-delay")
	await _delay(0.6)
	_trace_stage("guest-cold-loss-after-terminal-delay")
	var game = global_node.gameManager
	var ending = _mod.get_node("/root/UIManager").game_over_menu
	await _check_review("guest-cold-loss", endings.loss.inventory, capture)
	_mod.end_run_review._continue.pressed.emit()
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
	_mod.end_run_review.end_session()
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
	_prepare_end_review()
	_phase(phase)
	await _check_review("host-" + phase, endings[phase].inventory, capture)
	_mod.end_run_review._continue.pressed.emit()
	_check(menu.canvas.visible, "after hours: Continue restores the original native card")
	await capture.call("68-host-" + phase, "Host · native run " + phase + " result")
	_mod.end_run_review.end_session()


func _prepare_end_review() -> void:
	# Start the summary in its real pre-terminal state, then let _phase publish
	# native adapter results through _record_summary and the final-build route.
	var model = ReviewLobby.new()
	model.state = _mod.lobby.duplicate(true)
	_mod.lobby_model = model
	_mod.table_summaries = [{
		"table": 0, "leader_id": 1, "score": 0.0, "base_score": 0.0,
		"bounty_shot": 0, "shots_used": 0, "finished": false, "status": "Playing",
		"round": 1, "elapsed_ms": 0
	}]
	_mod.final_builds.reset(_mod.match_id)
	_mod.end_discussion.reset(_mod.match_id)
	_mod._final_build_sent = false
	_mod._last_state_sig = []
	_mod.cue_inventory = load(_mod.get_script().resource_path.get_base_dir().path_join("cue_inventory.gd")).new()
	_mod.cue_inventory.reset(_mod._members(0, false))
	_mod.end_run_review.begin_session()


func _check_review(role: String, inventory: Dictionary, capture: Callable) -> void:
	var review = _mod.end_run_review
	_trace_stage(role + "-before-review-refresh")
	review.refresh()
	_trace_stage(role + "-after-review-refresh-before-delay")
	await _delay(0.1)
	_trace_stage(role + "-after-review-delay")
	var ui = _mod.get_node("/root/UIManager")
	_check(review.is_open(), "after hours: " + role + " opens the final rack")
	_check(
		ui.game_over_menu.is_open and not ui.game_over_menu.canvas.visible
		and ui.active_popups.has(ui.game_over_menu),
		"after hours: " + role + " covers native results without replaying finalization"
	)
	_check(
		_mod.final_builds.get_record(0).get("inventory", {}) == inventory,
		"after hours: " + role + " reviews the production final inventory"
	)
	_check(not review._continue.disabled, "after hours: final summary and build enable Continue")
	_check_review_inventory(inventory, role)
	var first_balls = _review_ball_nodes(review._rack)
	review.refresh()
	_check(_review_ball_nodes(review._rack) == first_balls,
		"after hours: repeated summary retains native ball nodes")
	_trace_stage(role + "-before-review-capture")
	await capture.call("after-hours-" + role, "After-hours rack · " + role)
	_trace_stage(role + "-after-review-capture")


func _review_ball_nodes(rack: Control) -> Dictionary:
	var result: Dictionary = {}
	for original in rack.items:
		result[original] = rack.items[original].node
	return result


func _check_native_marker_alignment(rack: Control, context: String, held_original: int = -1) -> void:
	# Read the actual native marker transforms after Container layout. Comparing
	# against the component's cached slot positions would miss a stale 8px inset.
	var base = "PanelContainer/VBoxContainer/TextureRect"
	var inventory_node = rack.native_root.get_node(base + "/Node2D/Inventory")
	var markers: Array = inventory_node.get_node("Triangle").get_children()
	markers.append_array(inventory_node.get_node("Reserve").get_children())
	for display_slot in range(mini(16, rack.displayed_order.size())):
		var original: int = rack.displayed_order[display_slot]
		var marker_position: Vector2 = markers[display_slot].global_position
		_check(rack.slots[display_slot].button.get_global_rect().get_center().distance_to(marker_position) < 0.1,
			"after hours: " + context + " native slot hit target follows its real marker")
		if original != held_original and rack.items.has(original):
			_check(rack.items[original].node.global_position.distance_to(marker_position) < 0.1,
				"after hours: " + context + " undragged ball is centered on its real native marker")
	var snack_markers: Array = rack.native_root.get_node(base + "/PassivesInfo").get_children()
	for index in rack.passive_items:
		_check(rack.passive_items[index].node.global_position.distance_to(snack_markers[index].global_position) < 0.1,
			"after hours: " + context + " snack is centered on its real native marker")
	for index in rack.cube_items:
		_check(rack.cube_items[index].node.global_position.distance_to(rack.cube_slots[index].global_position) < 0.1,
			"after hours: " + context + " supplemental cube is centered on its marker")


func _check_review_inventory(inventory: Dictionary, context: String) -> void:
	var rack = _mod.end_run_review._rack
	var database = _mod.get_node("/root/BallDatabase")
	_check(rack.native_root != null and rack.native_root.get_script() == null,
		"after hours: " + context + " uses the scriptless native final-build scene")
	_check_native_marker_alignment(rack, context)
	_check(rack.slots.size() == inventory.build.size()
		and rack.displayed_order == range(inventory.build.size()),
		"after hours: " + context + " preserves every original rack and reserve slot")
	var occupied_build = inventory.build.filter(func(item): return item != null)
	_check(rack.items.size() == occupied_build.size(),
		"after hours: " + context + " preserves occupied slots and empty holes")
	# Independent native 0.17.2 ContinueRunInfo scene centers, relative to its
	# 600x376 background: ten triangular slots, then six reserve slots.
	var native_centers = [Vector2(301, 276), Vector2(261, 220), Vector2(337, 220),
		Vector2(225, 168), Vector2(301, 168), Vector2(373, 168), Vector2(185, 112),
		Vector2(261, 112), Vector2(341, 112), Vector2(413, 112), Vector2(428, 268),
		Vector2(492, 268), Vector2(556, 268), Vector2(428, 332), Vector2(492, 332),
		Vector2(556, 332)]
	var background = rack.native_root.get_node("PanelContainer/VBoxContainer/TextureRect")
	var inverse: Transform2D = background.get_global_transform().affine_inverse()
	for index in range(mini(16, rack.slots.size())):
		_check((inverse * rack.slot_center(index)).is_equal_approx(native_centers[index]),
			"after hours: " + context + " slot " + str(index) + " matches native triangle/reserve geometry")
	for index in inventory.build.size():
		var state = inventory.build[index]
		if state == null:
			_check(not rack.items.has(index) and rack.slots[index].button.tooltip_text == "Empty slot",
				"after hours: " + context + " null slot " + str(index) + " stays empty")
			continue
		if not _check(rack.items.has(index), "after hours: original ball identity is retained"):
			continue
		var item: Dictionary = rack.items[index]
		_check(item.state == state and item.node.position.is_equal_approx(rack.slots[index].position),
			"after hours: " + context + " ball stays in its captured native slot")
		_check_review_ball(item, state, context)
		var expected = database.id_to_ball[state.data].get_formatted_name()
		if state.mixed != "":
			expected += " + " + database.id_to_ball[state.mixed].get_formatted_name()
		_check(rack.slots[index].button.tooltip_text.begins_with(expected + "\n"),
			"after hours: native localized ball name remains available for inspection")
	var passive_centers = [Vector2(500, 120), Vector2(556, 120), Vector2(500, 172), Vector2(556, 172)]
	_check(rack.passive_slots.size() == 4, "after hours: all four native snack positions remain")
	for index in 4:
		_check((inverse * rack.passive_slots[index].global_position).is_equal_approx(passive_centers[index]),
			"after hours: " + context + " snack slot matches native geometry")
		var state = inventory.passives[index]
		_check(rack.passive_items.has(index) == (state != null),
			"after hours: " + context + " preserves the exact snack slot, including empties")
		if state != null and rack.passive_items.has(index):
			var item: Dictionary = rack.passive_items[index]
			_check(item.state == state and item.item.texture == database.id_to_passive[state.data].texture,
				"after hours: native snack art retains the captured identity")
			_check(item.node.global_position.is_equal_approx(rack.passive_slots[index].global_position),
				"after hours: snack art occupies its native slot")
	_check(rack.cube_slots.size() == inventory.cubes.size(),
		"after hours: supplemental cube strip preserves its original slot count")
	for index in inventory.cubes.size():
		var state = inventory.cubes[index]
		_check(rack.cube_items.has(index) == (state != null),
			"after hours: supplemental cubes preserve identities and empty slots")
		if state != null and rack.cube_items.has(index):
			_check_review_ball(rack.cube_items[index], state, context + " cube")


func _check_review_ball(item: Dictionary, state: Dictionary, context: String) -> void:
	var database = _mod.get_node("/root/BallDatabase")
	var native_item = BallItem.new()
	native_item.data = database.id_to_ball[state.data]
	if state.mixed != "":
		native_item.mixed_data = database.id_to_ball[state.mixed]
	for field in PlayerInventory.NUMBERS:
		native_item.set(field, state[field])
	for field in PlayerInventory.FLAGS:
		native_item.set(field, state[field])
	var expected_score = native_item.get_score()
	var expected_text = _mod.get_node("/root/Global").format_number(absi(expected_score), 4, 0)
	if expected_score < 0:
		expected_text = "-" + expected_text
	_check(item.points == expected_score and item.label.text == expected_text
		and item.label.is_visible_in_tree(),
		"after hours: " + context + " always shows the captured native ball points")
	_check_review_label(item.label, context + " points")
	_check(item.sphere.material.get_shader_parameter("tex") == database.id_to_ball[state.data].texture,
		"after hours: native sphere material uses the captured ball atlas")
	if state.mixed != "":
		_check(item.sphere.material.get_shader_parameter("mixed_tex") == database.id_to_ball[state.mixed].texture,
			"after hours: mixed ball keeps both native atlases")


func _check_review_label(label: Label, context: String) -> void:
	_check(
		label.get_line_count() > 0
		and label.get_visible_line_count() >= label.get_line_count()
		and label.size.y + 1.0 >= label.get_line_count() * label.get_line_height(),
		"after hours: " + context + " renders every text line"
	)


func _check_review_bounds(context: String) -> void:
	var review = _mod.end_run_review
	var bounds: Rect2 = review._root.get_global_rect().grow(1.0)
	for label in [review._heading, review._status, review._table_title, review._stats,
		review._discussion_hint, review._cue_label]:
		if not label.visible:
			continue
		_check_review_label(label, context)
		_check(bounds.encloses(label.get_global_rect()), "after hours: " + context + " heading fits viewport")
	for button in review._tabs + [review._continue, review._reset]:
		if not button.visible:
			continue
		_check(
			bounds.encloses(button.get_global_rect())
			and button.size.x + 1.0 >= button.get_combined_minimum_size().x,
			"after hours: " + context + " navigation text and control fit viewport"
		)


func _record_from_ending(phase: String) -> Dictionary:
	for packet in phases.get(phase, []):
		var message: Dictionary = bytes_to_var(packet.bytes)
		if message.get("kind") == "run_build":
			return message.record.duplicate(true)
	return {}


func _deliver_review(message: Dictionary) -> void:
	# Reuse the normal serialized coordinator -> guest receive path. This is a
	# deterministic room-presentation fixture, not a second running native table.
	_replay([{"recipient": 2, "bytes": var_to_bytes(message)}])


func _check_staggered_review(capture: Callable) -> void:
	var own_record = _record_from_ending("loss")
	var other_record = _record_from_ending("win")
	if not _check(
		not own_record.is_empty() and not other_record.is_empty(),
		"after hours: staggered room uses both production native ending records"
	):
		return
	_check(
		own_record.inventory.build != other_record.inventory.build,
		"after hours: native purchase and fresh-run records provide distinct racks"
	)
	var saved_lobby: Dictionary = _mod.lobby.duplicate(true)
	var saved_archive = _mod.final_builds
	var saved_discussion = _mod.end_discussion
	var saved_motion: Dictionary = _mod._end_motion_sent.duplicate(true)
	var native_inventory = PlayerInventory.capture(_mod.get_node("/root/Global").gameManager.player_info)
	var room: Dictionary = saved_lobby.duplicate(true)
	room.table_count = 2
	room.match_mode = "score"
	room.players.append({"id": 3, "name": "Night Shift", "table": 1, "slot": 0, "connected": true})
	var own_summary: Dictionary = room.table_summaries[0].duplicate(true)
	var other_summary: Dictionary = own_summary.duplicate(true)
	other_summary.merge({
		"table": 1, "leader_id": 3, "finished": false, "run_won": false,
		"status": "Playing", "score": own_summary.score + 10.0,
		"base_score": own_summary.score + 10.0
	}, true)
	room.table_summaries = [own_summary, other_summary]
	other_record.table = 1
	other_record.leader = 3
	var cue: Dictionary = other_record.cues.players[0].duplicate(true)
	cue.id = 3
	other_record.cues.players = [cue]
	_mod.final_builds = EndRunState.new()
	_mod.final_builds.reset(_mod.match_id)
	_mod.end_discussion = EndRunDiscussion.new()
	_mod.end_discussion.reset(_mod.match_id)
	_mod._end_motion_sent = {}
	var review = _mod.end_run_review
	review.begin_session()
	_deliver_review({"kind": "lobby_state", "lobby": room})
	_deliver_review({"kind": "run_build", "match": _mod.match_id, "record": own_record})
	await _delay(0.1)
	_check(review._tabs.filter(func(button): return button.visible).size() == 2,
		"after hours: both room tables have review controls")
	review._tabs[1].pressed.emit()
	review._tabs[1].grab_focus()
	await _delay(0.1)
	_check(
		review._selected == 1 and review._empty.visible
		and review._empty.text == "Still playing. Its final build will appear here."
		and review._continue.disabled and is_zero_approx(review._felt.chalk),
		"after hours: selecting an unfinished table waits without a winner or early exit"
	)
	_check_review_bounds("waiting table")
	_check_review_label(review._empty, "waiting table status")
	await capture.call("after-hours-two-tables-waiting", "After-hours rack · browsing the table still playing")
	other_summary.finished = true
	other_summary.status = "Finished"
	_deliver_review({"kind": "lobby_state", "lobby": room})
	_check(
		review._selected == 1 and review._empty.text == "Setting out the final rack…"
		and review._continue.disabled,
		"after hours: terminal summary preserves selection and waits for its delayed build"
	)
	var chalk_tween = review._chalk_tween
	await _delay(0.75)
	_check(
		is_equal_approx(review._felt.chalk, 0.9)
		and chalk_tween != null and not chalk_tween.is_running()
		and review._tabs[1].text == "Table 2 · chalked"
		and review._tabs[0].text == "Table 1"
		and review._heading.text == "Table 2 leaves its mark.",
		"after hours: final score leader receives one completed finite chalk flourish"
	)
	_deliver_review({"kind": "run_build", "match": _mod.match_id, "record": other_record})
	await _delay(0.1)
	_check(
		review._selected == 1 and not review._empty.visible and not review._continue.disabled
		and _mod.get_viewport().gui_get_focus_owner() == review._tabs[1],
		"after hours: delayed build hydrates the selected table and preserves focus"
	)
	_check_review_inventory(other_record.inventory, "second table")
	review._tabs[0].pressed.emit()
	await _delay(0.1)
	_check_review_inventory(own_record.inventory, "first table after switching")
	review._tabs[1].pressed.emit()
	await _delay(0.1)
	_check_review_inventory(other_record.inventory, "second table after switching back")
	var retained_balls = _review_ball_nodes(review._rack)
	_deliver_review({"kind": "lobby_state", "lobby": room})
	_check(
		_review_ball_nodes(review._rack) == retained_balls and review._chalk_tween == chalk_tween
		and is_equal_approx(review._felt.chalk, 0.9) and not chalk_tween.is_running(),
		"after hours: unchanged results retain native balls and cannot restart the chalk tween"
	)
	_check_review_bounds("final second table")
	await capture.call("after-hours-two-tables-final", "After-hours rack · Table 2's final build and settled chalk")
	await _check_shared_native_drag(other_record, capture)
	review._continue.pressed.emit()
	await _delay(0.1)
	var menu = _mod.get_node("/root/UIManager").game_over_menu
	_check(
		not review.is_open() and menu.is_open and menu.canvas.visible,
		"after hours: two-table Continue restores the native result card"
	)
	_check(
		PlayerInventory.capture(_mod.get_node("/root/Global").gameManager.player_info) == native_inventory,
		"after hours: inspecting both captured builds never mutates native inventory"
	)
	await capture.call("after-hours-two-tables-continue", "After-hours rack · native controls restored after both builds arrive")
	review.end_session()
	_mod.final_builds = saved_archive
	_mod.end_discussion = saved_discussion
	_mod._end_motion_sent = saved_motion
	_mod.lobby = saved_lobby


func _relay_rack_requests(host_model: RefCounted, stale_drop: bool = false) -> Array:
	# One native process, two independent discussion models. Deliver actual
	# serialized guest output through the production room-host receive boundary.
	var requests = _wire.drain()
	var guest_model = _mod.end_discussion
	var guest_actor = _mod._local_id
	var guest_motion: Dictionary = _mod._end_motion_sent
	var summaries: Array = _mod.table_summaries
	var blocked: bool = _mod.is_blocking_signals()
	_mod.set_block_signals(true)
	_mod.end_discussion = host_model
	_mod._end_motion_sent = {}
	_mod._local_id = 1
	_mod.table_summaries = _mod.lobby.table_summaries
	_wire.id = 1
	_wire.is_host = true
	for packet in requests:
		var message: Dictionary = bytes_to_var(packet.bytes)
		if packet.recipient == 1 and message.get("kind") in ["rack_request", "rack_motion"]:
			if stale_drop and message.get("request", {}).get("action") == "drop":
				# A stale reliable action must release its optimistic hold when
				# rejected; the server still owns the real hold until cancel arrives.
				message.request.revision -= 1
				message = bytes_to_var(var_to_bytes(message))
			_mod._received(2, message)
	var replies = _wire.drain()
	_mod.end_discussion = guest_model
	_mod._end_motion_sent = guest_motion
	_mod._local_id = guest_actor
	_mod.table_summaries = summaries
	_wire.id = 2
	_wire.is_host = false
	_mod.set_block_signals(blocked)
	_replay(replies)
	return replies


func _rack_action_count(packets: Array, action: String) -> int:
	var count = 0
	for packet in packets:
		var message: Dictionary = bytes_to_var(packet.bytes)
		if message.get("kind") == "rack_request" and message.get("request", {}).get("action") == action:
			count += 1
	return count


func _apply_rack_peer(peer: RefCounted, packets: Array, rack: Control, table: int) -> void:
	# The coordinator's broadcast bytes also feed an independent second renderer.
	# This proves shared-state presentation, not Steam delivery to another machine.
	for packet in packets:
		if packet.recipient != 2:
			continue
		var message: Dictionary = bytes_to_var(packet.bytes)
		if message.get("kind") == "rack_state":
			_check(peer.apply_state(message.table, message.state),
				"after hours: second viewer accepts the host's ordered rack state")
		elif message.get("kind") == "rack_motion":
			_check(peer.apply_motion(message.table, message.actor, message.token, message.seq, message.position),
				"after hours: second viewer accepts the shared held-ball position")
	rack.apply_discussion(peer.snapshot(table), 3, "Guest")


func _review_pointer_button(position: Vector2, pressed: bool) -> void:
	var event = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	_mod.get_viewport().push_input(event, true)


func _review_pointer_motion(position: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	_mod.get_viewport().push_input(event, true)


func _check_shared_native_drag(record: Dictionary, capture: Callable) -> void:
	var review = _mod.end_run_review
	var rack = review._rack
	var table: int = record.table
	var archive_before = _mod.final_builds.get_record(table)
	var info = _mod.get_node("/root/Global").gameManager.player_info
	var native_before = PlayerInventory.capture(info)
	var ball_nodes = _review_ball_nodes(rack)
	var occupied = rack.items.keys()
	if not _check(occupied.size() >= 2, "after hours: shared drag has two captured native balls"):
		return
	occupied.sort()
	var source: int = occupied[0]
	var target: int = occupied[1]
	var initial_order: Array = rack.displayed_order.duplicate()
	var host_model = EndRunDiscussion.new()
	host_model.reset(_mod.match_id)
	host_model.ensure_table(table, record.inventory.build)
	var peer_model = EndRunDiscussion.new()
	peer_model.reset(_mod.match_id)
	peer_model.ensure_table(table, record.inventory.build)
	var peer_rack = rack.get_script().new()
	review._root.add_child(peer_rack)
	peer_rack.setup(_mod)
	peer_rack.position = review._root.get_global_transform().affine_inverse() * rack.global_position
	peer_rack.size = rack.size
	peer_rack.present(record)
	await _delay(0.1)
	_check_native_marker_alignment(peer_rack, "fresh peer view after its first visible layout")
	peer_rack.hide()
	peer_rack.apply_discussion(peer_model.snapshot(table), 3)
	_wire.drain()
	_trace_stage("shared-native-rack-before-pickup")
	_review_pointer_button(rack.slot_center(source), true)
	_check(rack._local_slot == source and rack._pointer_held and rack.items[source].node.z_index == 100,
		"after hours: native GUI press picks up a ball immediately before host acknowledgement")
	var replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_check(_mod.end_discussion.snapshot(table).drag.get("actor") == 2
		and peer_model.snapshot(table) == host_model.snapshot(table),
		"after hours: production host grants the same hold to both viewers")
	var held_position: Vector2 = rack.slot_center(target) + Vector2(0, -64)
	_review_pointer_motion(held_position)
	_check(rack.items[source].node.global_position.distance_to(held_position) < 0.5,
		"after hours: native ball and its points follow the local pointer without a round trip")
	var has_disposable_motion = false
	for packet in _wire.packets:
		if packet.unreliable and bytes_to_var(packet.bytes).get("kind") == "rack_motion":
			has_disposable_motion = true
	_check(has_disposable_motion,
		"after hours: held motion uses the disposable channel")
	replies = _relay_rack_requests(host_model)
	var motion_packets = replies.duplicate(true)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_check(peer_rack.items[source].node.position.is_equal_approx(rack.items[source].node.position)
		and peer_rack.point_labels[source].text == rack.point_labels[source].text,
		"after hours: second viewer sees the same held ball and captured points")
	_check(peer_model.snapshot(table) == _mod.end_discussion.snapshot(table),
		"after hours: coordinator, guest and second viewer agree after shared motion")
	await capture.call("after-hours-shared-native-drag", "After-hours rack · shared native ball drag with points")
	# Render the same authoritative packet as the second viewer, using the real
	# review callback and independent native component. No second game is launched.
	rack.hide()
	peer_rack.show()
	review._rack = peer_rack
	_mod._local_id = 3
	review.refresh_discussion(table)
	await _delay(0.1)
	_check_native_marker_alignment(peer_rack, "second viewer during shared drag", source)
	_check(review._discussion_hint.text == "Guest is moving a ball." and peer_rack._actor_label.visible,
		"after hours: second viewer identifies who is discussing the held ball")
	await capture.call("after-hours-shared-native-peer", "After-hours rack · second viewer sees the shared drag")
	_mod._local_id = 2
	review._rack = rack
	peer_rack.hide()
	rack.show()
	review.refresh_discussion(table)
	_review_pointer_button(rack.slot_center(target), false)
	replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	var expected_order = initial_order.duplicate()
	expected_order[source] = target
	expected_order[target] = source
	_check(rack.displayed_order == expected_order and peer_rack.displayed_order == expected_order
		and host_model.snapshot(table).drag.is_empty(),
		"after hours: release swaps native slots identically for every viewer")
	_check(rack.items[source].node.position.is_equal_approx(rack.slots[target].position)
		and rack.items[target].node.position.is_equal_approx(rack.slots[source].position),
		"after hours: swapped balls settle into the native triangle positions")
	_check(_review_ball_nodes(rack) == ball_nodes,
		"after hours: shared arrangement retains the native ball nodes")
	_replay(motion_packets)
	_check(_mod.end_discussion.snapshot(table).drag.is_empty()
		and rack.items[source].node.position.is_equal_approx(rack.slots[target].position),
		"after hours: delayed old motion cannot resurrect a completed drag")
	await capture.call("after-hours-shared-native-swapped", "After-hours rack · shared rearrangement keeps native slots and points")
	review._reset.pressed.emit()
	replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_check(rack.displayed_order == initial_order and peer_rack.displayed_order == initial_order,
		"after hours: Reset arrangement restores the original rack for both viewers")
	_check_review_inventory(record.inventory, "reset shared rack")
	_check(_mod.final_builds.get_record(table) == archive_before and PlayerInventory.capture(info) == native_before,
		"after hours: pickup, shared motion, swap and reset never mutate archived or live inventory")
	await capture.call("after-hours-shared-native-reset", "After-hours rack · original native arrangement restored")
	# Fast users can release or switch tables before reliable begin returns.
	# Exercise those paths from actual pointer/GUI events, without granting a
	# hold or writing the expected order directly into either discussion model.
	var before_pickup_state = host_model.snapshot(table)
	_review_pointer_button(rack.slot_center(source), true)
	_review_pointer_motion(rack.slot_center(target))
	_deliver_review({"kind": "rack_state", "match": _mod.match_id, "table": table,
		"state": before_pickup_state, "accepted": true, "action": "", "reason": ""})
	_check(rack._local_slot == source and rack._pointer_held and rack._awaiting_pickup
		and rack.items[source].node.global_position.distance_to(rack.slot_center(target)) < 0.5,
		"after hours: an older empty snapshot cannot cancel a pickup still awaiting its grant")
	_review_pointer_button(rack.slot_center(target), false)
	_check(review._pending_release == target and host_model.snapshot(table).drag.is_empty(),
		"after hours: quick release retains one drop while the pickup is unacknowledged")
	replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_check(_rack_action_count(_wire.packets, "drop") == 1,
		"after hours: pickup acknowledgement sends the retained drop with the host token")
	replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_check(rack.displayed_order == expected_order and peer_rack.displayed_order == expected_order
		and host_model.snapshot(table).drag.is_empty() and review._holding_table == -1,
		"after hours: release before pickup acknowledgement completes once without a stranded hold")
	review._reset.pressed.emit()
	replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_review_pointer_button(rack.slot_center(source), true)
	review._tabs[0].pressed.emit()
	_check(review._selected == 0, "after hours: table switching stays local while pickup is pending")
	replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_check(_rack_action_count(_wire.packets, "cancel") == 1,
		"after hours: delayed pickup on a departed table immediately requests cancellation")
	replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_check(host_model.snapshot(table).drag.is_empty() and _mod.end_discussion.snapshot(table).drag.is_empty()
		and review._selected == 0 and review._holding_table == -1,
		"after hours: table switch before acknowledgement leaves no remote hold and preserves selection")
	review._tabs[1].pressed.emit()
	await _delay(0.1)
	_review_pointer_button(rack.slot_center(source), true)
	replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_check(host_model.snapshot(table).drag.get("actor") == 2 and review._holding_table == table
		and review._pending_pickup == -1,
		"after hours: acknowledged hold exists before switching away from its table")
	review._tabs[0].pressed.emit()
	_check(review._selected == 0 and _rack_action_count(_wire.packets, "cancel") == 1,
		"after hours: leaving an acknowledged hold sends one cancellation")
	replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_check(host_model.snapshot(table).drag.is_empty() and peer_model.snapshot(table).drag.is_empty()
		and review._selected == 0 and review._holding_table == -1
		and review._pending_pickup == -1 and review._pending_release == -2
		and not review._have_drag_position,
		"after hours: hidden-table cancel acknowledgement clears local hold bookkeeping")
	review._tabs[1].pressed.emit()
	await _delay(0.1)
	_review_pointer_button(rack.slot_center(source), true)
	replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_check(host_model.snapshot(table).drag.get("actor") == 2,
		"after hours: another pickup succeeds after hidden-table cancellation")
	_review_pointer_button(rack.slot_center(target), false)
	replies = _relay_rack_requests(host_model, true)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	var drop_rejected = false
	for packet in replies:
		if bytes_to_var(packet.bytes).get("accepted") == false:
			drop_rejected = true
	_check(drop_rejected and host_model.snapshot(table).drag.get("actor") == 2,
		"after hours: stale drop is rejected while the server still holds that ball")
	_check(_rack_action_count(_wire.packets, "cancel") == 1,
		"after hours: rejected drop sends exactly one reliable cancellation")
	replies = _relay_rack_requests(host_model)
	_apply_rack_peer(peer_model, replies, peer_rack, table)
	_check(host_model.snapshot(table).drag.is_empty() and _mod.end_discussion.snapshot(table).drag.is_empty()
		and review._holding_table == -1 and rack.displayed_order == initial_order
		and peer_rack.displayed_order == initial_order,
		"after hours: rejected drop recovers both viewers without stranding the rack")
	_check(_mod.final_builds.get_record(table) == archive_before and PlayerInventory.capture(info) == native_before,
		"after hours: delayed acknowledgements, tab changes and rejection preserve saved and live builds")

	_trace_stage("shared-native-rack-after-reset")
	peer_rack.free()


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
	_mod.final_builds = EndRunState.new()
	_mod.final_builds.reset(_mod.match_id)
	_mod.end_discussion = EndRunDiscussion.new()
	_mod.end_discussion.reset(_mod.match_id)
	_mod._end_motion_sent = {}
	_mod._final_build_sent = false
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
	_mod.end_run_review.end_session()
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


## Fixture-only bounded checkpoint: stdout may remain buffered on a watchdog
## failure. Overwrite and flush one small record at explicit phase boundaries.
## No frame callbacks, extra game process, or normal save directory is involved.
func _trace_stage(stage: String) -> void:
	if _trace_count >= 128 or not OS.get_user_data_dir().contains("UltrapoolTogetherRenderTest"):
		return
	var args = OS.get_cmdline_user_args()
	var output_index = args.find("--output")
	if output_index < 0 or output_index + 1 >= args.size():
		return
	var directory: String = args[output_index + 1]
	if not DirAccess.dir_exists_absolute(directory):
		return
	var file = FileAccess.open(directory.path_join("round-flow-stage.json"), FileAccess.WRITE)
	if file == null:
		return
	_trace_count += 1
	var ui = _mod.get_node("/root/UIManager")
	var checkpoint = {
		"stage": stage.left(120),
		"checkpoint": _trace_count,
		"ticks_ms": Time.get_ticks_msec(),
		"process_frames": Engine.get_process_frames(),
		"paused": _mod.get_tree().paused,
		"time_scale": Engine.time_scale,
		"active": _mod.active,
		"finished": _mod.finished,
		"ui_process_mode": ui.process_mode,
		"settings_open": ui.settings_menu.is_open,
		"native_ending_open": ui.game_over_menu.is_open,
		"review_open": _mod.end_run_review.is_open(),
		"popup_count": ui.active_popups.size()
	}
	file.store_string(JSON.stringify(checkpoint, "\t"))
	file.flush()
	file.close()


func _delay(seconds: float):
	await _mod.get_tree().create_timer(seconds).timeout


func _check(passed: bool, name: String) -> bool:
	checks.append({"passed": passed, "name": name})
	print("ROUND_FLOW_CHECK ", "PASS " if passed else "FAIL ", name)
	return passed

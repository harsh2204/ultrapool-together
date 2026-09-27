extends RefCounted

## Loaded only by the existing, explicitly authorized Capture-Screens harness.
## Real native shop + retained cue UI, deterministic transport, isolated test saves.
const CueModels = preload("../mod/cue_models.gd")
const CuePrefs = preload("../mod/cue_prefs.gd")
const SYNC_FIELDS = [
	"_state",
	"_authoritative_state",
	"_last_capture",
	"_revision",
	"_pending",
	"_pending_at",
	"_pending_message",
	"_request_id",
	"_cue_error",
	"last_error",
	"_queued_nav",
	"_applied_nav",
	"_saved_finish",
	"_continuing",
	"_actions_blocked",
]
const VOTE_FIELDS = ["revision", "last_error", "_eligible", "_ready", "_context"]


class Wire:
	extends Node
	var is_host = false
	var id = 2
	var packets: Array = []

	func local_id() -> int:
		return id

	func host_id() -> int:
		return 1

	func send(message: Dictionary) -> void:
		send_to(host_id(), message)

	func send_to(recipient: int, message: Dictionary, unreliable = false) -> void:
		packets.append(
			{"recipient": recipient, "message": message.duplicate(true), "unreliable": unreliable}
		)


func run_host(mod: Node, capture: Callable, check: Callable) -> void:
	var sync = mod.shop_sync
	var native = sync.native_shop()
	if not check.call(is_instance_valid(native), "cue shop: host native counter exists"):
		return
	var saved = _save(mod)
	var wire = Wire.new()
	wire.id = 1
	# Table authority is mod._local_id/table_leader_id. Record room-lobby messages
	# without applying them to the separate synthetic lobby-model fixture.
	mod.transport = wire
	mod.cue_inventory.reset(mod._members(mod.table_id))
	sync.capture()
	check.call(sync.show_section("snacks"), "cue shop: host can visit the native snack bar")
	await _settle(mod)
	check.call(sync.show_section("cues"), "cue shop: host enters the adjoining cue counter")
	await _settle(mod)
	var view = sync._cue_view
	if not check.call(is_instance_valid(view), "cue shop: world-space rack is constructed"):
		_restore(mod, saved, wire)
		return
	check.call(
		view.get_parent() == native.tapas_bar.get_parent(),
		"cue shop: rack shares native scrolling content parent"
	)
	check.call(
		view.position.x > native.tapas_bar.position.x, "cue shop: rack is to the right of snacks"
	)
	check.call(
		is_equal_approx(native.target_camera_x, -view.position.x),
		"cue shop: camera slides to the rack's world position"
	)
	check.call(sync.current_section() == "cues", "cue shop: navigation advertises the cue section")
	var before = mod.cue_inventory.snapshot()
	var wallet: float = native.player_info.money
	view._select_model("finesse")
	view._select_finish("gold")
	check.call(
		mod.cue_inventory.snapshot() == before and native.player_info.money == wallet,
		"cue shop: previews never buy, equip, recolor, or spend"
	)
	var focused: Button = view._cards.finesse.button
	focused.grab_focus()
	sync.capture()
	check.call(focused.has_focus(), "cue shop: authoritative refresh preserves local card focus")
	await _check_pages(view, capture, check)
	view._select_model("finesse")
	view._select_finish("gold")
	view._page = 0
	view._update_page()
	view._link_focus()
	await capture.call(
		"cue-shop-host-preview",
		"Cue workshop · subtle cue effects, free finishes, and the shared table wallet."
	)
	_reject(mod, _command(sync, "cue_equip", "firm", "rose"), 1, "unowned cue equip", check)
	var stale: Dictionary = _command(sync, "cue_buy", "finesse", "gold")
	stale.revision -= 1
	_reject(mod, stale, 1, "stale shop revision", check)
	var wrong_scene: Dictionary = _command(sync, "cue_buy", "finesse", "gold")
	wrong_scene.scene += 1
	_reject(mod, wrong_scene, 1, "wrong shop scene", check)
	_reject(mod, _command(sync, "cue_buy", "finesse", "gold"), 999, "outsider actor", check)
	var replay: Dictionary = _command(sync, "cue_buy", "finesse", "gold")
	view._action.pressed.emit()
	check.call(
		mod.cue_inventory.model_for(1) == "finesse",
		"cue shop: real Buy button equips the bought model"
	)
	check.call(
		mod.cue_inventory.finish_for(1) == "gold",
		"cue shop: purchase applies the selected finish atomically"
	)
	check.call(
		is_equal_approx(native.player_info.money, wallet - float(CueModels.entry("finesse").price)),
		"cue shop: native shared wallet debits the catalog price once"
	)
	_reject(mod, replay, 1, "replayed purchase", check)
	_reject(
		mod,
		_command(sync, "cue_equip", "finesse", "gold"),
		2,
		"teammate cannot equip another player's purchase",
		check
	)
	await capture.call(
		"cue-shop-host-equipped",
		"Purchased Finesse cue · Gold finish · confirmed shared-money debit."
	)
	check.call(sync.show_section("snacks"), "cue shop: Back returns to the snack counter")
	await _settle(mod)
	check.call(
		sync.current_section() == "snacks" and not view._active,
		"cue shop: leaving releases cue input and focus"
	)
	check.call(
		is_equal_approx(native.target_camera_x, -native.tapas_bar.position.x),
		"cue shop: Back restores the native snack camera target"
	)
	_restore(mod, saved, wire)


func run_guest(mod: Node, capture: Callable, check: Callable) -> void:
	var sync = mod.shop_sync
	if not check.call(
		is_instance_valid(sync.native_shop()), "cue shop: guest native counter exists"
	):
		return
	if not check.call(
		not mod.get_node("/root/UIManager").is_popup_open() and not mod.get_tree().paused,
		"cue shop: guest starts after the native cube popup releases input"
	):
		return
	var saved = _save(mod)
	var wire = Wire.new()
	mod.transport = wire
	var initial: Dictionary = sync._authoritative_state.duplicate(true)
	mod.cue_inventory.reset(mod._members(mod.table_id))
	initial.cues = mod.cue_inventory.snapshot()
	initial.revision += 1
	initial.section = "snacks"
	initial.focus = ""
	check.call(sync.apply_state(initial), "cue shop: guest imports authoritative personal racks")
	await _settle(mod)
	if not check.call(
		sync.show_section("cues"), "cue shop: guest enters the same adjoining counter"
	):
		_restore(mod, saved, wire)
		return
	await _settle(mod)
	var view = sync._cue_view
	if not check.call(is_instance_valid(view), "cue shop: guest rack is constructed"):
		_restore(mod, saved, wire)
		return
	var wallet: float = initial.money
	view._select_model("finesse")
	view._select_finish("gold")
	view._action.pressed.emit()
	if not check.call(
		sync._pending and not wire.packets.is_empty(),
		"cue shop: guest click sends a real bounded pending request"
	):
		_restore(mod, saved, wire)
		return
	var request_id: int = sync._pending_message.get("request_id", 0)
	check.call(
		sync._state.money == wallet and mod.cue_inventory.model_for(2) == "house",
		"cue shop: guest pending choice never predicts wallet or ownership"
	)
	view._change_page(1)
	view._select_finish("rose")
	check.call(
		view._page == 1 and view._selected_finish == "rose" and sync._pending,
		"cue shop: guest previews and paging remain responsive while pending"
	)
	await capture.call(
		"cue-shop-guest-pending",
		"Guest browsing the next cue rack while the table confirms a purchase."
	)
	sync.apply_result(false, "An old reply", request_id + 1, initial)
	check.call(sync._pending, "cue shop: unrelated result IDs cannot unlock a pending purchase")
	sync.apply_result(false, "Not enough shared money for that cue.", request_id, initial)
	check.call(
		not sync._pending and sync._state.money == wallet,
		"cue shop: rejected purchase rolls back to authoritative money"
	)
	check.call(
		mod.cue_inventory.model_for(2) == "house" and view._selected_finish == "rose",
		"cue shop: rejection preserves owned equipment and local preview"
	)
	check.call(
		not view._status.text.is_empty(), "cue shop: rejection has immediate visible feedback"
	)
	await capture.call(
		"cue-shop-guest-rejected",
		"Rejected cue purchase · inventory and money preserved · local browsing remains available."
	)
	view._page = 0
	view._update_page()
	view._link_focus()
	view._select_model("finesse")
	view._select_finish("gold")
	view._action.pressed.emit()
	if not check.call(sync._pending, "cue shop: a second guest purchase waits for authority"):
		_restore(mod, saved, wire)
		return
	var accepted: Dictionary = initial.duplicate(true)
	accepted.revision += 1
	accepted.cues.revision += 1
	accepted.money -= float(CueModels.entry("finesse").price)
	accepted.section = "cues"
	for row in accepted.cues.players:
		if row.id == 2:
			row.owned.append("finesse")
			row.equipped = "finesse"
			row.finish = "gold"
	sync.apply_result(true, "", sync._pending_message.get("request_id", 0), accepted)
	check.call(
		not sync._pending and mod.cue_inventory.model_for(2) == "finesse",
		"cue shop: accepted result imports the authoritative equipped cue"
	)
	check.call(
		mod.cue_inventory.finish_for(2) == "gold" and sync._state.money == accepted.money,
		"cue shop: accepted finish and wallet agree with host state"
	)
	sync.apply_state(initial)
	check.call(
		sync._state.money == accepted.money and mod.cue_inventory.model_for(2) == "finesse",
		"cue shop: reordered older state cannot undo a confirmed purchase"
	)
	await capture.call(
		"cue-shop-guest-equipped",
		"Guest cue purchase confirmed by the table · equipped model, finish, and wallet agree."
	)
	var latest_cues: Dictionary = mod.cue_inventory.snapshot()
	latest_cues.revision += 1
	for row in latest_cues.players:
		if row.id == 2:
			row.equipped = "house"
			row.finish = "rose"
	mod.cue_inventory.apply_snapshot(latest_cues)
	sync.refresh_cue_inventory(int(latest_cues.revision))
	check.call(
		view._player.equipped == "house" and view._player.finish == "rose",
		"cue shop: standalone cue confirmation refreshes the open rack"
	)
	check.call(
		view._selected_model == "finesse" and view._selected_finish == "gold",
		"cue shop: standalone equipment refresh preserves local preview"
	)
	var delayed_shop: Dictionary = accepted.duplicate(true)
	delayed_shop.revision += 1
	delayed_shop.money -= 1.0
	check.call(sync.apply_state(delayed_shop), "cue shop: later outer shop state is accepted")
	check.call(
		(
			mod.cue_inventory.model_for(2) == "house"
			and sync._state.cues == latest_cues
			and sync._authoritative_state.cues == latest_cues
			and view._player.equipped == "house"
			and view._player.finish == "rose"
		),
		"cue shop: stale nested cue revision cannot rewind rack or rollback state"
	)
	check.call(
		sync._state.money == delayed_shop.money and view._action.text == "Equip cue · free",
		"cue shop: newer wallet reconciles while cue ownership and action stay current"
	)
	_restore(mod, saved, wire)


func _check_pages(view, capture: Callable, check: Callable) -> void:
	var identities: Dictionary = {}
	for id in view._cards:
		identities[id] = view._cards[id].button.get_instance_id()
	var seen: Dictionary = {}
	var page_count = ceili(float(CueModels.ids().size()) / 3.0)
	for page in page_count:
		view._page = page
		view._update_page()
		view._link_focus()
		var visible = 0
		for id in view._cards:
			if view._cards[id].button.visible:
				visible += 1
				seen[id] = true
				view._select_model(id)
		check.call(
			visible > 0 and visible <= 3, "cue shop: rack page has readable bounded card count"
		)
		await capture.call(
			"cue-shop-rack-%d" % (page + 1),
			(
				"Cue workshop rack %d · distinct cues and their complete effect descriptions."
				% (page + 1)
			)
		)
		check.call(
			view._description.get_line_count() <= 3,
			"cue shop: full effect description fits the three-line placard"
		)
		check.call(
			view._description.get_global_rect().end.y < view._action.get_global_rect().position.y,
			"cue shop: cue description stays above the purchase controls and inventory"
		)
	check.call(
		seen.size() == 15 and seen.size() == CueModels.ids().size(),
		"cue shop: every one of the fifteen cues is reachable"
	)
	for id in identities:
		check.call(
			view._cards[id].button.get_instance_id() == identities[id],
			"cue shop: paging retains " + id + " card identity"
		)
	view._page = 0
	view._update_page()
	view._link_focus()


func _command(sync, action: String, model: String, finish: String) -> Dictionary:
	var state: Dictionary = sync.capture()
	return {
		"action": action,
		"model": model,
		"finish": finish,
		"scene": state.scene,
		"revision": state.revision
	}


func _reject(mod: Node, command: Dictionary, actor: int, label: String, check: Callable) -> void:
	var before: Dictionary = mod.cue_inventory.snapshot()
	var money: float = mod.shop_sync.native_shop().player_info.money
	check.call(not mod.shop_sync.handle_request(command, actor), "cue shop: rejects " + label)
	check.call(
		(
			mod.cue_inventory.snapshot() == before
			and mod.shop_sync.native_shop().player_info.money == money
		),
		"cue shop: " + label + " preserves racks and money"
	)


func _save(mod: Node) -> Dictionary:
	var saved = {
		"transport": mod.transport,
		"cues": mod.cue_inventory.snapshot(),
		"money": mod.shop_sync.native_shop().player_info.money,
		"section": mod.shop_sync.current_section(),
		"finish": CuePrefs.cue_id(),
		"sync": {},
		"vote": {},
	}
	for field in SYNC_FIELDS:
		saved.sync[field] = _copy(mod.shop_sync.get(field))
	for field in VOTE_FIELDS:
		saved.vote[field] = _copy(mod.shop_sync._ready_vote.get(field))
	return saved


func _restore(mod: Node, saved: Dictionary, wire: Node) -> void:
	var sync = mod.shop_sync
	sync.native_shop().player_info.money = saved.money
	mod.cue_inventory.reset([])
	mod.cue_inventory.apply_snapshot(saved.cues)
	for field in SYNC_FIELDS:
		sync.set(field, saved.sync[field])
	for field in VOTE_FIELDS:
		sync._ready_vote.set(field, saved.vote[field])
	mod.transport = saved.transport
	CuePrefs.set_cue_id(saved.finish)
	sync._render()
	sync.show_section(saved.section)
	sync.native_shop().inventory.update_money(saved.money)
	if mod.is_table_host():
		sync.native_shop().save_run_state()
	wire.free()


func _copy(value):
	return value.duplicate(true) if value is Dictionary or value is Array else value


func _settle(mod: Node) -> void:
	await mod.get_tree().create_timer(0.6).timeout

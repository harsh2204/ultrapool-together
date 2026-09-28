extends RefCounted

## Loaded only by the existing, explicitly authorized Capture-Screens harness.
## Real native shop + retained cue UI, deterministic transport, isolated test saves.
const CueModels = preload("../mod/cue_models.gd")
const CuePrefs = preload("../mod/cue_prefs.gd")
const CueCatalog = preload("../mod/cue_catalog.gd")
const CueVisuals = preload("../mod/cue_visuals.gd")
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
	"_cue_shop_enabled",
	"_tutorial_enabled",
	"_tutorial_saved",
	"_shared_sync_latched",
	"_was_finished",
	"_vote_hold",
	"_exclusive_shopper",
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
	var confirmed: Dictionary = view.confirmed_equipment()
	_check_confirmed(
		view,
		mod.cue_inventory.model_for(1),
		mod.cue_inventory.finish_for(1),
		"host opens with authoritative equipment",
		check
	)
	view._select_model("finesse")
	view._select_finish("gold")
	check.call(
		mod.cue_inventory.snapshot() == before and native.player_info.money == wallet,
		"cue shop: previews never buy, equip, recolor, or spend"
	)
	check.call(
		view.confirmed_equipment() == confirmed,
		"cue shop: host model and finish previews preserve the displayed equipped cue"
	)
	var focused: Button = view._cards.finesse.button
	focused.grab_focus()
	sync.capture()
	check.call(focused.has_focus(), "cue shop: authoritative refresh preserves local card focus")
	_check_rack_motion(view, check)
	_check_resize_layout(mod, view, check)
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
	_check_confirmed(view, "finesse", "gold", "host purchase updates the equipped display", check)
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
	await _capture_animation(mod, view, capture, check)
	var retained_nodes: Array = _node_ids(view)
	view._change_page(1)
	var leaving_tween: Tween = view._rack_tween
	check.call(view._rack_transitioning, "cue shop: leave fixture starts during rack movement")
	check.call(sync.show_section("snacks"), "cue shop: Back returns to the snack counter")
	_check_inactive(view, leaving_tween, check)
	await _settle(mod)
	check.call(
		sync.current_section() == "snacks" and not view._active,
		"cue shop: leaving releases cue input and focus"
	)
	check.call(
		is_equal_approx(native.target_camera_x, -native.tapas_bar.position.x),
		"cue shop: Back restores the native snack camera target"
	)
	check.call(sync.show_section("cues"), "cue shop: the retained counter can reopen")
	await _settle(mod)
	check.call(
		_node_ids(view) == retained_nodes, "cue shop: reopening retains all rack and seller nodes"
	)
	check.call(view._seller.is_processing(), "cue shop: Rook resumes only at the active counter")
	_check_confirmed(view, "finesse", "gold", "reopening preserves confirmed equipment", check)
	check.call(sync.show_section("snacks"), "cue shop: reopened counter releases navigation")
	_check_inactive(view, view._rack_tween, check)
	await _check_disabled_session(mod, wire, capture, check, "host")
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
	var confirmed: Dictionary = view.confirmed_equipment()
	_check_confirmed(
		view,
		mod.cue_inventory.model_for(2),
		mod.cue_inventory.finish_for(2),
		"guest opens with authoritative equipment",
		check
	)
	view._select_model("finesse")
	view._select_finish("gold")
	check.call(
		view.confirmed_equipment() == confirmed,
		"cue shop: guest preview does not replace the displayed equipped cue"
	)
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
	check.call(
		view.confirmed_equipment() == confirmed,
		"cue shop: pending purchase leaves the displayed equipped cue unchanged"
	)
	view._change_page(1)
	view._select_finish("rose")
	check.call(
		view._page == 1 and view._selected_finish == "rose" and sync._pending,
		"cue shop: guest previews and paging remain responsive while pending"
	)
	view.settle_rack()
	check.call(
		view.confirmed_equipment() == confirmed,
		"cue shop: browsing another rack while pending preserves the equipped display"
	)
	await capture.call(
		"cue-shop-guest-pending",
		"Guest browsing the next cue rack while the table confirms a purchase."
	)
	sync.apply_result(false, "An old reply", request_id + 1, initial)
	check.call(sync._pending, "cue shop: unrelated result IDs cannot unlock a pending purchase")
	check.call(
		view.confirmed_equipment() == confirmed,
		"cue shop: unrelated reply cannot replace the equipped display"
	)
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
		view.confirmed_equipment() == confirmed,
		"cue shop: rejected purchase preserves the equipped portrait, finish, and label"
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
	_check_confirmed(
		view, "finesse", "gold", "guest acceptance updates the equipped display", check
	)
	sync.apply_state(initial)
	check.call(
		sync._state.money == accepted.money and mod.cue_inventory.model_for(2) == "finesse",
		"cue shop: reordered older state cannot undo a confirmed purchase"
	)
	_check_confirmed(
		view, "finesse", "gold", "older state cannot rewind the equipped display", check
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
	_check_confirmed(
		view, "house", "rose", "new cue revision refreshes the equipped display", check
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
	_check_confirmed(
		view, "house", "rose", "stale nested cues cannot rewind the equipped display", check
	)
	check.call(
		sync._state.money == delayed_shop.money and view._action.text == "Equip",
		"cue shop: newer wallet reconciles while cue ownership and action stay current"
	)
	await _check_disabled_session(mod, wire, capture, check, "guest")
	_restore(mod, saved, wire)


func _check_disabled_session(
	mod: Node, wire: Node, capture: Callable, check: Callable, role: String
) -> void:
	var sync = mod.shop_sync
	var native = sync.native_shop()
	var native_id: int = native.get_instance_id()
	var old_rack_id: int = sync._cue_view.get_instance_id()
	var native_art: Dictionary = sync._cue_art.duplicate(true)
	var state: Dictionary = sync._authoritative_state.duplicate(true)
	var cues: Dictionary = mod.cue_inventory.snapshot()
	var finish: String = CuePrefs.cue_id()
	var money: float = native.player_info.money
	var prefix = "cue shop: " + role + " disabled session "
	check.call(not native_art.is_empty(), prefix + "starts with extended counter artwork")
	# Exercise the real session latch without destroying the native shop or guest
	# context owned by the enclosing render fixture. The outer fixture restores all
	# begin_session fields and the original frozen config/tutorial preference.
	mod.run_config = mod.run_config.duplicate(true)
	mod.run_config["cue_shop_enabled"] = false
	sync.begin_session(mod)
	check.call(not sync._cue_shop_enabled, prefix + "latches the frozen run setting")
	state.section = "snacks"
	state.focus = ""
	if role == "host":
		sync.capture()
	else:
		check.call(sync.apply_state(state), prefix + "hydrates ordinary shared shop state")
	await _settle(mod)
	check.call(
		(
			not is_instance_valid(sync._cue_view)
			and not is_instance_valid(sync._cue_link)
			and not is_instance_valid(sync._cue_shortcut)
			and native.camera.get_node_or_null("TogetherCueShop") == null
			and native.camera.get_node_or_null("TogetherMoveToCues") == null
			and native.camera.get_node_or_null("TogetherCuesShortcut") == null
		),
		prefix + "constructs no rack or cue navigation controls"
	)
	check.call(sync._cue_art.is_empty(), prefix + "keeps no cue art extension")
	for key in native_art:
		var original: Dictionary = native_art[key]
		var restored: bool = (
			is_instance_valid(original.node)
			and original.node.position.is_equal_approx(original.position)
		)
		if original.has("region"):
			restored = restored and original.node.region_rect.is_equal_approx(original.region)
		check.call(restored, prefix + "restores native artwork " + str(key))
	check.call(not sync.show_section("cues"), prefix + "rejects cue counter navigation")
	var before_packets: int = wire.packets.size()
	var requests: Array = []
	var remember_request = func(message): requests.append(message.duplicate(true))
	sync.request.connect(remember_request)
	for action in ["cue_buy", "cue_equip", "cue_finish"]:
		var command = {
			"action": action,
			"model": "firm" if action == "cue_buy" else "house",
			"finish": "native",
			"scene": sync._state.scene,
			"revision": sync._state.revision,
		}
		if role == "host":
			for actor in [1, 2]:
				check.call(
					not sync.handle_request(command.duplicate(true), actor),
					prefix + "rejects crafted " + action + " from actor " + str(actor)
				)
			check.call(
				not sync._apply_cue_action(native, command.duplicate(true), wire.local_id()),
				prefix + "guards direct " + action + " transaction application"
			)
		sync._submit(command.duplicate(true))
		check.call(
			(
				mod.cue_inventory.snapshot() == cues
				and native.player_info.money == money
				and not sync._pending
				and sync._pending_message.is_empty()
			),
			prefix + action + " preserves wallet/equipment and creates no pending transaction"
		)
	sync.request.disconnect(remember_request)
	check.call(
		requests.is_empty() and wire.packets.size() == before_packets,
		prefix + "emits no cue request or transport packet"
	)
	# Even a newer valid cue slice is inert while the run disables cues.
	var incoming: Dictionary = sync._authoritative_state.duplicate(true)
	incoming.revision += 1
	incoming.cues = cues.duplicate(true)
	incoming.cues.revision += 1
	for player in incoming.cues.players:
		if not player.owned.has("firm"):
			player.owned.append("firm")
		player.equipped = "firm"
		player.finish = "gold"
	check.call(sync.apply_state(incoming), prefix + "accepts the ordinary shop snapshot")
	check.call(
		mod.cue_inventory.snapshot() == cues and CuePrefs.cue_id() == finish,
		prefix + "ignores paid equipment and finish changes in a disabled cue snapshot"
	)
	for section in ["balls", "snacks"]:
		check.call(sync.show_section(section), prefix + "can navigate to native " + section)
		await _settle(mod)
		check.call(sync.current_section() == section, prefix + "settles at native " + section)
		var group = "offer:" if section == "balls" else "snack:"
		var available = false
		for key in sync._view_slots:
			if str(key).begins_with(group):
				var item = sync.slot_item(key)
				if is_instance_valid(item) and sync._can_drag_item(item):
					available = true
					break
		check.call(available, prefix + "retains native " + section + " item interaction")
	check.call(
		sync.native_shop().get_instance_id() == native_id,
		prefix + "keeps the native shop instance and inventory"
	)
	await capture.call(
		"cue-shop-" + role + "-disabled",
		(
			role.capitalize()
			+ " · Cue shop off for this run · native snacks and wallet remain available."
		)
	)
	mod.run_config["cue_shop_enabled"] = true
	sync.begin_session(mod)
	if role == "host":
		sync.capture()
	else:
		state.cues = cues.duplicate(true)
		check.call(sync.apply_state(state), prefix + "rehydrates the next enabled session")
	await _settle(mod)
	check.call(
		(
			sync._cue_shop_enabled
			and is_instance_valid(sync._cue_view)
			and sync._cue_view.get_instance_id() != old_rack_id
			and is_instance_valid(sync._cue_link)
			and is_instance_valid(sync._cue_shortcut)
			and not sync._cue_art.is_empty()
		),
		prefix + "rebuilds the cue counter and links at the next enabled session"
	)
	check.call(sync.show_section("cues"), prefix + "can enter the re-enabled cue counter")
	await _settle(mod)
	check.call(
		mod.cue_inventory.snapshot() == cues and native.player_info.money == money,
		prefix + "leaves confirmed equipment and money intact across both boundaries"
	)
	if is_instance_valid(sync._cue_view):
		_check_confirmed(
			sync._cue_view,
			mod.cue_inventory.model_for(wire.local_id()),
			mod.cue_inventory.finish_for(wire.local_id()),
			role + " re-enabled session restores the confirmed equipped display",
			check
		)
	sync.show_section("snacks")


func _capture_animation(mod: Node, view, capture: Callable, check: Callable) -> void:
	# Real viewport frames from the existing single-process harness. Static capture
	# waits two frames and has no timestamp return, so this bounded sequence reads
	# the same viewport at frame_post_draw and records its monotonic draw time.
	# A fixed 96-frame / 384 MiB buffer defers PNG compression until after the
	# eight-second recording, so disk encoding cannot stall the shown animation.
	var owner = capture.get_object()
	if not check.call(is_instance_valid(owner), "cue animation: capture owner exists"):
		return
	var output = str(owner.get("output"))
	if not check.call(not output.is_empty(), "cue animation: uses the harness output directory"):
		return
	var directory = output.path_join("cue-animation")
	if not check.call(
		DirAccess.make_dir_recursive_absolute(directory) == OK,
		"cue animation: frame directory created"
	):
		return
	var preview = [view._page, view._selected_model, view._selected_finish]
	var confirmed: Dictionary = view.confirmed_equipment()
	var inventory: Dictionary = mod.cue_inventory.snapshot()
	var wallet: float = mod.shop_sync.native_shop().player_info.money
	var retained_nodes: Array = _node_ids(view)
	view.settle_rack()
	var timeline = [
		{"at": 0.0, "action": "greet"},
		{"at": 0.7, "action": "next"},
		{"at": 1.5, "action": "next"},
		{"at": 2.3, "action": "previous"},
		{"at": 3.1, "action": "emerald"},
		{"at": 3.6, "action": "nudge"},
		{"at": 4.5, "action": "previous"},
		{"at": 5.2, "action": "rose"},
		{"at": 5.7, "action": "next"},
		{"at": 6.5, "action": "previous"},
	]
	var frames: Array = []
	var images: Array[Image] = []
	var buffered_bytes = 0
	var events: Array = []
	var observed = {"rack": false, "idle": false, "blink": false, "talk": false, "nudge": false}
	var unchanged = true
	var event_index = 0
	var next_sample = 0
	var bytes_written = 0
	var started = Time.get_ticks_usec()
	var started_unix = Time.get_unix_time_from_system()
	while frames.size() < 96 and Time.get_ticks_usec() - started < 8000000:
		await mod.get_tree().process_frame
		var elapsed = Time.get_ticks_usec() - started
		while event_index < timeline.size() and elapsed >= int(timeline[event_index].at * 1000000):
			var action = str(timeline[event_index].action)
			_cue_animation_action(view, action)
			events.append({"action": action, "elapsed_usec": Time.get_ticks_usec() - started})
			event_index += 1
		await RenderingServer.frame_post_draw
		var draw_time = Time.get_ticks_usec()
		elapsed = draw_time - started
		if elapsed >= 8000000:
			break
		if elapsed < next_sample:
			continue
		# Skip missed samples instead of queuing or fabricating intermediate frames.
		next_sample = (floori(float(elapsed) / 83333.0) + 1) * 83333
		var image = mod.get_viewport().get_texture().get_image()
		var image_bytes = image.get_data_size()
		if not check.call(
			buffered_bytes + image_bytes <= 384 * 1024 * 1024,
			"cue animation: raw frames stay within the fixed memory budget"
		):
			break
		buffered_bytes += image_bytes
		images.append(image)
		var filename = "frame-%03d.png" % frames.size()
		var displayed: Dictionary = view.confirmed_equipment()
		unchanged = unchanged and displayed == confirmed
		var seller_frame: int = view._seller._body.frame
		observed.rack = observed.rack or view._rack_transitioning
		observed.idle = observed.idle or seller_frame == 0
		observed.blink = observed.blink or seller_frame % 2 == 1
		observed.talk = observed.talk or seller_frame >= 2
		observed.nudge = observed.nudge or view._seller._nudge > 0.4
		(
			frames
			. append(
				{
					"file": filename,
					"draw_ticks_usec": draw_time,
					"elapsed_usec": elapsed,
					"engine_frame": Engine.get_frames_drawn(),
					"width": image.get_width(),
					"height": image.get_height(),
					"rack_page": view._page + 1,
					"rack_moving": view._rack_transitioning,
					"rack_offset_x": view._rack.position.x,
					"rack_alpha": view._rack.modulate.a,
					"preview_model": view._selected_model,
					"preview_finish": view._selected_finish,
					"seller_cel": seller_frame,
					"seller_body_y": view._seller._body.position.y,
					"seller_nudge": view._seller._nudge,
					"equipped_model": displayed.model,
					"equipped_finish": displayed.finish,
					"equipped_label": displayed.label,
				}
			)
		)
	var recorded_elapsed = Time.get_ticks_usec() - started
	for index in images.size():
		var filename: String = frames[index].file
		var path = directory.path_join(filename)
		if not check.call(images[index].save_png(path) == OK, "cue animation: saved " + filename):
			break
		images[index] = null
		var saved_file = FileAccess.open(path, FileAccess.READ)
		if saved_file != null:
			bytes_written += saved_file.get_length()
			saved_file.close()
		if not check.call(
			bytes_written <= 192 * 1024 * 1024, "cue animation: disk budget respected"
		):
			break
		await mod.get_tree().process_frame
	images.clear()
	var manifest = {
		"schema": 1,
		"source": "Actual Godot viewport after RenderingServer.frame_post_draw",
		"timing_note":
		"Monotonic draw timestamps; readback affects cadence, PNG encoding follows recording.",
		"target_fps": 12,
		"target_duration_seconds": 8,
		"started_ticks_usec": started,
		"started_unix_seconds": started_unix,
		"elapsed_usec": recorded_elapsed,
		"buffered_bytes": buffered_bytes,
		"bytes_written": bytes_written,
		"events": events,
		"observed": observed,
		"frames": frames,
	}
	var manifest_file = FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	if check.call(manifest_file != null, "cue animation: manifest opened"):
		manifest_file.store_string(JSON.stringify(manifest, "\t"))
		manifest_file.close()
	check.call(frames.size() >= 60, "cue animation: captured at least sixty actual rendered frames")
	check.call(
		event_index == timeline.size(), "cue animation: completed the bounded interaction timeline"
	)
	for motion in observed:
		check.call(observed[motion], "cue animation: actual frames include " + motion)
	check.call(
		(
			unchanged
			and mod.cue_inventory.snapshot() == inventory
			and mod.shop_sync.native_shop().player_info.money == wallet
		),
		"cue animation: browsing preserves confirmed equipment, ownership and money"
	)
	check.call(_node_ids(view) == retained_nodes, "cue animation: all presentation nodes retained")
	view.settle_rack()
	view._page = int(preview[0])
	view._selected_model = str(preview[1])
	view._selected_finish = str(preview[2])
	view.settle_rack()
	view._seller._stop_speech()
	print("CUE_ANIMATION_CAPTURE ", directory, " ", frames.size(), " real frames")


func _cue_animation_action(view, action: String) -> void:
	match action:
		"greet":
			view._seller.say("A little edge. All you.")
		"next":
			view._next_page.pressed.emit()
		"previous":
			view._previous_page.pressed.emit()
		"emerald", "rose":
			view._swatches[action].pressed.emit()
		"nudge":
			view._seller._hit.pressed.emit()


func _check_pages(view, capture: Callable, check: Callable) -> void:
	var identities: Dictionary = {}
	for id in view._cards:
		identities[id] = [
			view._cards[id].button.get_instance_id(), view._cards[id].preview.get_instance_id()
		]
	var retained_nodes: Array = _node_ids(view)
	var seen: Dictionary = {}
	var page_count = ceili(float(CueModels.ids().size()) / 3.0)
	for page in page_count:
		view._page = page
		view._update_page()
		view.settle_rack()
		view._link_focus()
		var visible = 0
		var visible_ids: Array = []
		for id in view._cards:
			if view._cards[id].button.visible:
				visible += 1
				visible_ids.append(id)
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
		for id in visible_ids:
			var portrait = view._cards[id].preview
			check.call(
				portrait.size.y > portrait.size.x and portrait.size.x > 0.0,
				"cue shop: " + id + " uses a positive portrait art area"
			)
			check.call(
				portrait.texture != null and portrait.texture == CueVisuals.texture(str(id)),
				"cue shop: " + id + " portrait reuses its matching cached cue art"
			)
		check.call(
			view._description.get_line_count() <= 6,
			"cue shop: full effect description fits the six-line portrait-shop placard"
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
			(
				[
					view._cards[id].button.get_instance_id(),
					view._cards[id].preview.get_instance_id()
				]
				== identities[id]
			),
			"cue shop: paging retains " + id + " card and portrait identity"
		)
	check.call(
		_node_ids(view) == retained_nodes, "cue shop: all catalog pages reuse the retained scene"
	)
	view._page = 0
	view._update_page()
	view.settle_rack()
	view._link_focus()


func _check_rack_motion(view, check: Callable) -> void:
	# PERF-027/034: rapid local browsing replaces motion instead of queuing work.
	# No frames or timer delays are needed: each retarget must cancel immediately.
	view.settle_rack()
	var retained_nodes: Array = _node_ids(view)
	var initial_page: int = view._page
	var initial_model: String = view._selected_model
	var confirmed: Dictionary = view.confirmed_equipment()
	var tweens: Array[Tween] = []
	var page_count = ceili(float(CueModels.ids().size()) / 3.0)
	var expected_page = initial_page
	for direction in [1, 1, -1, 1, -1, -1, 1, 1]:
		var previous: Tween = view._rack_tween
		expected_page = posmod(expected_page + direction, page_count)
		view._change_page(direction)
		var current: Tween = view._rack_tween
		if current != null:
			tweens.append(current)
		var running = 0
		for tween in tweens:
			if _tween_running(tween):
				running += 1
		check.call(
			view._page == expected_page and view._rack_transitioning,
			"cue shop: rapid rack input immediately retargets the requested page"
		)
		check.call(
			running == 1 and (previous == null or not _tween_running(previous)),
			"cue shop: rapid rack retarget retains only one running rack tween"
		)
		check.call(view._action.disabled, "cue shop: purchase is disabled while the rack moves")
		var disabled_cards = true
		for card in view._cards.values():
			disabled_cards = disabled_cards and card.button.disabled
		check.call(disabled_cards, "cue shop: cue cards cannot activate during a rack transition")
		check.call(
			not view._previous_page.disabled and not view._next_page.disabled,
			"cue shop: rack arrows stay responsive while retargeting"
		)
		check.call(
			_node_ids(view) == retained_nodes,
			"cue shop: rack retargeting does not construct or discard nodes"
		)
		check.call(
			view.confirmed_equipment() == confirmed,
			"cue shop: animated rack previews leave the equipped display unchanged"
		)
	view.settle_rack()
	check.call(
		not view._rack_transitioning, "cue shop: settling completes the current rack transition"
	)
	var cards_unlocked = true
	for card in view._cards.values():
		if card.button.visible:
			cards_unlocked = cards_unlocked and not card.button.disabled
	check.call(cards_unlocked, "cue shop: settling restores interaction for the visible cue cards")
	for tween in tweens:
		check.call(not _tween_running(tween), "cue shop: settling leaves no rack animation backlog")
	view._page = initial_page
	view._selected_model = initial_model
	view._update_page()
	view.settle_rack()
	view._link_focus()
	view._refresh()


func _check_resize_layout(mod: Node, view, check: Callable) -> void:
	# Exercise the production fit boundary without resizing the harness window.
	# The former fixed case extends past a 16:10 viewport's right edge.
	var native = mod.shop_sync.native_shop()
	var camera = mod.get_node("/root/Global").camera
	var original_size: Vector2 = view.get_viewport_rect().size
	var retained_nodes: Array = _node_ids(view)
	var confirmed: Dictionary = view.confirmed_equipment()
	var inventory_transform: Transform2D = native.inventory.transform
	var focused = view.get_viewport().gui_get_focus_owner()
	var case_art = view._equipped_case.get_node_or_null("CueCaseArt") as TextureRect
	check.call(
		case_art != null and case_art.texture != null,
		"cue shop: resize checks the actual equipped-case texture control"
	)
	var background = native.inventory.get_node_or_null("BuildBack")
	var inventory_rect = Rect2()
	if check.call(background is Sprite2D, "cue shop: resize checks native inventory artwork"):
		inventory_rect = (
			view.get_global_transform().affine_inverse()
			* background.get_global_transform()
			* background.get_rect()
		)
	for viewport_size in [
		Vector2(1280, 720),
		Vector2(1280, 800),
		Vector2(960, 720),
		Vector2(900, 1000),
		Vector2(720, 1280),
		Vector2(1280, 720)
	]:
		view.fit_to_viewport(viewport_size)
		var target: Vector2 = camera.TABLE_SIZE
		if viewport_size.x / viewport_size.y < camera.PORTRAIT_ASPECT_THRESHOLD:
			target.y += 2.0 * camera.PORTRAIT_VERTICAL_UI
		else:
			target.x += 2.0 * camera.LANDSCAPE_SIDE_UI
		var zoom = minf(viewport_size.x / target.x, viewport_size.y / target.y)
		var extent = viewport_size / zoom
		var visible_rect = Rect2(native.camera_target.position - extent * 0.5, extent)
		for control in [
			view._title.get_parent(),
			view._rack.get_parent(),
			view._equipped_case,
			view._equipped_label,
			view._action,
			view._back,
			view._seller._dialog
		]:
			check.call(
				visible_rect.grow(0.5).encloses(_cue_control_rect(view, control)),
				"cue shop: %s keeps %s within the native viewport" % [viewport_size, control.name]
			)
		check.call(
			not _cue_control_rect(view, view._equipped_case).intersects(inventory_rect),
			"cue shop: %s keeps the case clear of native inventory" % viewport_size
		)
		if case_art != null:
			# A small parent does not bound an oversized TextureRect descendant.
			# Setting size before IGNORE_SIZE previously left the PNG at its native
			# 522x1404 minimum, while all parent-only layout checks still passed.
			var artwork_rect = _cue_control_rect(view, case_art)
			check.call(
				_cue_control_rect(view, view._equipped_case).grow(0.5).encloses(artwork_rect),
				"cue shop: %s fits actual case artwork inside its case control" % viewport_size
			)
			check.call(
				visible_rect.grow(0.5).encloses(artwork_rect),
				"cue shop: %s keeps actual case artwork inside the viewport" % viewport_size
			)
			check.call(
				not artwork_rect.intersects(inventory_rect),
				"cue shop: %s keeps actual case artwork clear of native inventory" % viewport_size
			)
			check.call(
				artwork_rect.grow(0.5).encloses(_cue_control_rect(view, view._equipped_preview)),
				(
					"cue shop: %s keeps the confirmed cue within the fitted case artwork"
					% viewport_size
				)
			)
		check.call(
			is_equal_approx(view._seller.position.y + view._seller.scale.y * 409.0, 414.0),
			"cue shop: resize keeps Rook at the countertop"
		)
		check.call(
			(
				_node_ids(view) == retained_nodes
				and view.confirmed_equipment() == confirmed
				and native.inventory.transform == inventory_transform
				and view.get_viewport().gui_get_focus_owner() == focused
			),
			"cue shop: resizing preserves retained nodes, equipment, inventory and focus"
		)
	check.call(
		(
			view._root.scale == Vector2.ONE
			and view._root.position == Vector2.ZERO
			and view._equipped_case.scale == Vector2.ONE
		),
		"cue shop: returning to widescreen restores the full-size presentation"
	)
	view.fit_to_viewport(original_size)


func _cue_control_rect(view, control: Control) -> Rect2:
	var relative: Transform2D = (
		view.get_global_transform().affine_inverse() * control.get_global_transform()
	)
	return relative * Rect2(Vector2.ZERO, control.size)


func _check_confirmed(view, model: String, finish: String, label: String, check: Callable) -> void:
	# Read the case's actual displayed art, tint and text, not inventory/_player.
	# Otherwise a preview accidentally replacing the case would go undetected.
	var displayed: Dictionary = view.confirmed_equipment()
	var expected_texture: Texture2D = CueVisuals.texture(model)
	var expected_finish: Dictionary = CueCatalog.style(finish)
	var caption = str(displayed.get("label", "")).to_lower()
	check.call(
		displayed.get("model", "") == model and displayed.get("finish", "") == finish,
		"cue shop: " + label + " identifies the confirmed model and finish"
	)
	check.call(
		(
			expected_texture != null
			and displayed.get("texture") == expected_texture
			and displayed.get("tint") == expected_finish.modulate
		),
		"cue shop: " + label + " renders the confirmed cached art and tint"
	)
	check.call(
		(
			str(CueModels.entry(model).label).to_lower() in caption
			and str(expected_finish.label).to_lower() in caption
		),
		"cue shop: " + label + " names the confirmed cue and finish"
	)


func _check_inactive(view, leaving_tween: Tween, check: Callable) -> void:
	check.call(
		(
			not view._rack_transitioning
			and not _tween_running(view._rack_tween)
			and not _tween_running(leaving_tween)
		),
		"cue shop: leaving cancels current rack motion without a queued transition"
	)
	check.call(
		not view.is_processing() and not view._seller.is_processing(),
		"cue shop: rack and seller do no process work away from the counter"
	)
	check.call(
		not _tween_running(view._seller._speech_tween) and not view._seller._dialog.visible,
		"cue shop: leaving stops seller speech and dismisses the dialogue"
	)


func _tween_running(tween: Tween) -> bool:
	return tween != null and tween.is_valid() and tween.is_running()


func _node_ids(root: Node) -> Array:
	var result: Array = [root.get_instance_id()]
	for child in root.get_children():
		result.append_array(_node_ids(child))
	return result


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
	var confirmed: Dictionary = mod.shop_sync._cue_view.confirmed_equipment()
	check.call(not mod.shop_sync.handle_request(command, actor), "cue shop: rejects " + label)
	check.call(
		(
			mod.cue_inventory.snapshot() == before
			and mod.shop_sync.native_shop().player_info.money == money
		),
		"cue shop: " + label + " preserves racks and money"
	)
	check.call(
		mod.shop_sync._cue_view.confirmed_equipment() == confirmed,
		"cue shop: " + label + " preserves the displayed equipped cue"
	)


func _save(mod: Node) -> Dictionary:
	var saved = {
		"transport": mod.transport,
		"cues": mod.cue_inventory.snapshot(),
		"money": mod.shop_sync.native_shop().player_info.money,
		"section": mod.shop_sync.current_section(),
		"finish": CuePrefs.cue_id(),
		"run_config": mod.run_config.duplicate(true),
		"tutorial_enabled": mod.get_node("/root/TutorialManager").ENABLED,
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
	mod.run_config = saved.run_config
	mod.get_node("/root/TutorialManager").ENABLED = saved.tutorial_enabled
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

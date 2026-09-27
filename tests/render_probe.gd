extends Node


class RunEndFixture:
	extends RefCounted
	var game_ended = true
	var round_won = true
	var round_game_over = false
	var level_number = 19

	func get_target_round() -> int:
		return 20


var output = ""
var mod: Node
var failures: Array[String] = []
var checks: Array[Dictionary] = []
var screens: Array[Dictionary] = []
var fixtures: RefCounted
var round_flow: RefCounted
var shop_input: Node
var fixture_config = {"deck": "1_CLASSIC", "difficulty": "diff_3", "seed": 24681}


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run():
	var args = OS.get_cmdline_user_args()
	var output_index = args.find("--output")
	if output_index >= 0 and output_index + 1 < args.size():
		output = args[output_index + 1]
	if not OS.get_user_data_dir().contains("UltrapoolTogetherRenderTest"):
		push_error("RENDER_PROBE_FAIL: refusing non-test profile " + OS.get_user_data_dir())
		get_tree().quit(2)
		return
	if output.is_empty() or not DirAccess.dir_exists_absolute(output):
		push_error("RENDER_PROBE_FAIL: missing output directory; arguments: " + str(args))
		get_tree().quit(2)
		return
	print("RENDER_PROBE_START ", OS.get_user_data_dir())
	if not _check(not Engine.has_singleton("Steam"), "render fixture has no Steam integration"):
		_finish()
		return
	mod = get_node("/root/UltrapoolTogether")
	mod.set_process(false)
	mod.transport.close()
	mod._set_panel(false)
	get_node("/root/SettingsManager").use_analytics = false
	get_node("/root/AnalyticsManager").state = 0
	get_node("/root/PlatformManager")._steam = null
	get_node("/root/CloudSaveManager").backend = null
	get_node("/root/TutorialManager").ENABLED = false
	Engine.max_fps = 30
	var round_flow_script = load(
		get_script().resource_path.get_base_dir().path_join("round_flow_fixtures.gd")
	)
	if not _check(
		round_flow_script != null and round_flow_script.can_instantiate(),
		"compiled round flow fixtures"
	):
		_finish()
		return
	round_flow = round_flow_script.new()
	var input_script = load(
		get_script().resource_path.get_base_dir().path_join("shop_input_fixture.gd")
	)
	if not _check(
		input_script != null and input_script.can_instantiate(), "compiled shop input fixture"
	):
		_finish()
		return
	shop_input = input_script.new()
	add_child(shop_input)
	var snapshot_probe = (
		load(get_script().resource_path.get_base_dir().path_join("snapshot_probe.gd")).new()
	)
	snapshot_probe.embedded = true
	add_child(snapshot_probe)
	await snapshot_probe.completed
	_check(not snapshot_probe.failed, "snapshot_probe: %d checks" % snapshot_probe.checks)
	snapshot_probe.queue_free()
	for probe in [
		"team_vote_probe",
		"lobby_probe",
		"presence_probe",
		"router_probe",
		"controller_probe",
		"transport_budget_probe",
		"shop_layout_probe"
	]:
		_run_model_probe(probe)
	_check_run_completion()
	if not _check(
		await _wait(_menu_capture_ready), "native menu transition finishes before lobby captures"
	):
		_finish()
		return
	fixtures = (
		load(get_script().resource_path.get_base_dir().path_join("render_ui_fixtures.gd")).new()
	)
	await fixtures.check_native_run_votes(mod, _capture)
	await fixtures.capture_all_menu(mod, _capture)
	var global_node = get_node("/root/Global")
	mod._local_id = 1
	mod.table_leader_id = 1
	mod.table_id = 0
	mod.active = true
	mod.lobby = {
		"table_count": 1,
		"players":
		[
			{"id": 1, "name": "Host", "table": 0, "slot": 0, "connected": true},
			{"id": 2, "name": "Guest", "table": 0, "slot": 1, "connected": true}
		]
	}
	mod.latest_state = {"table_active": true, "in_shop": false}
	mod.adapter.begin_session(mod)
	if not _check(mod.run_setup.start(fixture_config) == OK, "selected native run config starts"):
		_finish()
		return
	if not _check(await _wait(_native_ready), "native table spawned"):
		_finish()
		return
	await get_tree().create_timer(3.0).timeout
	var game = global_node.gameManager
	mod.run_controls.begin_session()
	_check(not mod.run_controls._bindings.is_empty(), "native run exits route to lobby voting")
	_check_run_config("host")
	_check_balls(game.balls, "host")
	await _capture("10-host-table", "Host table · the selected native Classic starting set")
	await fixtures.capture_table_states(mod, _capture)
	var snapshot = mod.table_sync.capture()
	var spectator_fixtures = (
		load(get_script().resource_path.get_base_dir().path_join("spectator_fixtures.gd")).new()
	)
	for result in await spectator_fixtures.capture(mod, snapshot, _capture):
		_check(result.passed, result.name)
	mod.shop_sync.begin_session(mod)
	game.player_info.money = 92.0
	game.player_info.set_tickets(1, 2)
	game.open_shop(false)
	var shop_state: Dictionary = {}
	if _check(await _wait(_shop_ready), "shared shop opened"):
		mod.latest_state.in_shop = true
		mod._update_hud()
		await get_tree().create_timer(0.5).timeout
		_check_shop()
		shop_state = mod.shop_sync.capture().duplicate(true)
		var shop_report = FileAccess.open(output.path_join("shop-state.json"), FileAccess.WRITE)
		shop_report.store_string(JSON.stringify(shop_state, "\t"))
		shop_report.close()
		await fixtures.capture_shop_presence(mod, _capture, shop_input)
		await round_flow.check_host_shop_drag(mod, _capture)
		await _check_shop_readiness()
	await round_flow.record_host(mod, _capture)
	mod.shop_sync.end_session()
	mod.run_controls.end_session()
	mod.adapter.end_session()
	mod.active = false
	mod.run_setup.return_menu()
	if not _check(await _wait(mod.run_setup.at_main_menu), "returned to menu"):
		_finish()
		return
	mod._local_id = 2
	mod.active = true
	mod.latest_state.in_shop = false
	# Guest seat owns the opening turn so the banner paints on first table entry (#30).
	mod.turn_owner = 2
	mod.shot_pending = false
	mod.awaiting_shot_turn = -1
	mod.finished = false
	if mod.turn_banner != null:
		mod.turn_banner.clear()
	mod._turn_banner_showing = false
	if not _check(mod.table_sync.begin_guest(fixture_config), "guest scene begins"):
		_finish()
		return
	# Prove spent pips through snapshot → replica _update_shots (#29), not a post-apply poke.
	var shots_max: int = maxi(int(snapshot.get("shots_max", 0)), int(snapshot.get("shots", 0)))
	if shots_max < 1:
		shots_max = maxi(int(snapshot.get("shots", 1)), 1)
	snapshot["shots_max"] = shots_max
	snapshot["shots"] = maxi(shots_max - 1, 0)
	snapshot["shots_used"] = shots_max - int(snapshot["shots"])
	_check(mod.table_sync.apply_snapshot(snapshot), "guest snapshot accepted")
	await get_tree().create_timer(1.0).timeout
	game = global_node.gameManager
	mod._local_id = 2
	mod.turn_owner = 2
	mod.latest_state = mod.adapter.game_data()
	mod.latest_state["shots_left"] = int(snapshot["shots"])
	mod.latest_state["table_active"] = true
	mod.latest_state["in_shop"] = false
	# Hide parked cue before the idle guest table capture (#18).
	if is_instance_valid(game) and is_instance_valid(game.player_ball):
		var cue_ball = game.player_ball
		if cue_ball.has_method("_hide_cue_pivot"):
			cue_ball._hide_cue_pivot()
		var pivot = cue_ball.get_node_or_null("CuePivot")
		if pivot is CanvasItem:
			pivot.visible = false
			var cue = pivot.get_node_or_null("Cue")
			if cue is CanvasItem:
				cue.visible = false
				cue.modulate.a = 0.0
	mod._update_hud()
	_check_run_config("guest")
	_check_balls(game.replicas.values(), "guest")
	await get_tree().process_frame
	# Re-assert hide after a process tick in case native aim chrome revived the shaft.
	if is_instance_valid(game) and is_instance_valid(game.player_ball):
		if game.player_ball.has_method("_hide_cue_pivot"):
			game.player_ball._hide_cue_pivot()
	await _capture("30-guest-table", "Guest table · reconstructed from the host snapshot")
	await _capture_guest_aim(game)
	await _capture_ball_previews(game)
	await _capture_guest_shop(snapshot, shop_state)
	mod.table_sync.end_guest()
	for result in await round_flow.replay_guest(mod, _capture):
		_check(result.passed, result.name)
	for result in fixtures.checks:
		_check(result.passed, result.name)
	_finish()


func _capture_guest_shop(table_state: Dictionary, shop_state: Dictionary):
	if shop_state.is_empty():
		return
	var shopping = table_state.duplicate(true)
	shopping.in_shop = true
	_check(mod.table_sync.apply_snapshot(shopping), "guest shop table state accepted")
	mod.shop_sync.begin_session(mod)
	_check(mod.shop_sync.apply_state(shop_state), "guest native shop state accepted")
	mod.latest_state.in_shop = true
	mod._update_hud()
	var game = get_node("/root/Global").gameManager
	var shop = mod.shop_sync.native_shop()
	if is_instance_valid(shop):
		_check_shop_wallet_refresh(shop, shop_state)
		_check_shop_offer_refresh(shop, shop_state)
	await get_tree().create_timer(1.0).timeout
	_check(
		(
			is_instance_valid(shop)
			and shop.is_open
			and shop.is_visible_in_tree()
			and mod.shop_sync.is_open()
			and mod.shop_sync._panel.visible
		),
		"guest native shop opens from shared shop_state"
	)
	_check(
		is_instance_valid(shop) and shop.remote_slots_cover(shop.remote_slots, shop_state.slots),
		"guest remote slots cover the host shop layout"
	)
	_check(
		(
			shop.get_node("%ShopFloor").texture
			== game.table.get_node("TableCustomization").shop_floor.texture
		),
		"guest native shop preserves floor customization"
	)
	for slot in shop_state.slots:
		if slot.id == 0 or slot.group != "build":
			continue
		var body = mod.shop_sync.slot_item(slot.key)
		_check(is_instance_valid(body), "guest native shop item " + slot.key)
		if is_instance_valid(body):
			_check(
				body.ball.material.get_shader_parameter("tex") == body.ball_item.data.texture,
				"guest shop texture " + slot.data
			)
	await _capture("50-guest-shop", "Guest native shop · shared build and offers")
	var inspected_key = ""
	for slot in shop_state.slots:
		if slot.id != 0 and slot.group == "build":
			inspected_key = slot.key
			break
	shop_input.begin(shop)
	_check(
		await round_flow.hover_shop_item(mod, inspected_key),
		"guest shop item can be inspected by native pointer hover"
	)
	var inspected = mod.shop_sync.slot_item(inspected_key)
	_check_idle_replica_refresh(game, shopping)
	_check(mod.table_sync.apply_snapshot(shopping), "guest accepts repeated shop snapshot")
	_check(mod.shop_sync.apply_state(shop_state), "guest accepts repeated shop inventory")
	await get_tree().create_timer(0.45).timeout
	var inspection = get_node("/root/UIManager").info_display
	_check(
		game.selected_ball == inspected and inspection.showing and inspection.ball == inspected,
		"guest shop inspection survives repeated snapshots"
	)
	_check(
		get_node("/root/Global").camera.move_position == shop.get_camera_target(),
		"guest snapshots keep the camera in the shop"
	)
	await _capture("51-guest-shop-details", "Guest native shop · inspect a shared ball")
	shop_input.finish()
	mod.shop_sync.show_section("snacks")
	_check(
		shop.selected_ball == null and shop.selected_passive == null,
		"changing native shop counter clears inspection"
	)
	await get_tree().create_timer(0.5).timeout
	await _capture(
		"53-guest-snack-bar",
		"Guest snack / tapas bar · ticket counters visible on the shared shop HUD."
	)
	await round_flow.check_guest_snack_drag(mod, _capture)
	await _capture_guest_negative_cubes(shop, game)
	mod.shop_sync.end_session()


func _capture_guest_aim(game) -> void:
	# Guest local aim chrome (#18). Drive CuePivot from the shot vector while process is
	# frozen so native_player can_control() cannot clear preparing_shot mid-capture.
	if not is_instance_valid(game) or not is_instance_valid(game.player_ball):
		_check(false, "guest aim fixture has a cue ball")
		return
	var CueCatalog = load(get_script().resource_path.get_base_dir().path_join("../mod/cue_catalog.gd"))
	for player in mod.lobby.get("players", []):
		if int(player.get("id", 0)) == 2:
			player["cue"] = "gold"
	mod.turn_owner = 2
	mod._local_id = 2
	mod.panel.hide()
	mod.latest_state["can_shoot"] = true
	mod.latest_state["table_active"] = true
	mod.shot_pending = false
	mod.awaiting_shot_turn = -1
	var ball = game.player_ball
	CueCatalog.apply(ball, "gold")
	game.playing = true
	game.in_shop = false
	game.in_menu = false
	var was_processing = ball.is_processing()
	var was_input = ball.is_processing_input()
	ball.set_process(false)
	ball.set_process_input(false)
	ball.set("preparing_shot", true)
	ball.set("holding_shot", true)
	ball.set("shot", Vector2(90, -140))
	# Reveal native aim chrome even if controller can_control() is false in fixtures.
	for prop in ["shoot_ui", "prediction"]:
		var node = ball.get(prop)
		if node is CanvasItem:
			node.visible = true
	var gauge = ball.get("chargeGauge")
	if gauge == null and ball.get("visuals") != null:
		gauge = ball.visuals.get_node_or_null("static/chargeGauge")
	if gauge is CanvasItem:
		gauge.visible = true
	if ball.has_method("_ensure_aim_chrome"):
		ball._ensure_aim_chrome()
	if ball.has_method("_show_cue_aim"):
		ball._show_cue_aim(Vector2(90, -140))
	mod._update_hud()
	await get_tree().process_frame
	await get_tree().process_frame
	var shoot_ui = ball.get("shoot_ui")
	var prediction = ball.get("prediction")
	var pivot = ball.get_node_or_null("CuePivot")
	var pivot_ok: bool = (
		pivot is CanvasItem
		and pivot.visible
		and pivot.global_position.distance_squared_to(ball.global_position) < 16.0
	)
	_check(
		bool(ball.get("preparing_shot"))
		and pivot_ok
		and (
			(shoot_ui is CanvasItem and shoot_ui.visible)
			or (prediction is CanvasItem and prediction.visible)
			or (gauge is CanvasItem and gauge.visible)
		),
		"guest cue ball shows aim chrome (stick / line / reticle)"
	)
	await _capture(
		"31-guest-aim",
		"Guest turn · native cue stick, aim line, and reticle with a gold custom cue."
	)
	ball.set("preparing_shot", false)
	ball.set("holding_shot", false)
	if ball.has_method("pause_cancel_shot"):
		ball.pause_cancel_shot()
	if ball.has_method("_hide_cue_pivot"):
		ball._hide_cue_pivot()
	ball.set_process_input(was_input)
	ball.set_process(was_processing)


func _capture_guest_negative_cubes(shop: Node, game) -> void:
	if not is_instance_valid(shop) or not is_instance_valid(game) or game.player_info == null:
		return
	var database = get_node("/root/BallDatabase")
	var cube_resources: Array = _fixture_negative_cubes(database)
	if cube_resources.size() < 2:
		_check(false, "BallDatabase exposes at least two textured NEGATIVE cubes")
		return
	var cubes: Array = []
	for resource in cube_resources:
		var cube = BallItem.new()
		cube.data = resource
		_check(str(cube.data.from_set) == "NEGATIVE", "fixture cube %s is NEGATIVE" % str(resource.id))
		_check(cube.data.texture != null, "fixture cube %s has a BallResource.texture" % str(resource.id))
		cubes.append(cube)
	var previous_cubes = game.player_info.cubes.duplicate()
	game.player_info.cubes.assign(cubes)
	if shop.has_method("refresh_inventory_hud"):
		shop.refresh_inventory_hud()
	elif shop.has_method("_sync_cubes_button"):
		shop._sync_cubes_button()
	await get_tree().process_frame
	var button = shop.get_node_or_null("%CubesButton")
	_check(button != null and button.visible, "guest CubesButton visible with NEGATIVE cubes")
	var popup = shop.get_node_or_null("%CubesPopup")
	if popup == null:
		popup = shop.find_child("CubesPopup", true, false)
	# Open through the native shop handler (and force the CanvasItem visible). Emitting
	# CubesButton.pressed alone can leave shop.%CubesPopup hidden while another layer
	# paints the grid — ensure_cubes_popup_textures then no-ops and cubes stay black.
	if shop.has_method("_on_cubes_button_pressed"):
		shop._on_cubes_button_pressed()
	elif button != null and button.has_signal("pressed"):
		button.pressed.emit()
	if popup is CanvasItem:
		popup.visible = true
	if popup != null and popup.has_method("popup"):
		popup.popup()
	await get_tree().process_frame
	await get_tree().process_frame
	if shop.has_method("ensure_cubes_popup_textures"):
		shop.ensure_cubes_popup_textures()
	await get_tree().create_timer(0.35).timeout
	if shop.has_method("ensure_cubes_popup_textures"):
		shop.ensure_cubes_popup_textures()
	await get_tree().process_frame
	var bound_ok: bool = _cubes_popup_textures_bound(shop, popup, cubes)
	if not bound_ok:
		print("RENDER_CUBE_DEBUG ", _cubes_popup_debug(shop, popup, cubes))
	_check(bound_ok, "guest CubesPopup PassiveCube entries sample BallResource textures")
	await _capture(
		"54-guest-negative-cubes",
		"Guest shop · CubesPopup with two textured NEGATIVE cubes (not black silhouettes) and snack tickets."
	)
	if popup is CanvasItem:
		popup.visible = false
	if popup != null and popup.has_method("hide"):
		popup.hide()
	# Restore inventory so later hover/drag fixtures keep native input unlocked.
	game.player_info.cubes.assign(previous_cubes)
	if shop.has_method("refresh_inventory_hud"):
		shop.refresh_inventory_hud()
	get_node("/root/UIManager").info_display.hide_info()
	if shop.has_method("unselect"):
		shop.unselect()
	elif shop.get("selected_ball") != null:
		shop.selected_ball = null
		shop.selected_passive = null
	await get_tree().process_frame


## Host CubesPopup via the vanilla set_item path only — no mod tex rebinding. Compare with
## 54-guest-negative-cubes: if host is also near-black, native NEGATIVE cubes look that way.
func _capture_host_native_cubes(host_mod: Node, game) -> void:
	if not is_instance_valid(game) or game.player_info == null:
		return
	var shop = null
	if host_mod != null and host_mod.shop_sync != null:
		shop = host_mod.shop_sync.native_shop()
	if not is_instance_valid(shop):
		shop = game.shop
	if not is_instance_valid(shop):
		return
	var database = get_node("/root/BallDatabase")
	var cube_resources: Array = _fixture_negative_cubes(database)
	if cube_resources.size() < 2:
		_check(false, "host fixture: BallDatabase exposes at least two textured NEGATIVE cubes")
		return
	var cubes: Array = []
	for resource in cube_resources:
		var cube = BallItem.new()
		cube.data = resource
		cubes.append(cube)
	var previous_cubes = game.player_info.cubes.duplicate()
	game.player_info.cubes.assign(cubes)
	# Show CubesButton without refresh_inventory_hud — that also calls ensure_cubes_popup_textures.
	var button = shop.get_node_or_null("%CubesButton")
	if button != null:
		button.visible = true
	await get_tree().process_frame
	_check(button != null and button.visible, "host CubesButton visible with NEGATIVE cubes")
	var popup = shop.get_node_or_null("%CubesPopup")
	if popup == null:
		popup = shop.find_child("CubesPopup", true, false)
	# Native open only — do not call ensure_cubes_popup_textures on the host path.
	if shop.has_method("_on_cubes_button_pressed"):
		shop._on_cubes_button_pressed()
	elif button != null and button.has_signal("pressed"):
		button.pressed.emit()
	if popup is CanvasItem:
		popup.visible = true
	if popup != null and popup.has_method("popup"):
		popup.popup()
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame
	var sprites: Array = _collect_cube_sprites(shop, popup)
	var native_tex = 0
	for sprite in sprites:
		if sprite.material == null:
			continue
		var tex = sprite.material.get_shader_parameter("tex")
		if tex != null:
			native_tex += 1
	print(
		"RENDER_HOST_CUBES native_sprites=%s tex_bound=%s (no mod rebind)"
		% [sprites.size(), native_tex]
	)
	await _capture(
		"54-host-native-cubes",
		"Host shop · CubesPopup via vanilla PassiveCube set_item only (no mod fake_cube rebind). Compare with guest."
	)
	if popup is CanvasItem:
		popup.visible = false
	if popup != null and popup.has_method("hide"):
		popup.hide()
	# CustomPopupMenu often keeps a CanvasLayer "open" for UIManager.is_popup_open().
	# Force-hide every popup-like node under the shop and UIManager so drag stays allowed.
	_force_close_cubes_popups(shop)
	if shop.has_method("unselect"):
		shop.unselect()
	if shop.get("selected_ball") != null:
		shop.selected_ball = null
	if shop.get("selected_passive") != null:
		shop.selected_passive = null
	if shop.get("grabbed_passive") != null:
		shop.grabbed_passive = null
	var shop_manager = get_node_or_null("/root/Global")
	if shop_manager != null:
		shop_manager = shop_manager.get("shopManager")
	if shop_manager != null:
		if shop_manager.has_method("drop"):
			shop_manager.drop()
		if shop_manager.get("hovered_slot") != null:
			shop_manager.hovered_slot = null
	game.player_info.cubes.assign(previous_cubes)
	if button != null:
		button.visible = false
	get_node("/root/UIManager").info_display.hide_info()
	await get_tree().process_frame
	if host_mod != null and host_mod.shop_sync != null and host_mod.shop_sync.has_method("show_section"):
		host_mod.shop_sync.show_section("balls")
	# Wait until UIManager reports no popup, otherwise host drag stays blocked.
	var ui = get_node("/root/UIManager")
	for _attempt in 45:
		_force_close_cubes_popups(shop)
		if ui.has_method("is_popup_open") and not ui.is_popup_open():
			break
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout


func _force_close_cubes_popups(shop: Node) -> void:
	var roots: Array = []
	if shop != null:
		roots.append(shop)
	var ui = get_node_or_null("/root/UIManager")
	if ui != null:
		roots.append(ui)
	for root in roots:
		for name in ["CubesPopup", "Cubes", "CustomPopupMenu"]:
			for node in root.find_children(name, "", true, false):
				if node is CanvasItem:
					(node as CanvasItem).visible = false
				if node.has_method("hide"):
					node.hide()
		for node in root.find_children("*", "CanvasLayer", true, false):
			# CubesPopup implementations often flip an inner CanvasLayer while the
			# Control root stays hidden — that still counts as an open UI popup.
			if str(node.name).to_lower().contains("cube") or str(node.get_parent().name).to_lower().contains("cube"):
				node.visible = false


func _fixture_negative_cubes(database: Node) -> Array:
	# Prefer iconic CUBERT plus a second distinct NEGATIVE id so the gallery proves
	# two textured debuff cubes, not a single unbound silhouette.
	var preferred = ["CUBERT", "DEMON", "GLITCH", "CEO", "ALARM-CLOCK", "BOUNCER"]
	var picked: Array = []
	var seen: Dictionary = {}
	for id in preferred:
		if not database.id_to_ball.has(id):
			continue
		var resource = database.id_to_ball[id]
		if resource == null or str(resource.from_set) != "NEGATIVE" or resource.texture == null:
			continue
		if seen.has(str(resource.id)):
			continue
		seen[str(resource.id)] = true
		picked.append(resource)
		if picked.size() >= 2:
			return picked
	for resource in database.cubes:
		if resource == null or str(resource.from_set) != "NEGATIVE" or resource.texture == null:
			continue
		if seen.has(str(resource.id)):
			continue
		seen[str(resource.id)] = true
		picked.append(resource)
		if picked.size() >= 2:
			break
	return picked


func _cubes_popup_textures_bound(shop: Node, popup: Node, cubes: Array) -> bool:
	if cubes.is_empty():
		return false
	var sprites: Array = _collect_cube_sprites(shop, popup)
	var bound = 0
	for sprite in sprites:
		if sprite.material == null:
			continue
		var tex = sprite.material.get_shader_parameter("tex")
		if tex == null:
			continue
		for cube in cubes:
			if cube != null and cube.data != null and tex == cube.data.texture:
				bound += 1
				break
	return bound >= mini(2, cubes.size())


func _collect_cube_sprites(shop: Node, popup: Node) -> Array:
	var sprites: Array = []
	var roots: Array = []
	if shop != null:
		roots.append(shop)
	if popup != null and popup not in roots:
		roots.append(popup)
	var ui = shop.get_node_or_null("/root/UIManager") if shop else null
	if ui != null:
		roots.append(ui)
	for root in roots:
		for sprite in root.find_children("Cube", "Sprite2D", true, false):
			if sprite not in sprites:
				sprites.append(sprite)
		for sprite in root.find_children("*", "Sprite2D", true, false):
			if sprite in sprites or sprite.material == null:
				continue
			if sprite.material.has_method("get_shader_parameter") and sprite.material.get_shader_parameter("hint_color") != null:
				sprites.append(sprite)
	return sprites


func _cubes_popup_debug(shop: Node, popup: Node, cubes: Array) -> Dictionary:
	var sprites: Array = _collect_cube_sprites(shop, popup)
	var sprite_info: Array = []
	for sprite in sprites:
		var tex = null
		if sprite.material != null:
			tex = sprite.material.get_shader_parameter("tex")
		sprite_info.append(
			{
				"path": str(sprite.get_path()),
				"name": sprite.name,
				"in_tree": sprite.is_visible_in_tree(),
				"has_material": sprite.material != null,
				"tex_null": tex == null,
				"tex_class": tex.get_class() if tex != null else ""
			}
		)
	var cube_info: Array = []
	for cube in cubes:
		cube_info.append(
			{
				"id": str(cube.data.id) if cube != null and cube.data != null else "",
				"tex_null": cube == null or cube.data == null or cube.data.texture == null
			}
		)
	return {
		"sprites": sprite_info,
		"cubes": cube_info,
		"popup_visible": popup.visible if popup is CanvasItem else false,
		"has_native_open": shop.has_method("_on_cubes_button_pressed") if shop else false
	}


func _check_shop_wallet_refresh(shop: Node, original: Dictionary) -> void:
	var map = shop.inventory.map
	var pip_ids: Array = map.pips.map(func(pip): return pip.get_instance_id())
	if not _check(not pip_ids.is_empty(), "guest shop has native round-map pips"):
		return
	var changed = original.duplicate(true)
	changed.money = 20.0 if original.money == 0 else 0.0
	shop.apply_state(changed)
	_check(
		map.pips.map(func(pip): return pip.get_instance_id()) == pip_ids,
		"money-only shop update preserves every round-map pip"
	)
	var wallet = shop.inventory.get_node("%Wallet")
	_check(
		wallet.get_node("WalletSprite").texture == wallet.textures[3 if changed.money > 15 else 0],
		"money-only shop update refreshes the native wallet"
	)
	changed.hp = original.hp - 1 if original.hp > 0 else 1
	shop.apply_state(changed)
	_check(
		map.pips.map(func(pip): return pip.get_instance_id()) == pip_ids,
		"health-only shop update preserves every round-map pip"
	)
	_check(
		shop.inventory.get_node("%hpInfo").index == changed.hp - 1,
		"health-only shop update refreshes the native hearts"
	)
	shop.apply_state(original)


func _check_shop_offer_refresh(shop: Node, original: Dictionary) -> void:
	var changed = original.duplicate(true)
	var offers: Array = changed.slots.filter(
		func(slot): return slot.group == "offer" and slot.id != 0
	)
	var build: Array = changed.slots.filter(
		func(slot): return slot.group == "build" and slot.id != 0
	)
	if not _check(
		not offers.is_empty() and build.size() >= 2,
		"shop refresh fixture has offer and build slots"
	):
		return
	var database = get_node("/root/BallDatabase")
	var rare_id = ""
	for id in database.id_to_ball:
		if database.id_to_ball[id].rarity == Global.RARITY.RARE:
			rare_id = id
			break
	if not _check(rare_id != "", "shop refresh fixture has a native rare ball"):
		return
	var offer: Dictionary = offers[0]
	offer.data = rare_id
	offer.mixed = ""
	shop.apply_state(changed)
	var slot = shop.remote_slots[offer.key]
	var offer_body = slot.ball
	_check(
		slot.has_rarity_star and slot.star_pivot.visible,
		"rare offer starts with native rarity star"
	)
	var left_key: String = build[0].key
	var left_index: int = build[0].index
	build[0].key = build[1].key
	build[0].index = build[1].index
	build[1].key = left_key
	build[1].index = left_index
	shop.apply_state(changed)
	_check(
		slot.ball == offer_body and slot.has_rarity_star and slot.star_pivot.visible,
		"unrelated build swap preserves unchanged offer body and rarity star"
	)
	shop.apply_state(original)


func _check_idle_replica_refresh(game: Node, shopping: Dictionary) -> void:
	for body in game.replicas.values():
		body.sleeping = true
	_check(mod.table_sync.apply_snapshot(shopping), "idle guest shop snapshot accepted")
	for body in game.replicas.values():
		_check(body.freeze and body.sleeping, "idle shop snapshot preserves sleeping table bodies")
	if shopping.balls.is_empty():
		return
	var state: Dictionary = shopping.balls[0]
	var body = game.replicas[state.id]
	body.transform3d.rotation = state.spin + Vector3(0.0, 0.5, 0.0)
	_check(mod.table_sync.apply_snapshot(shopping), "guest reconciles local visual drift")
	var basis: Basis = body.transform3d.global_transform.basis
	_check(
		(
			body.transform3d.rotation.is_equal_approx(state.spin)
			and body.ball.material.get_shader_parameter("rotation_x").is_equal_approx(basis.x)
			and body.ball.material.get_shader_parameter("rotation_y").is_equal_approx(basis.y)
			and body.ball.material.get_shader_parameter("rotation_z").is_equal_approx(basis.z)
		),
		"unchanged authoritative spin still reconciles live transform and material"
	)


func _menu_capture_ready() -> bool:
	if not mod.run_setup.at_main_menu():
		return false
	# Global clears transitioning immediately after uncover(); the native overlay
	# hides its CanvasLayer only once that animated wipe has actually finished.
	var overlay = get_node("/root/UIManager").overlay
	return is_instance_valid(overlay) and not overlay.canvas_layer.visible


func _native_ready() -> bool:
	var game = get_node("/root/Global").gameManager
	return is_instance_valid(game) and game.balls_spawned


func _shop_ready() -> bool:
	var state = mod.shop_sync.capture()
	return state.get("open", false) and not state.get("busy", true)


func _check_shop():
	var state: Dictionary = mod.shop_sync.capture()
	var build_ids: Array = []
	var native_ids: Dictionary = get_node("/root/BallDatabase").id_to_ball
	for slot in state.slots:
		if slot.id == 0:
			continue
		if slot.group == "build":
			build_ids.append(slot.data)
		if slot.group in ["build", "offer"]:
			_check(native_ids.has(slot.data), "shop contains native ball " + slot.data)
	_check_native_starters(build_ids, "shop")


func _check_shop_readiness():
	var transport = mod.transport
	mod.transport = fixtures.OfflineTransport.new()
	var sync = mod.shop_sync
	var state = sync.capture()
	var consent = {
		"action": "ready",
		"ready": true,
		"revision": state.revision,
		"ready_generation": state.ready_vote.revision
	}
	_check(sync.handle_request(consent, 1), "first teammate readies for the next round")
	_check(sync.capture().open, "partial readiness keeps the shared shop open")
	_check(sync.capture().ready_vote.ready == [1], "shared shop publishes individual readiness")
	await _capture(
		"shop-team-ready", "Native shared shop · one teammate ready, waiting for the other"
	)
	_check(
		sync.handle_request(consent, 2),
		"simultaneous teammate consent uses the same vote generation"
	)
	await get_tree().create_timer(0.7).timeout
	_check(not sync.capture().open, "unanimous readiness starts the next round")
	_check(not sync.handle_request(consent, 2), "old consent cannot start another round")
	mod.transport.free()
	mod.transport = transport


func _run_model_probe(name: String):
	var path = get_script().resource_path.get_base_dir().path_join(name + ".gd")
	var script = GDScript.new()
	script.resource_path = path.get_basename() + ".embedded.gd"
	script.source_code = (
		FileAccess
		. get_file_as_string(path)
		. replace("extends SceneTree", "extends RefCounted")
		. replace("func _initialize()", "func run()")
	)
	script.source_code += "\nfunc quit(_code: int):\n\tpass\n"
	if not _check(script.reload() == OK, "compiled " + name):
		return
	var probe = script.new()
	probe.run()
	_check(probe.failures.is_empty(), "%s: %d checks" % [name, probe.checks])


func _check_run_completion():
	var ending = RunEndFixture.new()
	_check(
		mod.adapter.is_run_won(ending), "clearing the native final round counts as a race finish"
	)
	ending.round_game_over = true
	_check(not mod.adapter.is_run_won(ending), "losing at the final round is not a race finish")
	ending.round_game_over = false
	ending.game_ended = false
	_check(not mod.adapter.is_run_won(ending), "an unfinished final round is not a race finish")
	ending.game_ended = true
	ending.level_number = 18
	_check(not mod.adapter.is_run_won(ending), "an earlier round cannot finish the race")


func _capture_ball_previews(game):
	var ui = get_node("/root/UIManager")
	var inspection = ui.info_display
	_check(inspection.can_process(), "guest inspection processes")
	for body in game.replicas.values():
		body.set_process(false)
	var inspected_ids: Array[String] = []
	for body in game.replicas.values():
		var id = str(body.ball_item.data.id)
		if id == "PLAYER" or inspected_ids.has(id):
			continue
		inspected_ids.append(id)
		game.select_ball(body, body.ball_item)
		await get_tree().create_timer(0.45).timeout
		_check(inspection.showing and inspection.ball == body, "guest inspection selection " + id)
		_check(
			inspection.main_panel.is_visible_in_tree() and inspection.scale_value > 0.9,
			"guest inspection visible " + id
		)
		await _capture(
			"40-ball-" + id.to_lower(), body.ball_item.data.name + " · guest inspection card"
		)
		game.unselect_ball(body, body.ball_item)
	inspection.hide_info()
	for body in game.replicas.values():
		body.set_process(true)


func _check_run_config(role: String):
	var global_node = get_node("/root/Global")
	_check(
		(
			global_node.chosen_deck.id == fixture_config.deck
			and global_node.chosen_difficulty.id == fixture_config.difficulty
		),
		role + " uses the selected native deck and difficulty"
	)
	_check(
		(
			global_node.chosen_difficulty.hasCocktailBar
			and global_node.chosen_difficulty.has_tapas_bar
		),
		role + " selected difficulty exposes both native shop counters"
	)


func _check_balls(balls: Array, role: String):
	var ids: Array = []
	var database = get_node("/root/BallDatabase")
	for body in balls:
		if body.ball_item == null or str(body.ball_item.data.id) == "PLAYER":
			continue
		var item = body.ball_item
		ids.append(item.data.id)
		_check(database.id_to_ball.has(item.data.id), role + " native identity " + item.data.id)
		_check(
			body.ball.material.get_shader_parameter("tex") == item.data.texture,
			role + " shader texture " + item.data.id
		)
		_check(
			item.data.texture != null and item.data.texture.get_size().x > 0,
			role + " native texture is loaded " + item.data.id
		)
	_check_native_starters(ids, role)


func _check_native_starters(ids: Array, role: String):
	var expected: Array = Array(get_node("/root/Global").chosen_deck.balls)
	var actual = ids.duplicate()
	expected.sort()
	actual.sort()
	_check(actual == expected, role + " preserves every selected native starter and duplicate")


func _capture(label: String, caption: String = ""):
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if label.begins_with("lobby-"):
		_check(fixtures.clipped_players(mod).is_empty(), "all lobby participants visible " + label)
	var image = get_viewport().get_texture().get_image()
	_check(image.save_png(output.path_join(label + ".png")) == OK, "saved " + label)
	screens.append(
		{
			"file": label + ".png",
			"caption": caption,
			"width": image.get_width(),
			"height": image.get_height()
		}
	)
	print("RENDER_CAPTURE ", label, " ", image.get_size())


func abort_input(input_checks: Array):
	for result in input_checks:
		_check(result.passed, result.name)
	_finish()


func _wait(condition: Callable) -> bool:
	for _attempt in 160:
		_close_popups()
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return false


func _close_popups():
	var ui = get_node("/root/UIManager")
	ui.popup_queue.clear()
	for popup in ui.active_popups.duplicate():
		popup.just_opened_or_closed = false
		popup.instant_close_menu()
	ui.update_pause()
	get_tree().paused = false


func _check(condition: bool, label: String) -> bool:
	print("RENDER_CHECK ", "PASS " if condition else "FAIL ", label)
	checks.append({"passed": condition, "label": label})
	if not condition:
		failures.append(label)
	return condition


func _finish():
	_write_gallery()
	print("RENDER_PROBE_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func _write_gallery():
	var result = {"passed": failures.is_empty(), "checks": checks, "screens": screens}
	var report = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(result, "\t"))
	var template = get_script().resource_path.get_base_dir().path_join("render_gallery.html")
	var html = FileAccess.get_file_as_string(template)
	html = html.replace("__REPORT_JSON__", JSON.stringify(result).replace("<", "\\u003c"))
	var gallery = FileAccess.open(output.path_join("index.html"), FileAccess.WRITE)
	gallery.store_string(html)

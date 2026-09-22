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
	if not _check(mod.multiplayer_balls != null, "ball service loaded"):
		_finish()
		return
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
		"router_probe",
		"controller_probe",
		"multiplayer_balls_probe",
		"bounty_probe"
	]:
		_run_model_probe(probe)
	_check_run_completion()
	await _wait(mod.run_setup.at_main_menu)
	fixtures = (
		load(get_script().resource_path.get_base_dir().path_join("render_ui_fixtures.gd")).new()
	)
	await fixtures.capture_all_menu(mod, _capture)
	var global_node = get_node("/root/Global")
	var database = get_node("/root/BallDatabase")
	var catalog = mod.multiplayer_balls.catalog
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
	mod.multiplayer_balls.begin_session()
	mod.adapter.begin_session(mod)
	global_node.chosen_deck = database.id_to_deck["1_CLASSIC"].duplicate(true)
	global_node.chosen_deck.balls.assign(catalog.BALLS.keys())
	global_node.chosen_difficulty = database.id_to_difficulty["diff_1"]
	for id in ["diff_1", "diff_2", "diff_3", "diff_4"]:
		var difficulty = database.id_to_difficulty[id]
		if difficulty.hasCocktailBar and difficulty.has_tapas_bar:
			global_node.chosen_difficulty = difficulty
			break
	global_node.chosen_run_state = null
	global_node.run_mode = global_node.RunMode.NORMAL
	global_node.seed_text = "24681"
	global_node.set_seeded(true)
	global_node.set_seed(24681)
	global_node.go_to_game()
	if not _check(await _wait(_native_ready), "native table spawned"):
		_finish()
		return
	await get_tree().create_timer(3.0).timeout
	var game = global_node.gameManager
	mod.run_controls.begin_session()
	_check(not mod.run_controls._bindings.is_empty(), "native run exits route to lobby voting")
	_check_balls(game.balls, "host")
	await _capture("10-host-table", "Host table · all eight multiplayer balls")
	await fixtures.capture_table_states(mod, _capture)
	var snapshot = mod.table_sync.capture()
	var spectator_fixtures = (
		load(get_script().resource_path.get_base_dir().path_join("spectator_fixtures.gd")).new()
	)
	for result in await spectator_fixtures.capture(mod, snapshot, _capture):
		_check(result.passed, result.name)
	var ball_state = mod.multiplayer_balls.capture()
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
		await _capture(
			"20-shared-shop", "Shared shop · native offers and all eight balls in the build"
		)
		await fixtures.capture_shop_presence(mod, _capture)
		_check_shop_purchase()
		await _check_shop_readiness()
	await round_flow.record_host(mod, _capture)
	mod.shop_sync.end_session()
	mod.run_controls.end_session()
	mod.adapter.end_session()
	mod.multiplayer_balls.end_session()
	mod.active = false
	mod.run_setup.return_menu()
	if not _check(await _wait(mod.run_setup.at_main_menu), "returned to menu"):
		_finish()
		return
	mod._local_id = 2
	mod.active = true
	mod.latest_state.in_shop = false
	if not _check(mod.table_sync.begin_guest(), "guest scene begins"):
		_finish()
		return
	mod.multiplayer_balls.begin_session()
	_check(mod.table_sync.apply_snapshot(snapshot), "guest snapshot accepted")
	mod.multiplayer_balls.apply_state(ball_state)
	await get_tree().create_timer(1.0).timeout
	game = global_node.gameManager
	mod.latest_state = mod.adapter.game_data()
	mod._update_hud()
	_check_balls(game.replicas.values(), "guest")
	await _capture("30-guest-table", "Guest table · reconstructed from the host snapshot")
	await _capture_ball_previews(game)
	await _capture_guest_shop(snapshot, shop_state)
	mod.multiplayer_balls.end_session()
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
	await get_tree().create_timer(1.0).timeout
	var game = get_node("/root/Global").gameManager
	var shop = mod.shop_sync.native_shop()
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
		if slot.data == "TOGETHER_CALL":
			inspected_key = slot.key
			break
	_check(mod.shop_sync.inspect_slot(inspected_key), "guest shop item can be inspected")
	var inspected = mod.shop_sync.slot_item(inspected_key)
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
	mod.shop_sync.show_section("snacks")
	_check(
		shop.selected_ball == null and shop.selected_passive == null,
		"changing native shop counter clears inspection"
	)
	mod.shop_sync.end_session()


func _native_ready() -> bool:
	var game = get_node("/root/Global").gameManager
	return is_instance_valid(game) and game.balls_spawned


func _shop_ready() -> bool:
	mod.multiplayer_balls.prepare_shop()
	var state = mod.shop_sync.capture()
	return state.get("open", false) and not state.get("busy", true)


func _check_shop():
	var state: Dictionary = mod.shop_sync.capture()
	var multiplayer_ids = []
	for slot in state.slots:
		if slot.id != 0 and slot.group == "build" and slot.data.begins_with("TOGETHER_"):
			multiplayer_ids.append(slot.data)
	_check(multiplayer_ids.size() == 8, "shop contains all eight multiplayer balls")


func _check_shop_purchase():
	var sync = mod.shop_sync
	var state: Dictionary = sync.capture()
	var offer: Dictionary = {}
	var empty: Dictionary = {}
	for slot in state.slots:
		if slot.group == "offer" and slot.id != 0:
			offer = slot
		if slot.group == "build" and slot.id == 0:
			empty = slot
	if not _check(not offer.is_empty() and not empty.is_empty(), "shop purchase fixture available"):
		return
	var purchase = {
		"action": "move",
		"revision": state.revision,
		"source": offer.key,
		"item_id": offer.id,
		"target": empty.key,
		"target_id": 0
	}
	_check(sync.handle_request(purchase, 1), "shared shop accepts occupied offer purchase")
	var purchased: Dictionary = sync.capture()
	_check(purchased.revision > state.revision, "purchase advances shop revision")
	_check(not sync.handle_request(purchase, 1), "duplicate purchase rejected")
	_check(sync.capture().money == purchased.money, "duplicate purchase preserves money")


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
	for body in game.replicas.values():
		var id = str(body.ball_item.data.id)
		if not id.begins_with("TOGETHER_"):
			continue
		game.select_ball(body, body.ball_item)
		await get_tree().create_timer(0.45).timeout
		_check(inspection.showing and inspection.ball == body, "guest inspection selection " + id)
		_check(
			inspection.main_panel.is_visible_in_tree() and inspection.scale_value > 0.9,
			"guest inspection visible " + id
		)
		await _capture(
			"40-ball-" + id.trim_prefix("TOGETHER_").to_lower(),
			body.ball_item.data.name + " · guest inspection card"
		)
		game.unselect_ball(body, body.ball_item)
	inspection.hide_info()
	for body in game.replicas.values():
		body.set_process(true)


func _check_balls(balls: Array, role: String):
	var ids = []
	for body in balls:
		if body.ball_item == null or not str(body.ball_item.data.id).begins_with("TOGETHER_"):
			continue
		var item = body.ball_item
		ids.append(item.data.id)
		_check(
			body.ball.material.get_shader_parameter("tex") == item.data.texture,
			role + " shader texture " + item.data.id
		)
		_check(
			item.data.texture.get_size() == Vector2(1024, 768),
			role + " native-resolution cube atlas " + item.data.id
		)
	_check(ids.size() == 8, role + " displays all eight balls")


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

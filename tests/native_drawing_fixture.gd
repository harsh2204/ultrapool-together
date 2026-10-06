extends RefCounted
## Real native drawing entrypoints, production capture, guest and watched replay.
## One-process correctness evidence; neither live transport nor performance parity.

const Draw = preload("../mod/table_native_draw.gd")
const WatchFixture = preload("native_table_effects_fixture.gd")
var _stages: Array = []
var _active: Dictionary = {}


func check_host(mod: Node, game: Node, record: Callable, capture: Callable) -> void:
	var pentagram = game.table.get_node("Pentagram")
	if not record.call(
		game.candles_pocketed == 0, "native drawing: ritual fixture begins at zero candles"
	):
		return
	var original_process = pentagram.is_processing()
	var original_strength = game.ritual_strength
	pentagram.set_process(false)
	_stages.clear()
	for stage in 6:
		if stage > 0:
			# Zero strength follows the real candle/completion path without nudging
			# unrelated rack balls. This fixture tests drawing, not ritual bonuses.
			game.pocket_candle(0)
			pentagram._process(0.4)
		var state: Dictionary = mod.table_sync.capture().get("native_draw", {})
		_stages.append(state.duplicate(true))
		var ritual = _kind(state, "pentagram")
		record.call(
			Draw.problem(state).is_empty() and state.get("status") == "complete",
			"native drawing: candle stage %d valid" % stage
		)
		if stage == 0:
			record.call(
				ritual.is_empty(),
				"native drawing: reset ritual has no visible descriptor or idle traffic"
			)
		else:
			record.call(
				(
					not ritual.is_empty()
					and ritual.candles == stage
					and ritual.strength == game.ritual_strength
				),
				"native drawing: real candle count and strength %d" % stage
			)
		if not ritual.is_empty():
			record.call(
				ritual.parts[2].points == pentagram.get_node("Lines/Line2D").points,
				"native drawing: native ritual geometry stage %d" % stage
			)
		if stage == 3:
			await capture.call("17a-host-candle-stages", "Host · native CANDLE stage three")
	await capture.call("17b-host-candle-complete", "Host · native CANDLE completion")
	pentagram._process(1.1)
	pentagram._process(0.09)
	var faded: Dictionary = mod.table_sync.capture().get("native_draw", {})
	_stages.append(faded.duplicate(true))
	var faded_ritual = _kind(faded, "pentagram")
	record.call(
		not faded_ritual.is_empty() and faded_ritual.parts[1].modulate.a < 1.0,
		"native drawing: native ritual fades after completion"
	)
	pentagram.reset()
	game.candles_pocketed = 0
	game.ritual_strength = original_strength
	pentagram.set_process(original_process)
	var donors: Array = []
	for kind in ["REAPER", "LUNA"]:
		var item = game.balls[0].ball_item.duplicate(true)
		item.data = mod.get_node("/root/BallDatabase").id_to_ball[kind]
		var body = game.spawn_ball_from_item(
			item, "setup", Vector2(-140 + donors.size() * 280, -90), 0
		)
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.collision_layer = 0
		body.collision_mask = 0
		donors.append(body)
	var reaper = donors[0]
	var luna = donors[1]
	await mod.get_tree().process_frame
	record.call(
		reaper.deathline == reaper.get_node("visuals/deathline"),
		"native drawing: host lifecycle repairs missing native tether binding"
	)
	var original_line = reaper.deathline
	mod.table_sync.capture()
	record.call(
		reaper.deathline == original_line,
		"native drawing: repeated capture retains valid native tether binding"
	)
	reaper.hit(luna)
	reaper._process(0.03)
	luna.prediction_sys.predictive_stuff(Vector2(0, 150), 0.03, luna, false)
	var trail = reaper.get_node("Trail")
	trail.visible = true
	for step in 5:
		reaper.global_position += Vector2(8, 0)
		trail._process(0.03)
	reaper._process(0.03)
	print(
		"NATIVE_REAPER_BINDING ",
		{
			"native_reference": is_instance_valid(reaper.deathline),
			"known_node": is_instance_valid(reaper.get_node_or_null("visuals/deathline")),
			"visible": reaper.get_node("visuals/deathline").visible,
			"effective_visible": reaper.get_node("visuals/deathline").is_visible_in_tree(),
			"reaper": reaper.is_reaper,
			"source_alive": reaper.is_alive(),
			"target_alive": luna.is_alive(),
			"source_spawned": reaper.spawned,
			"source_inited": reaper.inited,
			"source_visible": reaper.is_visible_in_tree(),
			"source_processing": reaper.is_processing(),
			"target_spawned": luna.spawned,
			"target_inited": luna.inited,
			"target_visible": luna.is_visible_in_tree(),
			"in_run": mod.get_node("/root/Global").in_run,
			"target": reaper.last_collided_ball == luna
		}
	)
	var before_score = game.score
	var before_money = game.player_info.money
	game.display_score(-1234567, Vector2(-130, 100))
	var money = game.display_money(47, Vector2(100, 100), 1.5, true, "UI_POPUP_BONUS")
	money.redisplay(99, "€")
	var scores: Array = []
	for child in game.get_children():
		if child.scene_file_path == "res://ui/score_display.tscn":
			child.set_process(false)
			child._process(0.18)
			scores.append(child)
	# Let native minimum-size and container layout settle before comparing text
	# transforms; the frozen presentation roots keep this a deterministic pose.
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	_active = mod.table_sync.capture().get("native_draw", {}).duplicate(true)
	record.call(
		Draw.problem(_active).is_empty() and _active.get("status") == "complete",
		"native drawing: real native drawing state valid"
	)
	for kind in ["tether", "trail", "prediction", "score"]:
		record.call(
			not _kind(_active, kind).is_empty(), "native drawing: native capture includes " + kind
		)
	record.call(
		reaper.last_collided_ball == luna,
		"native drawing: REAPER contact chooses authoritative target"
	)
	record.call(
		game.score == before_score and game.player_info.money == before_money,
		"native drawing: presentation entrypoints preserve score and money"
	)
	await capture.call(
		"17c-host-native-drawing",
		"Host · REAPER tether, LUNA prediction, trails and native score/money"
	)
	# Target loss and transformed LUNA remove drawing through native callbacks.
	luna.alive = false
	reaper._process(0.03)
	var gone: Dictionary = mod.table_sync.capture().get("native_draw", {})
	record.call(
		_kind(gone, "tether").is_empty(), "native drawing: target death removes native tether"
	)
	for body in donors:
		game.unselect_ball(body, body.ball_item)
		mod.get_node("/root/GlobalPhysics").unregister_ball(body)
		mod.get_node("/root/Global").eventManager.unregister_ball(body)
		for field in [
			"balls", "active_balls", "active_balls_include_untargetable", "pocketed_balls"
		]:
			game.get(field).erase(body)
		body.queue_free()
	for score in scores:
		score.queue_free()
	await mod.get_tree().process_frame
	_check_validation(record)


func check_guest(mod: Node, baseline: Dictionary, record: Callable, capture: Callable) -> void:
	if not record.call(not _active.is_empty(), "native drawing: guest has host capture"):
		return
	var game = mod.get_node("/root/Global").gameManager
	var physics = mod.get_node("/root/GlobalPhysics")
	var bodies = physics.balls.duplicate()
	var shapes = physics.shapes.duplicate()
	var score = game.score
	var money = game.player_info.money
	for index in _stages.size():
		var packet = baseline.duplicate(true)
		packet["native_draw"] = _stages[index]
		record.call(
			mod.table_sync.apply_snapshot(packet),
			"native drawing: guest accepts candle stage %d" % index
		)
		await _drain(game._native_draw_view, mod)
		_check_view(game._native_draw_view, packet.native_draw, record, "guest ritual %d" % index)
	var packet = baseline.duplicate(true)
	packet["native_draw"] = _active.duplicate(true)
	record.call(
		mod.table_sync.apply_snapshot(packet), "native drawing: guest accepts native drawing"
	)
	await _drain(game._native_draw_view, mod)
	_check_view(game._native_draw_view, packet.native_draw, record, "guest")
	var ids = _ids(game._native_draw_view)
	mod.table_sync.apply_snapshot(packet)
	record.call(
		_ids(game._native_draw_view) == ids, "native drawing: duplicate retains visual identities"
	)
	record.call(
		(
			game.score == score
			and game.player_info.money == money
			and physics.balls == bodies
			and physics.shapes == shapes
		),
		"native drawing: replay has no gameplay, economy or physics callbacks"
	)
	await capture.call(
		"35a-guest-native-drawing",
		"Guest · authoritative ritual, tether, prediction and score/money"
	)
	var controller = WatchFixture.WatchController.new()
	controller.ui_root = mod.ui_root
	controller.skin = mod.skin
	mod.add_child(controller)
	var watcher = (
		load(get_script().resource_path.get_base_dir().path_join("../mod/table_spectator.gd")).new()
	)
	controller.add_child(watcher)
	watcher.setup(controller)
	watcher.watch(1)
	watcher.apply_snapshot(1, packet)
	for frame in 12:
		watcher.tick(0.0)
		if watcher._native_draw_view.stats.get("pending", 0) == 0:
			break
		await mod.get_tree().process_frame
	_check_view(watcher._native_draw_view, packet.native_draw, record, "spectator")
	await capture.call(
		"35b-spectator-native-drawing", "Spectator · native drawing in watched table coordinates"
	)
	var templates: Array = []
	for template in watcher._native_draw_view._templates.values():
		templates.append(weakref(template))
	record.call(
		not templates.is_empty(), "native drawing: watched board owns native visual templates"
	)
	watcher.watch(2)
	watcher._native_draw_view.tick()
	(
		record
		. call(
			(
				watcher._native_draw_view.entries.is_empty()
				and watcher._native_draw_view._templates.is_empty()
				and watcher._native_draw_view._parent == null
			),
			"native drawing: watcher switch disposes drawing nodes and templates without pending resurrection"
		)
	)
	for reference in templates:
		record.call(
			not is_instance_valid(reference.get_ref()),
			"native drawing: off-tree template actually freed on board disposal"
		)
	watcher.apply_snapshot(2, packet)
	for frame in 12:
		watcher.tick(0.0)
		if watcher._native_draw_view.stats.get("pending", 0) == 0:
			break
		await mod.get_tree().process_frame
	_check_view(watcher._native_draw_view, packet.native_draw, record, "spectator after disposal")
	record.call(
		not watcher._native_draw_view._templates.is_empty(),
		"native drawing: next board rebuilds required templates after disposal"
	)
	watcher.close()
	record.call(
		watcher._native_draw_view._templates.is_empty(),
		"native drawing: watcher close releases recreated templates"
	)
	controller.queue_free()
	var malformed = packet.duplicate(true)
	malformed.native_draw.items[0].parts[0].position.x = NAN
	var retained = _ids(game._native_draw_view)
	record.call(
		not mod.table_sync.apply_snapshot(malformed) and _ids(game._native_draw_view) == retained,
		"native drawing: invalid public snapshot cannot mutate the retained view"
	)
	var deadline = Time.get_ticks_msec() + 1500
	while _has_score(game._native_draw_view) and Time.get_ticks_msec() < deadline:
		game._native_draw_view.tick()
		await mod.get_tree().process_frame
	record.call(
		not _has_score(game._native_draw_view),
		"native drawing: lost removal cannot leave score text stuck"
	)
	mod.table_sync.apply_snapshot(packet)
	game._native_draw_view.tick()
	record.call(
		not _has_score(game._native_draw_view),
		"native drawing: duplicate expired score cannot resurrect"
	)
	var clean = packet.duplicate(true)
	clean.native_draw = Draw.empty()
	mod.table_sync.apply_snapshot(clean)
	game._native_draw_view.tick()
	record.call(
		game._native_draw_view.entries.is_empty(),
		"native drawing: removal cancels pending visual creation"
	)
	mod.table_sync.apply_snapshot(packet)
	await _drain(game._native_draw_view, mod)
	record.call(
		not game._native_draw_view.entries.is_empty(),
		"native drawing: full resync restores current state"
	)
	var overflow = clean.duplicate(true)
	overflow.rounds_played += 1
	overflow.native_draw = Draw.overflow("fixture")
	mod.table_sync.apply_snapshot(overflow)
	game._native_draw_view.tick()
	record.call(
		game._native_draw_view.entries.is_empty(),
		"native drawing: new epoch overflow cannot resurrect old state"
	)
	mod.table_sync.apply_snapshot(baseline)


func _drain(view, mod: Node) -> void:
	for frame in 24:
		view.tick()
		if view.stats.get("pending", 0) == 0:
			await mod.get_tree().process_frame
			return
		await mod.get_tree().process_frame


func _check_view(view, state: Dictionary, record: Callable, label: String) -> void:
	record.call(
		view.entries.size() == state.items.size(),
		"native drawing: " + label + " materializes every drawing"
	)
	for item in state.items:
		var entry = view.entries.get(item.id, {})
		if not record.call(
			not entry.is_empty(), "native drawing: " + label + " retained " + item.kind
		):
			continue
		record.call(
			_visual_only(entry.node), "native drawing: " + label + " scriptless " + item.kind
		)
		for part_state in item.parts:
			var part = entry.parts[part_state.index]
			if part is Control:
				if not part.size.is_equal_approx(part_state.size):
					print(
						"NATIVE_DRAW_CONTROL_BOUNDS ",
						label,
						" index=",
						part_state.index,
						" actual=",
						part.size,
						" host=",
						part_state.size
					)
				record.call(
					part.size.is_equal_approx(part_state.size),
					"native drawing: " + label + " native label/panel bounds"
				)
			record.call(
				(
					part.visible == part_state.visible
					and part.modulate == part_state.modulate
					and part.self_modulate == part_state.self_modulate
				),
				"native drawing: " + label + " tint/visibility " + item.kind
			)
			if part is Line2D:
				record.call(
					(
						part.points == part_state.points
						and is_equal_approx(part.width, part_state.width)
					),
					"native drawing: " + label + " authoritative points " + item.kind
				)
			if part is Label:
				record.call(
					part.text == part_state.text, "native drawing: " + label + " exact native text"
				)


func _check_validation(record: Callable) -> void:
	if not record.call(
		not _active.get("items", []).is_empty(),
		"native drawing: validation fixture has native descriptors"
	):
		return
	for field in ["kind", "id", "parts"]:
		var bad = _active.duplicate(true)
		bad.items[0][field] = "res://Game.gd"
		record.call(not Draw.problem(bad).is_empty(), "native drawing: rejects malformed " + field)
	var bad = _active.duplicate(true)
	bad.items[0].parts[0].position.x = NAN
	record.call(not Draw.problem(bad).is_empty(), "native drawing: rejects nonfinite geometry")
	bad = _active.duplicate(true)
	bad.items.append(bad.items[0].duplicate(true))
	record.call(not Draw.problem(bad).is_empty(), "native drawing: rejects duplicate IDs")
	bad = _active.duplicate(true)
	bad.items[0].parts[0]["resource"] = "res://Game.gd"
	record.call(
		not Draw.problem(bad).is_empty(), "native drawing: rejects unexpected resource fields"
	)
	record.call(
		not Draw.active(_stages[0]) and not Draw.active(_stages[3]),
		"native drawing: settled empty/partial rituals allow idle heartbeat"
	)


func _kind(state: Dictionary, kind: String) -> Dictionary:
	for item in state.get("items", []):
		if item.kind == kind:
			return item
	return {}


func _ids(view) -> Dictionary:
	var result: Dictionary = {}
	for id in view.entries:
		result[id] = view.entries[id].node.get_instance_id()
	return result


func _has_score(view) -> bool:
	for entry in view.entries.values():
		if entry.kind == "score":
			return true
	return false


func _visual_only(node: Node) -> bool:
	if (
		node.get_script() != null
		or node is CollisionObject2D
		or node is CollisionShape2D
		or node is AudioStreamPlayer2D
	):
		return false
	for child in node.get_children():
		if not _visual_only(child):
			return false
	return true

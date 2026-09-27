extends RefCounted
## Native transient effects are captured, then replayed without native callbacks.

const Fx = preload("../mod/table_visual_fx.gd")
const View = preload("../mod/table_visual_fx_view.gd")
const WatchFixture = preload("native_table_effects_fixture.gd")
var _state: Dictionary = {}
var _kinds: Array = []


func check_host(mod: Node, game: Node, record: Callable, capture: Callable) -> void:
	var manager = mod.get_node("/root/EffectManager")
	var nodes: Array = []
	var created_ids: Dictionary = {}
	var before_score = game.score
	var before_money = game.player_info.money
	for kind in ["boom", "tornado", "zap_line", "constellation"]:
		var node = manager.spawn(kind, Vector2(-120 + nodes.size() * 80, -100))
		if not record.call(is_instance_valid(node), "native visual FX: host spawns " + kind):
			continue
		nodes.append(node)
		if kind == "zap_line":
			node.setup(node.global_position, node.global_position + Vector2(110, 65))
		if kind == "constellation":
			var points: Array[Vector2] = [Vector2(-120, 80), Vector2(0, 30), Vector2(120, 100)]
			node.set_points(points)
	for kind in ["wisp", "pocket_wisp"]:
		var node = game.get(kind + "_scene").instantiate()
		game.add_child(node)
		node.buff_size = 0
		node.set_target(Vector2(220, 0))
		node.global_position = Vector2(-180, 40 + nodes.size() * 10)
		node.set_effect("rainbow" if kind == "wisp" else "cloud")
		nodes.append(node)
	# One actual native process tick establishes wisp trails and shader/tween pose.
	for node in nodes:
		created_ids[node.get_instance_id()] = true
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	var snapshot: Dictionary = mod.table_sync.capture()
	_state = snapshot.get("visual_fx", {}).duplicate(true)
	print("NATIVE_FX_CATALOG ", Fx.catalog(mod).keys())
	for kind in Fx.catalog(mod):
		record.call(
			Fx.catalog(mod)[kind].complete,
			"native visual FX: full allowlisted native layout " + kind
		)
	print("NATIVE_FX_CAPTURE ", mod.table_sync._visual_fx_capture.capture_stats)
	record.call(
		Fx.problem(_state).is_empty() and _state.get("status") == "complete",
		"native visual FX: complete valid native descriptor"
	)
	_kinds.clear()
	for item in _state.get("items", []):
		_kinds.append(item.kind)
	for kind in ["boom", "tornado", "zap_line", "constellation", "wisp", "pocket_wisp"]:
		record.call(kind in _kinds, "native visual FX: capture includes " + kind)
	await capture.call(
		"17-host-visual-effects",
		"Host · native explosions, tornado, lightning, constellation and wisps"
	)
	for node in nodes:
		if is_instance_valid(node):
			if node.has_method("kill_wisp"):
				node.kill_wisp()
			node.queue_free()
	await mod.get_tree().process_frame
	# No callbacks on these wisps mutate score/money. Native gameplay fixtures
	# separately prove WORMHOLE/BLACK-HOLE and droplet callback outcomes.
	record.call(
		game.score == before_score and game.player_info.money == before_money,
		"native visual FX: presentation fixture preserves gameplay values"
	)
	# Production retention uses wall time; wait on that clock rather than assuming
	# a scene timer and a deferred tree deletion complete at the same frame edge.
	var deadline = Time.get_ticks_msec() + 1200
	var retained = true
	while retained and Time.get_ticks_msec() < deadline:
		await mod.get_tree().process_frame
		var clean: Dictionary = mod.table_sync.capture().get("visual_fx", {})
		retained = clean.get("status") != "complete"
		for item in clean.get("items", []):
			retained = retained or created_ids.has(item.id)
	if retained:
		for id in created_ids:
			var entry = mod.table_sync._visual_fx_capture._tracked.get(id, {})
			if not entry.is_empty():
				print(
					"NATIVE_FX_EXPIRY_FAILURE ",
					id,
					" kind=",
					entry.kind,
					" until=",
					entry.until,
					" now=",
					Time.get_ticks_msec(),
					" alive=",
					is_instance_valid(entry.node.get_ref())
				)
	record.call(not retained, "native visual FX: ended effects expire from bounded capture")
	_check_validation(record)


func check_guest(mod: Node, baseline: Dictionary, record: Callable, capture: Callable) -> void:
	if not record.call(
		not _state.get("items", []).is_empty(), "native visual FX: guest receives real host capture"
	):
		return
	var packet = baseline.duplicate(true)
	packet["visual_fx"] = _state.duplicate(true)
	var game = mod.get_node("/root/Global").gameManager
	var physics = mod.get_node("/root/GlobalPhysics")
	var bodies = physics.balls.duplicate()
	var shapes = physics.shapes.duplicate()
	var score = game.score
	var money = game.player_info.money
	record.call(
		mod.table_sync.apply_snapshot(packet), "native visual FX: guest accepts native snapshot"
	)
	for frame in 12:
		game._visual_fx_view.tick()
		await mod.get_tree().process_frame
	_check_view(game._visual_fx_view, packet.visual_fx, record, "guest")
	var ids = _ids(game._visual_fx_view)
	mod.table_sync.apply_snapshot(packet)
	record.call(
		_ids(game._visual_fx_view) == ids,
		"native visual FX: duplicate snapshot reuses existing nodes"
	)
	var changed = _changed_kind_packet(packet)
	if record.call(
		not changed.is_empty(),
		"native visual FX: captured native kinds support replacement regression"
	):
		record.call(
			mod.table_sync.apply_snapshot(changed),
			"native visual FX: guest accepts valid same-ID kind replacement"
		)
		await _drain_replacement(mod, game._visual_fx_view, changed.visual_fx)
		_check_kind_replacement(game._visual_fx_view, packet, changed, ids, record, "guest")
		record.call(
			mod.table_sync.apply_snapshot(packet),
			"native visual FX: guest restores original kind after replacement"
		)
		await _drain_replacement(mod, game._visual_fx_view, packet.visual_fx)
		_check_view(game._visual_fx_view, packet.visual_fx, record, "guest restored kind")
	record.call(
		(
			physics.balls == bodies
			and physics.shapes == shapes
			and game.score == score
			and game.player_info.money == money
		),
		"native visual FX: guest adds no physics/scoring/economy callbacks"
	)
	await capture.call(
		"35-guest-visual-effects",
		"Guest · host-native transient visuals without gameplay callbacks"
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
	record.call(watcher.watch(1), "native visual FX: independent spectator opens")
	watcher.apply_snapshot(1, packet)
	for frame in 12:
		watcher.tick(0.0)
		await mod.get_tree().process_frame
	_check_view(watcher._visual_fx_view, packet.visual_fx, record, "spectator")
	if not changed.is_empty():
		var spectator_ids = _ids(watcher._visual_fx_view)
		watcher.apply_snapshot(1, changed)
		await _drain_replacement(mod, watcher._visual_fx_view, changed.visual_fx, watcher)
		_check_kind_replacement(
			watcher._visual_fx_view, packet, changed, spectator_ids, record, "spectator"
		)
		watcher.apply_snapshot(1, packet)
		await _drain_replacement(mod, watcher._visual_fx_view, packet.visual_fx, watcher)
		_check_view(watcher._visual_fx_view, packet.visual_fx, record, "spectator restored kind")
	record.call(
		packet.visual_fx == _state,
		"native visual FX: kind replacement leaves captured baseline untouched"
	)
	await capture.call(
		"36-spectator-visual-effects", "Spectator · native transient effects in the watched table"
	)
	watcher.watch(2)
	record.call(
		watcher._visual_fx_view.entries.is_empty(),
		"native visual FX: switching tables clears every previous visual"
	)
	watcher.close()
	controller.queue_free()
	var clean = packet.duplicate(true)
	clean.visual_fx.items.clear()
	record.call(
		mod.table_sync.apply_snapshot(clean), "native visual FX: reliable removal state accepted"
	)
	record.call(
		game._visual_fx_view.entries.is_empty(), "native visual FX: removal clears guest visuals"
	)
	record.call(
		not packet.visual_fx.items.is_empty(),
		"native visual FX: lifecycle cleanup never mutates borrowed snapshots"
	)
	mod.table_sync.apply_snapshot(packet)
	for frame in 12:
		game._visual_fx_view.tick()
		await mod.get_tree().process_frame
	record.call(
		game._visual_fx_view.entries.size() == packet.visual_fx.items.size(),
		"native visual FX: full resync reconstructs active effects"
	)
	var legacy = baseline.duplicate(true)
	legacy.erase("visual_fx")
	mod.table_sync.apply_snapshot(legacy)
	record.call(
		game._visual_fx_view.entries.is_empty(),
		"native visual FX: absent legacy field clears current presentation"
	)
	mod.table_sync.apply_snapshot(baseline)
	print("NATIVE_FX_APPLY ", game._visual_fx_view.stats)


func _changed_kind_packet(packet: Dictionary) -> Dictionary:
	var items: Array = packet.visual_fx.items
	var smallest = -1
	var largest = -1
	for index in items.size():
		if smallest < 0 or items[index].parts.size() < items[smallest].parts.size():
			smallest = index
		if largest < 0 or items[index].parts.size() > items[largest].parts.size():
			largest = index
	if smallest < 0 or largest < 0 or items[smallest].kind == items[largest].kind:
		return {}
	var result = packet.duplicate(true)
	var replacement = items[largest].duplicate(true)
	replacement.id = items[smallest].id
	result.visual_fx.items[smallest] = replacement
	return result


func _drain_replacement(mod: Node, view, state: Dictionary, watcher: Node = null) -> void:
	for frame in 32:
		if watcher != null:
			watcher.tick(0.0)
		else:
			view.tick()
		var matches = view.entries.size() == state.items.size()
		for item in state.items:
			matches = matches and view.entries.get(item.id, {}).get("state") == item
		if matches:
			return
		await mod.get_tree().process_frame


func _check_kind_replacement(
	view,
	original: Dictionary,
	changed: Dictionary,
	before: Dictionary,
	record: Callable,
	label: String
) -> void:
	record.call(
		Fx.problem(changed.visual_fx).is_empty(),
		"native visual FX: " + label + " replacement remains valid native schema"
	)
	for index in original.visual_fx.items.size():
		var item = changed.visual_fx.items[index]
		var entry = view.entries.get(item.id, {})
		if original.visual_fx.items[index].kind != item.kind:
			var replaced = (
				not entry.is_empty()
				and entry.kind == item.kind
				and entry.node.get_instance_id() != before[item.id]
			)
			record.call(
				replaced, "native visual FX: " + label + " changed kind replaces retained prefab"
			)
			if replaced:
				record.call(
					(
						entry.parts.size() == view._catalog[item.kind].parts.size()
						and entry.state == item
					),
					"native visual FX: " + label + " replacement uses correct native part mapping"
				)
		else:
			record.call(
				not entry.is_empty() and entry.node.get_instance_id() == before[item.id],
				"native visual FX: " + label + " unchanged kinds retain their visual nodes"
			)


func _check_view(view, data: Dictionary, record: Callable, label: String) -> void:
	record.call(
		view.entries.size() == data.items.size(),
		"native visual FX: " + label + " materializes every effect"
	)
	for item in data.items:
		var entry = view.entries.get(item.id, {})
		if not record.call(
			not entry.is_empty(), "native visual FX: " + label + " retained identity " + item.kind
		):
			continue
		record.call(
			_visual_only(entry.node), "native visual FX: " + label + " scriptless " + item.kind
		)
		for state in item.parts:
			var part = entry.parts[state.index]
			if not is_instance_valid(part):
				continue
			record.call(
				part.modulate.is_equal_approx(state.modulate) and part.visible == state.visible,
				"native visual FX: " + label + " native tint/visibility " + item.kind
			)
			if part is Line2D:
				record.call(
					part.points == state.points and is_equal_approx(part.width, state.width),
					"native visual FX: " + label + " native trail/endpoints " + item.kind
				)
			if part is GPUParticles2D or part is CPUParticles2D:
				record.call(
					part.process_mode == Node.PROCESS_MODE_INHERIT,
					"native visual FX: " + label + " particle rendering stays enabled"
				)
			for key in state.get("shader", {}):
				record.call(
					part.material.get_shader_parameter(key) == state.shader[key],
					"native visual FX: " + label + " native shader pose " + item.kind
				)
		if item.kind == "constellation":
			var visual_stars: Array = []
			var visual_lines: Array = []
			for child in entry.node.get_children():
				if child is Line2D:
					visual_lines.append(child)
				elif child is Node2D:
					visual_stars.append(child)
			record.call(
				(
					visual_stars.size() == item.stars.size()
					and visual_lines.size() == item.connections.size()
				),
				"native visual FX: " + label + " complete constellation graph"
			)
			for index in mini(visual_stars.size(), item.stars.size()):
				record.call(
					visual_stars[index].position.is_equal_approx(item.stars[index]),
					"native visual FX: " + label + " constellation preserves native world placement"
				)


func _check_validation(record: Callable) -> void:
	if _state.get("items", []).is_empty():
		return
	var bad = _state.duplicate(true)
	bad.items[0].kind = "res://Game.gd"
	record.call(
		not Fx.problem(bad).is_empty(), "native visual FX: rejects wire resource-path injection"
	)
	bad = _state.duplicate(true)
	bad.items.append(bad.items[0].duplicate(true))
	record.call(not Fx.problem(bad).is_empty(), "native visual FX: rejects duplicate identities")
	bad = _state.duplicate(true)
	bad.items[0].parts[0].position = Vector2(NAN, 0)
	record.call(not Fx.problem(bad).is_empty(), "native visual FX: rejects nonfinite transforms")
	bad = _state.duplicate(true)
	bad.items[0].parts[0].index = 99999
	record.call(
		not Fx.problem(bad).is_empty(), "native visual FX: rejects unknown native part indices"
	)
	bad = _state.duplicate(true)
	bad.status = "overflow"
	record.call(
		not Fx.problem(bad).is_empty(), "native visual FX: rejects partial overflow descriptors"
	)


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


func _ids(view) -> Dictionary:
	var result: Dictionary = {}
	for id in view.entries:
		result[id] = view.entries[id].node.get_instance_id()
	return result

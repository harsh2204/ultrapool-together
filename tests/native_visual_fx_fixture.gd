extends RefCounted
## Native transient effects are captured, then replayed without native callbacks.

const Fx = preload("../mod/table_visual_fx.gd")
const View = preload("../mod/table_visual_fx_view.gd")
const WatchFixture = preload("native_table_effects_fixture.gd")
const WISP_MODES = ["", "none", "negative_slow", "negative_fast", "vampire", "apple", "cloud", "compass", "rainbow", "egg", "window", "mirror", "tech", "wheel", "puzzle", "upgrade", "time", "mushroom", "drill", "beach", "roulette"]
var _state: Dictionary = {}
var _kinds: Array = []
var _catalog_samples: Array = []


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
	await _check_catalog_host(mod, game, record, capture)


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
	await _check_catalog_guest(mod, baseline, record, capture)


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


# Each catalog scene is exercised independently so captures stay within the
# production byte/time budgets. These are native scene/pose tests, not claims
# that every gameplay trigger or particle's random simulation phase is covered.
func _check_catalog_host(mod: Node, game: Node, record: Callable, capture: Callable) -> void:
	_catalog_samples.clear()
	var catalog = Fx.catalog(mod)
	var manager = mod.get_node("/root/EffectManager")
	var before_score = game.score
	var before_money = game.player_info.money
	for kind in catalog:
		var variants = range(1, 7) if kind == "dicepop" else [0]
		if kind in ["wisp", "pocket_wisp"]:
			variants = WISP_MODES
		for variant in variants:
			var node: Node2D
			if kind in ["wisp", "pocket_wisp"]:
				node = game.get(kind + "_scene").instantiate()
				game.add_child(node)
				node.buff_size = 0
				node.set_target(Vector2(500, 0))
				node.set_effect(str(variant))
			elif kind == "upgrade_big":
				# This legacy catalog scene requires a level before _ready. Its
				# bare default is zero, which produces negative tween durations.
				node = manager.effects[kind].instantiate()
				node.level = 2
				manager.add_child(node)
				node.global_position = Vector2.ZERO
			else:
				node = manager.spawn(kind, Vector2.ZERO)
			if not record.call(is_instance_valid(node), "native catalog: host spawn " + kind):
				continue
			if kind == "dicepop":
				node.set_value(variant)
			if kind == "zap_line":
				node.setup(Vector2(-120, -40), Vector2(130, 70))
			if kind == "constellation":
				var points: Array[Vector2] = [Vector2(-80, 30), Vector2(10, -50), Vector2(100, 60)]
				node.set_points(points)
			var sample = {"kind": kind, "variant": variant, "poses": []}
			var sampled_tween: Tween = null
			var previous_ring_scale = Vector2.ZERO
			if kind == "upgrade_big":
				sampled_tween = node.tween
				sampled_tween.pause()
				previous_ring_scale = node.get_node("Ring1").scale
				# Sample the native tween itself at 40/80 ms, independent of
				# screenshot/logging frame cost. No final property is seeded.
				record.call(is_equal_approx(node.speed_mult, 0.4), "native catalog: legacy upgrade uses valid native level")
			# Tiger's native shoot_balls method track is at 1.6 seconds. The
			# two early samples and immediate removal never reach that callback.
			for pose in 2:
				await mod.get_tree().process_frame
				await mod.get_tree().process_frame
				if kind == "final_round" and pose == 1:
					for frame in 8:
						await mod.get_tree().process_frame
				if not record.call(is_instance_valid(node), "native catalog: live pose " + kind):
					break
				if sampled_tween != null:
					sampled_tween.custom_step(0.04)
					record.call(is_equal_approx(sampled_tween.get_total_elapsed_time(), 0.04 * (pose + 1)), "native catalog: legacy upgrade samples fixed native tween time")
					var ring_scale: Vector2 = node.get_node("Ring1").scale
					record.call(not ring_scale.is_equal_approx(previous_ring_scale), "native catalog: legacy upgrade advances native ring pose")
					previous_ring_scale = ring_scale
				var data = mod.table_sync.capture().get("visual_fx", {})
				var item: Dictionary = {}
				for candidate in data.get("items", []):
					if candidate.id == node.get_instance_id():
						item = candidate.duplicate(true)
				if not record.call(data.get("status") == "complete" and not item.is_empty(), "native catalog: production capture " + kind):
					continue
				var state = {"version": 1, "status": "complete", "reason": "", "items": [item]}
				record.call(Fx.problem(state).is_empty(), "native catalog: valid native pose " + kind)
				if pose == 0:
					_check_catalog_validation(state, record)
				var native: Dictionary = {}
				_collect_native_pose(node, node, native)
				if kind == "constellation":
					var graph: Array = []
					for child in node.get_children():
						if child is Line2D:
							graph.append({"texture": child.texture, "texture_mode": child.texture_mode, "texture_filter": child.texture_filter, "width": child.width, "points": child.points.duplicate()})
					for path in native.keys():
						if path != ".":
							native.erase(path)
					native["_graph"] = graph
				sample.poses.append({"state": state, "native": native})
				if kind == "dicepop":
					record.call(node.get_node("Ring1").texture == node.dice_imgs[variant - 1], "native catalog: native dice selects face " + str(variant))
				if kind == "final_round" and pose == 1:
					await capture.call("17b-host-final-round", "Host · native localized final-round banner")
			_catalog_samples.append(sample)
			if is_instance_valid(node):
				if node.has_method("kill_wisp"):
					node.kill_wisp()
				node.queue_free()
			await mod.get_tree().process_frame
	record.call(game.score == before_score and game.player_info.money == before_money, "native catalog: scene samples preserve score and money")
	print("NATIVE_FX_CATALOG_POSES ", _catalog_samples.size())


func _collect_native_pose(root: Node, node: Node, result: Dictionary) -> void:
	if node is CanvasItem:
		var pose = {"class": node.get_class(), "modulate": node.modulate, "self_modulate": node.self_modulate, "visible": node.visible}
		if node is Node2D or node is Control:
			pose["relative_transform"] = _relative_transform(root, node)
		if node is Sprite2D:
			pose["texture"] = node.texture
			pose["frame"] = node.frame
		if node is AnimatedSprite2D:
			pose["sprite_frames"] = node.sprite_frames
			pose["animation"] = node.animation
			pose["frame"] = node.frame
		if node is RichTextLabel:
			pose["text"] = node.text
			pose["parsed_text"] = node.get_parsed_text()
			pose["font_size"] = node.get_theme_font_size("normal_font_size")
			pose["size"] = node.size
		if node is GPUParticles2D:
			pose["texture"] = node.texture
			pose["particle_material"] = _material_properties(node.process_material)
			pose["emitting"] = node.emitting
		if node is Line2D:
			pose["points"] = node.points.duplicate()
			pose["width"] = node.width
			pose["color"] = node.default_color
		if node.material is ShaderMaterial:
			var parameters: Dictionary = {}
			for uniform in node.material.shader.get_shader_uniform_list():
				var value = node.material.get_shader_parameter(uniform.name)
				if value is float or value is int or value is bool or value is Vector2 or value is Vector3 or value is Vector4 or value is Color:
					parameters[str(uniform.name)] = value
			pose["shader"] = parameters
		result[str(root.get_path_to(node))] = pose
	for child in node.get_children():
		_collect_native_pose(root, child, result)


func _check_catalog_guest(mod: Node, baseline: Dictionary, record: Callable, capture: Callable) -> void:
	var game = mod.get_node("/root/Global").gameManager
	var controller = WatchFixture.WatchController.new()
	controller.ui_root = mod.ui_root
	controller.skin = mod.skin
	mod.add_child(controller)
	var watcher = load(get_script().resource_path.get_base_dir().path_join("../mod/table_spectator.gd")).new()
	controller.add_child(watcher)
	watcher.setup(controller)
	watcher.watch(1)
	var covered: Dictionary = {}
	for sample in _catalog_samples:
		var retained_ids: Dictionary = {}
		for pose in sample.poses:
			var packet = baseline.duplicate(true)
			packet.visual_fx = pose.state.duplicate(true)
			record.call(mod.table_sync.apply_snapshot(packet), "native catalog: guest accepts " + sample.kind)
			watcher.apply_snapshot(1, packet)
			for pair in [["guest", game._visual_fx_view], ["spectator", watcher._visual_fx_view]]:
				var label: String = pair[0]
				var view = pair[1]
				await _drain_replacement(mod, view, packet.visual_fx, watcher if label == "spectator" else null)
				_check_view(view, pose.state, record, label + " catalog " + sample.kind)
				var id: int = pose.state.items[0].id
				if not view.entries.has(id):
					continue
				var visual = view.entries[id].node
				_compare_native_pose(visual, pose.native, record, label + " " + sample.kind)
				if sample.kind == "constellation":
					_check_constellation_update(view, pose.state, record, label)
				if retained_ids.has(label):
					record.call(retained_ids[label] == visual.get_instance_id(), "native catalog: animated pose retains " + label + " " + sample.kind)
				retained_ids[label] = visual.get_instance_id()
			covered[sample.kind] = true
		if sample.kind == "final_round":
			watcher.close()
			await capture.call("35b-guest-final-round", "Guest · native localized final-round text and pose")
			watcher.watch(1)
		var removed = baseline.duplicate(true)
		removed.visual_fx = {"version": 1, "status": "complete", "reason": "", "items": []}
		mod.table_sync.apply_snapshot(removed)
		watcher.apply_snapshot(1, removed)
		await _drain_replacement(mod, watcher._visual_fx_view, removed.visual_fx, watcher)
		record.call(game._visual_fx_view.entries.is_empty() and watcher._visual_fx_view.entries.is_empty(), "native catalog: reliable removal " + sample.kind)
	record.call(covered.size() == Fx.catalog(mod).size(), "native catalog: every installed definition compared on both views")
	watcher.close()
	controller.queue_free()
	mod.table_sync.apply_snapshot(baseline)
	# The independent host oracle retains native textures, SpriteFrames and
	# particle-material properties only until the final comparison.
	_catalog_samples.clear()


func _compare_native_pose(visual: Node, native: Dictionary, record: Callable, label: String) -> void:
	for path in native:
		if path == "_graph":
			var lines: Array = []
			for child in visual.get_children():
				if child is Line2D:
					lines.append(child)
			record.call(lines.size() == native._graph.size(), "native catalog: " + label + " native graph count")
			for index in mini(lines.size(), native._graph.size()):
				for property in native._graph[index]:
					record.call(lines[index].get(property) == native._graph[index][property], "native catalog: " + label + " native graph " + property)
			continue
		var expected: Dictionary = native[path]
		var part = visual.get_node_or_null(path)
		if not record.call(is_instance_valid(part), "native catalog: " + label + " native visual path " + path):
			continue
		# Native constellation runtime children use generated names. Their
		# count/placement is asserted separately by _check_view.
		for key in expected:
			var actual
			match key:
				"class":
					actual = part.get_class()
				"relative_transform":
					actual = _relative_transform(visual, part)
				"particle_material":
					actual = _material_properties(part.process_material)
				"parsed_text":
					actual = part.get_parsed_text() if part is RichTextLabel else ""
				"font_size":
					actual = part.get_theme_font_size("normal_font_size") if part is RichTextLabel else -1
				"shader":
					for uniform in expected.shader:
						record.call(part.material is ShaderMaterial and part.material.get_shader_parameter(uniform) == expected.shader[uniform], "native catalog: " + label + " native shader " + path + ":" + uniform)
					continue
				"color":
					actual = part.default_color
				_:
					actual = part.get(key)
			var matches = actual == expected[key]
			if actual is Transform2D and expected[key] is Transform2D:
				matches = actual.is_equal_approx(expected[key])
			if actual is Vector2 and expected[key] is Vector2:
				matches = actual.is_equal_approx(expected[key])
			if actual is Color and expected[key] is Color:
				matches = actual.is_equal_approx(expected[key])
			if not matches:
				print("NATIVE_FX_POSE_MISMATCH ", label, " ", path, ":", key, " actual=", actual, " expected=", expected[key])
			record.call(matches, "native catalog: " + label + " native " + path + ":" + key)
		if part is RichTextLabel:
			# Translation may contain BBCode. Compare the native parsed output,
			# while independently requiring that the source key resolves.
			record.call(part.get_parsed_text() == expected.parsed_text and part.tr(expected.text) != expected.text and part.get_parsed_text() != expected.text, "native catalog: " + label + " resolves native translation key")
			record.call(part.get_content_height() <= part.size.y + 1 and part.get_content_width() <= part.size.x + 1, "native catalog: " + label + " rich text fits native bounds")


func _material_properties(material: Material) -> Dictionary:
	var result: Dictionary = {}
	if material == null:
		return result
	for property in material.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["resource_name", "resource_path", "resource_local_to_scene", "script"]:
			result[property.name] = material.get(property.name)
	return result


func _check_catalog_validation(state: Dictionary, record: Callable) -> void:
	for index in state.items[0].parts.size():
		var part = state.items[0].parts[index]
		if part.has("dice_face"):
			for value in [-1, 6, "res://effects/dice1.png"]:
				var bad = state.duplicate(true)
				bad.items[0].parts[index].dice_face = value
				record.call(not Fx.problem(bad).is_empty(), "native catalog: rejects invalid dice face " + str(value))
		if part.has("animation"):
			var bad = state.duplicate(true)
			bad.items[0].parts[index].animation = "injected_animation"
			record.call(not Fx.problem(bad).is_empty(), "native catalog: rejects unknown native animation")
			bad = state.duplicate(true)
			bad.items[0].parts[index].erase("frame")
			record.call(not Fx.problem(bad).is_empty(), "native catalog: rejects animation without native frame")
		if state.items[0].kind == "final_round" and part.has("text"):
			var bad = state.duplicate(true)
			bad.items[0].parts[index].text = "[img]res://injected.png[/img]"
			record.call(not Fx.problem(bad).is_empty(), "native catalog: rejects wire rich-text resource markup")


func _check_constellation_update(view, data: Dictionary, record: Callable, label: String) -> void:
	var changed = data.duplicate(true)
	var item = changed.items[0]
	item.points.append(Vector2(160, -30))
	item.stars.append(Vector2(160, -30))
	item.connections.append([0, item.points.size() - 1])
	record.call(Fx.problem(changed).is_empty(), "native catalog: changed constellation graph remains bounded and valid")
	view.apply(changed, view._origin, view._epoch)
	_check_view(view, changed, record, label + " changed constellation")
	var before: Array = []
	for child in view.entries[item.id].links:
		before.append(child.get_instance_id())
	view.apply(changed, view._origin, view._epoch)
	var after: Array = []
	for child in view.entries[item.id].links:
		after.append(child.get_instance_id())
	record.call(before == after, "native catalog: unchanged constellation retains graph nodes")
	view.apply(data, view._origin, view._epoch)


func _relative_transform(root: CanvasItem, node: CanvasItem) -> Transform2D:
	# Compose local transforms without bringing the spectator's screen-space
	# offset into the arithmetic. Inverting large translated float32 matrices
	# loses precision near zero, especially during native zero-scale tweens.
	var result = Transform2D.IDENTITY
	var current: Node = node
	while current != root and current is CanvasItem:
		result = current.get_transform() * result
		if current.is_set_as_top_level():
			return root.get_global_transform().affine_inverse() * result
		current = current.get_parent()
	return result

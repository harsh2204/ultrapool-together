extends RefCounted
## GAP-007 / PERF-008/014/019/022: real native creation/callbacks, then visual-only
## guest and spectator replay in the one authorized Capture-Screens process.


class WatchController:
	extends Node
	var active = true
	var table_id = 0
	var lobby = {"table_count": 3}
	var ui_root: Control
	var skin: RefCounted

	func _table_abandoned(_table: int) -> bool:
		return false


var _birth: Dictionary = {}
var _active: Dictionary = {}
var _tail: Dictionary = {}
var _removed: Dictionary = {}
var _native_visuals: Dictionary = {}
var _pocket_active: Dictionary = {}
var _pocket_reset: Dictionary = {}
var _sampled_pocket_id = 0
var _candy_id = 0
var _replacement_candy_id = 0


func check_host(mod: Node, game: Node, record: Callable, capture: Callable) -> void:
	_candy_id = 0
	_replacement_candy_id = 0
	_native_visuals.clear()
	_check_template_lifecycle(mod, game, record)
	var before: Dictionary = mod.table_sync.capture()
	if not record.call(
		game.droplets.is_empty() and game.energy_balls.is_empty(),
		"native effects: fixture begins without live droplets or projectiles"
	):
		return
	var flower_stat = game.ach_data_planted_flowers_count
	var source = game.balls[0].ball_item.duplicate(true)
	var donor = game.spawn_ball_from_item(source, "setup", game.get_random_free_position(), 0)
	if not record.call(is_instance_valid(donor), "native effects: temporary callback ball spawns"):
		return
	_freeze_ball(donor)
	var drops: Array = []
	for method in [
		"spawn_flower", "spawn_oil", "spawn_thorn", "spawn_launchpad", "spawn_stove", "spawn_flame",
		"spawn_candy"
	]:
		game.call(method)
		if not record.call(game.droplets.size() == drops.size() + 1, "native effects: " + method):
			continue
		var drop = game.droplets.back()
		drop.set_process(false)
		drop.get_node("Area2D").monitoring = false
		drop.get_node("Area2D").monitorable = false
		drops.append(drop)
	var energy = game.spawn_energy_ball(game.get_random_free_position(), Vector2.ZERO)
	if not record.call(is_instance_valid(energy), "native effects: native ENERGY-BALL spawns"):
		_cleanup_host(mod, game, drops, donor, energy, flower_stat)
		return
	_freeze_ball(energy)
	var energy_nodes: Array = []
	for child in energy.find_children("*", "", true, false):
		energy_nodes.append("%s:%s" % [energy.get_path_to(child), child.get_class()])
	print("NATIVE_ENERGY_VISUAL_HIERARCHY ", energy_nodes)
	_birth = mod.table_sync.capture()
	record.call(
		(
			mod.table_sync.valid_capture(_birth)
			and _birth.get("effects", {}).get("droplets", []).size() == 7
			and _birth.get("effects", {}).get("energy", []).size() == 1
		),
		"native effects: all seven native types and energy are captured at birth"
	)
	if drops.size() != 7:
		_cleanup_host(mod, game, drops, donor, energy, flower_stat)
		return
	# Step native animation methods deterministically while collision monitoring is
	# disabled, so unrelated live rack balls cannot consume fixture effects.
	for drop in drops:
		drop._process(0.35)
	drops[0].improve_flower(4)
	drops[0]._process(0.15)
	donor.linear_velocity = Vector2(120, 0)
	drops[1]._on_area_2d_body_entered(donor)
	drops[3]._on_area_2d_body_entered(donor)
	drops[3]._process(0.2)
	drops[4]._on_area_2d_body_entered(donor)
	energy._process(0.2)
	for step in 4:
		energy.global_position += Vector2(10, 4)
		energy._process(0.03)
		for line in energy.find_children("*", "Line2D", true, false):
			if line.has_method("_physics_process"):
				line._physics_process(0.03)
			elif line.has_method("_process"):
				line._process(0.03)
	var pocket = game.table.get_node("Pockets").get_child(0)
	var area = pocket.get_node("Area2D")
	var white = pocket.get_node("%WhiteHoleEffect")
	var saved_pocket = {
		"scale": area.scale, "color": white.modulate, "process": pocket.is_processing(),
		"closed": pocket.closed, "shielded": pocket.shielded
	}
	pocket.set_process(false)
	pocket.increase_suck(2.5)
	pocket._process(0.05)
	pocket.close_pocket()
	pocket.set_shield(true)
	var door_animation = pocket.get_node("Doors/AnimationPlayer")
	door_animation.advance(0.25)
	door_animation.pause()
	_sampled_pocket_id = pocket.get_instance_id()
	_pocket_active = _inspect_pocket(pocket)
	record.call(pocket.closed and pocket.shielded and pocket.get_node("Doors").modulate.a > 0.0, "native effects: native pocket close animation and shield are active")
	_active = mod.table_sync.capture()
	record.call(
		mod.table_sync.valid_capture(_active), "native effects: active native capture is valid"
	)
	await _sample_native_capture(mod, record)
	record.call(
		drops[0].flower_power == 5, "native effects: native flower improvement changes power"
	)
	record.call(drops[1].charges == 3, "native effects: native oil collision spends one charge")
	record.call(
		drops[3].ball_held == donor and drops[3].launch_timer < 1,
		"native effects: native launchpad callback holds a ball and advances its timer"
	)
	record.call(
		donor.ball_item.flaming, "native effects: native stove ignites only the temporary donor"
	)
	for drop in drops:
		_remember_native_drop(drop)
	_candy_id = drops[6].get_instance_id()
	record.call(
		drops[6].droplet_type == drops[6].DROPLET_TYPE.CANDY
		and drops[6].get_node("MainSprite").texture == drops[6].droplet_sprites[6]
		and drops[6].get_node("shadow").visible,
		"native effects: native candy spawn selects the seventh texture and visible shadow"
	)
	await capture.call(
		"12-host-table-effects",
		"Host · native flowers, oil, thorns, launchpad, stove, flame, candy, energy and WORMHOLE"
	)
	# Consume effects through their real callbacks instead of manufacturing an
	# empty descriptor. The persistent stove is removed by native round cleanup API.
	drops[0]._on_area_2d_body_entered(donor)
	for hit in 3:
		donor.linear_velocity = Vector2(120, 0)
		drops[1]._on_area_2d_body_entered(donor)
	drops[2]._on_area_2d_body_entered(donor)
	drops[3]._process(1.1)
	drops[5]._on_area_2d_body_entered(donor)
	drops[4].remove()
	# The new floor family is collected only by the real PlayerBall. Exercise its
	# native callback (including PICK-CANDY and native replacement spawn), rather
	# than inventing a removal/replacement descriptor in the replication fixture.
	var candy = drops[6]
	candy._on_area_2d_body_entered(donor)
	record.call(
		game.droplets.has(candy) and not candy.is_queued_for_deletion(),
		"native effects: object-ball contact cannot consume player-only candy"
	)
	var events = mod.get_node("/root/Global").eventManager
	var event_slot: int = events._q_tail
	candy._on_area_2d_body_entered(game.player_ball)
	record.call(
		candy.is_queued_for_deletion() and not game.droplets.has(candy)
		and events._q_name[event_slot] == &"PICK-CANDY",
		"native effects: cue pickup consumes candy and dispatches the native PICK-CANDY event"
	)
	var replacement = game.droplets.back() if game.droplets.size() == 1 else null
	if record.call(
		is_instance_valid(replacement) and replacement != candy
		and replacement.droplet_type == replacement.DROPLET_TYPE.CANDY,
		"native effects: native candy pickup spawns a new authoritative identity"
	):
		replacement.set_process(false)
		replacement.get_node("Area2D").monitoring = false
		replacement.get_node("Area2D").monitorable = false
		replacement._process(0.35)
		_replacement_candy_id = replacement.get_instance_id()
		drops.append(replacement)
		_remember_native_drop(replacement)
	energy.linear_velocity = Vector2.ZERO
	energy._process(1.1)
	energy._physics_process(0.02)
	_tail = mod.table_sync.capture()
	record.call(
		(
			game.energy_balls.is_empty()
			and _tail.effects.energy.size() == 1
			and not _tail.effects.energy[0].alive
		),
		"native effects: expired projectile keeps its native visual tail before destruction"
	)
	record.call(
		_tail.effects.droplets.size() == 1
		and _tail.effects.droplets[0].id == _replacement_candy_id
		and _tail.effects.droplets[0].kind == 6,
		"native effects: production capture replaces the consumed candy identity without overflow"
	)
	energy._process(1.1)
	if is_instance_valid(replacement) and not replacement.is_queued_for_deletion():
		replacement.remove()
	area.scale = saved_pocket.scale
	white.modulate = saved_pocket.color
	if saved_pocket.closed:
		pocket.close_pocket()
	else:
		pocket.open_pocket()
	pocket.set_shield(saved_pocket.shielded)
	door_animation.advance(0.5)
	door_animation.pause()
	_pocket_reset = _inspect_pocket(pocket)
	pocket.set_process(saved_pocket.process)
	_removed = mod.table_sync.capture()
	(
		record
		. call(
			(
				_removed.get("effects", {}).get("droplets", []).is_empty()
				and _removed.get("effects", {}).get("energy", []).is_empty()
			),
			"native effects: pickup, depletion, launch and projectile expiry remove authoritative identities"
		)
	)
	_cleanup_host(mod, game, drops, donor, energy, flower_stat)
	await mod.get_tree().process_frame
	var clean: Dictionary = mod.table_sync.capture()
	record.call(
		(
			mod.table_sync.valid_capture(clean)
			and mod.table_sync.ball_ids(clean) == mod.table_sync.ball_ids(before)
			and clean.effects.droplets.is_empty()
			and clean.effects.energy.is_empty()
		),
		"native effects: host cleanup preserves the original rack and clears fixture objects"
	)


func check_guest(mod: Node, baseline: Dictionary, record: Callable, capture: Callable) -> void:
	if not record.call(not _active.is_empty(), "native effects: guest has actual host evidence"):
		return
	var sync = mod.table_sync
	var birth = _with_effects(baseline, _birth.effects)
	var active = _with_effects(baseline, _active.effects)
	var removed = _with_effects(baseline, _removed.effects)
	active.pockets = _active.pockets.duplicate(true)
	removed.pockets = _removed.pockets.duplicate(true)
	record.call(sync.apply_snapshot(birth), "native effects: guest accepts native birth")
	var game = mod.get_node("/root/Global").gameManager
	var view = game.effects_view
	await _drain(view, mod, record, "guest birth")
	_check_view(view, birth.effects, Vector2.ZERO, record, "guest birth", false)
	var identities = _node_ids(view)
	record.call(
		sync.apply_snapshot(active), "native effects: guest accepts native growth and depletion"
	)
	await _drain(view, mod, record, "guest growth")
	_check_view(view, active.effects, Vector2.ZERO, record, "guest active", true)
	_check_pockets(game.pocket_replicas, active.effects, record, "guest")
	_check_pocket_visual(game.pocket_replicas[_sampled_pocket_id], _pocket_active, record, "guest closed")
	var malformed_pocket = active.duplicate(true)
	malformed_pocket.pockets[0].pocket_visual[2][2] = Vector2(NAN, 1.0)
	record.call(not sync.apply_snapshot(malformed_pocket), "native effects: malformed ordinary pocket visual rejected before mutation")
	_check_pocket_visual(game.pocket_replicas[_sampled_pocket_id], _pocket_active, record, "rejected update")
	record.call(
		_node_ids(view) == identities, "native effects: growth retains existing guest nodes"
	)
	var protected = [game.score, game.replicas.size(), game.player_info.money]
	await capture.call(
		"33-guest-table-effects",
		"Guest · native table effects reconstructed without gameplay callbacks"
	)
	record.call(
		protected == [game.score, game.replicas.size(), game.player_info.money],
		"native effects: guest render frames cannot score, spawn balls or change money"
	)
	_check_invalid(sync, active, view, record)
	_check_pocket_substate_isolation(sync, game, active, removed, record)
	var tail = _with_effects(baseline, _tail.effects)
	var candy_event_cursor: Array = _native_event_cursor(mod)
	var native_drops: Array = game.droplets.duplicate()
	record.call(sync.apply_snapshot(tail), "native effects: guest accepts projectile visual tail")
	await _drain(view, mod, record, "guest tail")
	_check_view(view, tail.effects, Vector2.ZERO, record, "guest projectile tail and candy replacement", true)
	record.call(
		not view.entries.has(_candy_id) and view.entries.has(_replacement_candy_id)
		and game.droplets == native_drops and _native_event_cursor(mod) == candy_event_cursor,
		"native effects: guest replaces candy visuals without native pickup or spawn callbacks"
	)
	record.call(sync.apply_snapshot(removed), "native effects: guest accepts native consumption")
	_check_pocket_visual(game.pocket_replicas[_sampled_pocket_id], _pocket_reset, record, "guest reopened")
	await mod.get_tree().process_frame
	record.call(view.entries.is_empty(), "native effects: consumed guest effects are freed")
	record.call(
		sync.apply_snapshot(active), "native effects: full resync restores already-grown effects"
	)
	await _drain(view, mod, record, "guest resync")
	_check_view(view, active.effects, Vector2.ZERO, record, "guest resync", true)
	await _check_synthetic_burst(mod, active, view, record)
	_check_pocket_epoch(view, game.pocket_replicas, active.effects, active.pockets, record)
	await _drain(view, mod, record, "pocket epoch recovery")
	record.call(sync.apply_snapshot(baseline), "native effects: guest baseline restored")
	await mod.get_tree().process_frame
	record.call(view.entries.is_empty(), "native effects: baseline cleanup leaves no effect nodes")
	await _check_spectator(mod, active, removed, record, capture)


func _check_spectator(
	mod: Node, active: Dictionary, removed: Dictionary, record: Callable, capture: Callable
):
	var original_game = mod.get_node("/root/Global").gameManager
	var original_camera = mod.get_node("/root/Global").camera
	var physics = mod.get_node("/root/GlobalPhysics")
	var original_balls = physics.balls.duplicate()
	var controller = WatchController.new()
	controller.ui_root = mod.ui_root
	controller.skin = mod.skin
	mod.add_child(controller)
	var spectator = (
		load(get_script().resource_path.get_base_dir().path_join("../mod/table_spectator.gd")).new()
	)
	controller.add_child(spectator)
	spectator.setup(controller)
	record.call(spectator.watch(1), "native effects: spectator opens another table")
	spectator.apply_snapshot(1, active)
	spectator.tick(0.0)
	await _drain(spectator._effects_view, mod, record, "spectator birth")
	_check_view(
		spectator._effects_view, active.effects, active.table_position, record, "spectator", true
	)
	var identities = _node_ids(spectator._effects_view)
	spectator.apply_snapshot(1, active)
	spectator.tick(0.0)
	record.call(
		_node_ids(spectator._effects_view) == identities,
		"native effects: duplicate spectator snapshot retains nodes"
	)
	var pockets = {}
	for state in active.pockets:
		pockets[state.id] = (
			spectator._table.get_node("Pockets").get_child(state.base_index)
			if state.base_index >= 0
			else spectator._holes.get(state.id)
		)
	_check_pockets(pockets, active.effects, record, "spectator")
	_check_pocket_visual(pockets[_sampled_pocket_id], _pocket_active, record, "spectator closed")
	await capture.call(
		"spectate-table-effects", "Spectator · the same native table effects without host gameplay"
	)
	record.call(
		(
			mod.get_node("/root/Global").gameManager == original_game
			and mod.get_node("/root/Global").camera == original_camera
			and physics.balls == original_balls
		),
		"native effects: spectator leaves native game, camera and physics registration untouched"
	)
	var replaced = _with_effects(active, _tail.effects)
	var candy_event_cursor: Array = _native_event_cursor(mod)
	var native_drops: Array = original_game.droplets.duplicate()
	spectator._frames.clear()
	spectator.apply_snapshot(1, replaced)
	spectator.tick(0.0)
	await _drain(spectator._effects_view, mod, record, "spectator candy replacement")
	_check_view(spectator._effects_view, replaced.effects, replaced.table_position, record, "spectator candy replacement", true)
	record.call(
		not spectator._effects_view.entries.has(_candy_id)
		and spectator._effects_view.entries.has(_replacement_candy_id)
		and original_game.droplets == native_drops and _native_event_cursor(mod) == candy_event_cursor,
		"native effects: spectator replaces candy visuals without native pickup or spawn callbacks"
	)
	spectator._frames.clear()
	spectator.apply_snapshot(1, removed)
	spectator.tick(0.0)
	_check_pocket_visual(pockets[_sampled_pocket_id], _pocket_reset, record, "spectator reopened")
	await mod.get_tree().process_frame
	record.call(
		spectator._effects_view.entries.is_empty(),
		"native effects: spectator consumes authoritative removal"
	)
	spectator.apply_snapshot(1, active)
	spectator._frames = [spectator._frames.back()]
	spectator.tick(0.0)
	await _drain(spectator._effects_view, mod, record, "spectator resync")
	record.call(
		spectator._effects_view.entries.size() == identities.size(),
		"native effects: spectator resync restores active effects"
	)
	spectator.watch(2)
	record.call(
		spectator._effects_view.entries.is_empty(),
		"native effects: watcher switch clears old effects"
	)
	spectator.apply_snapshot(2, active)
	spectator.tick(0.0)
	spectator.close()
	record.call(
		spectator._effects_view.entries.is_empty(),
		"native effects: spectator teardown clears all effects"
	)
	controller.free()


func _check_invalid(sync: Node, active: Dictionary, view, record: Callable):
	var cases: Array = []
	var duplicate = active.duplicate(true)
	duplicate.effects.droplets.append(duplicate.effects.droplets[0].duplicate(true))
	cases.append([duplicate, "duplicate identity"])
	var unknown = active.duplicate(true)
	unknown.effects.droplets[0].kind = 7
	cases.append([unknown, "unknown effect type"])
	var unknown_texture = active.duplicate(true)
	unknown_texture.effects.droplets.back().texture_index = 7
	cases.append([unknown_texture, "texture outside installed candy catalog"])
	var nonfinite = active.duplicate(true)
	nonfinite.effects.energy[0].position = Vector2(NAN, 0)
	cases.append([nonfinite, "nonfinite projectile pose"])
	var oversized = active.duplicate(true)
	var schema = load(
		get_script().resource_path.get_base_dir().path_join("../mod/table_effects_sync.gd")
	)
	for index in schema.MAX_DROPLETS + 1:
		var drop = active.effects.droplets[0].duplicate(true)
		drop.id = 100000 + index
		oversized.effects.droplets.append(drop)
	cases.append([oversized, "unbounded effect count"])
	var identities = _node_ids(view)
	for invalid in cases:
		record.call(not sync.apply_snapshot(invalid[0]), "native effects: reject " + invalid[1])
		record.call(
			_node_ids(view) == identities,
			"native effects: rejected update preserves visible identities"
		)


func _check_view(
	view,
	effects: Dictionary,
	origin: Vector2,
	record: Callable,
	label: String,
	compare_native: bool
):
	var states: Array = effects.droplets + effects.energy
	record.call(
		view.entries.size() == states.size(), "native effects: " + label + " renders all identities"
	)
	for state in states:
		var entry: Dictionary = view.entries.get(state.id, {})
		if not record.call(
			not entry.is_empty(), "native effects: " + label + " identity " + str(state.id)
		):
			continue
		var node: Node2D = entry.node
		record.call(
			(
				node.position.is_equal_approx(state.position - origin)
				and node.scale.is_equal_approx(state.scale)
				and node.modulate.is_equal_approx(state.color)
				and is_equal_approx(node.rotation, state.rotation)
				and node.visible == state.visible
			),
			"native effects: " + label + " authoritative pose/color"
		)
		record.call(
			_visual_only(node), "native effects: " + label + " contains no gameplay or collision"
		)
		if compare_native and _native_visuals.has(state.id):
			var actual = _native_visuals[state.id]
			var sprite = node.get_node("MainSprite")
			var detail = "%s kind=%d" % [label, state.kind]
			if sprite.texture != actual.texture:
				print(
					"NATIVE_EFFECT_TEXTURE ",
					detail,
					" actual=",
					sprite.texture,
					" expected=",
					actual.texture
				)
			record.call(
				sprite.texture == actual.texture,
				"native effects: " + detail + " preserves native type texture"
			)
			record.call(
				node.get_node("shadow").texture == actual.shadow_texture
				and node.get_node("shadow").visible == actual.shadow_visible,
				"native effects: " + detail + " preserves native shadow texture and visibility"
			)
			record.call(
				sprite.flip_h == actual.flip and is_equal_approx(sprite.rotation, actual.rotation),
				"native effects: " + detail + " preserves native direction"
			)
			record.call(
				sprite.self_modulate.is_equal_approx(actual.color),
				"native effects: " + detail + " preserves native tint"
			)
			record.call(
				node.get_node("Flower").visible == actual.flower,
				"native effects: " + detail + " preserves native flower visibility"
			)
			if state.kind == 0:
				record.call(
					(
						entry.flower_label.text == actual.label
						and is_equal_approx(entry.flower_spin.rotation, state.flower_rotation)
					),
					"native effects: " + label + " preserves flower power label and growth pose"
				)
				for index in state.flower_colors.size():
					record.call(
						entry.flower_colors[index].modulate.is_equal_approx(
							state.flower_colors[index]
						),
						"native effects: " + label + " preserves authoritative flower color"
					)
		elif state.has("trails"):
			record.call(
				entry.visuals.scale.is_equal_approx(state.visual_scale),
				"native effects: " + label + " preserves projectile size"
			)
			for trail in state.trails:
				var line: Line2D = entry.trails[trail.index]
				var matching = line.points.size() == trail.points.size()
				for index in mini(line.points.size(), trail.points.size()):
					matching = (
						matching
						and line.to_global(line.points[index]).is_equal_approx(
							view._root.to_global(trail.points[index] - origin)
						)
					)
				record.call(
					matching,
					"native effects: " + label + " preserves native projectile trail geometry"
				)


func _check_pockets(pockets: Dictionary, effects: Dictionary, record: Callable, label: String):
	for state in effects.pockets:
		var pocket = pockets.get(state.id)
		record.call(
			(
				is_instance_valid(pocket)
				and pocket.get_node("Area2D").scale.is_equal_approx(state.suction_scale)
				and pocket.find_child("WhiteHoleEffect", true, false).modulate.is_equal_approx(
					state.suction_color
				)
			),
			"native effects: " + label + " preserves WORMHOLE child suction and pulse"
		)


func _node_ids(view) -> Dictionary:
	var result = {}
	for id in view.entries:
		result[id] = view.entries[id].node.get_instance_id()
	return result


func _check_template_lifecycle(mod: Node, game: Node, record: Callable) -> void:
	var reader = preload("../mod/spectator_scene.gd")
	var view_script = preload("../mod/table_effects_view.gd")
	var packed: PackedScene = mod.get_node("/root/Global").SCENE_GAME
	var droplet_scene: PackedScene = reader.exported(packed, "droplet_scene")
	var originals: Array = reader.exported(droplet_scene, "droplet_sprites").duplicate()
	record.call(not originals.is_empty(), "native effects: installed native texture catalog exists")
	var view = view_script.new()
	for cycle in 2:
		view.setup(game, packed)
		record.call(
			view._textures == originals,
			"native effects: new renderer retains native texture identities"
		)
		view.dispose()
		record.call(
			reader.exported(droplet_scene, "droplet_sprites") == originals,
			"native effects: renderer teardown preserves shared native texture catalog"
		)


func _sample_native_capture(mod: Node, record: Callable) -> void:
	# Actual installed native 7-droplet + 1-projectile capture and validation.
	# These timings are deliberately separate from the synthetic 128-node replay.
	var samples: Array = []
	var valid = true
	for sample in 16:
		await mod.get_tree().process_frame
		var started = Time.get_ticks_usec()
		var state: Dictionary = mod.table_sync.capture()
		valid = mod.table_sync.valid_capture(state) and valid
		samples.append(Time.get_ticks_usec() - started)
	record.call(valid, "native effects: repeated native capture and validation stay valid")
	print(
		"NATIVE_EFFECT_METRICS ",
		JSON.stringify(
			{
				"workload": "actual native 7 droplets + 1 energy + 6 pockets",
				"frame_cap": Engine.max_fps,
				"capture_and_validation_ms": _distribution(samples)
			}
		)
	)


func _check_synthetic_burst(mod: Node, active: Dictionary, view, record: Callable) -> void:
	# Synthetic cap/recovery workload based on real host descriptors. It proves
	# bounded materialization and latest-state cleanup, not 128 native pickups or
	# network latency. No extra game process or artificial delay is introduced.
	var sync = mod.table_sync
	var effects_schema = preload("../mod/table_effects_sync.gd")
	var burst = active.duplicate(true)
	burst.effects.droplets = []
	burst.effects.energy = []
	for index in 128:
		var state: Dictionary = (
			active.effects.droplets[index % active.effects.droplets.size()].duplicate(true)
		)
		state.id = 900000000000000 + index
		burst.effects.droplets.append(state)
	var full_problem: String = effects_schema.problem(burst.effects)
	record.call(
		full_problem in ["", "encoded bytes"],
		"native effects stress: full count is accepted or explicitly limited by encoded bytes"
	)
	var full_bytes = var_to_bytes(burst.effects).size()
	# Count and byte ceilings both apply. Find the largest accepted prefix; never
	# loosen the wire budget to force a chosen synthetic count through it.
	var source: Array = burst.effects.droplets
	var low = 0
	var high = source.size()
	while low < high:
		var middle = (low + high + 1) / 2
		burst.effects.droplets = source.slice(0, middle)
		if effects_schema.valid(burst.effects):
			low = middle
		else:
			high = middle - 1
	burst.effects.droplets = source.slice(0, low)
	var effect_count = burst.effects.droplets.size()
	if not record.call(
		effect_count >= 32 and sync.valid_capture(burst),
		"native effects stress: meaningful native-derived burst validates within both budgets"
	):
		return
	var apply_samples: Array = []
	var tick_samples: Array = []
	var frame_samples: Array = []
	var started = Time.get_ticks_usec()
	record.call(sync.apply_snapshot(burst), "native effects stress: guest accepts full cap")
	apply_samples.append(Time.get_ticks_usec() - started)
	var cap_respected = view.entries.size() <= effect_count
	var deadline = Time.get_ticks_msec() + 2200
	var previous_frame = Time.get_ticks_usec()
	for frame in 64:
		await mod.get_tree().process_frame
		var now = Time.get_ticks_usec()
		frame_samples.append(now - previous_frame)
		previous_frame = now
		tick_samples.append(int(view.stats.get("usec", 0)))
		cap_respected = cap_respected and view.entries.size() <= effect_count
		if view.stats.get("pending", 0) == 0 or Time.get_ticks_msec() >= deadline:
			break
	record.call(cap_respected, "native effects stress: materialized node count never exceeds cap")
	record.call(
		view.entries.size() == effect_count and view.stats.get("pending", 0) == 0,
		"native effects stress: full cap drains within bounded frame deadline"
	)
	# Start a disjoint burst, then supersede it immediately while births remain
	# staged. Subsequent production ticks must never resurrect old queued IDs.
	var second = burst.duplicate(true)
	for state in second.effects.droplets:
		state.id += 1000
	started = Time.get_ticks_usec()
	record.call(sync.apply_snapshot(second), "native effects stress: replacement burst accepted")
	apply_samples.append(Time.get_ticks_usec() - started)
	record.call(
		view.stats.get("pending", 0) > 0,
		"native effects stress: replacement actually has staged births"
	)
	var removed = burst.duplicate(true)
	removed.effects.droplets = []
	started = Time.get_ticks_usec()
	record.call(sync.apply_snapshot(removed), "native effects stress: newest removal accepted")
	apply_samples.append(Time.get_ticks_usec() - started)
	var no_resurrection = view.entries.is_empty() and view.stats.get("pending", 0) == 0
	for frame in 4:
		await mod.get_tree().process_frame
		no_resurrection = (
			no_resurrection and view.entries.is_empty() and view.stats.get("pending", 0) == 0
		)
	record.call(
		no_resurrection,
		"native effects stress: newest removal cancels staged births without resurrection"
	)
	print(
		"NATIVE_EFFECT_METRICS ",
		JSON.stringify(
			{
				"workload":
				"synthetic largest accepted native-derived droplet burst, then superseded burst",
				"droplets": effect_count,
				"effects_bytes": var_to_bytes(burst.effects).size(),
				"full_128_bytes": full_bytes,
				"full_128_problem": full_problem,
				"frame_cap": Engine.max_fps,
				"frame_interval_ms": _distribution(frame_samples),
				"snapshot_apply_ms": _distribution(apply_samples),
				"renderer_tick_ms": _distribution(tick_samples)
			}
		)
	)


func _distribution(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {"samples": 0}
	var sorted = samples.duplicate()
	sorted.sort()
	var result = {"samples": sorted.size(), "max": float(sorted.back()) / 1000.0}
	for pair in [["p50", 0.5], ["p95", 0.95], ["p99", 0.99]]:
		result[pair[0]] = float(sorted[ceili(sorted.size() * pair[1]) - 1]) / 1000.0
	return result


func _drain(view, mod: Node, record: Callable, label: String) -> void:
	# Scene construction is deliberately bounded across frames; assert completion
	# after that production budget drains, not synchronously after snapshot apply.
	for frame in 32:
		view.tick()
		if int(view.stats.get("pending", 0)) == 0:
			record.call(
				true, "native effects: " + label + " materialization completes within budget"
			)
			return
		await mod.get_tree().process_frame
	record.call(false, "native effects: " + label + " materialization did not drain")


func _visual_only(node: Node) -> bool:
	if node.get_script() != null or node is CollisionObject2D or node is CollisionShape2D:
		return false
	for child in node.get_children():
		if not _visual_only(child):
			return false
	return true


func _with_effects(baseline: Dictionary, effects: Dictionary) -> Dictionary:
	var result = baseline.duplicate(true)
	result["effects"] = effects.duplicate(true)
	return result


func _remember_native_drop(drop: Node) -> void:
	_native_visuals[drop.get_instance_id()] = {
		"texture": drop.get_node("MainSprite").texture,
		"flip": drop.get_node("MainSprite").flip_h,
		"rotation": drop.get_node("MainSprite").rotation,
		"color": drop.get_node("MainSprite").self_modulate,
		"flower": drop.get_node("Flower").visible,
		"label": drop.get_node("%FlowerLabel").text,
		"shadow_texture": drop.get_node("shadow").texture,
		"shadow_visible": drop.get_node("shadow").visible
	}


func _native_event_cursor(mod: Node) -> Array:
	var events = mod.get_node("/root/Global").eventManager
	# Guests intentionally discard native gameplay managers. If a manager exists
	# underneath a watched table, visual replay must not enqueue events on it.
	return [events.get_instance_id(), events._q_tail] if is_instance_valid(events) else []


func _freeze_ball(ball: Node):
	ball.freeze = true
	ball.set_process(false)
	ball.set_physics_process(false)
	ball.collision_layer = 0
	ball.collision_mask = 0


func _cleanup_host(mod: Node, game: Node, drops: Array, donor, energy, flower_stat):
	for drop in drops:
		if is_instance_valid(drop) and not drop.is_queued_for_deletion():
			drop.remove()
	if is_instance_valid(energy):
		if energy.alive:
			energy.unalive()
		energy.queue_free()
	if is_instance_valid(donor):
		mod.get_node("/root/GlobalPhysics").unregister_ball(donor)
		mod.get_node("/root/Global").eventManager.unregister_ball(donor)
		for field in [
			"balls", "active_balls", "active_balls_include_untargetable", "pocketed_balls"
		]:
			game.get(field).erase(donor)
		donor.queue_free()
	game.ach_data_planted_flowers_count = flower_stat


func _inspect_pocket(pocket: Node) -> Dictionary:
	return {
		"root_color": pocket.modulate,
		"door_color": pocket.get_node("Doors").modulate,
		"left": pocket.get_node("Doors/Left").position,
		"right": pocket.get_node("Doors/Right").position,
		"left_tint": pocket.get_node("Doors/Left").self_modulate,
		"right_tint": pocket.get_node("Doors/Right").self_modulate,
		"shield": pocket.get_node("ShieldIndicator").visible,
		"label": pocket.get_node("Label").text,
		"score_scale": pocket.get_node("ExtraScoreLabelPivot").scale
	}


func _check_pocket_visual(pocket: Node, expected: Dictionary, record: Callable, role: String) -> void:
	var actual = _inspect_pocket(pocket)
	for key in expected:
		record.call(actual[key] == expected[key], "native effects: " + role + " preserves native pocket " + key)


func _check_pocket_epoch(view, pockets: Dictionary, effects: Dictionary, ordinary: Array, record: Callable) -> void:
	var epoch: String = view._epoch
	var overflow = preload("../mod/table_effects_sync.gd").overflow("descriptor")
	view.apply(overflow, Vector2.ZERO, epoch + ":pocket-reset")
	view.apply_pockets(overflow, pockets)
	var pocket = pockets[_sampled_pocket_id]
	record.call(pocket.get_node("Doors").modulate.a == 0.0 and not pocket.get_node("ShieldIndicator").visible, "native effects: new-epoch overflow clears obsolete pocket doors and shield")
	view.apply(effects, Vector2.ZERO, epoch)
	view.apply_pockets(effects, pockets, ordinary)
	_check_pocket_visual(pocket, _pocket_active, record, "epoch recovery")


func _check_pocket_substate_isolation(sync, game: Node, active: Dictionary, removed: Dictionary, record: Callable) -> void:
	var pocket = game.pocket_replicas[_sampled_pocket_id]
	var suction_scale: Vector2 = pocket.get_node("Area2D").scale
	var suction_color: Color = pocket.find_child("WhiteHoleEffect", true, false).modulate
	var retained = _node_ids(game.effects_view)
	var partial = active.duplicate(true)
	partial.effects = preload("../mod/table_effects_sync.gd").overflow("bytes")
	partial.pockets = removed.pockets.duplicate(true)
	record.call(sync.apply_snapshot(partial), "native effects: ordinary pocket update survives independent durable overflow")
	_check_pocket_visual(pocket, _pocket_reset, record, "independent pocket update")
	record.call(pocket.get_node("Area2D").scale == suction_scale and pocket.find_child("WhiteHoleEffect", true, false).modulate == suction_color, "native effects: durable overflow retains last complete suction while pocket art advances")
	record.call(_node_ids(game.effects_view) == retained, "native effects: independent pocket art update retains durable effect nodes")
	var missing_art = active.duplicate(true)
	missing_art.effects = partial.effects.duplicate(true)
	missing_art.pocket_visual_status = "overflow"
	for state in missing_art.pockets:
		state.erase("pocket_visual")
	record.call(sync.apply_snapshot(missing_art), "native effects: optional art omission preserves authoritative pocket fields")
	_check_pocket_visual(pocket, _pocket_reset, record, "omitted art retention")
	record.call(sync.apply_snapshot(active), "native effects: complete state recovers both pocket substates")
	_check_pocket_visual(pocket, _pocket_active, record, "independent recovery")

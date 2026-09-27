extends RefCounted

## Runs only inside the authorized Capture-Screens native host/guest lifecycle.
## PERF-008/014: exercise the real BLACK-HOLE spawn path, then replay its captured
## pocket state on a guest without enabling native pocket gameplay.

var _birth: Dictionary = {}
var _grown: Dictionary = {}
var _hole_id = 0


func check_host(mod: Node, game: Node, record: Callable, capture: Callable) -> void:
	_birth.clear()
	_grown.clear()
	_hole_id = 0
	var sync = mod.table_sync
	var before: Dictionary = sync.capture()
	var before_ids: Dictionary = sync.pocket_ids(before)
	if not record.call(
		sync.valid_capture(before) and before_ids.size() == 6 and game.hole_count == 0,
		"native blackhole: host starts with a valid six-pocket table"
	):
		return
	game.spawn_hole(2)
	var created: Array = []
	for pocket in game.pockets:
		if not before_ids.has(pocket.get_instance_id()):
			created.append(pocket)
	if record.call(created.size() == 1, "native blackhole: native spawn creates one hole"):
		var hole = created[0]
		_hole_id = hole.get_instance_id()
		_birth = sync.capture()
		var birth_state = _pocket(_birth, _hole_id)
		print(
			(
				"NATIVE_POCKET_BIRTH host_scale=(%.12f, %.12f) captured_scale=%s multiplier=%s native_multiplier=%s"
				% [
					hole.scale.x,
					hole.scale.y,
					birth_state.get("scale"),
					birth_state.get("multiplier"),
					hole.get_multiplier()
				]
			)
		)
		record.call(
			game.table.get_pockets().size() == 7 and game.base_pockets.size() == 7,
			"native blackhole: actual game mutates the aliased table and base pocket arrays"
		)
		record.call(
			sync.valid_capture(_birth) and birth_state.get("base_index") == -1,
			"native blackhole: immediate native spawn produces an accepted dynamic identity"
		)
		record.call(
			birth_state.get("scale") == hole.scale,
			"native blackhole: capture preserves the live native birth scale"
		)
		# Native spawn assigns zero, but the supported engine exposes (0.00001,
		# 0.00001). Test visually collapsed birth and exact native capture parity,
		# not an assumed representation of a singular Node2D transform.
		record.call(
			hole.scale.length() < 0.001,
			"native blackhole: native birth starts visually collapsed"
		)
		record.call(
			birth_state.get("multiplier") == 3.0,
			"native blackhole: capture preserves the native level multiplier"
		)
		for frame in 8:
			await mod.get_tree().process_frame
		_grown = sync.capture()
		var grown_state = _pocket(_grown, _hole_id)
		record.call(
			sync.valid_capture(_grown)
			and grown_state.get("scale", Vector2.ZERO).x > birth_state.scale.x,
			"native blackhole: growing native hole remains a valid table update"
		)
		await capture.call(
			"11-host-blackhole", "Host · native BLACK-HOLE spawn captured as a dynamic pocket"
		)
	# Restore only this fixture's spawn. Full clear_table() would destroy the live
	# rack needed by the following native shop/round fixtures.
	for hole in created:
		game.pockets.erase(hole)
		game.spawned_stuff.erase(hole)
		hole.queue_free()
	game.hole_count = 0
	await mod.get_tree().process_frame
	var clean: Dictionary = sync.capture()
	record.call(
		sync.valid_capture(clean) and sync.pocket_ids(clean) == before_ids,
		"native blackhole: fixture cleanup restores the original native pocket identities"
	)


func check_guest(mod: Node, baseline: Dictionary, record: Callable, capture: Callable) -> void:
	if not record.call(
		_hole_id > 0 and not _birth.is_empty() and not _grown.is_empty(),
		"native blackhole: guest replay has actual host capture evidence"
	):
		return
	var sync = mod.table_sync
	var birth = baseline.duplicate(true)
	birth.pockets = _birth.pockets.duplicate(true)
	var grown = baseline.duplicate(true)
	grown.pockets = _grown.pockets.duplicate(true)
	if not record.call(sync.apply_snapshot(birth), "native blackhole: guest accepts native birth"):
		return
	var game = mod.get_node("/root/Global").gameManager
	var hole = game.pocket_replicas.get(_hole_id)
	if not record.call(
		is_instance_valid(hole), "native blackhole: guest creates a native hole node"
	):
		sync.apply_snapshot(baseline)
		return
	record.call(
		hole.get_meta("remote_hole", false) and hole.get_meta("remote_base_index") == -1,
		"native blackhole: guest hole is separate from the six fixed pockets"
	)
	var birth_state = _pocket(birth, _hole_id)
	print(
		(
			"NATIVE_POCKET_BIRTH guest_scale=(%.12f, %.12f) captured_scale=%s blackhole_visible=%s"
			% [
				hole.scale.x,
				hole.scale.y,
				birth_state.get("scale"),
				hole.get_node("%BlackHole").visible
			]
		)
	)
	record.call(
		hole.scale == birth_state.get("scale"),
		"native blackhole: guest applies the authoritative native birth scale"
	)
	record.call(
		hole.scale.length() < 0.001,
		"native blackhole: guest birth starts visually collapsed"
	)
	record.call(
		hole.get_node("%BlackHole").visible,
		"native blackhole: guest enables the native blackhole visual"
	)
	var area = hole.get_node("Area2D")
	record.call(
		(
			not hole.is_processing()
			and not hole.is_physics_processing()
			and not area.monitoring
			and not area.monitorable
			and area.collision_layer == 0
			and area.collision_mask == 0
		),
		"native blackhole: guest pocket cannot run suction, collision or scoring callbacks"
	)
	record.call(sync.apply_snapshot(grown), "native blackhole: guest accepts native growth")
	var state = _pocket(_grown, _hole_id)
	record.call(
		(
			hole.global_position == state.position
			and hole.scale == state.scale
			and hole.get_multiplier() == state.multiplier
		),
		"native blackhole: guest pose and multiplier match authoritative native capture"
	)
	var stable_id: int = hole.get_instance_id()
	record.call(sync.apply_snapshot(grown), "native blackhole: repeated native capture is accepted")
	record.call(
		game.pocket_replicas[_hole_id].get_instance_id() == stable_id,
		"native blackhole: repeated state retains the existing replica"
	)
	var score_before = game.score
	var balls_before: int = game.replicas.size()
	await capture.call(
		"32-guest-blackhole",
		"Guest · the host's native BLACK-HOLE replicated without gameplay callbacks"
	)
	record.call(
		(
			game.score == score_before
			and game.replicas.size() == balls_before
			and hole.pulled_objects.is_empty()
		),
		"native blackhole: guest render frames do not consume balls or mutate score"
	)
	record.call(sync.apply_snapshot(baseline), "native blackhole: guest accepts hole removal")
	await mod.get_tree().process_frame
	record.call(
		(
			not game.pocket_replicas.has(_hole_id)
			and not is_instance_valid(hole)
			and game.pockets.size() == 6
		),
		"native blackhole: authoritative removal frees the dynamic replica"
	)
	record.call(
		sync.apply_snapshot(grown) and game.pocket_replicas.has(_hole_id),
		"native blackhole: full resync hydrates an already-grown hole"
	)
	record.call(sync.apply_snapshot(baseline), "native blackhole: guest baseline restored")
	await mod.get_tree().process_frame


func _pocket(snapshot: Dictionary, id: int) -> Dictionary:
	for pocket in snapshot.get("pockets", []):
		if pocket.id == id:
			return pocket
	return {}

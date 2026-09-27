extends RefCounted
## Native ShotsInfo spent-shot visuals (#29 / PERF-015).
## Floor spectator and live tables show one white pip per remaining shot (not max with a
## modulate dim). ShotPip's circle shader overwrites COLOR.rgb from `color`, so modulate
## tweaks are invisible — paint the shader parameter like table_spectator.

const PIP_SPACING := 20.0
const PIP_SCALE := 0.4
const LIT_COLOR := Color.WHITE


static func apply(info: Node, remaining: int, maximum: int, used: int) -> void:
	if not is_instance_valid(info):
		return
	var max_shots: int = maximum if maximum >= remaining else remaining + maxi(used, 0)
	max_shots = maxi(max_shots, 0)
	var used_shots: int = clampi(used, 0, max_shots)
	if remaining >= 0 and remaining <= max_shots:
		used_shots = clampi(max_shots - remaining, 0, max_shots)
	var show_count: int = clampi(remaining, 0, max_shots)
	_enable(info)
	var holder = info.get("pips_holder")
	if holder == null:
		holder = info.get_node_or_null("%PipsHolder")
	if info.get("shots_max") != null:
		info.shots_max = max_shots
	if info.get("shots_used") != null:
		info.shots_used = used_shots
	var pips: Array = []
	if info.get("shot_pips") is Array:
		pips = info.shot_pips
	if pips.size() != show_count:
		for pip in pips:
			if is_instance_valid(pip):
				pip.queue_free()
		if info.get("shot_pips") is Array:
			info.shot_pips.clear()
		else:
			pips.clear()
		if holder != null:
			for child in holder.get_children():
				child.queue_free()
			holder.position = Vector2(-PIP_SPACING * (show_count - 1) * 0.5, 0.0)
		var pip_scene = info.get("pip_scene")
		if pip_scene == null:
			return
		for index in show_count:
			var pip = pip_scene.instantiate()
			if holder != null:
				holder.add_child(pip)
				pip.position = Vector2(index * PIP_SPACING, 0.0)
			else:
				info.add_child(pip)
			if pip is Node2D:
				pip.scale = Vector2.ONE * PIP_SCALE
			if info.get("shot_pips") is Array:
				info.shot_pips.append(pip)
			else:
				pips.append(pip)
	if info.has_method("update_visuals"):
		info.update_visuals(true)
	paint(info)


static func paint(info: Node) -> void:
	if not is_instance_valid(info) or not info.get("shot_pips") is Array:
		return
	for pip in info.shot_pips:
		if not pip is CanvasItem:
			continue
		var material = pip.material
		if material is ShaderMaterial:
			if not material.resource_local_to_scene:
				material = material.duplicate()
				pip.material = material
			material.set_shader_parameter("color", LIT_COLOR)
		# Keep modulate neutral so the shader color is the visible pip.
		if pip.modulate != Color.WHITE:
			pip.modulate = Color.WHITE


static func _enable(info: Node) -> void:
	info.set_process(true)
	info.set_physics_process(true)
	info.process_mode = Node.PROCESS_MODE_INHERIT
	for child in info.find_children("*", "", true, false):
		if child is AnimationPlayer or child is CanvasItem:
			child.set_process(true)
			child.process_mode = Node.PROCESS_MODE_INHERIT

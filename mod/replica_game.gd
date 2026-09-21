extends "res://Game.gd"

var remote_ready = false
var remote_shots = 0
var remote_required_score = 1.0
var remote_max_hp = 3
var remote_daily = false
var replicas: Dictionary = {}
var pocket_replicas: Dictionary = {}
var targets: Dictionary = {}
var interpolation_time = 0.0
var interpolation_duration = 0.05
var last_snapshot_at = 0


func prepare_scene() -> void:
	var cameras = find_children("*", "Camera2D", true, false)
	var camera = cameras[0] if not cameras.is_empty() else null
	if camera != null:
		camera.get_parent().remove_child(camera)
	var info = get_node("PlayerInfo")
	remove_child(info)
	for child in get_children():
		remove_child(child)
		child.free()
	add_child(info)
	if camera != null:
		add_child(camera)
	var ui = Node2D.new()
	ui.name = "UI"
	add_child(ui)
	var empty_shop = Node2D.new()
	empty_shop.name = "Shop"
	ui.add_child(empty_shop)
	var holder = Node2D.new()
	holder.name = "Balls"
	add_child(holder)


func _ready() -> void:
	Global.gameManager = self
	table = (table_rotated_scene if Global.ROTATED_TABLE else table_scene).instantiate()
	# Native customization expects a shop floor even though the guest has no shop.
	var floor_target = Sprite2D.new()
	floor_target.visible = false
	table.add_child(floor_target)
	table.get_node("TableCustomization").shop_floor = floor_target
	add_child(table)
	table.position = Vector2.ZERO
	base_pockets = table.get_pockets().duplicate()
	pockets = base_pockets.duplicate()
	ball_positions = table.get_ball_positions()
	player_ball_position = table.get_player_ball_position()
	_disable_gameplay(table)
	table.score_display_diamond.set_process(true)
	table.shots_info.set_process(true)
	table.hide_end_round()
	playing = false
	balls_spawned = true


func _exit_tree() -> void:
	pass


func _process(delta: float) -> void:
	interpolation_time = minf(interpolation_time + delta, interpolation_duration)
	var weight = interpolation_time / interpolation_duration
	for id in targets:
		var body = replicas[id]
		var target: Dictionary = targets[id]
		body.position = target.from.lerp(target.position, weight)
		body.rotation = lerp_angle(target.from_rotation, target.rotation, weight)


func apply_table(data: Dictionary) -> void:
	var now = Time.get_ticks_msec()
	if last_snapshot_at > 0:
		interpolation_duration = clampf((now - last_snapshot_at) / 1000.0, 0.05, 0.25)
	last_snapshot_at = now
	remote_ready = data.ready
	remote_shots = data.shots
	remote_required_score = data.required_score
	remote_max_hp = data.max_hp
	remote_daily = data.daily
	level_number = data.round
	rounds_played = data.rounds_played
	in_menu = data.in_menu
	in_shop = data.in_shop
	round_ended = data.round_ended
	game_ended = data.game_over
	score = data.score
	player_info.money = data.money
	player_info.hp = data.hp
	table.update_score_display(score, maxf(remote_required_score, 1.0))
	table.update_money(data.money)
	table.update_round_text(str(data.round + 1))
	table.get_hp_info().display_hp(data.hp, data.max_hp, true)
	_update_shots(data.shots)
	_update_pockets(data.pockets)
	var present: Dictionary = {}
	active_balls.clear()
	active_balls_include_untargetable.clear()
	for state in data.balls:
		var id: int = state.id
		present[id] = true
		if not replicas.has(id):
			_create_ball(state)
		var body = replicas[id]
		if body.get_meta("remote_item") != state.item:
			_set_item(body, state.item)
		var destination: Vector2 = state.position
		var start: Vector2 = body.position if not data.ready else destination
		targets[id] = {
			"from": start,
			"position": destination,
			"from_rotation": body.rotation if not data.ready else state.rotation,
			"rotation": state.rotation
		}
		body.position = start
		body.visible = state.visible
		body.alive = state.alive
		body.spawned = state.spawned
		body.falling = state.falling
		body.gone = state.gone
		body.is_passive = state.passive
		body.mass = state.mass
		body.scale_modifier = state.radius_scale
		body.visuals.scale = state.visual_scale
		body.modulate = state.color
		body.transform3d.rotation = state.spin
		var basis: Basis = body.transform3d.transform.basis
		body.ball.material.set_shader_parameter("rotation_x", basis.x)
		body.ball.material.set_shader_parameter("rotation_y", basis.y)
		body.ball.material.set_shader_parameter("rotation_z", basis.z)
		if state.alive and state.visible and not state.player and not state.passive:
			if body.is_targetable():
				active_balls.append(body)
			active_balls_include_untargetable.append(body)
	for id in replicas.keys():
		if not present.has(id):
			var body = replicas[id]
			if body == player_ball:
				player_ball = null
			GlobalPhysics.unregister_ball(body)
			body.queue_free()
			replicas.erase(id)
			targets.erase(id)
	interpolation_time = 0.0


func _update_pockets(states: Array) -> void:
	var present: Dictionary = {}
	pockets.clear()
	for state in states:
		var id: int = state.id
		present[id] = true
		if not pocket_replicas.has(id):
			if state.base_index >= 0:
				pocket_replicas[id] = base_pockets[state.base_index]
			else:
				var hole = hole_scene.instantiate()
				add_child(hole)
				hole.show_hole()
				_disable_gameplay(hole)
				hole.set_meta("remote_hole", true)
				pocket_replicas[id] = hole
			pocket_replicas[id].set_meta("remote_base_index", state.base_index)
		var pocket = pocket_replicas[id]
		pockets.append(pocket)
		pocket.global_position = state.position
		pocket.rotation = state.rotation
		pocket.scale = state.scale
		var score_changed: bool = pocket.extra_score != state.score
		pocket.base_multiplier = state.multiplier
		pocket.extra_multiplier = 0.0
		pocket.extra_score = state.score
		if pocket.closed != state.closed:
			pocket.get_node("%AnimationPlayer").play("close" if state.closed else "open")
			pocket.closed = state.closed
		pocket.set_shield(state.shielded)
		pocket.get_node("SkullIndicator").visible = state.has_held_balls
		pocket.update_label()
		if score_changed:
			pocket.update_extra_score_label()
	for id in pocket_replicas.keys():
		if not present.has(id):
			var pocket = pocket_replicas[id]
			if pocket.get_meta("remote_hole", false):
				pocket.queue_free()
			pocket_replicas.erase(id)


func _create_ball(state: Dictionary) -> void:
	var body = (player_ball_scene if state.player else ball_scene).instantiate()
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	_set_item(body, state.item)
	if state.player:
		player_ball = body
	get_node("Balls").add_child(body)
	body.position = state.position
	body.ball_init()
	_set_item(body, state.item)
	body.spawned = true
	body.set_physics_process(false)
	body.set_process(state.player)
	replicas[state.id] = body


func _set_item(body, item: Dictionary) -> void:
	var native_item = BallItem.new()
	native_item.data = BallDatabase.id_to_ball[item.data]
	if item.mixed != "":
		native_item.mixed_data = BallDatabase.id_to_ball[item.mixed]
	for field in [
		"base_score",
		"temp_extra_score",
		"level",
		"weight_state",
		"flaming",
		"fleeting",
		"star_power",
		"shielded",
		"shield_broken",
		"locked"
	]:
		native_item.set(field, item[field])
	body.set_item(native_item)
	body.ball_item.weight_state = item.weight_state
	body.update_weight()
	body.set_star(item.star_power)
	body.set_flame(item.flaming)
	body.set_shield_broken(item.shield_broken)
	body.set_shield(item.shielded)
	if body.freeze_icon:
		body.freeze_icon.visible = item.locked
	if item.fleeting:
		body.set_fleeting()
	body.set_meta("remote_item", item.duplicate())


func _update_shots(count: int) -> void:
	var info = table.shots_info
	if info.shots_max == count and info.shots_used == 0:
		return
	for pip in info.shot_pips:
		pip.queue_free()
	info.shot_pips.clear()
	info.shots_max = count
	info.shots_used = 0
	for index in count:
		var pip = info.pip_scene.instantiate()
		info.pips_holder.add_child(pip)
		info.shot_pips.append(pip)
	info.update_visuals(true)


func _disable_gameplay(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	if node is CollisionObject2D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is Area2D:
		node.monitoring = false
		node.monitorable = false
	if node is BaseButton:
		node.disabled = true
	if node is Timer:
		node.stop()
	for child in node.get_children():
		_disable_gameplay(child)


func can_shoot():
	return remote_ready and not in_menu and not in_shop and not round_ended and not game_ended


func has_shots():
	return remote_shots > 0


func get_shots_left():
	return remote_shots


func get_required_score():
	return remote_required_score


func get_max_hp():
	return remote_max_hp


func is_daily():
	return remote_daily


func select_ball(_ball, _item, _from_shop = false):
	pass


func unselect_ball(_ball, _item, _from_shop = false):
	pass


func force_round_end():
	pass


func shoot(_impulse):
	pass

extends "res://Game.gd"

const PlayerInventory = preload("player_inventory_sync.gd")

var remote_ready = false
var remote_shots = 0
var remote_required_score = 1.0
var remote_max_hp = 3
var remote_daily = false
var remote_rotated = false
var replicas: Dictionary = {}
var pocket_replicas: Dictionary = {}
var corrections: Dictionary = {}
var remote_round_reward = 0.0
var _inventory_state: Dictionary = {}


func prepare_scene() -> void:
	var floating_ui = get_node("UI/FloatingUI")
	floating_ui.get_parent().remove_child(floating_ui)
	var native_shop = get_node("UI/Shop")
	var source_floor: Sprite2D = native_shop.get_node("%ShopFloor")
	var floor_target: Sprite2D = source_floor.duplicate()
	var floor_transform = source_floor.transform
	var floor_parent = source_floor.get_parent()
	while floor_parent != self:
		if floor_parent is Node2D:
			floor_transform = floor_parent.transform * floor_transform
		floor_parent = floor_parent.get_parent()
	floor_target.transform = floor_transform
	var posters = native_shop.posters
	native_shop.get_parent().remove_child(native_shop)
	native_shop.set_script(
		load(get_script().resource_path.get_base_dir().path_join("native_shop.gd"))
	)
	native_shop.posters = posters
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
	ui.add_child(floating_ui)
	ui.add_child(floor_target)
	ui.add_child(native_shop)
	var holder = Node2D.new()
	holder.name = "Balls"
	add_child(holder)


func _ready() -> void:
	Global.gameManager = self
	table = (table_rotated_scene if remote_rotated else table_scene).instantiate()
	table.get_node("TableCustomization").shop_floor = get_node("UI/ShopFloor")
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
	table.get_graveyard()._process(0.0)
	playing = false
	balls_spawned = true


func _exit_tree() -> void:
	pass


func _process(_delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	for id in replicas:
		var body = replicas[id]
		if body.freeze:
			continue
		if corrections.has(id):
			var correction: Vector2 = corrections[id] * (1.0 - exp(-12.0 * delta))
			body.global_position += correction
			corrections[id] -= correction
			if corrections[id].length_squared() < 0.25:
				corrections.erase(id)
		if body.linear_velocity.length() > 2500.0:
			body.linear_velocity = body.linear_velocity.limit_length(2500.0)
		elif body.linear_velocity.length() < 10.0 and body.constant_force == Vector2.ZERO:
			body.linear_velocity = Vector2.ZERO
			body.angular_velocity = 0.0
		body._anti_tunnel_walls(delta)
	if is_instance_valid(player_ball) and not player_ball.freeze:
		player_ball._anti_tunnel_balls(delta)


func begin_shot(vector: Vector2) -> bool:
	if not is_instance_valid(player_ball) or not player_ball.alive or player_ball.falling:
		return false
	remote_ready = false
	player_ball.pause_cancel_shot()
	player_ball.freeze = false
	player_ball.sleeping = false
	player_ball.linear_velocity = vector.limit_length(200.0) * 12.5 / player_ball.mass
	player_ball.angular_velocity = 0.0
	corrections.clear()
	return true


func apply_table(data: Dictionary) -> void:
	if (data.in_shop != in_shop or data.in_menu) and is_instance_valid(selected_ball):
		unselect_ball(selected_ball, selected_ball_item)
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
	var result: Dictionary = data.results
	round_won = result.won
	score_this_round = result.score
	extra_money_earned = result.bonus_money
	money_last_round = result.money_before
	remote_round_reward = result.round_reward
	balls_pocketed = result.balls_pocketed
	money_earned = result.money_earned
	game_time = result.game_time
	get_node("UI/FloatingUI").show_time(game_time)
	score = data.score
	player_info.money = data.money
	player_info.hp = data.hp
	if _inventory_state != data.inventory:
		PlayerInventory.apply(player_info, data.inventory, BallDatabase)
		_inventory_state = data.inventory.duplicate(true)
	table.global_position = data.table_position
	if is_instance_valid(shop) and shop.has_method("apply_state") and shop.is_open:
		Global.camera.move(shop.get_camera_target())
	else:
		Global.camera.move(data.table_position)
	table.update_score_display(score, maxf(remote_required_score, 1.0))
	table.update_money(data.money)
	table.update_round_text(tr("UI_ROUND") + " " + str(data.round + 1))
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
		var simulate: bool = (
			state.alive
			and state.spawned
			and not state.falling
			and not state.gone
			and not state.passive
			and not data.in_shop
		)
		var error: Vector2 = state.position - body.global_position
		if data.ready or not simulate or error.length() > body.get_radius() * 8.0:
			body.global_position = state.position
			body.rotation = state.rotation
			body.transform3d.rotation = state.spin
			corrections.erase(id)
		else:
			corrections[id] = error
		body.freeze = not simulate
		body.collision_shape.disabled = not simulate
		body.sleeping = false
		body.linear_velocity = state.velocity
		body.angular_velocity = state.angular_velocity
		body.linear_damp = state.linear_damp
		body.angular_damp = state.angular_damp
		body.constant_force = state.force if simulate else Vector2.ZERO
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
		var basis: Basis = body.transform3d.global_transform.basis
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
			if selected_ball == body:
				unselect_ball(body, body.ball_item)
			GlobalPhysics.unregister_ball(body)
			body.queue_free()
			replicas.erase(id)
			corrections.erase(id)


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
	if not state.player:
		body.set_script(
			load(get_script().resource_path.get_base_dir().path_join("replica_ball.gd"))
		)
	body.freeze = true
	body.set_meta("together_replica", true)
	_set_item(body, state.item)
	if state.player:
		player_ball = body
	get_node("Balls").add_child(body)
	body.global_position = state.position
	body.ball_init()
	_set_item(body, state.item)
	body.spawned = true
	body.set_physics_process(false)
	body.set_process(true)
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
	body.ball.material.set_shader_parameter("tex", native_item.data.texture)
	if native_item.mixed_data != null:
		body.ball.material.set_shader_parameter("mixed_tex", native_item.mixed_data.texture)
	body.flash_spr.material = body.flash_spr.material.duplicate()
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
	body.flash_alpha = 0.0
	body.flash_spr.material.set_shader_parameter("alpha", 0.0)
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
	if node is CollisionObject2D and not node is StaticBody2D:
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
	return (
		remote_ready
		and not in_menu
		and not in_shop
		and not round_ended
		and not game_ended
		and not UIManager.is_popup_open()
	)


func has_shots():
	return remote_shots > 0


func get_shots_left():
	return remote_shots


func get_required_score():
	return remote_required_score


func get_round_win_reward():
	return remote_round_reward


func get_max_hp():
	return remote_max_hp


func is_daily():
	return remote_daily


func select_ball(body, item, from_shop = false):
	if (in_shop and not from_shop) or in_menu or selected_ball == body:
		return
	selected_ball = body
	selected_ball_item = item
	Global.set_hovered_item(body, item)


func unselect_ball(body, item, _from_shop = false):
	if selected_ball == body:
		selected_ball = null
		Global.unset_hovered_item(body, item)


func force_round_end():
	pass


func shoot(_impulse):
	pass

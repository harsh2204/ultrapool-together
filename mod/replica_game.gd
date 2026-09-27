extends "res://Game.gd"

const PlayerInventory = preload("player_inventory_sync.gd")
const TableSync = preload("table_sync.gd")
const ReplicaFx = preload("replica_fx.gd")
const CueCatalog = preload("cue_catalog.gd")
const BallLevelFx = preload("ball_level_fx.gd")
const ShotsPips = preload("shots_pips.gd")
const TableEffectsView = preload("table_effects_view.gd")
const TableVisualFxView = preload("table_visual_fx_view.gd")

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
var _hud_state: Dictionary = {}
var _pocket_states: Array = []
var _ball_bases: Dictionary = {}
var _fx = ReplicaFx.new()
var effects_view = TableEffectsView.new()
var _visual_fx_view = TableVisualFxView.new()


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
	_enable_shots_info(table.shots_info)
	_enable_potted_rail(table.get_graveyard())
	# Doors AnimationPlayer must run for the guest round-start open (#15).
	var doors = table.get_node_or_null("Doors")
	if doors != null:
		var doors_anim = doors.get_node_or_null("AnimationPlayer")
		if doors_anim != null:
			doors_anim.set_process(true)
			doors_anim.process_mode = Node.PROCESS_MODE_INHERIT
	table.hide_end_round()
	table.get_graveyard()._process(0.0)
	# Enable native aim chrome (cue / prediction / reticle) on the local guest turn.
	# Host Game sets this during play; keeping it false suppresses shoot_ui (#18).
	playing = true
	balls_spawned = true
	effects_view.setup(self, Global.SCENE_GAME)
	_visual_fx_view.setup(self, Global.SCENE_GAME)


func _exit_tree() -> void:
	_fx.clear()
	effects_view.dispose()
	_visual_fx_view.clear()


func _process(_delta: float) -> void:
	_update_potted_rail_hover()
	effects_view.tick()
	_visual_fx_view.tick()


func _physics_process(delta: float) -> void:
	for id in replicas:
		var body = replicas[id]
		if body.freeze or (body.sleeping and not corrections.has(id)):
			continue
		if corrections.has(id):
			var correction: Vector2 = corrections[id] * (1.0 - exp(-12.0 * delta))
			body.global_position += correction
			corrections[id] -= correction
			if corrections[id].length_squared() < 0.25:
				corrections.erase(id)
		var speed_squared: float = body.linear_velocity.length_squared()
		if speed_squared > 2500.0 * 2500.0:
			body.linear_velocity = body.linear_velocity.limit_length(2500.0)
		elif speed_squared < 100.0 and body.constant_force == Vector2.ZERO:
			if body.linear_velocity != Vector2.ZERO:
				body.linear_velocity = Vector2.ZERO
			if body.angular_velocity != 0.0:
				body.angular_velocity = 0.0
		# Native ball physics only needs supplemental raycasts above this speed;
		# ordinary rigid-body contacts handle slow movement.
		if speed_squared > Ball.BALL_SUBSTEP_VELOCITY_THRESHOLD_SQ:
			body._anti_tunnel_walls(delta)
	if (
		is_instance_valid(player_ball)
		and not player_ball.freeze
		and not player_ball.sleeping
		and player_ball.linear_velocity.length_squared() > Ball.BALL_SUBSTEP_VELOCITY_THRESHOLD_SQ
	):
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
	_fx.observe_shot()
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
	# Keep native PlayerBall aim/cue/reticle eligible outside shop/menu (#18).
	playing = not data.in_shop and not data.in_menu and not data.game_over
	var result: Dictionary = data.results
	round_won = result.won
	score_this_round = result.score
	extra_money_earned = result.bonus_money
	money_last_round = result.money_before
	remote_round_reward = result.round_reward
	balls_pocketed = result.balls_pocketed
	money_earned = result.money_earned
	game_time = result.game_time
	score = data.score
	if player_info.money != data.money:
		player_info.money = data.money
	if player_info.hp != data.hp:
		player_info.hp = data.hp
	if _inventory_state != data.inventory:
		PlayerInventory.apply(player_info, data.inventory, BallDatabase)
		_inventory_state = data.inventory.duplicate(true)
		_refresh_inventory_visuals()
	if table.global_position != data.table_position:
		table.global_position = data.table_position
		_pocket_states.clear()
	var camera_target: Vector2 = data.table_position
	if is_instance_valid(shop) and shop.has_method("apply_state") and shop.is_open:
		camera_target = shop.get_camera_target()
	if Global.camera.move_position != camera_target:
		Global.camera.move(camera_target)
	var locale_changed: bool = _hud_state.get("locale") != TranslationServer.get_locale()
	_update_hud(data, locale_changed)
	_update_pockets(data.pockets, locale_changed)
	# GAP-007: native effect presentation has no guest gameplay callbacks.
	var effect_epoch = "%s:%s" % [data.scene_id, data.rounds_played]
	effects_view.apply(data.get("effects", {}), Vector2.ZERO, effect_epoch)
	effects_view.apply_pockets(data.get("effects", {}), pocket_replicas)
	_visual_fx_view.apply(data.get("visual_fx", {}), Vector2.ZERO, effect_epoch)
	_fx.begin_apply()
	_fx.observe_round(table, data.rounds_played, data.in_shop)
	_update_aim_reminder(data.ready and playing)
	var present: Dictionary = {}
	active_balls.clear()
	active_balls_include_untargetable.clear()
	for state in data.balls:
		var id: int = state.id
		present[id] = true
		var created: bool = not replicas.has(id)
		if created:
			_create_ball(state)
		var body = replicas[id]
		_fx.observe_ball(body, state, created)
		var item_changed: bool = body.get_meta("remote_item") != state.item
		if item_changed:
			_set_item(body, state.item)
		# Local-predictive aim: do not snap the cue while the guest is drawing (#18).
		var aiming_local: bool = state.player and bool(body.get("preparing_shot"))
		var simulate: bool = (
			state.alive
			and state.spawned
			and not state.falling
			and not state.gone
			and not state.passive
			and not data.in_shop
		)
		var error: Vector2 = state.position - body.global_position
		var spin_changed = false
		if not aiming_local:
			if data.ready or not simulate or error.length() > body.get_radius() * 8.0:
				if body.global_position != state.position:
					body.global_position = state.position
				if body.rotation != state.rotation:
					body.rotation = state.rotation
				if body.transform3d.rotation != state.spin:
					body.transform3d.rotation = state.spin
					spin_changed = true
				corrections.erase(id)
			elif error != Vector2.ZERO:
				corrections[id] = error
			else:
				corrections.erase(id)
		else:
			corrections.erase(id)
		# Compare live values: moving replicas predict between snapshots and must still
		# reconcile even when two authoritative samples contain identical values.
		if body.freeze != (not simulate):
			body.freeze = not simulate
		if body.collision_shape.disabled != (not simulate):
			body.collision_shape.disabled = not simulate
		if not aiming_local:
			if body.linear_velocity != state.velocity:
				body.linear_velocity = state.velocity
			if body.angular_velocity != state.angular_velocity:
				body.angular_velocity = state.angular_velocity
		if body.linear_damp != state.linear_damp:
			body.linear_damp = state.linear_damp
		if body.angular_damp != state.angular_damp:
			body.angular_damp = state.angular_damp
		var force: Vector2 = state.force if simulate and not aiming_local else Vector2.ZERO
		if body.constant_force != force:
			body.constant_force = force
		if (
			simulate
			and not aiming_local
			and body.sleeping
			and (
				state.velocity != Vector2.ZERO
				or state.angular_velocity != 0.0
				or force != Vector2.ZERO
			)
		):
			body.sleeping = false
		if body.visible != state.visible:
			body.visible = state.visible
		body.alive = state.alive
		body.spawned = state.spawned
		body.falling = state.falling
		body.gone = state.gone
		body.is_passive = state.passive
		if body.mass != state.mass:
			body.mass = state.mass
		if body.scale_modifier != state.radius_scale:
			body.scale_modifier = state.radius_scale
		if body.visuals.scale != state.visual_scale:
			body.visuals.scale = state.visual_scale
		if body.modulate != state.color:
			body.modulate = state.color
		body.set_process(simulate or state.player)
		var basis: Basis = body.transform3d.global_transform.basis
		if item_changed or spin_changed or _ball_bases.get(id) != basis:
			body.ball.material.set_shader_parameter("rotation_x", basis.x)
			body.ball.material.set_shader_parameter("rotation_y", basis.y)
			body.ball.material.set_shader_parameter("rotation_z", basis.z)
			_ball_bases[id] = basis
		if state.alive and state.visible and not state.player and not state.passive:
			if body.is_targetable():
				active_balls.append(body)
			active_balls_include_untargetable.append(body)
	_fx.finish_apply(present)
	# CUSTOM CUES (#20): tint the guest replica cue for the current turn owner.
	if is_instance_valid(player_ball):
		var controller = get_parent().get_parent() if get_parent() else null
		if controller != null:
			var lobby: Dictionary = controller.get("lobby") if controller.get("lobby") is Dictionary else {}
			var turn_owner: int = int(controller.get("turn_owner"))
			CueCatalog.apply(player_ball, CueCatalog.cue_for_player(lobby, turn_owner))
		# Tint must not revive the packed rest-pose shaft (#18).
		if not bool(player_ball.get("preparing_shot")) and player_ball.has_method("_hide_cue_pivot"):
			player_ball._hide_cue_pivot()
		if controller != null:
			player_ball.set("together_controller", controller)
	_sync_potted_rail(data.balls)
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
			_ball_bases.erase(id)


func _update_hud(data: Dictionary, locale_changed: bool) -> void:
	# Keep only display inputs, not an entire snapshot. A replacement replica starts
	# with an empty cache, so even zero-valued initial state hydrates the native UI.
	var time_seconds = floori(game_time)
	if locale_changed or _hud_state.get("time_seconds") != time_seconds:
		get_node("UI/FloatingUI").show_time(game_time)
	if (
		locale_changed
		or _hud_state.get("score") != score
		or _hud_state.get("required_score") != remote_required_score
	):
		table.update_score_display(score, maxf(remote_required_score, 1.0))
	if locale_changed or _hud_state.get("money") != data.money:
		table.update_money(data.money)
	if locale_changed or _hud_state.get("round") != data.round:
		table.update_round_text(tr("UI_ROUND") + " " + str(data.round + 1))
	if _hud_state.get("hp") != data.hp or _hud_state.get("max_hp") != data.max_hp:
		table.get_hp_info().display_hp(data.hp, data.max_hp, true)
	var shots_max: int = int(data.get("shots_max", data.shots))
	var shots_used: int = int(data.get("shots_used", 0))
	_update_shots(data.shots, shots_max, shots_used)
	for field in ["score", "required_score", "money", "round", "hp", "max_hp"]:
		_hud_state[field] = data[field]
	_hud_state.time_seconds = time_seconds
	_hud_state.locale = TranslationServer.get_locale()
	_hud_state.shots = data.shots
	_hud_state.shots_max = shots_max
	_hud_state.shots_used = shots_used


func _update_pockets(states: Array, locale_changed: bool = false) -> void:
	if not locale_changed and _pocket_states == states:
		return
	var present: Dictionary = {}
	pockets.clear()
	for state in states:
		var id: int = state.id
		present[id] = true
		var created: bool = not pocket_replicas.has(id)
		if created:
			if state.base_index >= 0:
				if state.base_index >= base_pockets.size():
					push_warning(
						(
							"Together: pocket base_index %d out of range (%d); skipping"
							% [state.base_index, base_pockets.size()]
						)
					)
					continue
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
		if pocket.global_position != state.position:
			pocket.global_position = state.position
		if pocket.rotation != state.rotation:
			pocket.rotation = state.rotation
		if pocket.scale != state.scale:
			pocket.scale = state.scale
		var score_changed: bool = pocket.extra_score != state.score
		var multiplier_changed: bool = (
			pocket.base_multiplier != state.multiplier or pocket.extra_multiplier != 0.0
		)
		pocket.base_multiplier = state.multiplier
		pocket.extra_multiplier = 0.0
		pocket.extra_score = state.score
		if pocket.closed != state.closed:
			pocket.get_node("%AnimationPlayer").play("close" if state.closed else "open")
			pocket.closed = state.closed
		if created or pocket.shielded != state.shielded:
			pocket.set_shield(state.shielded)
		pocket.get_node("SkullIndicator").visible = state.has_held_balls
		if multiplier_changed or locale_changed or created:
			pocket.update_label()
		if score_changed or locale_changed or created:
			pocket.update_extra_score_label()
	for id in pocket_replicas.keys():
		if not present.has(id):
			var pocket = pocket_replicas[id]
			if pocket.get_meta("remote_hole", false):
				pocket.queue_free()
			pocket_replicas.erase(id)
	_pocket_states = states.duplicate(true)


func _create_ball(state: Dictionary) -> void:
	var body = (player_ball_scene if state.player else ball_scene).instantiate()
	if not state.player:
		body.set_script(
			load(get_script().resource_path.get_base_dir().path_join("replica_ball.gd"))
		)
	else:
		# Host adapter swaps PlayerBall → native_player; guests must too or CuePivot stays
		# at the packed rest pose and CueCatalog tint makes that shaft look "solid" (#18).
		_install_native_player(body)
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
	# ball.tscn packs static/spark visible=true; host spawn clears it, guests must too (#32).
	BallLevelFx.hide_default_table_fx(body)
	if state.player and body.has_method("_hide_cue_pivot"):
		body._hide_cue_pivot()
	replicas[state.id] = body


func _install_native_player(body: Node) -> void:
	var script = load(get_script().resource_path.get_base_dir().path_join("native_player.gd"))
	var values = {}
	for property in body.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = body.get(property.name)
	body.set_script(script)
	for property in body.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and values.has(property.name):
			body.set(property.name, values[property.name])
	var controller = get_parent().get_parent() if get_parent() else null
	body.set("together_controller", controller)


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
	# Native never draws star chrome on the cue ball (#31). Object-ball star_power only.
	var is_cue: bool = body == player_ball or item.get("data") == "PLAYER"
	if is_cue:
		if body.has_method("set_star"):
			body.set_star(false)
		_hide_star_chrome(body)
	else:
		body.set_star(bool(item.star_power))
		if not bool(item.star_power):
			_hide_star_chrome(body)
	body.set_flame(item.flaming)
	body.set_shield_broken(item.shield_broken)
	body.set_shield(item.shielded)
	if body.freeze_icon:
		body.freeze_icon.visible = item.locked
	if item.fleeting:
		body.set_fleeting()
	body.flash_alpha = 0.0
	body.flash_spr.material.set_shader_parameter("alpha", 0.0)
	# Shop Upgradebar + packed table spark gate (#32).
	BallLevelFx.apply_upgrade_badge(body, int(item.level), BallLevelFx.start_level_of(native_item))
	BallLevelFx.hide_default_table_fx(body)
	body.set_meta("remote_item", item.duplicate())


func _hide_star_chrome(body: Node) -> void:
	if not is_instance_valid(body):
		return
	var visuals = body.get("visuals")
	if not is_instance_valid(visuals):
		return
	for path in ["static/star_indicator", "static/StarEffect", "static/spark"]:
		var node = visuals.get_node_or_null(path)
		if node is CanvasItem and node.visible:
			node.visible = false


func _enable_shots_info(info: Node) -> void:
	if not is_instance_valid(info):
		return
	info.set_process(true)
	info.set_physics_process(true)
	info.process_mode = Node.PROCESS_MODE_INHERIT
	# prepare_scene/_disable_gameplay clears process on AnimationPlayer/pips; restore (#29).
	for child in info.find_children("*", "", true, false):
		if child is AnimationPlayer or child is CanvasItem:
			child.set_process(true)
			child.process_mode = Node.PROCESS_MODE_INHERIT


func _update_shots(remaining: int, maximum: int, used: int) -> void:
	var info = table.shots_info
	if not is_instance_valid(info):
		return
	# Native / spectator show one white pip per remaining shot. Modulate dimming is a
	# no-op on ShotPip's circle shader (COLOR.rgb comes from shader `color`) (#29).
	var max_shots: int = maximum if maximum >= remaining else remaining + maxi(used, 0)
	var used_shots: int = clampi(used, 0, max_shots)
	if remaining >= 0 and remaining <= max_shots:
		used_shots = clampi(max_shots - remaining, 0, max_shots)
	var show_count: int = clampi(remaining, 0, max_shots)
	if (
		_hud_state.get("shots_max") == max_shots
		and _hud_state.get("shots_used") == used_shots
		and _hud_state.get("shots") == remaining
		and info.shots_max == max_shots
		and info.shots_used == used_shots
		and info.shot_pips.size() == show_count
	):
		ShotsPips.paint(info)
		return
	ShotsPips.apply(info, remaining, max_shots, used_shots)


func _refresh_inventory_visuals() -> void:
	# Inventory tickets/cubes/passives live on PlayerInfo; native snack counters and the
	# CubesButton live on the shop inventory HUD. Drive the shop HUD only (#33 / PERF-015/020).
	# Removed dead update_cubes / update_build has_method fallbacks (no such native APIs).
	if is_instance_valid(shop) and shop.has_method("refresh_inventory_hud"):
		shop.refresh_inventory_hud()



func _update_aim_reminder(show_aim: bool) -> void:
	if not is_instance_valid(table):
		return
	var reminder = table.get_node_or_null("%AimReminder")
	if reminder == null:
		reminder = table.find_child("AimReminder", true, false)
	if reminder is CanvasItem:
		reminder.visible = show_aim


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

func _enable_potted_rail(rail: Node) -> void:
	if rail == null:
		return
	_resume_rail_node(rail)
	rail._process(0.0)


func _resume_rail_node(node: Node) -> void:
	node.set_process(true)
	node.set_process_input(true)
	node.set_process_unhandled_input(true)
	if node is Area2D:
		node.monitoring = true
		node.monitorable = true
	if node is CollisionObject2D:
		node.input_pickable = true
	for child in node.get_children():
		_resume_rail_node(child)


func _sync_potted_rail(states: Array) -> void:
	pocketed_balls.clear()
	for state in states:
		if not TableSync.ball_on_potted_rail(state):
			continue
		var body = replicas.get(state.id)
		if is_instance_valid(body):
			pocketed_balls.append(body)
	var rail = table.get_graveyard()
	if is_instance_valid(rail):
		rail._process(0.0)

func _update_potted_rail_hover() -> void:
	if in_shop or in_menu or UIManager.is_popup_open():
		return
	var hit = _potted_rail_ball_at(get_global_mouse_position())
	if hit != null:
		select_ball(hit, hit.ball_item)
		return
	if is_instance_valid(selected_ball) and _is_potted_rail_body(selected_ball):
		unselect_ball(selected_ball, selected_ball_item)

func _is_potted_rail_body(body) -> bool:
	return (
		is_instance_valid(body)
		and body.visible
		and not body.is_player
		and not body.alive
		and body.ball_item != null
	)

func _potted_rail_ball_at(mouse: Vector2):
	var best = null
	var best_d2 = INF
	for body in replicas.values():
		if not _is_potted_rail_body(body):
			continue
		var radius = body.get_radius() if body.has_method("get_radius") else 12.0
		var scale = body.visuals.scale.x if is_instance_valid(body.visuals) else 1.0
		var hover_r = maxf(radius * maxf(scale, 0.35), 10.0)
		var d2 = body.global_position.distance_squared_to(mouse)
		if d2 <= hover_r * hover_r and d2 < best_d2:
			best_d2 = d2
			best = body
	return best



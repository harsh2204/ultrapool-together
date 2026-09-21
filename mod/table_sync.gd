extends Node

const MAX_BALLS = 128
const ITEM_NUMBERS = {
	"base_score": [-1.0e18, 1.0e18],
	"temp_extra_score": [-1.0e18, 1.0e18],
	"level": [1, 1000000],
	"weight_state": [0, 3]
}
const ITEM_FLAGS = ["flaming", "fleeting", "star_power", "shielded", "shield_broken", "locked"]
const TABLE_FLAGS = ["ready", "in_menu", "in_shop", "round_ended", "game_over", "daily"]
const BALL_FLAGS = ["player", "visible", "alive", "spawned", "falling", "gone", "passive"]

var _guest = false
var _replica = null
var _scene_key = ""
var _saved_global: Dictionary = {}
var _saved_nodes: Array = []
var _saved_shapes: Array = []
var _saved_balls: Array = []
var _saved_tutorial: Dictionary = {}


func capture() -> Dictionary:
	var game = get_node("/root/Global").gameManager
	if not is_instance_valid(game) or not is_instance_valid(game.table):
		return {"available": false}
	var data = {
		"available": true,
		"scene_id": game.get_instance_id(),
		"round": game.level_number,
		"rounds_played": game.rounds_played,
		"ready": game.can_shoot() and game.has_shots() and not game.balls_moving,
		"in_menu": game.in_menu,
		"in_shop": game.in_shop,
		"round_ended": game.round_ended,
		"game_over": game.game_ended,
		"score": game.score,
		"required_score": game.get_required_score(),
		"shots": game.get_shots_left(),
		"money": game.player_info.money,
		"hp": game.player_info.hp,
		"max_hp": game.get_max_hp(),
		"daily": game.is_daily(),
		"balls": [],
		"pockets": []
	}
	var bodies = game.balls.duplicate()
	if is_instance_valid(game.player_ball) and not bodies.has(game.player_ball):
		bodies.append(game.player_ball)
	for body in bodies:
		if (
			not is_instance_valid(body)
			or not body.is_inside_tree()
			or body.ball_item == null
			or not body.inited
		):
			continue
		var item = body.ball_item
		var item_data = {
			"data": str(item.data.id),
			"mixed": str(item.mixed_data.id) if item.mixed_data != null else ""
		}
		for field in ITEM_NUMBERS:
			item_data[field] = item.get(field)
		for field in ITEM_FLAGS:
			item_data[field] = item.get(field)
		data.balls.append(
			{
				"id": body.get_instance_id(),
				"player": body == game.player_ball,
				"item": item_data,
				"position": body.global_position,
				"rotation": body.rotation,
				"spin": body.transform3d.rotation,
				"visual_scale": body.visuals.scale,
				"radius_scale": body.scale_modifier,
				"mass": body.mass,
				"color": body.modulate,
				"visible": body.visible,
				"alive": body.alive,
				"spawned": body.spawned,
				"falling": body.falling,
				"gone": body.gone,
				"passive": body.is_passive
			}
		)
	var fixed_pockets = game.table.get_node("Pockets").get_children()
	for pocket in game.pockets:
		data.pockets.append(
			{
				"id": pocket.get_instance_id(),
				"base_index": fixed_pockets.find(pocket),
				"position": pocket.global_position,
				"rotation": pocket.rotation,
				"scale": pocket.scale,
				"multiplier": pocket.get_multiplier(),
				"score": pocket.extra_score,
				"closed": pocket.closed,
				"shielded": pocket.shielded,
				"has_held_balls": not pocket.held_balls.is_empty()
			}
		)
	return data


func begin_guest() -> bool:
	if _guest:
		return true
	var global_node = get_node("/root/Global")
	var current_scene = get_tree().current_scene
	if (
		global_node.transitioning
		or global_node.in_run
		or current_scene == null
		or current_scene.scene_file_path != global_node.SCENE_MENU.resource_path
	):
		return false
	_guest = true
	for key in [
		"gameManager",
		"camera",
		"in_run",
		"IS_HOVER_SUPPRESSED",
		"hovered_item",
		"hovered_item_object",
		"sticker_manager"
	]:
		_saved_global[key] = global_node.get(key)
	_saved_shapes = get_node("/root/GlobalPhysics").shapes.duplicate()
	_saved_balls = get_node("/root/GlobalPhysics").balls.duplicate()
	_suspend(current_scene)
	_suspend(get_node("/root/UIManager"))
	_suspend(get_node("/root/TutorialManager"))
	var tutorial = get_node("/root/TutorialManager")
	_saved_tutorial = {"ENABLED": tutorial.ENABLED, "active_popup": tutorial.active_popup}
	tutorial.ENABLED = false
	tutorial.active_popup = null
	global_node.IS_HOVER_SUPPRESSED = true
	global_node.hovered_item = null
	global_node.hovered_item_object = null
	global_node.gameManager = null
	return true


func end_guest() -> void:
	if not _guest:
		return
	_clear_replica()
	var global_node = get_node("/root/Global")
	for key in _saved_global:
		global_node.set(key, _saved_global[key])
	var physics = get_node("/root/GlobalPhysics")
	physics.shapes.assign(_saved_shapes.filter(func(shape): return is_instance_valid(shape)))
	physics.balls.assign(_saved_balls.filter(func(ball): return is_instance_valid(ball)))
	var tutorial = get_node("/root/TutorialManager")
	for key in _saved_tutorial:
		tutorial.set(key, _saved_tutorial[key])
	for state in _saved_nodes:
		var node = state.node
		if not is_instance_valid(node):
			continue
		node.process_mode = state.process_mode
		if state.has("visible"):
			node.visible = state.visible
		if state.has("freeze"):
			node.freeze = state.freeze
	if is_instance_valid(global_node.camera):
		global_node.camera.make_current()
	_saved_nodes.clear()
	_saved_global.clear()
	_saved_shapes.clear()
	_saved_balls.clear()
	_saved_tutorial.clear()
	_guest = false


func apply_snapshot(data: Dictionary) -> bool:
	if not _guest or not _valid_snapshot(data):
		return false
	if not data.available:
		_clear_replica()
		return true
	var key = "%s:%s" % [data.scene_id, data.rounds_played]
	if key == _scene_key:
		for body in data.balls:
			if (
				_replica.replicas.has(body.id)
				and _replica.replicas[body.id].is_player != body.player
			):
				return false
		for pocket in data.pockets:
			if (
				_replica.pocket_replicas.has(pocket.id)
				and (
					_replica.pocket_replicas[pocket.id].get_meta("remote_base_index")
					!= pocket.base_index
				)
			):
				return false
	if key != _scene_key:
		_clear_replica()
		var global_node = get_node("/root/Global")
		var scene = global_node.SCENE_GAME.instantiate()
		var exports: Dictionary = {}
		for property in scene.get_property_list():
			if (
				property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE
				and property.usage & PROPERTY_USAGE_STORAGE
			):
				exports[property.name] = scene.get(property.name)
		scene.set_script(
			load(get_script().resource_path.get_base_dir().path_join("replica_game.gd"))
		)
		for property in exports:
			scene.set(property, exports[property])
		scene.remote_daily = data.daily
		scene.remote_max_hp = data.max_hp
		scene.prepare_scene()
		global_node.gameManager = scene
		get_node("/root/GlobalPhysics").clear_walls()
		get_node("/root/GlobalPhysics").clear_balls()
		add_child(scene)
		_replica = scene
		_scene_key = key
		global_node.camera.make_current()
	_replica.apply_table(data)
	return true


func ready_for_input() -> bool:
	if not is_instance_valid(_replica) or not _replica.can_shoot():
		return false
	var cue = _replica.player_ball
	return is_instance_valid(cue) and cue.visible and cue.alive and cue.spawned and not cue.falling


func _clear_replica() -> void:
	if is_instance_valid(_replica):
		remove_child(_replica)
		_replica.free()
	_replica = null
	_scene_key = ""
	get_node("/root/Global").gameManager = null
	if _saved_global.has("camera"):
		get_node("/root/Global").camera = _saved_global.camera
		get_node("/root/Global").sticker_manager = _saved_global.sticker_manager
	get_node("/root/GlobalPhysics").clear_walls()
	get_node("/root/GlobalPhysics").clear_balls()


func _suspend(node: Node) -> void:
	if node == null:
		return
	var state = {"node": node, "process_mode": node.process_mode}
	if node is CanvasItem or node is CanvasLayer:
		state.visible = node.visible
		node.visible = false
	if node is RigidBody2D:
		state.freeze = node.freeze
		node.freeze = true
	_saved_nodes.append(state)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_suspend(child)


func _valid_snapshot(data: Dictionary) -> bool:
	if typeof(data.get("available")) != TYPE_BOOL:
		return false
	if not data.available:
		return data.size() == 1
	for key in TABLE_FLAGS:
		if typeof(data.get(key)) != TYPE_BOOL:
			return false
	for key in ["scene_id", "round", "rounds_played", "shots", "hp", "max_hp"]:
		if typeof(data.get(key)) != TYPE_INT:
			return false
	if (
		data.scene_id <= 0
		or not _number(data.round, 0, 1000000)
		or not _number(data.rounds_played, 0, 1000000)
		or not _number(data.shots, 0, 20)
		or not _number(data.hp, 0, 100)
		or not _number(data.max_hp, 1, 100)
	):
		return false
	for key in ["score", "required_score", "money"]:
		if not _number(data.get(key), -1.0e18, 1.0e18):
			return false
	if (
		not data.get("balls") is Array
		or data.balls.size() > MAX_BALLS
		or not data.get("pockets") is Array
		or data.pockets.size() > 16
	):
		return false
	var ids: Dictionary = {}
	var cue_count = 0
	for body in data.balls:
		if not body is Dictionary or not _valid_ball(body) or ids.has(body.id):
			return false
		ids[body.id] = true
		cue_count += int(body.player)
	if cue_count > 1:
		return false
	var pocket_ids: Dictionary = {}
	var base_indices: Dictionary = {}
	var holes = 0
	for pocket in data.pockets:
		if not pocket is Dictionary or not _valid_pocket(pocket) or pocket_ids.has(pocket.id):
			return false
		pocket_ids[pocket.id] = true
		if pocket.base_index < 0:
			holes += 1
		elif base_indices.has(pocket.base_index):
			return false
		else:
			base_indices[pocket.base_index] = true
	if holes > 10 or base_indices.size() != 6:
		return false
	return true


func _valid_pocket(pocket: Dictionary) -> bool:
	if (
		typeof(pocket.get("id")) != TYPE_INT
		or pocket.id <= 0
		or typeof(pocket.get("base_index")) != TYPE_INT
		or not _number(pocket.base_index, -1, 5)
	):
		return false
	for key in ["closed", "shielded", "has_held_balls"]:
		if typeof(pocket.get(key)) != TYPE_BOOL:
			return false
	for key in ["position", "scale"]:
		if (
			typeof(pocket.get(key)) != TYPE_VECTOR2
			or not pocket[key].is_finite()
			or pocket[key].length() > 100000.0
		):
			return false
	return (
		pocket.scale.x >= 0
		and pocket.scale.y >= 0
		and pocket.scale.x <= 16
		and pocket.scale.y <= 16
		and _number(pocket.get("rotation"), -1.0e6, 1.0e6)
		and _number(pocket.get("multiplier"), -1.0e12, 1.0e12)
		and _number(pocket.get("score"), -1.0e18, 1.0e18)
	)


func _valid_ball(body: Dictionary) -> bool:
	if typeof(body.get("id")) != TYPE_INT or body.id <= 0:
		return false
	for key in BALL_FLAGS:
		if typeof(body.get(key)) != TYPE_BOOL:
			return false
	for key in ["position", "visual_scale"]:
		if (
			typeof(body.get(key)) != TYPE_VECTOR2
			or not body[key].is_finite()
			or body[key].length() > 100000.0
		):
			return false
	if (
		body.visual_scale.x < 0.0
		or body.visual_scale.y < 0.0
		or body.visual_scale.x > 16.0
		or body.visual_scale.y > 16.0
	):
		return false
	if (
		typeof(body.get("spin")) != TYPE_VECTOR3
		or not body.spin.is_finite()
		or body.spin.length() > 1.0e6
		or not _number(body.get("rotation"), -1.0e6, 1.0e6)
		or not _number(body.get("mass"), 0.01, 100000.0)
		or not _number(body.get("radius_scale"), 0.01, 100.0)
	):
		return false
	if typeof(body.get("color")) != TYPE_COLOR:
		return false
	for component in [body.color.r, body.color.g, body.color.b, body.color.a]:
		if not _number(component, 0, 16):
			return false
	if not body.get("item") is Dictionary:
		return false
	var item: Dictionary = body.item
	var resources: Dictionary = get_node("/root/BallDatabase").id_to_ball
	if (
		typeof(item.get("data")) != TYPE_STRING
		or not resources.has(item.data)
		or typeof(item.get("mixed")) != TYPE_STRING
		or (item.mixed != "" and not resources.has(item.mixed))
	):
		return false
	if body.player != (item.data == "PLAYER"):
		return false
	for key in ITEM_NUMBERS:
		if (
			typeof(item.get(key)) != TYPE_INT
			or not _number(item[key], ITEM_NUMBERS[key][0], ITEM_NUMBERS[key][1])
		):
			return false
	for key in ITEM_FLAGS:
		if typeof(item.get(key)) != TYPE_BOOL:
			return false
	return true


func _number(value, minimum: float, maximum: float) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and value >= minimum
		and value <= maximum
	)

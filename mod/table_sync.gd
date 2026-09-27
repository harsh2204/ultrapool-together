extends Node

const MAX_BALLS = 128
const RoundPresentation = preload("round_presentation.gd")
const PlayerInventory = preload("player_inventory_sync.gd")
const ITEM_NUMBERS = {
	"base_score": [-1.0e18, 1.0e18],
	"temp_extra_score": [-1.0e18, 1.0e18],
	"level": [1, 1000000],
	"weight_state": [0, 3]
}
const ITEM_FLAGS = ["flaming", "fleeting", "star_power", "shielded", "shield_broken", "locked"]
const TABLE_FLAGS = ["ready", "in_menu", "in_shop", "round_ended", "game_over", "daily", "rotated"]
const BALL_FLAGS = ["player", "visible", "alive", "spawned", "falling", "gone", "passive"]

## Guest potted-rail hover: pocketed object balls stay in the synced snapshot with
## full BallItem fields (id, scores, flags). The replica maps those onto bodies and
## drives native inspection; no extra network fields are required.
static func ball_on_potted_rail(state: Dictionary) -> bool:
	return (
		state.get("visible") == true
		and state.get("player") == false
		and state.get("alive") == false
	)


var _guest = false
var _replica = null
var _scene_key = ""
var _saved_global: Dictionary = {}
var _saved_nodes: Array = []
var _saved_shapes: Array = []
var _saved_balls: Array = []
var _saved_tutorial: Dictionary = {}
var _results: Node


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
		"inventory": PlayerInventory.capture(game.player_info),
		"results": RoundPresentation.capture(game, get_node("/root/UIManager")),
		"daily": game.is_daily(),
		"rotated": game.table.scene_file_path == game.table_rotated_scene.resource_path,
		"table_position": game.table.global_position,
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
				"velocity": body.linear_velocity,
				"angular_velocity": body.angular_velocity,
				"linear_damp": body.linear_damp,
				"angular_damp": body.angular_damp,
				"force": body.constant_force,
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
	# Match replica_game.base_pockets = table.get_pockets() so base_index never
	# points past the guest pocket list (get_children can differ; see #17 get_child OOB).
	var fixed_pockets = game.table.get_pockets()
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


## True while an authoritative mid-round body is still initializing and would be
## omitted from capture(). Hosts hold publish until this clears (PERF-008 barrier).
func spawn_barrier_active() -> bool:
	var game = get_node("/root/Global").gameManager
	if not is_instance_valid(game) or not is_instance_valid(game.table):
		return false
	var bodies = game.balls.duplicate()
	if is_instance_valid(game.player_ball) and not bodies.has(game.player_ball):
		bodies.append(game.player_ball)
	for body in bodies:
		if not is_instance_valid(body):
			continue
		if body.is_inside_tree() and (body.ball_item == null or not body.inited):
			return true
		if not body.is_inside_tree() and body.ball_item != null:
			return true
	return false


func ball_ids(data: Dictionary) -> Dictionary:
	var ids: Dictionary = {}
	if not data.get("balls") is Array:
		return ids
	for body in data.balls:
		if body is Dictionary and typeof(body.get("id")) == TYPE_INT:
			ids[body.id] = true
	return ids


## Human-readable reject cause for guest diagnostics. Empty means valid.
## Keep network validation strict; call this only when logging a rejection (#17).
func snapshot_problem(data: Dictionary) -> String:
	return _snapshot_problem(data)


func begin_guest(config: Dictionary = {}) -> bool:
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
		"shopManager",
		"camera",
		"in_run",
		"IS_HOVER_SUPPRESSED",
		"hovered_item",
		"hovered_item_object",
		"sticker_manager",
		"floating_ui",
		"chosen_deck",
		"chosen_difficulty",
		"seed",
		"seed_text",
		"seeded_run",
		"run_mode"
	]:
		_saved_global[key] = global_node.get(key)
	if not is_instance_valid(_saved_global.shopManager):
		_saved_global.shopManager = null
	_saved_shapes = get_node("/root/GlobalPhysics").shapes.duplicate()
	_saved_balls = get_node("/root/GlobalPhysics").balls.duplicate()
	_suspend(current_scene)
	_suspend(get_node("/root/UIManager"))
	_resume_display(get_node("/root/UIManager"))
	_results = RoundPresentation.new()
	add_child(_results)
	_results.setup()
	global_node.in_run = true
	global_node.run_mode = global_node.RunMode.NORMAL
	if not config.is_empty():
		var database = get_node("/root/BallDatabase")
		global_node.chosen_deck = database.id_to_deck[config.deck]
		global_node.chosen_difficulty = database.id_to_difficulty[config.difficulty]
		global_node.seed = config.seed
		global_node.seed_text = str(config.seed)
		global_node.seeded_run = true
	_suspend(get_node("/root/TutorialManager"))
	var tutorial = get_node("/root/TutorialManager")
	_saved_tutorial = {"ENABLED": tutorial.ENABLED, "active_popup": tutorial.active_popup}
	tutorial.ENABLED = false
	tutorial.active_popup = null
	global_node.IS_HOVER_SUPPRESSED = false
	global_node.hovered_item = null
	global_node.hovered_item_object = null
	global_node.gameManager = null
	return true


func end_guest() -> void:
	if not _guest:
		return
	_results.end_session()
	_results.queue_free()
	_results = null
	var ui = get_node("/root/UIManager")
	for popup in ui.active_popups.duplicate():
		popup.just_opened_or_closed = false
		popup.instant_close_menu()
		popup.underlay_canvas.hide()
	ui.popup_queue.clear()
	ui.update_pause()
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
		if state.has("collision_layer"):
			node.collision_layer = state.collision_layer
			node.collision_mask = state.collision_mask
		if state.has("monitoring"):
			node.monitoring = state.monitoring
			node.monitorable = state.monitorable
	if is_instance_valid(global_node.camera):
		global_node.camera.make_current()
	_saved_nodes.clear()
	_saved_global.clear()
	_saved_shapes.clear()
	_saved_balls.clear()
	_saved_tutorial.clear()
	_guest = false


func valid_capture(data: Dictionary) -> bool:
	return _valid_snapshot(data)


func apply_snapshot(data: Dictionary) -> bool:
	if not _guest or not _valid_snapshot(data):
		return false
	if not data.available:
		_clear_replica()
		return true
	var key = "%s:%s" % [data.scene_id, data.rotated]
	if key == _scene_key and is_instance_valid(_replica):
		# Slot and similar native effects can rematerialize pockets/balls under the
		# same remote id with a new base_index or cue/object role. Rebuild those
		# replicas in place instead of rejecting the whole snapshot.
		_rebuild_incompatible_identities(data)
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
		scene.remote_rotated = data.rotated
		scene.prepare_scene()
		global_node.gameManager = scene
		get_node("/root/GlobalPhysics").clear_walls()
		get_node("/root/GlobalPhysics").clear_balls()
		add_child(scene)
		_replica = scene
		_scene_key = key
		global_node.camera.make_current()
	_replica.apply_table(data)
	_results.apply(data)
	return true


func _rebuild_incompatible_identities(data: Dictionary) -> void:
	for body in data.balls:
		if not _replica.replicas.has(body.id):
			continue
		var existing = _replica.replicas[body.id]
		if not is_instance_valid(existing) or existing.is_player == body.player:
			continue
		if existing == _replica.player_ball:
			_replica.player_ball = null
		if _replica.get("selected_ball") == existing and _replica.has_method("unselect_ball"):
			_replica.unselect_ball(existing, existing.ball_item)
		var physics = get_node_or_null("/root/GlobalPhysics")
		if physics != null and physics.has_method("unregister_ball"):
			physics.unregister_ball(existing)
		existing.queue_free()
		_replica.replicas.erase(body.id)
		if _replica.corrections.has(body.id):
			_replica.corrections.erase(body.id)
	for pocket in data.pockets:
		if not _replica.pocket_replicas.has(pocket.id):
			continue
		var existing_pocket = _replica.pocket_replicas[pocket.id]
		if (
			not is_instance_valid(existing_pocket)
			or existing_pocket.get_meta("remote_base_index") == pocket.base_index
		):
			continue
		if existing_pocket.get_meta("remote_hole", false):
			existing_pocket.queue_free()
		_replica.pocket_replicas.erase(pocket.id)


func begin_shot(vector: Vector2) -> bool:
	if not _guest or not is_instance_valid(_replica):
		return false
	if not vector.is_finite() or vector.length() <= 50.0 or vector.length() > 200.1:
		return false
	return _replica.begin_shot(vector)


func ready_for_input() -> bool:
	if not is_instance_valid(_replica) or not _replica.can_shoot():
		return false
	var cue = _replica.player_ball
	return is_instance_valid(cue) and cue.visible and cue.alive and cue.spawned and not cue.falling


func _clear_replica() -> void:
	if is_instance_valid(_results):
		_results.clear()
	get_node("/root/Global").clear_hovered_item()
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


func _resume_display(display: Node) -> void:
	for state in _saved_nodes:
		if state.node == display or display.is_ancestor_of(state.node):
			state.node.process_mode = state.process_mode
			if state.has("visible"):
				state.node.visible = state.visible
	display.process_mode = Node.PROCESS_MODE_ALWAYS


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
	if node is CollisionObject2D:
		state.collision_layer = node.collision_layer
		state.collision_mask = node.collision_mask
		node.collision_layer = 0
		node.collision_mask = 0
	if node is Area2D:
		state.monitoring = node.monitoring
		state.monitorable = node.monitorable
		node.monitoring = false
		node.monitorable = false
	_saved_nodes.append(state)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_suspend(child)


func _valid_snapshot(data: Dictionary) -> bool:
	return _snapshot_problem(data) == ""


func _snapshot_problem(data: Dictionary) -> String:
	if typeof(data.get("available")) != TYPE_BOOL:
		return "available type"
	if not data.available:
		return "" if data.size() == 1 else "unavailable payload size"
	if not RoundPresentation.valid(data.get("results")):
		return "results"
	if not PlayerInventory.valid(data.get("inventory"), get_node("/root/BallDatabase")):
		return _inventory_problem(data.get("inventory"))
	for key in TABLE_FLAGS:
		if typeof(data.get(key)) != TYPE_BOOL:
			return "table flag " + key
	for key in ["scene_id", "round", "rounds_played", "shots", "hp", "max_hp"]:
		if typeof(data.get(key)) != TYPE_INT:
			return "int field " + key
	if (
		data.scene_id <= 0
		or not _number(data.round, 0, 1000000)
		or not _number(data.rounds_played, 0, 1000000)
		or not _number(data.shots, 0, 20)
		or not _number(data.hp, 0, 100)
		or not _number(data.max_hp, 1, 100)
	):
		return "table number range"
	for key in ["score", "required_score", "money"]:
		if not _number(data.get(key), -1.0e18, 1.0e18):
			return "score field " + key
	if not _vector(data.get("table_position"), 100000.0):
		return "table_position"
	if not data.get("balls") is Array:
		return "balls type"
	if data.balls.size() > MAX_BALLS:
		return "balls count %d" % data.balls.size()
	if not data.get("pockets") is Array:
		return "pockets type"
	if data.pockets.size() > 16:
		return "pockets count %d" % data.pockets.size()
	var ids: Dictionary = {}
	var cue_count = 0
	for body in data.balls:
		if not body is Dictionary:
			return "ball type"
		var ball_problem = _ball_problem(body)
		if ball_problem != "":
			return ball_problem
		if ids.has(body.id):
			return "duplicate ball id %d" % body.id
		ids[body.id] = true
		cue_count += int(body.player)
	if cue_count > 1:
		return "multiple cue balls"
	var pocket_ids: Dictionary = {}
	var base_indices: Dictionary = {}
	var holes = 0
	for pocket in data.pockets:
		if not pocket is Dictionary:
			return "pocket type"
		var pocket_problem = _pocket_problem(pocket)
		if pocket_problem != "":
			return pocket_problem
		if pocket_ids.has(pocket.id):
			return "duplicate pocket id %d" % pocket.id
		pocket_ids[pocket.id] = true
		if pocket.base_index < 0:
			holes += 1
		elif base_indices.has(pocket.base_index):
			return "duplicate base_index %d" % pocket.base_index
		else:
			base_indices[pocket.base_index] = true
	if holes > 10:
		return "holes %d" % holes
	if base_indices.size() != 6:
		return "base pockets %d (need 6)" % base_indices.size()
	return ""


func _inventory_problem(data) -> String:
	if not data is Dictionary:
		return "inventory type"
	var database = get_node("/root/BallDatabase")
	for key in ["snacks", "cocktails"]:
		if not data.get(key) is int or data[key] < 0 or data[key] > 1000000:
			return "inventory " + key
	for group in PlayerInventory.SLOT_LIMITS:
		if (
			not data.get(group) is Array
			or data[group].size() < PlayerInventory.SLOT_MINIMUMS[group]
			or data[group].size() > PlayerInventory.SLOT_LIMITS[group]
		):
			return "inventory " + group + " size"
		var resources: Dictionary = (
			database.id_to_passive if group == "passives" else database.id_to_ball
		)
		for item in data[group]:
			if item == null:
				continue
			if not item is Dictionary or not PlayerInventory._valid_item(item, resources):
				return "inventory " + group + " item"
			if group == "cubes" and resources[item.data].from_set != &"NEGATIVE":
				return "inventory cubes non-NEGATIVE " + str(item.data)
	return "inventory"


func _valid_pocket(pocket: Dictionary) -> bool:
	return _pocket_problem(pocket) == ""


func _pocket_problem(pocket: Dictionary) -> String:
	if (
		typeof(pocket.get("id")) != TYPE_INT
		or pocket.id <= 0
		or typeof(pocket.get("base_index")) != TYPE_INT
		or not _number(pocket.base_index, -1, 5)
	):
		return "pocket id/base_index"
	for key in ["closed", "shielded", "has_held_balls"]:
		if typeof(pocket.get(key)) != TYPE_BOOL:
			return "pocket flag " + key
	for key in ["position", "scale"]:
		if (
			typeof(pocket.get(key)) != TYPE_VECTOR2
			or not pocket[key].is_finite()
			or pocket[key].length() > 100000.0
		):
			return "pocket " + key
	if not (
		pocket.scale.x >= 0
		and pocket.scale.y >= 0
		and pocket.scale.x <= 16
		and pocket.scale.y <= 16
		and _number(pocket.get("rotation"), -1.0e6, 1.0e6)
		and _number(pocket.get("multiplier"), -1.0e12, 1.0e12)
		and _number(pocket.get("score"), -1.0e18, 1.0e18)
	):
		return "pocket metrics"
	return ""


func _valid_ball(body: Dictionary) -> bool:
	return _ball_problem(body) == ""


func _ball_problem(body: Dictionary) -> String:
	if typeof(body.get("id")) != TYPE_INT or body.id <= 0:
		return "ball id"
	for key in BALL_FLAGS:
		if typeof(body.get(key)) != TYPE_BOOL:
			return "ball flag " + key
	for key in ["position", "visual_scale", "velocity"]:
		if (
			typeof(body.get(key)) != TYPE_VECTOR2
			or not body[key].is_finite()
			or body[key].length() > 100000.0
		):
			return "ball " + key
	if not _vector(body.get("force"), 1.0e7):
		return "ball force"
	if (
		body.visual_scale.x < 0.0
		or body.visual_scale.y < 0.0
		or body.visual_scale.x > 16.0
		or body.visual_scale.y > 16.0
	):
		return "ball visual_scale"
	if (
		typeof(body.get("spin")) != TYPE_VECTOR3
		or not body.spin.is_finite()
		or body.spin.length() > 1.0e6
		or not _number(body.get("rotation"), -1.0e6, 1.0e6)
		or not _number(body.get("mass"), 0.01, 100000.0)
		or not _number(body.get("radius_scale"), 0.01, 100.0)
		or not _number(body.get("angular_velocity"), -100000.0, 100000.0)
		or not _number(body.get("linear_damp"), 0.0, 10000.0)
		or not _number(body.get("angular_damp"), 0.0, 10000.0)
	):
		return "ball physics"
	if typeof(body.get("color")) != TYPE_COLOR:
		return "ball color"
	for component in [body.color.r, body.color.g, body.color.b, body.color.a]:
		if not _number(component, 0, 16):
			return "ball color component"
	if not body.get("item") is Dictionary:
		return "ball item type"
	var item: Dictionary = body.item
	var resources: Dictionary = get_node("/root/BallDatabase").id_to_ball
	if typeof(item.get("data")) != TYPE_STRING or not resources.has(item.data):
		return "ball item data " + str(item.get("data"))
	if typeof(item.get("mixed")) != TYPE_STRING or (item.mixed != "" and not resources.has(item.mixed)):
		return "ball item mixed " + str(item.get("mixed"))
	if body.player != (item.data == "PLAYER"):
		return "ball cue role mismatch id=%d" % body.id
	for key in ITEM_NUMBERS:
		if (
			typeof(item.get(key)) != TYPE_INT
			or not _number(item[key], ITEM_NUMBERS[key][0], ITEM_NUMBERS[key][1])
		):
			return "ball item " + key
	for key in ITEM_FLAGS:
		if typeof(item.get(key)) != TYPE_BOOL:
			return "ball item flag " + key
	return ""


func _vector(value, maximum: float) -> bool:
	return typeof(value) == TYPE_VECTOR2 and value.is_finite() and value.length() <= maximum


func _number(value, minimum: float, maximum: float) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and value >= minimum
		and value <= maximum
	)

extends Node

const MAX_BALLS = 128
const MAX_TABLE_CAPTURE_BYTES = 192 * 1024
const RoundPresentation = preload("round_presentation.gd")
const PlayerInventory = preload("player_inventory_sync.gd")
const TableEffects = preload("table_effects_sync.gd")
const VisualFx = preload("table_visual_fx.gd")
const NativeDraw = preload("table_native_draw.gd")
const BallVisual = preload("ball_visual_state.gd")
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
var _committed_context: Dictionary = {}
var _saved_global: Dictionary = {}
var _saved_nodes: Array = []
var _saved_shapes: Array = []
var _saved_balls: Array = []
var _saved_tutorial: Dictionary = {}
var _results: Node
var _visual_fx_capture: Node
var _native_draw_capture: Node
var _effects_game: WeakRef
var _effects_were_active = false


func _ready() -> void:
	# PERF-019: native presentation templates are read once at lifecycle setup.
	BallVisual.prepare()
	_visual_fx_capture = VisualFx.new()
	add_child(_visual_fx_capture)
	_native_draw_capture = NativeDraw.new()
	add_child(_native_draw_capture)


func clear_effect_capture() -> void:
	if is_instance_valid(_native_draw_capture):
		_native_draw_capture.clear()
	if is_instance_valid(_visual_fx_capture):
		_visual_fx_capture.clear()
	if _effects_game != null:
		TableEffects.clear(_effects_game.get_ref())
	_effects_game = null
	_effects_were_active = false


func effects_active() -> bool:
	var global_node = get_node_or_null("/root/Global")
	var game = global_node.gameManager if global_node != null else null
	if not is_instance_valid(game) or not is_instance_valid(game.table) or game.in_shop:
		return false
	if is_instance_valid(_native_draw_capture) and _native_draw_capture.has_pending_or_active_effects():
		return true
	if _effects_were_active or not game.droplets.is_empty() or not game.energy_balls.is_empty():
		return true
	if is_instance_valid(_visual_fx_capture) and _visual_fx_capture.has_pending_or_active_effects():
		return true
	# WORMHOLE can finish after ordinary balls stop. Native fixed+dynamic pockets
	# are capped at16; never turn this scheduler hint into an unbounded scan.
	if game.pockets.size() > 16:
		return true
	for pocket in game.pockets:
		if not is_instance_valid(pocket) or pocket.is_queued_for_deletion():
			continue
		var area = pocket.get_node_or_null("Area2D")
		if area is Node2D and not area.scale.is_equal_approx(Vector2.ONE):
			return true
	return false


func _prepare_effect_capture(game: Node) -> void:
	if _effects_game != null and _effects_game.get_ref() == game:
		return
	if _effects_game != null:
		TableEffects.clear(_effects_game.get_ref())
	_effects_game = weakref(game)
	_effects_were_active = false
	# VisualFx observes native node_added before the first snapshot of a scene.
	# Its own epoch handling keeps those new effects and discards the old scene;
	# clearing that registry here would lose startup effects before delivery.


## Final-build archival does not depend on render topology/spawn readiness.
func capture_inventory() -> Dictionary:
	var global_node = get_node_or_null("/root/Global")
	var game = global_node.gameManager if global_node != null else null
	if not is_instance_valid(game) or not is_instance_valid(game.player_info):
		return {}
	return PlayerInventory.capture(game.player_info)


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
		# Native ShotsInfo tracks round max + spent separately; remaining alone cannot
		# rebuild the spent-pip panel on guests (#29).
		"shots_max": _capture_shots_max(game),
		"shots_used": _capture_shots_used(game),
		"money": game.player_info.money,
		"hp": game.player_info.hp,
		"max_hp": game.get_max_hp(),
		"inventory": PlayerInventory.capture(game.player_info),
		"results": RoundPresentation.capture(game, get_node("/root/UIManager")),
		"daily": game.is_daily(),
		"rotated": game.table.scene_file_path == game.table_rotated_scene.resource_path,
		"table_position": game.table.global_position,
		"ball_visual_status": "complete",
		"pocket_visual_status": "complete",
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
				"ball_visual": BallVisual.capture(body),
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
	data.pockets = _capture_pockets(game)
	_prepare_effect_capture(game)
	data.effects = TableEffects.capture(game)
	data.visual_fx = (
		_visual_fx_capture.capture(game) if is_instance_valid(_visual_fx_capture) else {}
	)
	data.native_draw = (
		_native_draw_capture.capture(game) if is_instance_valid(_native_draw_capture) else {}
	)
	_limit_effect_payload(data)
	_effects_were_active = _active_effect_state(data)
	return data


static func _active_effect_state(data: Dictionary) -> bool:
	var effects: Dictionary = data.get("effects", {})
	if effects.get("status") == "overflow":
		return true
	if not effects.get("droplets", []).is_empty() or not effects.get("energy", []).is_empty():
		return true
	for pocket in effects.get("pockets", []):
		if not pocket.suction_scale.is_equal_approx(Vector2.ONE) or pocket.suction_color.a > 0:
			return true
	var native_draw: Dictionary = data.get("native_draw", {})
	if native_draw.get("status") == "overflow" or NativeDraw.active(native_draw):
		return true
	if data.get("ball_visual_status") == "overflow" or data.get("pocket_visual_status") == "overflow":
		return true
	var visual_fx: Dictionary = data.get("visual_fx", {})
	return visual_fx.get("status") == "overflow" or not visual_fx.get("items", []).is_empty()


static func _limit_effect_payload(data: Dictionary) -> void:
	# Leave 64 KiB for controller/transport envelope data within its 256 KiB cap.
	# Effects are additive, so exhaustion must never suppress balls, turn state or
	# actions. First defer transient FX, then durable FX if the table is still big.
	# This bounded encoding is necessary because independent descriptor limits do
	# not guarantee a valid combined packet (PERF-008/019).
	if _effect_substates_empty(data):
		# Without effect descriptors there is nothing this limit could trim, and
		# 128 ordinary bodies stay beneath the target; skip the whole-table encode.
		return
	if var_to_bytes(data).size() <= MAX_TABLE_CAPTURE_BYTES:
		return
	data.visual_fx = {
		"version": 1, "status": "overflow", "reason": "combined table bytes", "items": []
	}
	if var_to_bytes(data).size() > MAX_TABLE_CAPTURE_BYTES:
		data.native_draw = NativeDraw.overflow("combined table bytes")
	if var_to_bytes(data).size() > MAX_TABLE_CAPTURE_BYTES:
		data.effects = TableEffects.overflow("bytes")
	if var_to_bytes(data).size() > MAX_TABLE_CAPTURE_BYTES:
		# Preserve authoritative body identities and item state. The next complete
		# visual sample restores presentation; never truncate the live body list.
		data.ball_visual_status = "overflow"
		for body in data.get("balls", []):
			if body is Dictionary:
				body.erase("ball_visual")
	if var_to_bytes(data).size() > MAX_TABLE_CAPTURE_BYTES:
		# Pocket art is additive protocol-10 state, separate from authoritative
		# pocket identity/score and the legacy durable-effect schema.
		data.pocket_visual_status = "overflow"
		for pocket in data.get("pockets", []):
			if pocket is Dictionary:
				pocket.erase("pocket_visual")


static func _effect_substates_empty(data: Dictionary) -> bool:
	# This fast path recognizes only empty known shapes. Unknown/oversized data
	# must still reach the aggregate byte guard (PERF-008).
	for key in data.get("effects", {}):
		if key not in ["version", "status", "reason", "droplets", "energy", "pockets"]:
			return false
	for key in data.get("visual_fx", {}):
		if key not in ["version", "status", "reason", "items"]:
			return false
	for body in data.get("balls", []):
		if body is Dictionary and not body.get("ball_visual", {}).is_empty():
			return false
	for pocket in data.get("pockets", []):
		if pocket is Dictionary and not pocket.get("pocket_visual", []).is_empty():
			return false
	var native_draw: Dictionary = data.get("native_draw", {})
	if native_draw.get("status", "complete") != "complete" or not native_draw.get("items", []).is_empty():
		return false
	var effects: Dictionary = data.get("effects", {})
	var visual_fx: Dictionary = data.get("visual_fx", {})
	return (
		effects.get("status", "complete") == "complete"
		and effects.get("droplets", []).is_empty()
		and effects.get("energy", []).is_empty()
		and effects.get("pockets", []).is_empty()
		and visual_fx.get("status", "complete") == "complete"
		and visual_fx.get("items", []).is_empty()
	)


func _capture_pockets(game: Node) -> Array:
	# Native Game aliases pockets/base_pockets to table.get_pockets(). BLACK-HOLE
	# appends to that same Array, so its index is 6+ despite being a dynamic hole.
	# Preserve the native order, but identify fixed pockets by scene ownership.
	# PERF-008/014: six fixed identities stay valid without weakening wire bounds.
	var fixed_pockets: Array = []
	var pocket_parent = game.table.get_node("Pockets")
	for pocket in game.table.get_pockets():
		if is_instance_valid(pocket) and pocket.get_parent() == pocket_parent:
			fixed_pockets.append(pocket)
	var states: Array = []
	for pocket in game.pockets:
		states.append(
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
				"has_held_balls": not pocket.held_balls.is_empty(),
				"pocket_visual": TableEffects.capture_pocket_visuals(pocket)
			}
		)
	return states


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


func pocket_ids(data: Dictionary) -> Dictionary:
	var ids: Dictionary = {}
	if not data.get("pockets") is Array:
		return ids
	for pocket in data.pockets:
		if (
			pocket is Dictionary
			and typeof(pocket.get("id")) == TYPE_INT
			and typeof(pocket.get("base_index")) == TYPE_INT
		):
			ids[pocket.id] = pocket.base_index
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
	_committed_context = {}
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
		"chosen_run_state",
		"seed",
		"seed_text",
		"seeded_run",
		"creative_run",
		"force_selected_item",
		"force_selected_object",
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
	# Replicas display a normal shared run even after local solo Creative play.
	# The saved guest globals above are restored by end_guest, including selection.
	global_node.set_creative(false)
	global_node.chosen_run_state = null
	global_node.force_selected_item = null
	global_node.force_selected_object = null
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


## Public apply: safe for independent callers and fixtures; validates first.
func apply_snapshot(data: Dictionary) -> bool:
	if not _guest or not _valid_snapshot(data):
		return false
	return apply_validated_snapshot(data)


## PERF-014: internal apply for state that main._received_table has already
## validated at the network boundary in the same frame, so accepted snapshots are
## checked exactly once. There is no flag on the data: wire payloads can only
## reach this method through that validated path.
func apply_validated_snapshot(data: Dictionary) -> bool:
	if not _guest:
		return false
	# Native setters and result menus can call back during hydration. Readiness is
	# unavailable until the complete table and phase presentation have committed.
	_committed_context = {}
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
	_committed_context = {
		"round": data.round,
		"rounds_played": data.rounds_played,
		"playable": (
			data.ready and not data.in_menu and not data.in_shop
			and not data.round_ended and not data.game_over and data.results.phase == "play"
		)
	}
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
	if (
		not _guest or not _committed_context.get("playable", false)
		or not is_instance_valid(_replica) or not _replica.can_shoot()
	):
		return false
	var cue = _replica.player_ball
	return is_instance_valid(cue) and cue.visible and cue.alive and cue.spawned and not cue.falling


## Reliable table state may precede its reliable scene baseline. The wire state
## uses a one-based round while native snapshots retain zero-based level_number.
func ready_for_state(state: Dictionary) -> bool:
	if (
		not ready_for_input() or state.get("available") != true
		or state.get("table_active") != true or state.get("can_shoot") != true
		or state.get("rounds_played", -1) != _committed_context.get("rounds_played")
		or state.get("round", 0) != _committed_context.get("round", -1) + 1
	):
		return false
	for field in ["in_menu", "in_shop", "round_ended", "game_over", "round_result_open", "pending", "finished"]:
		if state.get(field, false):
			return false
	return true


func _clear_replica() -> void:
	_committed_context = {}
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
	for key in [
		"scene_id", "round", "rounds_played", "shots", "shots_max", "shots_used", "hp", "max_hp"
	]:
		if typeof(data.get(key)) != TYPE_INT:
			return "int field " + key
	if (
		data.scene_id <= 0
		or not _number(data.round, 0, 1000000)
		or not _number(data.rounds_played, 0, 1000000)
		or not _number(data.shots, 0, 20)
		or not _number(data.shots_max, 0, 20)
		or not _number(data.shots_used, 0, 20)
		or data.shots_used > data.shots_max
		or data.shots > data.shots_max
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
	if data.has("ball_visual_status") and data.ball_visual_status not in ["complete", "overflow"]:
		return "ball visual status"
	if data.has("pocket_visual_status") and data.pocket_visual_status not in ["complete", "overflow"]:
		return "pocket visual status"
	# Absent on older peers; present fields remain strict before any native mutation.
	if data.has("native_draw"):
		var draw_problem = NativeDraw.problem(data.native_draw)
		if draw_problem != "":
			return "native draw " + draw_problem
	if data.has("visual_fx"):
		var visual_fx_problem = VisualFx.problem(data.visual_fx)
		if visual_fx_problem != "":
			return "visual fx " + visual_fx_problem
	if data.has("effects"):
		var effects_problem = TableEffects.problem(data.effects)
		if effects_problem != "":
			return "effects " + effects_problem
		for effect in data.effects.pockets:
			if not pocket_ids.has(effect.id):
				return "effects unknown pocket"
		for group in ["droplets", "energy"]:
			for effect in data.effects[group]:
				if ids.has(effect.id) or pocket_ids.has(effect.id):
					return "effects identity collision"
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
			if (
				not item is Dictionary
				or not PlayerInventory._valid_item(item, resources, group == "passives")
			):
				return "inventory " + group + " item"
			if group == "cubes" and not PlayerInventory._is_negative_cube(resources[item.data]):
				return "inventory cubes non-NEGATIVE " + str(item.data)
	return "inventory"


func _valid_pocket(pocket: Dictionary) -> bool:
	return _pocket_problem(pocket) == ""


func _pocket_problem(pocket: Dictionary) -> String:
	if pocket.has("pocket_visual") and not TableEffects.pocket_visual_valid(pocket.pocket_visual):
		return "pocket visual fields"
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
	if body.has("ball_visual"):
		var visual_problem = BallVisual.problem(body.ball_visual)
		if visual_problem != "":
			return "ball visual " + visual_problem
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
	if (
		typeof(item.get("mixed")) != TYPE_STRING
		or (item.mixed != "" and not resources.has(item.mixed))
	):
		return "ball item mixed " + str(item.get("mixed"))
	if not body.get("ball_visual", {}).is_empty() and body.ball_visual.p != int(body.player):
		return "ball visual cue role"
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


func _capture_shots_max(game: Node) -> int:
	var remaining: int = int(game.get_shots_left())
	var info = game.table.shots_info if is_instance_valid(game.table) else null
	if is_instance_valid(info) and int(info.shots_max) > 0:
		return maxi(int(info.shots_max), remaining)
	return maxi(remaining, 0)


func _capture_shots_used(game: Node) -> int:
	# Derive spent count from remaining vs round max. Do not trust a fixture-only
	# shots_used bump that never decremented get_shots_left() (#29 / PERF-015).
	var remaining: int = int(game.get_shots_left())
	var maximum: int = _capture_shots_max(game)
	return clampi(maximum - remaining, 0, maximum)

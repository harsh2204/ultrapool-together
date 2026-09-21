extends Node

const PREFIX = "TOGETHER_"
const BallRules = preload("multiplayer_ball_rules.gd")

var catalog: Node
var rules: RefCounted
var _controller: Node
var _ui: Node
var _ball_script: Script
var _native_ball_script: Script
var _hooked: Dictionary = {}
var _remote: Dictionary = {}
var _active = false
var _round_key = ""
var _encore: WeakRef
var _potted: Array = []


func setup(controller: Node) -> bool:
	_controller = controller
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -900
	var base = get_script().resource_path.get_base_dir()
	catalog = load(base.path_join("multiplayer_ball_catalog.gd")).new()
	add_child(catalog)
	if not catalog.register_balls():
		return false
	_ball_script = load(base.path_join("multiplayer_ball.gd"))
	_native_ball_script = load("res://ball.gd")
	_ui = load(base.path_join("multiplayer_ball_ui.gd")).new()
	add_child(_ui)
	_ui.setup(controller, self)
	get_tree().node_added.connect(_node_added)
	return true


func begin_session() -> void:
	rules = BallRules.new()
	_active = true
	_round_key = ""
	_remote.clear()
	catalog.set_active(true)


func end_session() -> void:
	_active = false
	for entry in _hooked.values():
		var body = entry.body.get_ref()
		if is_instance_valid(body):
			_controller.adapter._replace_script(body, entry.script)
	_hooked.clear()
	_potted.clear()
	_encore = null
	_remote.clear()
	_round_key = ""
	if catalog != null:
		catalog.set_active(false)
	if _ui != null:
		_ui.clear()


func _process(_delta: float) -> void:
	if not _active:
		return
	if _controller.is_table_host():
		_sync_round()
		_try_encore()
	_ui.refresh(capture() if _controller.is_table_host() else _remote)


func _game():
	var game = get_node("/root/Global").gameManager
	return game if is_instance_valid(game) and game.is_node_ready() else null


func _sync_round() -> void:
	var game = _game()
	if game == null:
		return
	var key = "%d:%d" % [game.get_instance_id(), game.rounds_played]
	if key != _round_key:
		_round_key = key
		rules.reset_round(key)
		_potted.clear()
		_encore = null
	for body in game.balls:
		_hook_ball(body)
	for id in _hooked.keys():
		if _hooked[id].body.get_ref() == null:
			_hooked.erase(id)


func _node_added(node: Node) -> void:
	if _active and _controller.is_table_host() and node is Ball and not node is PlayerBall:
		node.ready.connect(_hook_ball.bind(node), CONNECT_ONE_SHOT)


func _hook_ball(body: Node) -> void:
	if (
		not _active
		or not _controller.is_table_host()
		or not is_instance_valid(body)
		or body is PlayerBall
		or body.get_script() not in [_native_ball_script, _ball_script]
		or body.get_meta("together_replica", false)
		or body.ball_item == null
		or body.is_passive
	):
		return
	var game = _game()
	if game == null or not game.is_ancestor_of(body):
		return
	var id: int = body.get_instance_id()
	if not _hooked.has(id):
		_hooked[id] = {"body": weakref(body), "script": body.get_script()}
		_controller.adapter._replace_script(body, _ball_script)
		body.together_balls = self
	rules.register_ball(id, _kinds(body))


func _kinds(body) -> Array:
	var result: Array = []
	for resource in [body.ball_item.data, body.ball_item.mixed_data]:
		if resource != null and str(resource.id).begins_with(PREFIX):
			if not result.has(str(resource.id)):
				result.append(str(resource.id))
	return result


func begin_shot(index: int, shooter: int) -> bool:
	_sync_round()
	return rules.begin_shot(
		index,
		shooter,
		_controller._score_match(),
		_controller._members(_controller.table_id).size()
	)


func finish_shot() -> void:
	var survivors: Array = []
	for entry in _hooked.values():
		var body = entry.body.get_ref()
		if is_instance_valid(body) and body.alive and not body.gone:
			survivors.append(body.get_instance_id())
	rules.finish_shot(survivors)


func record_hit(body, other) -> void:
	if not _active or not rules.pending or body.is_passive or not body.alive:
		return
	if not other.alive or other.is_passive:
		return
	if not other is PlayerBall and other.get_script() not in [_native_ball_script, _ball_script]:
		return
	_hook_ball(body)
	rules.hit(body.get_instance_id())
	if not other is PlayerBall:
		_hook_ball(other)
		rules.hit(other.get_instance_id())


func record_wall(body) -> void:
	if _active and rules.pending and body.alive:
		rules.wall(body.get_instance_id())


func record_pocket(body, pocket, multiplier: float) -> void:
	if not _active or not rules.pending or body.is_passive:
		return
	var game = _game()
	if (
		game == null
		or game.round_ended
		or game.in_shop
		or multiplier <= 0
		or not game.pockets.has(pocket)
	):
		return
	_hook_ball(body)
	var fixed: Array = game.table.get_node("Pockets").get_children()
	var kinds = _kinds(body)
	var action: Dictionary = rules.pocket(
		body.get_instance_id(),
		kinds,
		maxf(0.0, body.get_score()),
		fixed.find(pocket),
		kinds.is_empty()
	)
	if action.points > 0:
		game.add_score(action.points, body.global_position, false, true, body, false)
	if action.money > 0:
		game.player_info.gain_money(action.money)
		game.table.update_money(game.player_info.money)
		game.display_money(action.money, body.global_position)
	if action.heal > 0 and game.player_info.hp < game.get_max_hp():
		game.player_info.hp = mini(game.get_max_hp(), game.player_info.hp + action.heal)
		game.update_hp(game.player_info.hp)
	if action.encore:
		for index in range(_potted.size() - 1, -1, -1):
			var candidate = _potted[index].get_ref()
			if _encore_candidate(candidate):
				_encore = weakref(candidate)
				break
	if kinds.is_empty():
		_potted.append(weakref(body))


func _encore_candidate(body) -> bool:
	return (
		is_instance_valid(body)
		and not body.alive
		and not body.is_passive
		and not body.ball_item.fleeting
		and _kinds(body).is_empty()
	)


func _try_encore() -> void:
	if _encore == null:
		return
	var game = _game()
	var body = _encore.get_ref()
	if game == null or game.round_ended or game.in_shop or not _encore_candidate(body):
		_encore = null
		return
	if (
		get_tree().paused
		or game.balls_moving
		or game.player_ball.is_moving()
		or get_node("/root/Global").has_active_wisp()
	):
		return
	for moving in game.balls:
		if is_instance_valid(moving) and moving.is_moving():
			return
	# Return the ball before the native round-end timer can cash out the board.
	game.respawn_specific_ball(body)
	game.pocketed_balls.erase(body)
	game.delay_round_end(1.0)
	_encore = null


func prepare_shop() -> void:
	if not _active or not _controller.is_table_host():
		return
	var game = _game()
	if game != null and game.in_shop:
		catalog.ensure_shop_offer(get_node("/root/Global").shopManager)


func request_call(ball_id: int, pocket_index: int) -> void:
	if not _active:
		return
	_controller._table_send(
		{
			"kind": "ball_call",
			"ball": ball_id,
			"pocket": pocket_index,
			"turn": _controller.shot_number
		}
	)


func blocks_shot_input() -> bool:
	return _ui != null and _ui.blocks_shot_input()


func handle_call(actor: int, message: Dictionary) -> bool:
	if (
		not _active
		or not _controller.is_table_host()
		or _controller.finished
		or _controller.shot_pending
		or message.get("turn") != _controller.shot_number
		or not message.get("ball") is int
		or not message.get("pocket") is int
		or not _controller.adapter.can_shoot()
	):
		return false
	var game = _game()
	var fixed: Array = game.table.get_node("Pockets").get_children()
	if message.pocket < 0 or message.pocket >= fixed.size() or fixed[message.pocket].closed:
		return false
	if not _hooked.has(message.ball):
		return false
	var body = _hooked[message.ball].body.get_ref()
	return (
		is_instance_valid(body)
		and body.alive
		and not body.gone
		and rules.call_ball(actor, message.ball, message.pocket)
	)


func bounty_shot() -> int:
	if _active and rules.bounty_shot <= _controller.used_shots:
		return rules.bounty_shot
	return 0


func capture() -> Dictionary:
	if not _active:
		return {}
	var data = {
		"last_shooter": rules.last_shooter,
		"pending": rules.pending,
		"bounty_shot": bounty_shot(),
		"call": rules.call_state.duplicate(),
		"balls": [],
		"pockets": []
	}
	for id in _hooked:
		var body = _hooked[id].body.get_ref()
		if not is_instance_valid(body) or not rules.balls.has(id):
			continue
		var state: Dictionary = rules.balls[id]
		if state.kinds.is_empty():
			continue
		data.balls.append(
			{
				"id": id,
				"kinds": state.kinds.duplicate(),
				"name": body.ball_item.get_formatted_name(),
				"position": body.global_position,
				"color": body.ball_item.data.main_color,
				"marker": 0 if state.paid.has(BallRules.RELAY) else state.marker,
				"charge": 0 if state.paid.has(BallRules.PATIENCE) else state.charge,
				"callable": BallRules.CALL in state.kinds and not state.paid.has(BallRules.CALL),
				"alive": body.alive and body.visible and not body.gone
			}
		)
	if (
		not data.call.is_empty()
		and not data.balls.any(func(ball): return ball.id == data.call.ball)
	):
		data.call.clear()
	var game = _game()
	if game != null and is_instance_valid(game.table):
		var fixed: Array = game.table.get_node("Pockets").get_children()
		for index in range(fixed.size()):
			data.pockets.append(
				{
					"index": index,
					"position": fixed[index].global_position,
					"open": not fixed[index].closed
				}
			)
	return data


func ball_position(id: int, fallback: Vector2) -> Vector2:
	if _controller.is_table_host():
		if _hooked.has(id):
			var body = _hooked[id].body.get_ref()
			if is_instance_valid(body):
				return body.global_position
	else:
		var game = _game()
		if game != null and game.replicas.has(id):
			return game.replicas[id].global_position
	return fallback


func apply_state(data: Dictionary) -> void:
	_remote = data.duplicate(true)


func valid_state(data) -> bool:
	return BallRules.valid_state(data)

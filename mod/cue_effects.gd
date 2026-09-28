extends Node
## Native cue-perk adapter. Refs PERF-010/030/034/035. All scans occur at shot or
## round boundaries; node_added handles spawned balls. No recurring frame hook.
## Native compatibility and timing remain implemented, unmeasured.

const Rules = preload("cue_effect_rules.gd")
const MAX_FIXED_POCKETS = 16
const CUSTOM_PREFIXES = ["TOGETHER_", "PHASES_", "MORPH_", "TIDE_", "RELIC_", "TAROT_", "ZODIAC_"]

var rules: RefCounted
var _controller: Node
var _ball_script: Script
var _native_ball_script: Script
var _hooked: Dictionary = {}
var _fixed_pockets: Dictionary = {}
var _round_key = ""
var _active = false


func setup(controller: Node) -> bool:
	_controller = controller
	var base = get_script().resource_path.get_base_dir()
	_ball_script = load(base.path_join("multiplayer_ball.gd"))
	_native_ball_script = load("res://ball.gd")
	get_tree().node_added.connect(_node_added)
	return true


func begin_session() -> void:
	end_session()
	if _controller == null or not _controller.cue_shop_enabled():
		return
	rules = Rules.new()
	_active = true


func end_session() -> void:
	_active = false
	_release_hooks()
	_fixed_pockets.clear()
	_round_key = ""
	rules = null


func begin_shot(index: int, actor: int, raw_vector: Vector2) -> bool:
	if not _active or not _controller.is_table_host():
		return true
	var game = _game()
	if game == null or not raw_vector.is_finite():
		return false
	var key = "%d:%d" % [game.get_instance_id(), game.rounds_played]
	if key != _round_key:
		_release_hooks()
		_round_key = key
		rules.reset_round(key)
		_cache_pockets(game)
	if game.balls.size() > Rules.MAX_BALLS:
		# Other native services have already admitted this shot. Skip only its cue
		# perks, preserving spent budget and marking unobserved pot history unknown.
		return rules.skip_shot(index, actor)
	_prune_hooks(game)
	var ids: Array = []
	var ordinary_count = 0
	for body in game.balls:
		_hook_ball(body)
		if not _known_object(body):
			continue
		ids.append(body.get_instance_id())
		if body.alive and not body.gone and _ordinary(body):
			ordinary_count += 1
	return rules.begin_shot(
		index, actor, _controller.cue_inventory.model_for(actor),
		raw_vector.length(), ordinary_count, ids
	)


func finish_shot() -> void:
	if _active and rules != null:
		rules.finish_shot()


func record_hit(body, other) -> void:
	if not _recording() or not _known_object(body) or not _known_object(other):
		return
	if not body.alive or not other.alive or body.gone or other.gone:
		return
	rules.hit(body.get_instance_id(), other.get_instance_id())


func record_wall(body) -> void:
	if _recording() and _known_object(body) and body.alive and not body.gone:
		rules.wall(body.get_instance_id())


func record_pocket(body, pocket, multiplier: float) -> Dictionary:
	if not _recording() or not _known_object(body):
		return {}
	if (
		not is_instance_valid(pocket) or not pocket is Pocket or pocket is VirtualPocket
		or not _fixed_pockets.has(pocket.get_instance_id())
		or not is_finite(multiplier) or multiplier <= 0.0
		or not body.alive or body.gone or not body.was_alive_one_frame_ago
		or body.pocketed_this_frame or body.has_id("WEREWOLF") or body.has_id("POT")
		or body.is_shielded() or (pocket.shielded and not body.is_shield_broken())
	):
		return {}
	var game = _game()
	if (
		game == null or game.round_ended or game.in_shop or game.game_is_broken
		or not game.pockets.has(pocket)
	):
		return {}
	var pocket_entry: Dictionary = _fixed_pockets[pocket.get_instance_id()]
	if pocket_entry.body.get_ref() != pocket:
		return {}
	var base_value: float = body.get_score()
	var pocket_multiplier: float = pocket.get_multiplier()
	if not is_finite(base_value) or base_value <= 0.0:
		return {}
	if not is_finite(pocket_multiplier) or pocket_multiplier <= 0.0:
		return {}
	var scored: float = (
		pocket.get_score_imp(base_value) if body.has_id("IMP") else pocket.get_score(base_value)
	)
	var native_points: float = scored * multiplier
	if not is_finite(native_points) or native_points <= 0.0:
		return {}
	var points: float = rules.pocket(body.get_instance_id(), base_value, pocket_entry.kind)
	if points <= 0.0:
		return {}
	# Reserve the capped award using pre-pot value/contact evidence, but do not
	# score while the source is alive. A threshold-crossing bonus before native
	# unalive would let a GAMEBALL trigger its own REACH-SCORE virtual pot.
	return {
		"points": points, "position": body.global_position,
		"source": weakref(body), "game": weakref(game), "service": get_instance_id(),
		"round": _round_key, "shot": rules.shot_index, "consumed": false,
	}


func commit_pocket(award: Dictionary) -> void:
	if award.is_empty() or bool(award.get("consumed", true)):
		return
	# The callback-local payload is consumed before any native event can reenter.
	award.consumed = true
	if (
		not _recording() or award.get("service") != get_instance_id()
		or award.get("round") != _round_key or award.get("shot") != rules.shot_index
		or not award.get("source") is WeakRef or not award.get("game") is WeakRef
		or not award.get("position") is Vector2 or not award.position.is_finite()
		or not (award.get("points") is float or award.get("points") is int)
		or not is_finite(float(award.points)) or award.points <= 0.0
	):
		return
	var game = _game()
	var body = award.source.get_ref()
	if (
		game == null or game != award.game.get_ref() or not _known_object(body)
		or body.alive or not body.pocketed_this_frame or body.is_shielded()
		or game.round_ended or game.in_shop or game.game_is_broken
	):
		return
	# Native super.pocket has now marked the source dead and delivered its normal
	# score. Only other living GAMEBALLs may observe a bonus threshold crossing.
	# chains=false prevents SCORE/SCORE-SELF recursion; keep the pre-graveyard point.
	game.add_score(float(award.points), award.position, false, true, body, false)


func _recording() -> bool:
	return _active and rules != null and rules.pending and _controller.is_table_host()


func _game():
	if not is_inside_tree():
		return null
	var global = get_node_or_null("/root/Global")
	if global == null:
		return null
	var game = global.gameManager
	return game if is_instance_valid(game) and game.is_node_ready() else null


func _node_added(node: Node) -> void:
	if _active and _controller.is_table_host() and node is Ball and not node is PlayerBall:
		if node.is_node_ready():
			_hook_ball(node)
		else:
			node.ready.connect(_hook_ball.bind(node), CONNECT_ONE_SHOT)


func _hook_ball(body) -> void:
	if (
		not _active or not _controller.is_table_host() or not _native_object(body)
		or body.get_meta("together_replica", false)
	):
		return
	var game = _game()
	if game == null or not game.is_ancestor_of(body):
		return
	var id: int = body.get_instance_id()
	if not _hooked.has(id):
		if _hooked.size() >= Rules.MAX_BALLS:
			if rules != null and rules.pending:
				rules.invalidate_shot()
			return
		_hooked[id] = weakref(body)
	if body.get_script() != _ball_script:
		_controller.adapter._replace_script(body, _ball_script)
	# Reusing the shared script preserves the other services' refs and native state.
	# Do not set opt-in services here: the cue shop works when both are disabled.
	body.cue_effects = self
	if rules != null and rules.pending:
		rules.register_ball(id)


func _native_object(body) -> bool:
	return (
		is_instance_valid(body) and body is Ball and not body is PlayerBall
		and not body.is_player and not body.is_passive and body.ball_item != null
		and body.get_script() in [_native_ball_script, _ball_script]
	)


func _known_object(body) -> bool:
	return (
		_native_object(body) and _hooked.has(body.get_instance_id())
		and _hooked[body.get_instance_id()].get_ref() == body
	)


func _ordinary(body) -> bool:
	for data in [body.ball_item.data, body.ball_item.mixed_data]:
		if data == null:
			continue
		for prefix in CUSTOM_PREFIXES:
			if str(data.id).begins_with(prefix):
				return false
	return true


func _cache_pockets(game) -> void:
	_fixed_pockets.clear()
	var container = game.table.get_node_or_null("Pockets")
	if container == null or container.get_child_count() > MAX_FIXED_POCKETS:
		return
	var fixed: Array = []
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	var positions: Dictionary = {}
	for pocket in container.get_children():
		if pocket is Pocket and not pocket is VirtualPocket:
			if not pocket.position.is_finite() or positions.has(pocket.position):
				return
			positions[pocket.position] = true
			fixed.append(pocket)
			min_x = minf(min_x, pocket.position.x)
			max_x = maxf(max_x, pocket.position.x)
			min_y = minf(min_y, pocket.position.y)
			max_y = maxf(max_y, pocket.position.y)
	if fixed.is_empty() or is_equal_approx(min_x, max_x) or is_equal_approx(min_y, max_y):
		return
	var next: Dictionary = {}
	var corners = 0
	# Native table.tscn places one side pocket at x=552 while the adjacent
	# corners sit at x=550. Allow a small relative edge inset/outset; exact
	# extrema would reject that real layout and disable every cue perk.
	var tolerance: float = minf(max_x - min_x, max_y - min_y) * 0.01
	for pocket in fixed:
		var extreme_x: bool = (
			absf(pocket.position.x - min_x) <= tolerance
			or absf(pocket.position.x - max_x) <= tolerance
		)
		var extreme_y: bool = (
			absf(pocket.position.y - min_y) <= tolerance
			or absf(pocket.position.y - max_y) <= tolerance
		)
		if not extreme_x and not extreme_y:
			return
		var corner: bool = extreme_x and extreme_y
		corners += int(corner)
		next[pocket.get_instance_id()] = {
			"body": weakref(pocket), "kind": "corner" if corner else "middle",
		}
	# Both rectangular orientations have four corners; a side pocket lies on
	# exactly one extreme axis. Reject partial/degenerate geometry atomically.
	if corners == 4:
		_fixed_pockets = next


func _prune_hooks(game) -> void:
	for id in _hooked.keys():
		var body = _hooked[id].get_ref()
		if not is_instance_valid(body):
			_hooked.erase(id)
		elif not game.is_ancestor_of(body):
			_release_body(body)
			_hooked.erase(id)


func _release_hooks() -> void:
	for reference in _hooked.values():
		_release_body(reference.get_ref())
	_hooked.clear()


func _release_body(body) -> void:
	if not is_instance_valid(body) or body.get_script() != _ball_script:
		return
	if body.get("cue_effects") == self:
		body.cue_effects = null
	if (
		not is_instance_valid(body.get("cue_effects"))
		and not _service_active(body.get("together_balls"))
		and not _service_active(body.get("expansion_balls"))
		and is_instance_valid(_controller) and is_instance_valid(_controller.adapter)
	):
		_controller.adapter._replace_script(body, _native_ball_script)


func _service_active(service) -> bool:
	if not is_instance_valid(service):
		return false
	# Existing MP teardown can restore the wrapper with its own inactive ref still
	# present. Known stopped services relinquish it; preserve an unknown live owner.
	return service.get("_active") != false

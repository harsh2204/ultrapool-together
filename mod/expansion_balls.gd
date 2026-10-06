extends Node
## Coordinator for shop-only expansion sets (PHASES/MORPH/TIDE/RELIC/TAROT/ZODIAC).
## Host-authoritative shared state; guests receive dirty-gated display snapshots.
## Implemented, unmeasured — needs authorized live playtest (PERF-010 state path).

const CatalogUtil = preload("sets/catalog_util.gd")
const Registry = preload("sets/registry.gd")
const MAX_BALLS = 128
const MAX_LAUNCH_SPEED = 420.0

var catalogs: Dictionary = {}
var rules: Dictionary = {}
var _controller: Node
var _ball_script: Script
var _native_ball_script: Script
var _hooked: Dictionary = {}
var _remote: Dictionary = {}
var _last_capture: Dictionary = {}
var _active_flags: Dictionary = {}
var _active = false
var _round_key = ""
var _kind_to_set: Dictionary = {}
var _echo_queue: Array = []
var _locked: Dictionary = {}
var _closed_pocket = null
var _next_ordinary_points = 0.0


func setup(controller: Node) -> bool:
	_controller = controller
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 90
	var base = get_script().resource_path.get_base_dir().path_join("sets")
	var modules = {
		"PHASES": ["phases_catalog.gd", "phases_rules.gd"],
		"MORPH": ["morph_catalog.gd", "morph_rules.gd"],
		"TIDE": ["tide_catalog.gd", "tide_rules.gd"],
		"RELIC": ["relic_catalog.gd", "relic_rules.gd"],
		"TAROT": ["tarot_catalog.gd", "tarot_rules.gd"],
		"ZODIAC": ["zodiac_catalog.gd", "zodiac_rules.gd"]
	}
	for set_id in modules:
		var catalog = load(base.path_join(modules[set_id][0])).new()
		add_child(catalog)
		if not catalog.register_balls():
			return false
		catalogs[set_id] = catalog
		rules[set_id] = load(base.path_join(modules[set_id][1])).new()
		for kind in catalog.kind_ids():
			_kind_to_set[kind] = set_id
	_ball_script = load(get_script().resource_path.get_base_dir().path_join("multiplayer_ball.gd"))
	_native_ball_script = load("res://ball.gd")
	get_tree().node_added.connect(_node_added)
	_active_flags = Registry.default_flags()
	return true


func begin_session(flags: Dictionary) -> void:
	_active_flags = Registry.normalize_flags(flags)
	_active = Registry.any_enabled(_active_flags)
	_round_key = ""
	_remote.clear()
	_last_capture = {}
	_echo_queue.clear()
	_locked.clear()
	_closed_pocket = null
	for set_id in catalogs:
		var enabled = bool(_active_flags.get(set_id, false))
		catalogs[set_id].set_active(enabled)
		if enabled:
			rules[set_id] = (
				load(
					get_script()
					.resource_path
					.get_base_dir()
					.path_join("sets")
					.path_join(_rules_file(set_id))
				)
				.new()
			)


func end_session() -> void:
	_restore_closed_pocket()
	_unlock_all()
	_active = false
	for entry in _hooked.values():
		var body = entry.body.get_ref()
		if is_instance_valid(body) and body.get("expansion_balls") == self:
			body.expansion_balls = null
	_hooked.clear()
	_echo_queue.clear()
	_remote.clear()
	_last_capture = {}
	_round_key = ""
	for set_id in catalogs:
		catalogs[set_id].set_active(false)
	_active_flags = Registry.default_flags()


func _rules_file(set_id: String) -> String:
	return {
		"PHASES": "phases_rules.gd",
		"MORPH": "morph_rules.gd",
		"TIDE": "tide_rules.gd",
		"RELIC": "relic_rules.gd",
		"TAROT": "tarot_rules.gd",
		"ZODIAC": "zodiac_rules.gd"
	}[set_id]


func _process(_delta: float) -> void:
	if not _active or not _controller.is_table_host():
		return
	_sync_round()
	_try_echo()


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
		for set_id in _enabled_sets():
			rules[set_id].reset_round(key)
		_echo_queue.clear()
		_unlock_all()
		_restore_closed_pocket()
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
		if body.get_script() != _ball_script:
			_controller.adapter._replace_script(body, _ball_script)
		body.expansion_balls = self
		if _controller.get("multiplayer_balls") != null:
			body.together_balls = _controller.multiplayer_balls
	var kinds = _kinds(body)
	for kind in kinds:
		var set_id = _kind_to_set.get(kind, "")
		if set_id != "" and bool(_active_flags.get(set_id, false)):
			rules[set_id].register_ball(id, kinds)


func _kinds(body) -> Array:
	var result: Array = []
	for resource in [body.ball_item.data, body.ball_item.mixed_data]:
		if resource == null:
			continue
		var id = str(resource.id)
		if _kind_to_set.has(id) and id not in result:
			result.append(id)
	return result


func _enabled_sets() -> Array:
	var result: Array = []
	for set_id in Registry.SET_IDS:
		if bool(_active_flags.get(set_id, false)):
			result.append(set_id)
	return result


func begin_shot(index: int, _shooter: int) -> bool:
	if not _active:
		return true
	_sync_round()
	_unlock_all()
	_restore_closed_pocket()
	for set_id in _enabled_sets():
		rules[set_id].begin_shot(index)
	return true


func finish_shot() -> void:
	if not _active:
		return
	var survivors: Array = []
	for entry in _hooked.values():
		var body = entry.body.get_ref()
		if is_instance_valid(body) and body.alive and not body.gone:
			survivors.append(body.get_instance_id())
	for set_id in _enabled_sets():
		var result = rules[set_id].finish_shot(survivors)
		if result is Dictionary:
			_apply_action(result, null)
	_unlock_all()
	_restore_closed_pocket()


func record_hit(body, other) -> void:
	if not _active or body.is_passive or not body.alive:
		return
	if not other.alive or other.is_passive:
		return
	if not other is PlayerBall and other.get_script() not in [_native_ball_script, _ball_script]:
		return
	# Cue-ball contacts are reported from the object ball (other is PlayerBall).
	if body is PlayerBall:
		return
	_hook_ball(body)
	var cue_hit = other is PlayerBall
	if not cue_hit:
		_hook_ball(other)
	for set_id in _enabled_sets():
		rules[set_id].mark_object_hit()
	var ordinary = _ordinary_ids()
	for set_id in _enabled_sets():
		if set_id == "MORPH" and not cue_hit:
			continue
		if set_id == "ZODIAC" and not cue_hit:
			# Taurus / form-style reactions are cue-driven; survival uses mark_object_hit.
			continue
		_apply_action(rules[set_id].hit(body.get_instance_id(), ordinary), body)
	if not cue_hit:
		for set_id in _enabled_sets():
			if set_id in ["MORPH", "ZODIAC"]:
				continue
			_apply_action(rules[set_id].hit(other.get_instance_id(), ordinary), other)


func record_wall(body) -> void:
	if not _active or not body.alive:
		return
	_hook_ball(body)
	for set_id in _enabled_sets():
		var action = rules[set_id].wall(body.get_instance_id())
		_apply_action(action, body)


func record_pocket(body, pocket, multiplier: float) -> void:
	if not _active or body.is_passive:
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
	var kinds = _kinds(body)
	var ordinary = kinds.is_empty()
	var value = maxf(0.0, body.get_score())
	var merged = CatalogUtil.empty_action()
	for set_id in _enabled_sets():
		CatalogUtil.merge_action(
			merged, rules[set_id].pocket(body.get_instance_id(), kinds, value, ordinary)
		)
	if _next_ordinary_points > 0.0 and ordinary:
		merged.points += _next_ordinary_points
		_next_ordinary_points = 0.0
	_apply_action(merged, body)


func _apply_action(action: Dictionary, source) -> void:
	if action.is_empty():
		return
	var game = _game()
	if game == null:
		return
	var origin = source.global_position if is_instance_valid(source) else Vector2.ZERO
	if action.points > 0:
		game.add_score(action.points, origin, false, true, source, false)
	if action.money > 0:
		game.player_info.gain_money(action.money)
		game.table.update_money(game.player_info.money)
		game.display_money(action.money, origin)
	if action.heal > 0 and game.player_info.hp < game.get_max_hp():
		game.player_info.hp = mini(game.get_max_hp(), game.player_info.hp + action.heal)
		game.update_hp(game.player_info.hp)
	for entry in action.get("temp", []):
		var body = _body_for(int(entry.get("id", 0)))
		if not is_instance_valid(body) or body.ball_item == null:
			continue
		var amount = int(entry.get("amount", 0))
		if amount <= -999:
			body.ball_item.temp_extra_score = 0
		else:
			body.ball_item.temp_extra_score = maxi(0, int(body.ball_item.temp_extra_score) + amount)
	for entry in action.get("weight", []):
		var body = _body_for(int(entry.get("id", 0)))
		if not is_instance_valid(body) or body.ball_item == null:
			continue
		body.ball_item.weight_state = clampi(
			int(body.ball_item.weight_state) + int(entry.get("delta", 0)), 0, 3
		)
	if action.close_top_pocket:
		_close_top_pocket(game)
	if action.launch_nearest:
		_launch_nearest(game, source)
	if action.spawn_echo and is_instance_valid(source):
		_echo_queue.append(weakref(source))
	if action.lock_random:
		_lock_random(game, source)
	if action.clear_temps:
		_clear_all_temps(game)
	if action.consume_nearest:
		_consume_or_shade(game, source, false, action)
	if action.shade_nearest:
		_consume_or_shade(game, source, true, action)
	if action.strip_and_spread:
		_strip_and_spread(game)


func _body_for(id: int):
	if not _hooked.has(id):
		return null
	return _hooked[id].body.get_ref()


func _ordinary_ids() -> Array:
	var ids: Array = []
	for id in _hooked:
		var body = _hooked[id].body.get_ref()
		if (
			is_instance_valid(body)
			and body.alive
			and not body.gone
			and _kinds(body).is_empty()
			and not body.is_passive
		):
			ids.append(id)
	return ids


func _close_top_pocket(game) -> void:
	_restore_closed_pocket()
	var best = null
	var best_mult = -1.0
	for pocket in game.table.get_node("Pockets").get_children():
		if pocket.closed:
			continue
		var mult = float(pocket.get("multiplier")) if pocket.get("multiplier") != null else 1.0
		if mult > best_mult:
			best_mult = mult
			best = pocket
	if best != null:
		best.closed = true
		var anim = best.get_node_or_null("%AnimationPlayer")
		if anim != null:
			anim.play("close")
		_closed_pocket = weakref(best)


func _restore_closed_pocket() -> void:
	if _closed_pocket == null:
		return
	var pocket = _closed_pocket.get_ref()
	if is_instance_valid(pocket):
		pocket.closed = false
		var anim = pocket.get_node_or_null("%AnimationPlayer")
		if anim != null:
			anim.play("open")
	_closed_pocket = null


func _launch_nearest(game, source) -> void:
	if not is_instance_valid(source):
		return
	var best = null
	var best_dist = INF
	for body in game.balls:
		if (
			not is_instance_valid(body)
			or body == source
			or not body.alive
			or body.gone
			or body.is_passive
			or body is PlayerBall
			or not _kinds(body).is_empty()
		):
			continue
		var dist = source.global_position.distance_squared_to(body.global_position)
		if dist < best_dist:
			best_dist = dist
			best = body
	if best != null:
		var direction = (best.global_position - source.global_position).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT
		best.linear_velocity = direction * MAX_LAUNCH_SPEED


func _lock_random(game, source) -> void:
	var candidates: Array = []
	for body in game.balls:
		if (
			not is_instance_valid(body)
			or body == source
			or not body.alive
			or body.gone
			or body.is_passive
			or body is PlayerBall
		):
			continue
		var kinds = _kinds(body)
		var is_relic_or_zodiac = false
		for kind in kinds:
			var set_id = _kind_to_set.get(kind, "")
			if set_id in ["RELIC", "ZODIAC"]:
				is_relic_or_zodiac = true
				break
		if is_relic_or_zodiac:
			continue
		candidates.append(body)
	if candidates.is_empty():
		return
	var pick = candidates[absi(hash(str(shot_seed()))) % candidates.size()]
	pick.ball_item.locked = true
	_locked[pick.get_instance_id()] = weakref(pick)


func shot_seed() -> int:
	return int(_controller.shot_number) if _controller != null else 0


func _unlock_all() -> void:
	for id in _locked.keys():
		var body = _locked[id].get_ref()
		if is_instance_valid(body) and body.ball_item != null:
			body.ball_item.locked = false
	_locked.clear()


func _clear_all_temps(game) -> void:
	for body in game.balls:
		if is_instance_valid(body) and body.ball_item != null:
			body.ball_item.temp_extra_score = 0


func _consume_or_shade(game, source, as_shade: bool, action: Dictionary) -> void:
	if not is_instance_valid(source) or source.ball_item == null:
		return
	var source_base = int(source.ball_item.data.base_score)
	var best = null
	var best_dist = INF
	for body in game.balls:
		if (
			not is_instance_valid(body)
			or body == source
			or not body.alive
			or body.gone
			or body.is_passive
			or body is PlayerBall
			or not _kinds(body).is_empty()
			or body.ball_item == null
			or int(body.ball_item.data.base_score) >= source_base
		):
			continue
		var dist = source.global_position.distance_squared_to(body.global_position)
		if dist < best_dist:
			best_dist = dist
			best = body
	if best == null:
		return
	if as_shade:
		best.ball_item.base_score = 0
		best.ball_item.fleeting = true
		if best.has_method("set_fleeting"):
			best.set_fleeting()
	else:
		var level = maxi(1, int(best.ball_item.level))
		var rate = float(action.get("consume_rate", 0.5))
		if rate <= 0.0:
			rate = 0.5
		var bonus = ceilf(maxf(0.0, source.get_score()) * rate * level)
		game.add_score(bonus, source.global_position, false, true, source, false)
		best.alive = false
		best.gone = true
		best.visible = false
		game.pocketed_balls.append(best)


func _strip_and_spread(game) -> void:
	var with_temp: Array = []
	var others: Array = []
	for body in game.balls:
		if not is_instance_valid(body) or not body.alive or body.ball_item == null:
			continue
		if int(body.ball_item.temp_extra_score) > 0:
			with_temp.append(body)
		else:
			others.append(body)
	if with_temp.is_empty():
		return
	var victim = with_temp[0]
	victim.ball_item.temp_extra_score = 0
	var granted = 0
	for body in others:
		if granted >= 2:
			break
		body.ball_item.temp_extra_score = int(body.ball_item.temp_extra_score) + 1
		granted += 1


func _try_echo() -> void:
	if _echo_queue.is_empty():
		return
	var game = _game()
	if game == null or get_tree().paused or game.balls_moving or game.in_shop:
		return
	for moving in game.balls:
		if is_instance_valid(moving) and moving.is_moving():
			return
	var source = _echo_queue.pop_back().get_ref()
	if not is_instance_valid(source):
		return
	# Spawn a fleeting zero-score copy near the pocketed ball's last position.
	if game.has_method("respawn_specific_ball"):
		var echo = source.duplicate()
		if echo != null and echo.ball_item != null:
			echo.ball_item = source.ball_item.duplicate(true)
			echo.ball_item.base_score = 0
			echo.ball_item.fleeting = true
			echo.ball_item.temp_extra_score = 0
			game.add_child(echo)
			echo.global_position = source.global_position + Vector2(24, 0)
			if echo.has_method("set_fleeting"):
				echo.set_fleeting()
			game.delay_round_end(0.5)


func prepare_shop() -> void:
	if not _active or not _controller.is_table_host():
		return
	var game = _game()
	if game == null or not game.in_shop:
		return
	var shop = get_node("/root/Global").shopManager
	# One offer attempt per enabled set; each uses its own stock key / chance gate.
	for set_id in _enabled_sets():
		catalogs[set_id].ensure_shop_offer(shop)


## Presentation input for the shared ability overlay (MOD-07..12): the host's
## latest published capture, or the validated remote state on guests. Never
## captures per frame (PERF-028).
func display_state() -> Dictionary:
	return _last_capture if _controller.is_table_host() else _remote


func capture() -> Dictionary:
	if not _active:
		_last_capture = {}
		return {}
	var data = {"sets": {}, "balls": []}
	for set_id in _enabled_sets():
		if rules[set_id].has_method("capture_shared"):
			data.sets[set_id] = rules[set_id].capture_shared()
	var count = 0
	for id in _hooked:
		if count >= MAX_BALLS:
			break
		var body = _hooked[id].body.get_ref()
		if not is_instance_valid(body):
			continue
		var kinds = _kinds(body)
		if kinds.is_empty():
			continue
		var entry = {
			"id": id,
			"kinds": kinds.duplicate(),
			"name": body.ball_item.get_formatted_name(),
			"position": body.global_position,
			"color": body.ball_item.data.main_color,
			"alive": body.alive and body.visible and not body.gone,
			"extra": {}
		}
		for kind in kinds:
			var set_id = _kind_to_set.get(kind, "")
			if set_id != "" and rules[set_id].has_method("capture_ball"):
				entry.extra[set_id] = rules[set_id].capture_ball(id)
		data.balls.append(entry)
		count += 1
	_last_capture = data
	return data


func apply_state(data: Dictionary) -> void:
	_remote = data.duplicate(true)


func display_signature(data: Dictionary = {}) -> Array:
	var signature: Array = []
	var sets: Dictionary = data.get("sets", {})
	for set_id in Registry.SET_IDS:
		signature.append(sets.get(set_id, {}))
	for ball in data.get("balls", []):
		if not ball is Dictionary:
			continue
		signature.append(
			[
				ball.get("id", 0),
				ball.get("alive", false),
				ball.get("extra", {}),
				ball.get("kinds", [])
			]
		)
	return signature


func valid_state(data) -> bool:
	if not data is Dictionary:
		return false
	if data.is_empty():
		return true
	if not data.get("sets") is Dictionary or not data.get("balls") is Array:
		return false
	if data.balls.size() > MAX_BALLS or data.sets.size() > Registry.SET_IDS.size():
		return false
	for set_id in data.sets:
		if set_id not in Registry.SET_IDS or not _valid_shared_display(set_id, data.sets[set_id]):
			return false
	var ids: Dictionary = {}
	for ball in data.balls:
		if (
			not ball is Dictionary
			or not ball.get("id") is int
			or ball.id <= 0
			or ids.has(ball.id)
			or not ball.get("kinds") is Array
			or ball.kinds.is_empty()
			or ball.kinds.size() > 4
			or not ball.get("name") is String
			or ball.name.length() > 160
			or not ball.get("position") is Vector2
			or not ball.position.is_finite()
			or ball.position.length() > 100000
			or not ball.get("color") is Color
			or not ball.get("alive") is bool
			or not ball.get("extra") is Dictionary
		):
			return false
		for channel in [ball.color.r, ball.color.g, ball.color.b, ball.color.a]:
			if not is_finite(channel):
				return false
		var seen_kinds: Dictionary = {}
		var ball_sets: Dictionary = {}
		for kind in ball.kinds:
			if not _kind_to_set.has(kind) or seen_kinds.has(kind):
				return false
			seen_kinds[kind] = true
			ball_sets[_kind_to_set[kind]] = true
		if ball.extra.size() > ball_sets.size():
			return false
		for set_id in ball.extra:
			if not ball_sets.has(set_id) or not _valid_ball_display(set_id, ball.extra[set_id]):
				return false
		ids[ball.id] = true
	return true


## Display schemas are checked at the network boundary before the overlay reads
## them. Fixed keys bound panel work; ranges match each authoritative rules model.
func _valid_shared_display(set_id: String, data) -> bool:
	if not data is Dictionary:
		return false
	match set_id:
		"PHASES":
			return data.size() == 2 and _display_int(data.get("phase"), 0, 3) and _display_int(data.get("silent"), 0, 2)
		"TIDE":
			return data.size() == 1 and _display_int(data.get("height"), 0, 3)
		"MORPH":
			return data.size() == 2 and data.get("form_changes") is int and data.form_changes >= 0 and data.get("prime") is bool
		"RELIC":
			return data.size() == 2 and data.get("persist") is bool and _display_int(data.get("idol_temps"), 0, 3)
		"TAROT":
			if data.size() != 1 or not data.get("spread") is Array or data.spread.size() > 3:
				return false
			var seen: Dictionary = {}
			for kind in data.spread:
				if _kind_to_set.get(kind, "") != "TAROT" or seen.has(kind):
					return false
				seen[kind] = true
			return true
		"ZODIAC":
			if data.size() != 1 or not data.get("align") is Dictionary or data.align.size() != 4:
				return false
			for element in ["fire", "earth", "air", "water"]:
				if not _display_int(data.align.get(element), 0, 3):
					return false
			return true
	return false


func _valid_ball_display(set_id: String, data) -> bool:
	if not data is Dictionary:
		return false
	# A registered resource may be captured before its first host rule hook.
	if data.is_empty():
		return set_id in ["MORPH", "RELIC", "TAROT", "ZODIAC"]
	match set_id:
		"MORPH":
			return data.size() == 3 and _display_int(data.get("form"), 0, 1) and _display_int(data.get("charge"), 0, 1) and data.get("marked") is bool
		"RELIC":
			return data.size() == 1 and _display_int(data.get("dig"), 0, 4)
		"TAROT":
			return data.size() == 3 and data.get("upright") is bool and data.get("in_spread") is bool and _display_int(data.get("charge"), 0, 1)
		"ZODIAC":
			return data.size() == 1 and _display_int(data.get("charge"), 0, 2)
	return false


static func _display_int(value, minimum: int, maximum: int) -> bool:
	return value is int and value >= minimum and value <= maximum

extends Node

## Host-authoritative between-round set voting. Replaces the native random set
## roll: the table host gathers candidates, members vote, majority (host
## tiebreak) applies the chosen set on every member via shop sync.

const SetVote = preload("set_vote.gd")
const TIMEOUT_MSEC = 30000
const CANDIDATE_COUNT = 3

var _controller: Node
var _vote = SetVote.new()
var _panel: Control
var _title: Label
var _timer: Label
var _buttons: VBoxContainer
var _round_key = ""
var _applied_key = ""
var _pending_options: Array[String] = []


func setup(controller: Node) -> void:
	_controller = controller
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func begin_session() -> void:
	_vote.clear()
	_round_key = ""
	_applied_key = ""
	_pending_options.clear()
	if _controller.shop_sync != null:
		_controller.shop_sync.set_vote_hold(false)
	_hide()


func end_session() -> void:
	begin_session()


func active() -> bool:
	return _vote.active()


func snapshot() -> Dictionary:
	return _vote.snapshot()


func _process(_delta: float) -> void:
	if _controller == null or not _controller.active:
		_hide()
		return
	if _controller.is_table_host():
		_host_tick()
	_render()


func _host_tick() -> void:
	var shop = _controller.shop_sync.open_shop() if _controller.shop_sync != null else null
	if shop == null:
		if _vote.active():
			_abort_vote()
		return
	var game = get_node("/root/Global").gameManager
	if not is_instance_valid(game):
		return
	var key = "%d:%d" % [shop.get_instance_id(), game.rounds_played]
	if key != _round_key:
		_round_key = key
		if _applied_key != key:
			_try_start_vote(shop, game, key)
	if _vote.active() and (_vote.everyone_voted() or _vote.timed_out()):
		_finish_vote(shop, key, _vote.timed_out())


func _try_start_vote(shop, game, key: String) -> void:
	if game.rounds_played < 1:
		return
	var options = _candidate_sets(shop, game)
	if options.size() < 2:
		return
	var members: Array = _controller._members(_controller.table_id).map(
		func(player): return player.id
	)
	if members.is_empty():
		return
	var context = {"round": game.rounds_played, "scene": shop.get_instance_id()}
	if not _vote.configure(members, options, _controller.table_leader_id, context, TIMEOUT_MSEC):
		return
	_pending_options = options.duplicate()
	_controller.shop_sync.set_vote_hold(true)
	_vote.cast(_controller.table_leader_id, options[0])
	_broadcast({"kind": "set_vote", "action": "open", "vote": _vote.snapshot()})
	_controller._status("Vote for the next set. Majority wins; host breaks ties.")


func _candidate_sets(shop, game) -> Array[String]:
	var database = get_node("/root/BallDatabase")
	var deck_set = _deck_set_id()
	var pool: Array[String] = []
	for set_id in database.id_to_set.keys():
		var id = str(set_id)
		if id.is_empty() or id == deck_set or id == "DAILY" or id == "TOGETHER":
			continue
		var resource = database.id_to_set[set_id]
		if resource != null and _has_property(resource, "can_be_chosen") and not resource.can_be_chosen:
			continue
		pool.append(id)
	pool.sort()
	if pool.size() < 2:
		for offered in shop.sets_offered:
			var id = str(offered)
			if id.is_empty() or id == deck_set or pool.has(id):
				continue
			pool.append(id)
	if pool.size() < 2:
		return []
	var generator = RandomNumberGenerator.new()
	var seed_value = int(get_node("/root/Global").get("seed"))
	generator.seed = hash("%s:%s:%s" % [str(seed_value), str(game.rounds_played), deck_set])
	var picks: Array[String] = []
	var remaining = pool.duplicate()
	while picks.size() < mini(CANDIDATE_COUNT, remaining.size()):
		var index = generator.randi_range(0, remaining.size() - 1)
		picks.append(remaining[index])
		remaining.remove_at(index)
	return picks


func _deck_set_id() -> String:
	var deck = get_node("/root/Global").chosen_deck
	if deck == null:
		return ""
	if _has_property(deck, "from_set") and str(deck.from_set) != "":
		return str(deck.from_set)
	return str(deck.id)


func handle_table_message(actor: int, message: Dictionary) -> bool:
	if message.get("kind") != "set_vote":
		return false
	var action = str(message.get("action", ""))
	if _controller.is_table_host():
		if action == "cast" and message.get("option") is String and message.get("revision") is int:
			if not _vote.cast(actor, message.option, message.revision):
				_controller._table_send(
					{"kind": "set_vote", "action": "reject", "error": _vote.last_error}, actor
				)
				return true
			_broadcast({"kind": "set_vote", "action": "update", "vote": _vote.snapshot()})
			var shop = _controller.shop_sync.open_shop()
			if shop != null and (_vote.everyone_voted() or _vote.timed_out()):
				var game = get_node("/root/Global").gameManager
				var key = (
					"%d:%d" % [shop.get_instance_id(), game.rounds_played]
					if is_instance_valid(game)
					else _round_key
				)
				_finish_vote(shop, key, _vote.timed_out())
		return true
	if actor != _controller.table_leader_id:
		return true
	match action:
		"open", "update":
			if message.get("vote") is Dictionary:
				_apply_remote_vote(message.vote)
		"result":
			if message.get("vote") is Dictionary:
				_apply_remote_vote(message.vote)
			_controller.shop_sync.set_vote_hold(false)
			_hide()
		"reject":
			_controller._status(str(message.get("error", "Set vote rejected.")))
	return true


func cast_local(option: String) -> void:
	if not _vote.active() or not _pending_options.has(option):
		return
	if _controller.is_table_host():
		_vote.cast(_controller.transport.local_id(), option, _vote.revision)
		_broadcast({"kind": "set_vote", "action": "update", "vote": _vote.snapshot()})
		var shop = _controller.shop_sync.open_shop()
		if shop != null and _vote.everyone_voted():
			var game = get_node("/root/Global").gameManager
			var key = (
				"%d:%d" % [shop.get_instance_id(), game.rounds_played]
				if is_instance_valid(game)
				else _round_key
			)
			_finish_vote(shop, key, false)
		return
	_controller._table_send(
		{"kind": "set_vote", "action": "cast", "option": option, "revision": _vote.revision}
	)


func _finish_vote(shop, key: String, timed_out: bool) -> void:
	if not _vote.active():
		return
	var chosen = _vote.host_default() if timed_out and not _vote.everyone_voted() else _vote.resolve()
	_apply_set(shop, chosen)
	_applied_key = key
	_controller.shop_sync.set_vote_hold(false)
	var result = _vote.snapshot()
	result["chosen"] = chosen
	result["timed_out"] = timed_out
	_broadcast({"kind": "set_vote", "action": "result", "vote": result, "chosen": chosen})
	_vote.clear()
	_pending_options.clear()
	_hide()
	_controller._publish_state()
	_controller._status("Set locked in: %s" % _label_for(chosen))


func _apply_set(shop, chosen: String) -> void:
	if not is_instance_valid(shop) or chosen.is_empty():
		return
	var deck_set = _deck_set_id()
	var offered: Array = []
	if not deck_set.is_empty():
		offered.append(deck_set)
	if chosen != deck_set and not offered.has(chosen):
		offered.append(chosen)
	for existing in shop.sets_offered:
		var id = str(existing)
		if id.is_empty() or offered.has(id):
			continue
		if offered.size() >= 3:
			break
		offered.append(id)
	shop.sets_offered = offered
	if shop.has_method("display_sets_offered"):
		shop.display_sets_offered()


func _abort_vote() -> void:
	_vote.clear()
	_pending_options.clear()
	_controller.shop_sync.set_vote_hold(false)
	_broadcast({"kind": "set_vote", "action": "result", "vote": _vote.snapshot(), "chosen": ""})
	_hide()


func _apply_remote_vote(data: Dictionary) -> void:
	_pending_options.clear()
	for option in data.get("options", []):
		if option is String:
			_pending_options.append(option)
	if not data.get("active", false) or _pending_options.size() < 2:
		_vote.clear()
		_controller.shop_sync.set_vote_hold(false)
		return
	_vote.import_snapshot(data)
	_controller.shop_sync.set_vote_hold(true)


func _broadcast(message: Dictionary) -> void:
	_controller._table_send(message)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_controller.ui_root.add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -220
	_panel.offset_right = 220
	_panel.offset_top = -160
	_panel.offset_bottom = 160
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	_title = Label.new()
	_title.text = "Vote for the next set"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_timer = Label.new()
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_timer)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 6)
	column.add_child(_buttons)


func _render() -> void:
	var show = (
		_controller.active
		and _vote.active()
		and not _controller.is_spectating()
		and not _controller.panel.visible
	)
	_panel.visible = show
	if not show:
		return
	var snap = _vote.snapshot()
	var seconds = ceili(float(snap.remaining_msec) / 1000.0)
	_timer.text = "%d s left · majority wins, host breaks ties" % seconds
	for child in _buttons.get_children():
		child.queue_free()
	var local = _controller.transport.local_id()
	var my_vote = str(snap.votes.get(local, ""))
	if my_vote.is_empty():
		my_vote = str(snap.votes.get(str(local), ""))
	for option in snap.options:
		var count = int(snap.tally.get(option, 0))
		var button = Button.new()
		button.text = "%s · %d" % [_label_for(option), count]
		button.disabled = my_vote == option
		button.pressed.connect(func(): cast_local(option))
		_buttons.add_child(button)


func _hide() -> void:
	if _panel != null:
		_panel.visible = false


func _label_for(set_id: String) -> String:
	var database = get_node_or_null("/root/BallDatabase")
	if database != null and database.id_to_set.has(set_id):
		var resource = database.id_to_set[set_id]
		for field in ["title", "name", "display_name"]:
			if not _has_property(resource, field):
				continue
			var value = str(resource.get(field)).strip_edges()
			if not value.is_empty():
				return value
	return set_id


func _has_property(object, property_name: String) -> bool:
	if object == null:
		return false
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false

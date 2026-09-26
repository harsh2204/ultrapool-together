extends Node

signal request(message: Dictionary)

const GROUPS = ["offer", "build", "snack", "passive", "mix"]
const MAX_SLOTS = 64

var last_error = ""
var _controller: Node
var _state: Dictionary = {}
var _authoritative_state: Dictionary = {}
var _last_capture: Dictionary = {}
var _revision = 0
var _native_slots: Dictionary = {}
var _bound_items: Dictionary = {}
var _bound_buttons: Dictionary = {}
var _tutorial_enabled = true
var _tutorial_saved = false
var _was_finished = false
var _pending = false
var _pending_at = 0
var _request_id = 0
var _pending_message: Dictionary = {}
var _ball_script: Script
var _passive_script: Script
var _panel: Control
var _notice: Label
var _view: Node
var _guest_view: Node
var _guest_game: Node
var _saved_deck: Resource
var _saved_difficulty: Resource
var _guest_context_saved = false
var _view_slots: Dictionary = {}
var _ready_vote: RefCounted
var _continuing = false
var _actions_blocked = false


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 500
	var directory = get_script().resource_path.get_base_dir()
	_ball_script = load(directory.path_join("native_shop_ball.gd"))
	_passive_script = load(directory.path_join("native_shop_passive.gd"))
	get_tree().node_added.connect(_node_added)
	_ready_vote = load(get_script().resource_path.get_base_dir().path_join("team_vote.gd")).new()
	_build_ui()


func begin_session(controller: Node):
	_controller = controller
	_revision = 0
	_last_capture.clear()
	_state.clear()
	_authoritative_state.clear()
	_pending = false
	_pending_message.clear()
	_request_id = 0
	_ready_vote.configure([])
	_continuing = false
	_actions_blocked = false
	_was_finished = _controller.finished
	if _controller.is_table_host():
		var tutorial = get_node("/root/TutorialManager")
		_tutorial_enabled = tutorial.ENABLED
		_tutorial_saved = true
		tutorial.ENABLED = false
		if tutorial.active_popup != null:
			tutorial.cancel()


func end_session():
	if _tutorial_saved:
		get_node("/root/TutorialManager").ENABLED = _tutorial_enabled
		_tutorial_saved = false
	_restore_items()
	_clear_guest_view()
	_view = null
	_view_slots.clear()
	_controller = null
	_state.clear()
	_authoritative_state.clear()
	_last_capture.clear()
	_native_slots.clear()
	_pending = false
	_pending_message.clear()
	_ready_vote.configure([])
	_continuing = false
	_panel.hide()


func is_open() -> bool:
	return _controller != null and _state.get("open", false)


func presence_rect() -> Rect2:
	return get_viewport().get_visible_rect() if is_open() and _panel.visible else Rect2()


func presence_target() -> String:
	if not is_instance_valid(_view) or not _panel.visible:
		return ""
	return _slot_key(_view.get_hovered_slot())


static func presence_slot_key(group: String, index: int) -> String:
	return "%s:%d" % [group, index]


static func presence_target_resolves(slots: Dictionary, key: String, panel_visible: bool) -> bool:
	return panel_visible and not key.is_empty() and slots.has(key)


func presence_target_position(key: String) -> Vector2:
	if not presence_target_resolves(_view_slots, key, _panel.visible):
		return Vector2(INF, INF)
	var slot = _view_slots[key]
	var position = slot_screen_position(key)
	if slot.is_visible_in_tree() and get_viewport().get_visible_rect().has_point(position):
		return position
	return Vector2(INF, INF)


func _process(_delta):
	if _controller == null:
		return
	_panel.visible = (
		is_open()
		and not _controller.panel.visible
		and not get_node("/root/UIManager").is_popup_open()
	)
	if is_open():
		if (
			not is_instance_valid(_view)
			or (
				not _controller.is_table_host()
				and _guest_game != get_node("/root/Global").gameManager
			)
		):
			_render()
		if is_instance_valid(_view):
			if not _controller.is_table_host():
				get_node("/root/Global").camera.move(_view.get_camera_target())
				var floor_texture = (
					_guest_game.table.get_node("TableCustomization").shop_floor.texture
				)
				if _view.get_node("%ShopFloor").texture != floor_texture:
					_view.set_floor(floor_texture)
			_update_actions()
	if _was_finished != _controller.finished:
		_was_finished = _controller.finished
		_update_actions()
	if _pending and Time.get_ticks_msec() - _pending_at > 5000:
		_pending = false
		_pending_message.clear()
		_display_state(_authoritative_state)
		_notice.text = "Waiting for the shop update. Try your action again."
		_notice.show()
		_update_actions()
		request.emit({"kind": "sync_request"})


func _shop():
	var game = get_node("/root/Global").gameManager
	if not is_instance_valid(game) or not game.in_shop or not is_instance_valid(game.shop):
		return null
	return game.shop if game.shop.is_open else null


func capture() -> Dictionary:
	if _controller == null or not _controller.is_table_host():
		return {}
	var shop = _shop()
	var data = {"open": shop != null}
	_native_slots.clear()
	if shop != null:
		var bar = shop.cocktail_bar
		var info = shop.player_info
		var busy: bool = get_tree().paused or shop.introt > 0 or bar.mix_animation.is_processing()
		data.merge(
			{
				"scene": shop.get_instance_id(),
				"round": get_node("/root/Global").gameManager.level_number,
				"money": info.money,
				"hp": info.hp,
				"deck": str(get_node("/root/Global").chosen_deck.id),
				"difficulty": str(get_node("/root/Global").chosen_difficulty.id),
				"sets": shop.sets_offered.map(func(id): return str(id)),
				"snacks": info.snack_tickets,
				"cocktails": info.cocktail_tickets,
				"reroll": shop.roll_cost,
				"busy": busy,
				"can_mix":
				(
					not busy
					and bar.slot_center.is_empty()
					and bar.can_mix()
					and info.cocktail_tickets > 0
				),
				"can_continue":
				(
					not busy
					and bar.slot_left.is_empty()
					and bar.slot_right.is_empty()
					and bar.slot_center.is_empty()
				),
				"slots": []
			}
		)
		var groups = {
			"offer": shop.shop_slots,
			"build": shop.get_inventory_slots(),
			"snack": shop.tapas_bar.slots,
			"passive": shop.get_passive_slots(),
			"mix": [bar.slot_left, bar.slot_right, bar.slot_center]
		}
		for group in GROUPS:
			for index in groups[group].size():
				var key = "%s:%d" % [group, index]
				var slot = groups[group][index]
				_native_slots[key] = slot
				data.slots.append(_pack_slot(group, index, slot))
		var consent_context = data.duplicate(true)
		for field in ["busy", "can_mix", "can_continue"]:
			consent_context.erase(field)
		var members: Array = _controller._members(_controller.table_id).map(
			func(player): return player.id
		)
		_ready_vote.configure(members, consent_context)
		data["ready_vote"] = _ready_vote.snapshot()
	else:
		_ready_vote.configure([])
		_continuing = false
	if data != _last_capture:
		_revision += 1
		_last_capture = data.duplicate(true)
	data["revision"] = _revision
	apply_state(data)
	return data


func _pack_slot(group: String, index: int, slot) -> Dictionary:
	var passive = group in ["snack", "passive"]
	var object = slot.item if passive else slot.ball
	var packed = {"key": "%s:%d" % [group, index], "group": group, "index": index, "id": 0}
	if not is_instance_valid(object) or object.is_queued_for_deletion():
		return packed
	var item = object.get_item()
	packed.merge(
		{
			"id": object.get_instance_id(),
			"data": str(item.data.id),
			"mixed": str(item.mixed_data.id) if item.mixed_data != null else "",
			"level": item.level,
			"score": item.get_score(),
			"price": slot.get_price() if not passive else 0,
			"sell": item.get_sell_price()
		},
		true
	)
	return packed


func handle_request(message: Dictionary, actor: int = 0) -> bool:
	last_error = ""
	if _controller == null or not _controller.is_table_host():
		return false
	if _controller.finished:
		return _reject("This table has finished. Return to the lobby to play again.")
	if actor == 0:
		actor = _controller.transport.local_id()
	if not message.get("revision") is int or not message.get("action") is String:
		return _reject("Invalid shop action.")
	var action: String = message.action
	if (
		action == "ready"
		and (not message.get("ready") is bool or not message.get("ready_generation") is int)
	):
		return _reject("Invalid shop ready vote.")
	capture()
	if not is_open():
		return _reject("The shop changed. Please choose again.")
	if action == "ready":
		if message.ready_generation != _ready_vote.revision:
			return _reject("The shop changed. Ready up again when you are finished shopping.")
	elif message.revision != _revision:
		return _reject("The shop changed. Please choose again.")
	if not _state.ready_vote.eligible.has(actor):
		return _reject("Only connected teammates can use this shop.")
	if _continuing:
		return _reject("The next round is starting.")
	if _state.busy:
		return _reject("Wait for the shop animation to finish.")
	var shop = _shop()
	_cancel_native_drag()
	match action:
		"reroll":
			if shop.player_info.money < shop.roll_cost:
				return _reject("Not enough shared money to reroll.")
			shop._on_reroll_button_pressed()
		"ready":
			if not _state.can_continue:
				return _reject("Return the cocktail balls to your build before continuing.")
			if not _ready_vote.set_ready(actor, message.ready, message.ready_generation):
				return _reject(_ready_vote.last_error)
			if _ready_vote.unanimous():
				_continuing = true
				shop._on_play_button_pressed()
		"mix":
			if not _state.can_mix:
				return _reject("Choose two different, unmixed balls and a cocktail ticket.")
			shop.cocktail_bar._on_mix_pressed()
		"move", "sell":
			if not _apply_item_action(shop, message):
				return false
		_:
			return _reject("Unknown shop action.")
	if is_instance_valid(shop) and shop.is_open:
		shop.save_run_state()
	capture()
	return true


func _apply_item_action(shop, message: Dictionary) -> bool:
	var source_key = message.get("source", "")
	if not source_key is String or not _native_slots.has(source_key):
		return _reject("Choose an item first.")
	var source = _native_slots[source_key]
	var group = source_key.get_slice(":", 0)
	var passive = group in ["snack", "passive"]
	var item = source.item if passive else source.ball
	if (
		not is_instance_valid(item)
		or item.is_queued_for_deletion()
		or item.get_instance_id() != message.get("item_id")
	):
		return _reject("That item has already moved. Please choose again.")
	if message.action == "sell":
		if group not in ["build", "passive"]:
			return _reject("Only items in your build can be sold.")
		if not shop.try_sell(item):
			return _reject("This item cannot be sold.")
		var events = get_node("/root/Global").eventManager
		if passive:
			events.run_event("SELL-ANOTHER", item)
			events.run_event_on_ball("SELL-SELF", item)
			item.set_slot(null)
			item.queue_free()
		else:
			item.break_shop_ball()
			events.run_event("SELL-ANOTHER", item)
			events.run_event_on_ball("SELL-SELF", item)
		shop.on_item_sold(item)
		return true
	var target_key = message.get("target", "")
	if not target_key is String or not _native_slots.has(target_key) or target_key == source_key:
		return _reject("Choose a different destination.")
	var target = _native_slots[target_key]
	var target_group = target_key.get_slice(":", 0)
	var target_passive = target_group in ["snack", "passive"]
	var target_item = target.item if target_passive else target.ball
	var target_id: int = target_item.get_instance_id() if is_instance_valid(target_item) else 0
	if target_id != message.get("target_id"):
		return _reject("Your partner changed that slot. Please choose again.")
	if passive:
		if target_group != "passive":
			return _reject("Place snacks in a passive slot.")
		if group == "snack":
			if shop.player_info.snack_tickets <= 0 or target_item != null:
				return _reject("Buying a snack needs a ticket and an empty passive slot.")
			item.set_slot(target)
			shop.buy_passive(item, target)
			shop.on_item_bought(item)
		else:
			_swap(item, target, target_item)
		return true
	if target_group not in ["build", "mix"]:
		return _reject("Place balls in your build, reserve, or cocktail slots.")
	if target_group == "mix":
		if (
			group != "build"
			or target_key == "mix:2"
			or target_item != null
			or shop.player_info.cocktail_tickets <= 0
		):
			return _reject("Place a ball from your build into an empty cocktail ingredient slot.")
		if item.ball_item.is_mixed() or not shop.cocktail_bar.slot_center.is_empty():
			return _reject("Collect the mixed ball first; ingredients must be unmixed balls.")
		item.set_slot(target)
		return true
	if group == "offer":
		if target_item != null:
			if not item.try_upgrade(target_item):
				return _reject("Choose an empty slot or an affordable matching ball to merge.")
			shop.buy_ball(item, source, target, target_item)
			shop.report_upgrade(target_item)
			shop.on_item_upgraded(item)
		else:
			if not get_node("/root/Global").gameManager.try_buy(source.get_price()):
				return _reject("Not enough shared money to buy this ball.")
			item.set_slot(target)
			shop.buy_ball(item, source, target, null)
			shop.on_item_bought(item)
	elif group == "mix":
		if target_item != null:
			return _reject("Move the cocktail ball to an empty build or reserve slot.")
		item.set_slot(target)
	elif target_item != null and item.try_upgrade(target_item):
		shop.report_upgrade(target_item)
		shop.on_item_upgraded(item)
	else:
		_swap(item, target, target_item)
	return true


func _swap(item, target, other):
	var source = item.slot
	item.set_slot(null)
	if other != null:
		other.set_slot(source)
	item.set_slot(target)


func _reject(reason: String) -> bool:
	last_error = reason
	return false


func apply_result(accepted: bool, reason = "", request_id: int = 0, shop: Dictionary = {}):
	if request_id != 0 and request_id != _pending_message.get("request_id", 0):
		return
	_pending = false
	_pending_message.clear()
	if not shop.is_empty():
		apply_state(shop)
	if not _authoritative_state.is_empty():
		_display_state(_authoritative_state)
	if not accepted:
		_notice.text = reason if reason != "" else "The shop changed. Please choose again."
		_notice.show()
	else:
		_notice.hide()
	_update_actions()


func apply_state(data: Dictionary) -> bool:
	if not _valid_state(data):
		return false
	if data.get("revision", -1) < _authoritative_state.get("revision", -1):
		return true
	_authoritative_state = data.duplicate(true)
	if not data.open:
		_pending = false
		_pending_message.clear()
	_display_state(_predict_state(data, _pending_message) if _pending else data)
	return true


func _display_state(data: Dictionary):
	if data == _state and (not data.get("open", false) or is_instance_valid(_view)):
		return
	var was_open: bool = _state.get("open", false)
	_state = data.duplicate(true)
	_panel.visible = data.open and not get_node("/root/UIManager").is_popup_open()
	if not data.open:
		_restore_items()
		_clear_guest_view()
		_view = null
		_view_slots.clear()
		_actions_blocked = false
		return
	if not was_open:
		get_viewport().gui_release_focus()
	_notice.hide()
	_render()


func _valid_state(data: Dictionary) -> bool:
	if not data.get("open") is bool or not data.get("revision") is int or data.revision < 0:
		return false
	if not data.open:
		return true
	for field in ["scene", "round", "hp", "snacks", "cocktails", "reroll"]:
		if not data.get(field) is int:
			return false
	for field in ["snacks", "cocktails", "reroll"]:
		if data[field] < 0:
			return false
	if (
		not (data.get("money") is int or data.get("money") is float)
		or not is_finite(float(data.money))
	):
		return false
	for field in ["busy", "can_mix", "can_continue"]:
		if not data.get(field) is bool:
			return false
	if not _valid_vote(data.get("ready_vote")):
		return false
	if not data.get("slots") is Array or data.slots.size() > MAX_SLOTS:
		return false
	var keys = {}
	var identities = {}
	var database = get_node("/root/BallDatabase")
	if (
		not data.get("deck") is String
		or not database.id_to_deck.has(data.deck)
		or not data.get("difficulty") is String
		or not database.id_to_difficulty.has(data.difficulty)
		or not data.get("sets") is Array
		or data.sets.is_empty()
		or data.sets.size() > 64
	):
		return false
	for id in data.sets:
		if not id is String or not database.id_to_set.has(id):
			return false
	for slot in data.slots:
		if (
			not slot is Dictionary
			or not slot.get("group") in GROUPS
			or not slot.get("index") is int
			or slot.index < 0
			or slot.index >= MAX_SLOTS
		):
			return false
		if (
			slot.get("key") != "%s:%d" % [slot.group, slot.index]
			or keys.has(slot.key)
			or not slot.get("id") is int
		):
			return false
		keys[slot.key] = true
		if slot.id == 0:
			continue
		if slot.id < 0 or identities.has(slot.id):
			return false
		identities[slot.id] = true
		for field in ["data", "mixed"]:
			if not slot.get(field) is String or slot[field].length() > 128:
				return false
		for field in ["level", "score", "price", "sell"]:
			if not slot.get(field) is int:
				return false
		if slot.level < 1 or slot.level > 1000000 or slot.price < 0 or slot.sell < 0:
			return false
		var passive = slot.group in ["snack", "passive"]
		var catalog = database.id_to_passive if passive else database.id_to_ball
		if not catalog.has(slot.data):
			return false
		if slot.mixed != "" and (passive or not database.id_to_ball.has(slot.mixed)):
			return false
	return true


func _valid_vote(vote) -> bool:
	if not vote is Dictionary or not vote.get("revision") is int or vote.revision < 0:
		return false
	if not vote.get("eligible") is Array or not vote.get("ready") is Array:
		return false
	if vote.eligible.is_empty() or vote.eligible.size() > 8:
		return false
	var members = {}
	for id in vote.eligible:
		if not id is int or id <= 0 or members.has(id):
			return false
		members[id] = true
	var consent = {}
	for id in vote.ready:
		if not id is int or not members.has(id) or consent.has(id):
			return false
		consent[id] = true
	return true


func _bind_native_items(shop):
	for id in _bound_items.keys():
		if not is_instance_valid(_bound_items[id].node):
			_bound_items.erase(id)
	for container in [
		shop.items,
		shop.shop_items,
		shop.tapas_bar.passive_holder,
		shop.cocktail_bar.get_node("Pos/Items")
	]:
		for item in container.get_children():
			_bind_native_item(item)
	_bind_action(shop.reroll_button, "reroll")
	_bind_action(shop.play_button, "ready")
	_bind_action(shop.cocktail_bar.mix_button, "mix")


func _node_added(node: Node):
	if _controller == null or not (node is ShopBall or node is ShopPassive):
		return
	if node.is_node_ready():
		_bind_native_item(node)
		return
	var callback = _bind_native_item.bind(node)
	if not node.ready.is_connected(callback):
		node.ready.connect(callback, CONNECT_ONE_SHOT)


func _bind_native_item(item: Node):
	if (
		_controller == null
		or not (item is ShopBall or item is ShopPassive)
		or item.is_queued_for_deletion()
	):
		return
	var id = item.get_instance_id()
	if _bound_items.has(id):
		return
	_bound_items[id] = {"node": item, "script": item.get_script()}
	_replace_item_script(item, _passive_script if item is ShopPassive else _ball_script)
	item.drag_started = _begin_native_drag
	item.drop_requested = _drop_native_item
	item.can_interact = _can_drag_item


func _replace_item_script(item: Node, script: Script):
	var values = {}
	for property in item.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = item.get(property.name)
	item.set_script(script)
	for property in item.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and values.has(property.name):
			item.set(property.name, values[property.name])


func _cancel_native_drag():
	if not is_instance_valid(_view):
		return
	for item in [_view.grabbed_ball, _view.grabbed_passive]:
		if is_instance_valid(item):
			item.drag_context.clear()
			if is_instance_valid(item.slot):
				item.tpos = item.slot.global_position
	_view.drop()
	_clear_inspection()
	_view.hovered_slot = null


func _interaction_blocked() -> bool:
	return (
		not is_open()
		or not is_instance_valid(_view)
		or _pending
		or _state.busy
		or _controller.finished
		or _controller.panel.visible
		or _view.moving()
		or _controller.is_spectating()
		or get_node("/root/UIManager").is_popup_open()
	)


func _can_drag_item(item: Node) -> bool:
	return (
		not _interaction_blocked()
		and item.is_visible_in_tree()
		and is_instance_valid(item.slot)
		and item.slot.is_visible_in_tree()
		and not item.slot.disabled_slot
	)


func _slot_key(slot) -> String:
	for key in _view_slots:
		if _view_slots[key] == slot:
			return key
	return ""


func _begin_native_drag(item: Node) -> Dictionary:
	var source = _slot_key(item.slot)
	return {
		"source": source, "revision": _state.revision, "item_id": _find_slot(source).get("id", 0)
	}


func _drop_native_item(item: Node, context: Dictionary):
	if context.is_empty() or not _can_drag_item(item):
		return
	var source: String = context.source
	if context.revision != _state.revision or _find_slot(source).get("id", 0) != context.item_id:
		_notice.text = "The shop changed during your drag. Please choose again."
		_notice.show()
		return
	if _view.is_hovering_sell_area():
		_submit_item("sell", source)
		return
	var hovered = _view.get_hovered_slot()
	if (
		not is_instance_valid(hovered)
		or hovered.disabled_slot
		or not hovered.is_visible_in_tree()
		or hovered.global_position.distance_to(hovered.get_global_mouse_position()) >= 40
	):
		return
	var target = _slot_key(hovered)
	if target != "" and target != source:
		_submit_item("move", source, target)


func _bind_action(button, action: String):
	var id = button.get_instance_id()
	if _bound_buttons.has(id):
		return
	var connections = button.pressed.get_connections()
	for connection in connections:
		button.pressed.disconnect(connection.callable)
	var handler = func(): _submit({"action": action})
	button.pressed.connect(handler)
	_bound_buttons[id] = {
		"node": button, "connections": connections, "handler": handler, "disabled": button.disabled
	}
	if action == "ready":
		_bound_buttons[id]["text"] = button.text


func _restore_items():
	_cancel_native_drag()
	for entry in _bound_items.values():
		if is_instance_valid(entry.node):
			_replace_item_script(entry.node, entry.script)
	_bound_items.clear()
	for entry in _bound_buttons.values():
		if not is_instance_valid(entry.node):
			continue
		entry.node.pressed.disconnect(entry.handler)
		for connection in entry.connections:
			if connection.callable.is_valid():
				entry.node.pressed.connect(connection.callable, connection.flags)
		entry.node.set_disabled(entry.disabled)
		if entry.has("text"):
			entry.node.set_text(entry.text)
	_bound_buttons.clear()


func _build_ui():
	var layer = CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_notice = Label.new()
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.add_theme_color_override("font_shadow_color", Color.BLACK)
	_notice.add_theme_constant_override("shadow_outline_size", 3)
	_panel.add_child(_notice)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_notice.offset_left = 24
	_notice.offset_right = -24
	_notice.offset_top = -42
	_notice.offset_bottom = -12
	_notice.hide()
	_panel.hide()


func native_shop():
	return _view if is_instance_valid(_view) else null


func slot_item(key: String):
	if not _view_slots.has(key):
		return null
	var slot = _view_slots[key]
	return slot.item if key.get_slice(":", 0) in ["snack", "passive"] else slot.ball


func slot_screen_position(key: String) -> Vector2:
	if not _view_slots.has(key):
		return Vector2(INF, INF)
	return get_viewport().get_canvas_transform() * _view_slots[key].global_position


func inspect_slot(key: String) -> bool:
	if not is_instance_valid(_view) or _view.moving():
		return false
	var body = slot_item(key)
	if not is_instance_valid(body):
		return false
	if body is ShopPassive:
		_view.select_passive(body)
	else:
		_view.select_ball(body)
	return true


func _clear_inspection():
	if is_instance_valid(_view.selected_ball):
		_view.unselect_ball(_view.selected_ball)
	if is_instance_valid(_view.selected_passive):
		_view.unselect_passive(_view.selected_passive)
	get_node("/root/Global").clear_hovered_item()


func current_section() -> String:
	if not is_instance_valid(_view):
		return "balls"
	return ["balls", "mix", "snacks"][_view.state]


func show_section(section: String) -> bool:
	if not is_instance_valid(_view) or section not in ["balls", "mix", "snacks"]:
		return false
	if section == "mix" and not _view.cocktail_bar.visible:
		return false
	if section == "snacks" and not _view.tapas_bar.visible:
		return false
	_cancel_native_drag()
	_view.set_state(["balls", "mix", "snacks"].find(section))
	return true


func _ensure_view() -> bool:
	if _controller.is_table_host():
		_view = _shop()
	else:
		var global_node = get_node("/root/Global")
		var game = global_node.gameManager
		if not is_instance_valid(game) or not game.has_method("apply_table"):
			return false
		if _guest_game != game:
			_restore_items()
			_clear_guest_view()
		if not is_instance_valid(_guest_view):
			if not _guest_context_saved:
				_saved_deck = global_node.chosen_deck
				_saved_difficulty = global_node.chosen_difficulty
				_guest_context_saved = true
			var database = get_node("/root/BallDatabase")
			global_node.chosen_deck = database.id_to_deck[_state.deck]
			global_node.chosen_difficulty = database.id_to_difficulty[_state.difficulty]
			_guest_view = game.shop
			_guest_game = game
			var floor_target = game.table.get_node("TableCustomization").shop_floor
			_guest_view.set_floor(floor_target.texture)
			global_node.camera.move(_guest_view.get_camera_target())
		_view = _guest_view
		# Host slot layout is authoritative. Guest remote_slots are built in replica
		# _ready() before apply_table syncs inventory, so counts often mismatch until
		# ensure_remote_layout() rebuilds against the shared player_info.
		if not _guest_view.ensure_remote_layout(_state.slots):
			# Leave _view unset so _process retries after the next inventory snapshot.
			_view = null
			return false
		_guest_view.apply_state(_state)
	if not is_instance_valid(_view):
		return false
	var groups = {
		"offer": _view.shop_slots,
		"build": _view.get_inventory_slots(),
		"snack": _view.tapas_bar.slots,
		"passive": _view.get_passive_slots(),
		"mix":
		[
			_view.cocktail_bar.slot_left,
			_view.cocktail_bar.slot_right,
			_view.cocktail_bar.slot_center
		]
	}
	_view_slots.clear()
	for group in groups:
		for index in groups[group].size():
			_view_slots[presence_slot_key(group, index)] = groups[group][index]
	return true


func _clear_guest_view():
	if not _guest_context_saved:
		return
	var global_node = get_node("/root/Global")
	global_node.clear_hovered_item()
	if is_instance_valid(_guest_view):
		_guest_view.is_open = false
		_guest_view.hide()
		_guest_view.process_mode = Node.PROCESS_MODE_DISABLED
	_guest_view = null
	_guest_game = null
	global_node.chosen_deck = _saved_deck
	global_node.chosen_difficulty = _saved_difficulty
	_guest_context_saved = false
	if is_instance_valid(global_node.camera):
		global_node.camera.move(Vector2.ZERO)


func _render():
	if not _ensure_view():
		return
	_bind_native_items(_view)
	_update_actions()


func _find_slot(key: String) -> Dictionary:
	for slot in _state.get("slots", []):
		if slot.key == key:
			return slot
	return {}


func _submit_item(action: String, source: String, target = ""):
	var slot = _find_slot(source)
	if slot.get("id", 0) == 0:
		return
	var message = {"action": action, "source": source, "item_id": slot.id}
	if action == "move":
		message["target"] = target
		message["target_id"] = _find_slot(target).get("id", 0)
	_submit(message)


func _submit(message: Dictionary):
	if not is_open() or _pending or _controller.panel.visible or _controller.finished:
		return
	if _controller.is_spectating() or get_node("/root/UIManager").is_popup_open():
		return
	message["kind"] = "shop_request"
	message["revision"] = _state.revision
	if message.action == "ready":
		message["ready"] = not _state.ready_vote.ready.has(_controller.transport.local_id())
		message["ready_generation"] = _state.ready_vote.revision
	if _controller.is_table_host():
		var accepted = handle_request(message)
		apply_result(accepted, last_error)
	else:
		_pending = true
		_pending_at = Time.get_ticks_msec()
		_request_id += 1
		message["request_id"] = _request_id
		_pending_message = message.duplicate(true)
		_display_state(_predict_state(_authoritative_state, message))
		_notice.hide()
		_update_actions()
		request.emit(message)


func _update_actions():
	if not is_open() or not is_instance_valid(_view):
		return
	var blocked = _interaction_blocked()
	if _controller.finished:
		_notice.text = "This table has finished. Scores and purchases are locked."
		_notice.show()
	# A pending acknowledgement can span many frames. Cancel the native drag once
	# when interaction becomes blocked, preserving local camera/hover frame time.
	if blocked and not _actions_blocked:
		_cancel_native_drag()
	_actions_blocked = blocked
	_set_disabled(_view.reroll_button, blocked or _state.money < _state.reroll)
	_set_disabled(_view.cocktail_bar.mix_button, blocked or not _state.can_mix)
	_set_disabled(_view.play_button, blocked or not _state.can_continue)
	var vote: Dictionary = _state.ready_vote
	var label = "Unready" if vote.ready.has(_controller.transport.local_id()) else "Ready"
	var text = "%s\n%d/%d" % [label, vote.ready.size(), vote.eligible.size()]
	if _view.play_button.text != text:
		_view.play_button.set_text(text)


func _set_disabled(button, value: bool):
	if button.disabled != value:
		button.set_disabled(value)


func _predict_state(base: Dictionary, message: Dictionary) -> Dictionary:
	var data = base.duplicate(true)
	if not data.get("open", false) or data.get("busy", true) or message.is_empty():
		return data
	if message.action == "ready":
		if message.ready_generation == data.ready_vote.revision:
			var actor: int = _controller.transport.local_id()
			data.ready_vote.ready.erase(actor)
			if message.ready:
				data.ready_vote.ready.append(actor)
			data.ready_vote.ready.sort()
		return data
	var source: Dictionary = {}
	var target: Dictionary = {}
	for slot in data.slots:
		if slot.key == message.get("source") and slot.id == message.get("item_id"):
			source = slot
		if slot.key == message.get("target") and slot.id == message.get("target_id"):
			target = slot
	if source.is_empty():
		return data
	if message.action == "sell" and source.group in ["build", "passive"]:
		data.money += source.sell
		_empty_prediction(source)
	elif message.action == "move" and not target.is_empty() and target.id == 0:
		if source.group in ["offer", "build", "mix"] and target.group == "build":
			if source.group == "offer":
				if data.money < source.price:
					return data
				data.money -= source.price
		elif source.group == "build" and target.key in ["mix:0", "mix:1"]:
			if data.cocktails <= 0 or source.mixed != "":
				return data
		else:
			return data
		for field in ["id", "data", "mixed", "level", "score", "price", "sell"]:
			target[field] = source[field]
		_empty_prediction(source)
	else:
		return data
	data.ready_vote.ready.clear()
	return data


func _empty_prediction(slot: Dictionary):
	var identity = {"key": slot.key, "group": slot.group, "index": slot.index, "id": 0}
	slot.clear()
	slot.merge(identity)

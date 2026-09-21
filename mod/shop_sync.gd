extends Node

signal request(message: Dictionary)

const GROUPS = ["offer", "build", "snack", "passive", "mix"]
const MAX_SLOTS = 64

var last_error = ""
var _controller: Node
var _state: Dictionary = {}
var _last_capture: Dictionary = {}
var _revision = 0
var _native_slots: Dictionary = {}
var _disabled_items: Dictionary = {}
var _disabled_buttons: Dictionary = {}
var _buttons: Dictionary = {}
var _tutorial_enabled = true
var _selected = ""
var _pending = false
var _pending_at = 0
var _columns = 5
var _slot_script: Script
var _panel: PanelContainer
var _wallet: Label
var _notice: Label
var _sections: VBoxContainer
var _scroll: ScrollContainer
var _details: RichTextLabel
var _reroll: Button
var _sell: Button
var _mix: Button
var _continue: Button


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -500
	_slot_script = load(get_script().resource_path.get_base_dir().path_join("shop_slot_button.gd"))
	_build_ui()


func begin_session(controller: Node):
	_controller = controller
	_revision = 0
	_last_capture.clear()
	_state.clear()
	_selected = ""
	_pending = false
	if _controller.local_player == 0:
		var tutorial = get_node("/root/TutorialManager")
		_tutorial_enabled = tutorial.ENABLED
		tutorial.ENABLED = false
		if tutorial.active_popup != null:
			tutorial.cancel()


func end_session():
	if _controller != null and _controller.local_player == 0:
		get_node("/root/TutorialManager").ENABLED = _tutorial_enabled
	_restore_items()
	_controller = null
	_state.clear()
	_last_capture.clear()
	_native_slots.clear()
	_selected = ""
	_pending = false
	_panel.hide()


func is_open() -> bool:
	return _controller != null and _state.get("open", false)


func presence_rect() -> Rect2:
	return _panel.get_global_rect() if is_open() and _panel.visible else Rect2()


func presence_target() -> String:
	var hovered = get_viewport().gui_get_hovered_control()
	while hovered != null and hovered != _panel:
		if hovered.has_meta("shop_slot"):
			return str(hovered.get_meta("shop_slot"))
		hovered = hovered.get_parent()
	return ""


func presence_target_position(key: String) -> Vector2:
	if not _buttons.has(key) or not _panel.visible:
		return Vector2(INF, INF)
	var center = _buttons[key].get_global_rect().get_center()
	return center if _scroll.get_global_rect().has_point(center) else Vector2(INF, INF)


func _process(_delta):
	if _controller == null:
		return
	_panel.visible = is_open() and not get_node("/root/UIManager").is_popup_open()
	if is_open() and _columns != _column_count():
		_render()
	if _controller.local_player == 0:
		var shop = _shop()
		if shop != null:
			_lock_native_items(shop)
		elif not _disabled_items.is_empty() or not _disabled_buttons.is_empty():
			_restore_items()
	if _pending and Time.get_ticks_msec() - _pending_at > 5000:
		_pending = false
		_notice.text = "Waiting for the shop update. Try your action again."
		_update_actions()


func _shop():
	var game = get_node("/root/Global").gameManager
	if not is_instance_valid(game) or not game.in_shop or not is_instance_valid(game.shop):
		return null
	return game.shop if game.shop.is_open else null


func capture() -> Dictionary:
	if _controller == null or _controller.local_player != 0:
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
		}
	)
	return packed


func handle_request(message: Dictionary) -> bool:
	last_error = ""
	if _controller == null or _controller.local_player != 0:
		return false
	if not message.get("revision") is int or not message.get("action") is String:
		return _reject("Invalid shop action.")
	capture()
	if not is_open() or message.get("revision") != _revision:
		return _reject("The shop changed. Please choose again.")
	if _state.busy:
		return _reject("Wait for the shop animation to finish.")
	var shop = _shop()
	var action = message.get("action", "")
	match action:
		"reroll":
			if shop.player_info.money < shop.roll_cost:
				return _reject("Not enough shared money to reroll.")
			shop._on_reroll_button_pressed()
		"continue":
			if not _state.can_continue:
				return _reject("Return the cocktail balls to your build before continuing.")
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


func apply_result(accepted: bool, reason = ""):
	_pending = false
	if not accepted:
		_notice.text = reason if reason != "" else "The shop changed. Please choose again."
	_update_actions()


func apply_state(data: Dictionary) -> bool:
	if not _valid_state(data):
		return false
	if data.get("revision", -1) < _state.get("revision", -1):
		return true
	if data == _state:
		return true
	var selection_id = _find_slot(_selected).get("id", 0)
	var was_open: bool = _state.get("open", false)
	_state = data.duplicate(true)
	_panel.visible = data.open and not get_node("/root/UIManager").is_popup_open()
	_pending = false
	if not data.open:
		_selected = ""
		return true
	if _find_slot(_selected).get("id", 0) != selection_id:
		_selected = ""
	if not was_open:
		get_viewport().gui_release_focus()
	_notice.text = "Shop animation…" if _state.busy else "Your money and build are shared."
	_render()
	return true


func _valid_state(data: Dictionary) -> bool:
	if not data.get("open") is bool or not data.get("revision") is int or data.revision < 0:
		return false
	if not data.open:
		return true
	for field in ["scene", "round", "snacks", "cocktails", "reroll"]:
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
	if not data.get("slots") is Array or data.slots.size() > MAX_SLOTS:
		return false
	var keys = {}
	var database = get_node("/root/BallDatabase")
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
		if slot.id < 0:
			return false
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


func _lock_native_items(shop):
	shop.drop()
	shop.selected_ball = null
	shop.selected_passive = null
	for container in [
		shop.items,
		shop.shop_items,
		shop.tapas_bar.passive_holder,
		shop.cocktail_bar.get_node("Pos/Items")
	]:
		for item in container.get_children():
			if not item.has_method("get_item") or item.is_queued_for_deletion():
				continue
			var id = item.get_instance_id()
			if not _disabled_items.has(id):
				_disabled_items[id] = {"node": item, "interactable": item.interactable}
			item.interactable = false
	for button in shop.find_children("*", "BaseButton", true, false):
		var id = button.get_instance_id()
		if not _disabled_buttons.has(id):
			_disabled_buttons[id] = {"node": button, "disabled": button.disabled}
		button.disabled = true


func _restore_items():
	for entry in _disabled_items.values():
		if is_instance_valid(entry.node):
			entry.node.interactable = entry.interactable
	_disabled_items.clear()
	for entry in _disabled_buttons.values():
		if is_instance_valid(entry.node):
			entry.node.disabled = entry.disabled
	_disabled_buttons.clear()


func _build_ui():
	var layer = CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	_panel = PanelContainer.new()
	layer.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin = MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 88)
	_panel.add_child(margin)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	_wallet = Label.new()
	_wallet.add_theme_font_size_override("font_size", 21)
	_wallet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_wallet)
	var help = Label.new()
	help.text = "Shop together · Drag a ball, or select it and click a destination. Both players can buy and arrange."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(help)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_scroll)
	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", 8)
	_scroll.add_child(_sections)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.custom_minimum_size.y = 65
	_details.add_theme_color_override("default_color", Color(0.12, 0.12, 0.12))
	var details_style = StyleBoxFlat.new()
	details_style.bg_color = Color(0.94, 0.94, 0.9)
	_details.add_theme_stylebox_override("normal", details_style)
	content.add_child(_details)
	_notice = Label.new()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_notice)
	var actions = HFlowContainer.new()
	content.add_child(actions)
	_sell = _button("Sell selected", func(): _submit_item("sell", _selected))
	actions.add_child(_sell)
	_reroll = _button("Reroll", func(): _submit({"action": "reroll"}))
	actions.add_child(_reroll)
	_mix = _button("Mix cocktail", func(): _submit({"action": "mix"}))
	actions.add_child(_mix)
	_continue = _button("Continue to table", func(): _submit({"action": "continue"}))
	actions.add_child(_continue)
	_panel.hide()


func _button(text: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


func _render():
	_columns = _column_count()
	_wallet.text = (
		"Shared shop · %d € · %d snack tickets · %d cocktail tickets"
		% [_state.money, _state.snacks, _state.cocktails]
	)
	for child in _sections.get_children():
		_sections.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_add_section("Balls for sale", "offer", 0, MAX_SLOTS)
	_add_section("Table · front to back", "build", 0, 10)
	_add_section("Reserve", "build", 10, MAX_SLOTS)
	if _state.snacks > 0:
		_add_section("Snacks · one ticket each", "snack", 0, MAX_SLOTS)
	_add_section("Your passives", "passive", 0, MAX_SLOTS)
	if _state.cocktails > 0 or _mix_has_items():
		_add_section("Cocktail · ingredient 1, ingredient 2, mixed result", "mix", 0, MAX_SLOTS)
	_update_actions()


func _add_section(title: String, group: String, start: int, end: int):
	var label = Label.new()
	label.text = title
	_sections.add_child(label)
	var grid = GridContainer.new()
	grid.columns = mini(5 if group == "build" else 4, _columns)
	_sections.add_child(grid)
	for slot in _state.slots:
		if slot.group != group or slot.index < start or slot.index >= end:
			continue
		var button = _slot_script.new()
		button.slot_key = slot.key
		button.set_meta("shop_slot", slot.key)
		_buttons[slot.key] = button
		button.revision = _state.revision
		button.item_id = slot.id
		button.custom_minimum_size = Vector2(128, 84)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_pressed = _selected == slot.key
		button.disabled = _state.busy or _pending
		var description = _describe(slot)
		button.tooltip_text = description.get("name", "Empty slot")
		button.pressed.connect(_select_slot.bind(slot.key))
		button.mouse_entered.connect(_show_details.bind(slot))
		button.drop_requested.connect(_drop_item)
		grid.add_child(button)
		var box = VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(box)
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var line = Label.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.text = str(slot.index + 1) if slot.id == 0 else description.name
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.custom_minimum_size.x = 110
		line.add_theme_font_size_override("font_size", 13)
		box.add_child(line)
		if slot.id == 0:
			continue
		var icon = _make_icon(slot)
		box.add_child(icon)
		var price = Label.new()
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.add_theme_font_size_override("font_size", 12)
		price.text = (
			"%d € · Lv %d" % [slot.price, slot.level]
			if group == "offer"
			else "Lv %d · %d pts" % [slot.level, slot.score]
		)
		box.add_child(price)


func _make_icon(slot: Dictionary) -> TextureRect:
	var icon = TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var database = get_node("/root/BallDatabase")
	var passive = slot.group in ["snack", "passive"]
	var resource = (
		database.get_passive_by_id(slot.data) if passive else database.get_ball_by_id(slot.data)
	)
	if resource == null:
		return icon
	icon.texture = resource.texture
	if not passive:
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		var material_path = (
			"res://materials/preview_ball.tres"
			if slot.mixed == ""
			else "res://materials/preview_ball_mixed.tres"
		)
		icon.material = load(material_path).duplicate()
		icon.material.set_shader_parameter("tex", resource.texture)
		if slot.mixed != "":
			var mixed = database.get_ball_by_id(slot.mixed)
			if mixed != null:
				icon.material.set_shader_parameter("mixed_tex", mixed.texture)
		var basis = Basis(Vector3.FORWARD, PI / 2) * Basis(Vector3.RIGHT, PI / 1.5)
		icon.material.set_shader_parameter("rotation_x", basis.x)
		icon.material.set_shader_parameter("rotation_y", basis.y)
		icon.material.set_shader_parameter("rotation_z", basis.z)
	return icon


func _column_count() -> int:
	return clampi(int((get_viewport().get_visible_rect().size.x - 40) / 132.0), 1, 5)


func _describe(slot: Dictionary) -> Dictionary:
	if slot.id == 0:
		return {}
	var database = get_node("/root/BallDatabase")
	var passive = slot.group in ["snack", "passive"]
	var resource = (
		database.get_passive_by_id(slot.data) if passive else database.get_ball_by_id(slot.data)
	)
	var name = resource.get_formatted_name()
	var description = resource.get_formatted_description(mini(slot.level, 5))
	if slot.mixed != "":
		var mixed = database.get_ball_by_id(slot.mixed)
		name += " + " + mixed.get_formatted_name()
		description += "\n·····\n" + mixed.get_formatted_description(mini(slot.level, 5))
	return {"name": name, "description": description}


func _show_details(slot: Dictionary):
	if slot.id == 0:
		_details.text = "Empty slot · Select a ball, then click here to move or buy it."
		return
	var description = _describe(slot)
	_details.text = (
		"[b]%s[/b] · Level %d · Score %d · Sell for %d €\n%s"
		% [
			description.name,
			slot.level,
			slot.score,
			slot.sell,
			load("res://utils/text_formatter.gd").format(description.description)
		]
	)


func _find_slot(key: String) -> Dictionary:
	for slot in _state.get("slots", []):
		if slot.key == key:
			return slot
	return {}


func _select_slot(key: String):
	if _pending or _state.busy:
		return
	var slot = _find_slot(key)
	if _selected == key:
		_selected = ""
	elif _selected != "":
		_submit_item("move", _selected, key)
		_selected = ""
	elif slot.get("id", 0) != 0:
		_selected = key
	_render()
	_show_details(slot)


func _drop_item(source: String, target: String, revision: int, item_id: int):
	if revision != _state.revision or _find_slot(source).get("id", 0) != item_id:
		_notice.text = "The shop changed during your drag. Please choose again."
		return
	_submit_item("move", source, target)
	_selected = ""


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
	if not is_open() or _pending or _controller.panel.visible:
		return
	message["kind"] = "shop_request"
	message["revision"] = _state.revision
	if _controller.local_player == 0:
		var accepted = handle_request(message)
		apply_result(accepted, last_error)
	else:
		_pending = true
		_pending_at = Time.get_ticks_msec()
		_notice.text = "Updating the shared shop…"
		_update_actions()
		request.emit(message)


func _mix_has_items() -> bool:
	for slot in _state.get("slots", []):
		if slot.group == "mix" and slot.id != 0:
			return true
	return false


func _update_actions():
	if not is_open():
		return
	var blocked = _pending or _state.busy
	for button in _buttons.values():
		button.disabled = blocked
	_reroll.text = "Reroll · %d €" % _state.reroll
	_reroll.disabled = blocked or _state.money < _state.reroll
	_sell.disabled = (
		blocked or _selected == "" or _selected.get_slice(":", 0) not in ["build", "passive"]
	)
	_mix.visible = _state.cocktails > 0 or _mix_has_items()
	_mix.disabled = blocked or not _state.can_mix
	_continue.disabled = blocked or not _state.can_continue

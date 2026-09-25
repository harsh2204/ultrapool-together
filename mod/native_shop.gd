extends "res://ui/shop.gd"

var remote_items: Dictionary = {}
var remote_slots: Dictionary = {}
var _displayed: Dictionary = {}


func _ready() -> void:
	Global.shopManager = self
	player_info = Global.gameManager.get_node("PlayerInfo")
	inventory.setup()
	shop_slots = %ShopSlots.get_children()
	cocktail_bar.update_can_leave.connect(_on_cocktail_bar_update_can_leave)
	cocktail_bar.leave.connect(leave_cocktails)
	tapas_bar.leave.connect(leave_tapas)
	passive_grabbed.connect(tapas_bar._on_passive_grabbed)
	passive_dropped.connect(tapas_bar._on_passive_dropped)
	get_viewport().size_changed.connect(update_shop_positions)
	update_shop_positions()
	rebuild_remote_slots()
	is_open = false
	moving_time = -1.0
	girl.react_none()
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED


func _process(delta: float) -> void:
	moving_time = maxf(-1.0, moving_time - delta)
	camera.position.x = lerpf(camera.position.x, target_camera_x, minf(delta * 12.0, 1.0))


static func remote_slots_cover(slots: Dictionary, entries: Array) -> bool:
	for entry in entries:
		if not entry is Dictionary or not slots.has(entry.get("key", "")):
			return false
	return true


func rebuild_remote_slots() -> void:
	remote_slots.clear()
	var groups = {
		"offer": shop_slots,
		"build": get_inventory_slots(),
		"snack": tapas_bar.slots,
		"passive": get_passive_slots(),
		"mix": [cocktail_bar.slot_left, cocktail_bar.slot_right, cocktail_bar.slot_center]
	}
	for group in groups:
		for index in groups[group].size():
			remote_slots["%s:%d" % [group, index]] = groups[group][index]


func ensure_remote_layout(entries: Array) -> bool:
	if remote_slots_cover(remote_slots, entries):
		return true
	# Replica _ready() often runs before the host inventory snapshot arrives, so rebuild
	# once player_info matches the shared run. Avoid rebuilding under live remote items.
	if not remote_items.is_empty():
		return false
	inventory.setup()
	shop_slots = %ShopSlots.get_children()
	rebuild_remote_slots()
	return remote_slots_cover(remote_slots, entries)


func apply_state(data: Dictionary) -> void:
	is_open = true
	show()
	process_mode = Node.PROCESS_MODE_INHERIT
	player_info.money = data.money
	player_info.hp = data.hp
	player_info.snack_tickets = data.snacks
	player_info.cocktail_tickets = data.cocktails
	roll_cost = data.reroll
	var slots_changed: bool = not _displayed.has("slots") or data.slots != _displayed.slots
	if slots_changed:
		_sync_items(data.slots)
	if _changed(data, ["round", "deck", "difficulty", "money", "hp"]):
		inventory.update_info(
			data.round, Global.chosen_deck, Global.chosen_difficulty, data.money, data.hp
		)
	if _changed(data, ["money", "slots"]):
		for slot in shop_slots:
			slot.update_price()
	if _changed(data, ["sets", "deck", "difficulty"]):
		sets_offered = data.sets.duplicate()
		display_sets_offered()
	if _changed(data, ["snacks", "round"]):
		update_snack_tickets()
	if _changed(data, ["cocktails", "round"]):
		update_cocktail_tickets()
	if _changed(data, ["reroll", "money"]):
		update_reroll_button()
	if slots_changed or _changed(data, ["cocktails", "round"]):
		cocktail_bar.round = data.round
		cocktail_bar.set_state(cocktail_bar.derive_state(), true)
		cocktail_bar._on_items_changed()
	if _changed(data, ["round", "deck", "difficulty"]):
		%ButtonMoveToCocktail.visible = Global.is_cocktail_available()
		%ButtonMoveToTapas.visible = Global.is_tapas_available()
		cocktail_bar.visible = Global.is_cocktail_available()
		tapas_bar.visible = Global.is_tapas_available()
		%CubesButton.hide()
	_displayed = data.duplicate(true)


func _changed(data: Dictionary, fields: Array) -> bool:
	for field in fields:
		if not _displayed.has(field) or data[field] != _displayed[field]:
			return true
	return false


func _sync_items(entries: Array):
	var previous: Dictionary = {}
	for stored in remote_items.values():
		previous[stored.state.id] = stored
	for key in remote_slots:
		var slot = remote_slots[key]
		if key.get_slice(":", 0) in ["snack", "passive"]:
			slot.item = null
		else:
			slot.ball = null
			slot.has_rarity_star = false
	remote_items.clear()
	for entry in entries:
		if entry.id == 0:
			continue
		var slot = remote_slots[entry.key]
		var passive: bool = entry.group in ["snack", "passive"]
		var old: Dictionary = previous.get(entry.id, {})
		var body = old.get("node")
		var item_changed = old.is_empty()
		var created = not is_instance_valid(body)
		if not old.is_empty():
			for field in ["data", "mixed", "level", "score"]:
				if old.state[field] != entry[field]:
					item_changed = true
		if created:
			body = (passive_item_scene if passive else shop_item_scene).instantiate()
		elif old.state.key != entry.key or item_changed:
			_release_remote_item(body)
		if item_changed:
			var item = BallItem.new()
			item.data = (
				BallDatabase.id_to_passive[entry.data]
				if passive
				else BallDatabase.id_to_ball[entry.data]
			)
			if entry.mixed != "":
				item.mixed_data = BallDatabase.id_to_ball[entry.mixed]
			item.level = entry.level
			item.base_score = entry.score
			body.set_item(item)
		var holder = items
		if entry.group == "offer":
			holder = shop_items
		elif entry.group == "snack":
			holder = tapas_bar.passive_holder
		elif entry.group == "mix":
			holder = cocktail_bar.get_node("Pos/Items")
		if body.get_parent() == null:
			holder.add_child(body)
		elif body.get_parent() != holder:
			body.reparent(holder)
		if created:
			body.global_position = slot.global_position
		if not is_grabbed(body):
			body.tpos = slot.global_position
		body.slot = slot
		if passive:
			slot.item = body
		else:
			slot.ball = body
			slot.price = entry.price
			body.update_level_spark()
			body.score_ui.show()
			body.get_node("%ScoreLabel").text = Global.format_number(
				body.get_item().get_base_score(), 4, 0
			)
		remote_items[entry.key] = {"node": body, "state": entry.duplicate(true)}
		previous.erase(entry.id)
	for old in previous.values():
		var body = old.node
		_release_remote_item(body)
		body.slot = null
		body.get_parent().remove_child(body)
		body.queue_free()


func _release_remote_item(body):
	if is_grabbed(body):
		drop()
	Global.gameManager.unselect_ball(body, body.get_item(), true)
	if selected_ball == body:
		selected_ball = null
	if selected_passive == body:
		selected_passive = null


func save_run_state() -> void:
	pass


func _on_play_button_pressed() -> void:
	pass


func _on_reroll_button_pressed() -> void:
	pass

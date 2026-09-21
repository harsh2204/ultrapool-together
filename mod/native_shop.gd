extends "res://ui/shop.gd"

var remote_items: Dictionary = {}
var remote_slots: Dictionary = {}


func _ready() -> void:
	Global.shopManager = self
	player_info = Global.gameManager.player_info
	inventory.setup()
	shop_slots = %ShopSlots.get_children()
	cocktail_bar.update_can_leave.connect(_on_cocktail_bar_update_can_leave)
	cocktail_bar.leave.connect(leave_cocktails)
	tapas_bar.leave.connect(leave_tapas)
	get_viewport().size_changed.connect(update_shop_positions)
	update_shop_positions()
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
	is_open = true
	moving_time = -1.0
	girl.react_none()


func _process(delta: float) -> void:
	moving_time = maxf(-1.0, moving_time - delta)
	camera.position.x = lerpf(camera.position.x, target_camera_x, minf(delta * 12.0, 1.0))


func apply_state(data: Dictionary) -> void:
	player_info.money = data.money
	player_info.hp = data.hp
	player_info.snack_tickets = data.snacks
	player_info.cocktail_tickets = data.cocktails
	roll_cost = data.reroll
	sets_offered = data.sets.duplicate()
	for entry in data.slots:
		var slot = remote_slots[entry.key]
		var previous: Dictionary = remote_items.get(entry.key, {})
		if previous.get("state") == entry:
			continue
		if previous.has("node"):
			Global.gameManager.unselect_ball(previous.node, previous.node.get_item(), true)
			if selected_ball == previous.node:
				selected_ball = null
			if selected_passive == previous.node:
				selected_passive = null
			previous.node.get_parent().remove_child(previous.node)
			previous.node.queue_free()
			remote_items.erase(entry.key)
		if entry.group in ["snack", "passive"]:
			slot.item = null
		else:
			slot.ball = null
			slot.has_rarity_star = false
		if entry.id == 0:
			continue
		var passive: bool = entry.group in ["snack", "passive"]
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
		var body = (passive_item_scene if passive else shop_item_scene).instantiate()
		body.set_item(item)
		body.interactable = false
		var holder = items
		if entry.group == "offer":
			holder = shop_items
		elif entry.group == "snack":
			holder = tapas_bar.passive_holder
		elif entry.group == "mix":
			holder = cocktail_bar.get_node("Pos/Items")
		holder.add_child(body)
		body.global_position = slot.global_position
		body.tpos = body.global_position
		body.slot = slot
		if passive:
			slot.item = body
		else:
			slot.ball = body
			slot.price = entry.price
			slot.update_price()
			body.update_level_spark()
			body.score_ui.show()
			body.get_node("%ScoreLabel").text = Global.format_number(item.get_base_score(), 4, 0)
		remote_items[entry.key] = {"node": body, "state": entry.duplicate(true)}
	inventory.update_info(
		data.round, Global.chosen_deck, Global.chosen_difficulty, data.money, data.hp
	)
	for slot in shop_slots:
		slot.update_price()
	display_sets_offered()
	update_snack_tickets()
	update_cocktail_tickets()
	update_reroll_button()
	cocktail_bar.round = data.round
	cocktail_bar.set_state(cocktail_bar.derive_state(), true)
	cocktail_bar._on_items_changed()
	%ButtonMoveToCocktail.visible = Global.is_cocktail_available()
	%ButtonMoveToTapas.visible = Global.is_tapas_available()
	cocktail_bar.visible = Global.is_cocktail_available()
	tapas_bar.visible = Global.is_tapas_available()
	%CubesButton.hide()


func save_run_state() -> void:
	pass


func _on_play_button_pressed() -> void:
	pass


func _on_reroll_button_pressed() -> void:
	pass

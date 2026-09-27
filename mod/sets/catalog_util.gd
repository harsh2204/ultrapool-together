extends RefCounted
## Shared BallResource registration for shop-only expansion sets.
## Textures live under mod/assets/balls and use the same 2:1 atlas source format as TOGETHER.

const SHOP_OFFER_CHANCE = 6
const MAX_OFFERS_SCAN = 32


static func register_balls(
	owner: Node, balls: Dictionary, from_set: String, resources: Dictionary, active: bool
) -> bool:
	if not resources.is_empty():
		return resources.size() == balls.size()
	var database = owner.get_node("/root/BallDatabase")
	var assets_root = (
		owner.get_script().resource_path.get_base_dir().get_base_dir().path_join("assets/balls")
	)
	for id in balls:
		var definition: Dictionary = balls[id]
		var resource = BallResource.new()
		resource.id = id
		resource.name = definition.name
		resource.description = definition.description
		resource.main_color = definition.color
		resource.texture = load_texture(assets_root, definition.asset)
		if resource.texture == null:
			return false
		resource.base_score = int(definition.get("base_score", 2))
		resource.start_level = 1
		resource.rarity = definition.rarity
		resource.tags = definition.get("tags", []).duplicate()
		resource.from_set = from_set
		resource.can_drop = active
		resource.upgradeable = false
		database.id_to_ball[id] = resource
		database.balls.append(resource)
		database.plain_ball_ids.append(id.to_lower())
		resources[id] = resource
	return true


static func set_active(resources: Dictionary, active: bool) -> void:
	for resource in resources.values():
		resource.can_drop = active


static func ensure_shop_offer(
	owner: Node,
	shop,
	active: bool,
	resources: Dictionary,
	offer_ids: Array,
	stock_key_holder: Dictionary
) -> void:
	if not active or not is_instance_valid(shop) or not shop.is_open or offer_ids.is_empty():
		return
	var game = owner.get_node("/root/Global").gameManager
	var stock_key = (
		"%d:%d:%d" % [shop.get_instance_id(), game.rounds_played, shop.times_rerolled_total]
	)
	if stock_key_holder.get("key", "") == stock_key:
		return
	for slot in shop.shop_slots:
		if is_instance_valid(slot.ball) and resources.has(slot.ball.ball_item.data.id):
			stock_key_holder["key"] = stock_key
			return
	if absi(hash(stock_key + str(offer_ids[0]))) % SHOP_OFFER_CHANCE != 0:
		stock_key_holder["key"] = stock_key
		return
	var scanned = 0
	for slot in shop.shop_slots:
		scanned += 1
		if scanned > MAX_OFFERS_SCAN:
			break
		if not is_instance_valid(slot.ball) or slot.ball.is_queued_for_deletion():
			continue
		var offer_index = maxi(0, game.rounds_played - 1) + shop.times_rerolled_total
		var item = BallItem.new()
		item.data = resources[offer_ids[offer_index % offer_ids.size()]]
		item.base_score = item.data.base_score
		item.level = 1
		slot.ball.ball_item = item
		slot.ball.update_upgrade_status(false)
		slot.set_ball(slot.ball)
		AchievementManager.mark_ball_as_seen(item)
		game.track_ball_seen(item)
		stock_key_holder["key"] = stock_key
		owner.get_node("/root/SaveManager").save_run_state()
		return


static func load_texture(assets_root: String, asset: String) -> ImageTexture:
	var path = assets_root.path_join(asset)
	var source = Image.new()
	if source.load(path) != OK or source.get_width() != source.get_height() * 2:
		push_error("Missing or invalid expansion ball art: " + asset)
		return null
	var face = source.get_region(Rect2i(0, 0, source.get_height(), source.get_height()))
	face.convert(Image.FORMAT_RGBA8)
	face.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var atlas = Image.create(1024, 768, false, Image.FORMAT_RGBA8)
	atlas.fill(face.get_pixel(0, 0))
	for cell in [
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(2, 1),
		Vector2i(3, 1),
		Vector2i(1, 2)
	]:
		atlas.blit_rect(face, Rect2i(0, 0, 256, 256), cell * 256)
	atlas.generate_mipmaps()
	return ImageTexture.create_from_image(atlas)


static func empty_action() -> Dictionary:
	return {
		"points": 0.0,
		"money": 0,
		"heal": 0,
		"temp": [],
		"weight": [],
		"close_top_pocket": false,
		"launch_nearest": false,
		"spawn_echo": false,
		"lock_random": false,
		"clear_temps": false,
		"consume_nearest": false,
		"shade_nearest": false,
		"strip_and_spread": false,
		"consume_rate": 0.0,
		"next_ordinary_bonus": 0.0,
		"buoy_bonus": 0.0
	}


static func merge_action(into: Dictionary, extra: Dictionary) -> Dictionary:
	into.points += float(extra.get("points", 0.0))
	into.money += int(extra.get("money", 0))
	into.heal += int(extra.get("heal", 0))
	for key in [
		"temp",
		"weight"
	]:
		for entry in extra.get(key, []):
			into[key].append(entry)
	for flag in [
		"close_top_pocket",
		"launch_nearest",
		"spawn_echo",
		"lock_random",
		"clear_temps",
		"consume_nearest",
		"shade_nearest",
		"strip_and_spread"
	]:
		into[flag] = into[flag] or bool(extra.get(flag, false))
	into.next_ordinary_bonus = maxf(
		into.next_ordinary_bonus, float(extra.get("next_ordinary_bonus", 0.0))
	)
	into.buoy_bonus = maxf(into.buoy_bonus, float(extra.get("buoy_bonus", 0.0)))
	into.consume_rate = maxf(into.consume_rate, float(extra.get("consume_rate", 0.0)))
	return into

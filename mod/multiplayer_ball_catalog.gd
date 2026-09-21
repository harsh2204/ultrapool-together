extends Node

const STARTER_IDS = ["TOGETHER_RELAY", "TOGETHER_PATIENCE", "TOGETHER_BOUNTY"]
const OFFER_IDS = [
	"TOGETHER_CALL",
	"TOGETHER_BANKROLL",
	"TOGETHER_LIFELINE",
	"TOGETHER_ENCORE",
	"TOGETHER_DOMINO",
	"TOGETHER_RELAY",
	"TOGETHER_PATIENCE",
	"TOGETHER_BOUNTY"
]
const BALLS = {
	"TOGETHER_RELAY":
	{
		"name": "Relay",
		"description":
		(
			"After a teammate touches this ball on an earlier shot, pocket it for +50% value. "
			+ "In competitive play, any later shot qualifies."
		),
		"color": Color("29c7d8"),
		"asset": "relay.png",
		"rarity": Global.RARITY.COMMON
	},
	"TOGETHER_CALL":
	{
		"name": "Called Shot",
		"description":
		(
			"The previous shooter calls a pocket before the next shot. "
			+ "Pocket this ball there on that shot for +100% value."
		),
		"color": Color("f3a83b"),
		"asset": "called_shot.png",
		"rarity": Global.RARITY.COMMON
	},
	"TOGETHER_PATIENCE":
	{
		"name": "Patience",
		"description":
		(
			"Survive a shot that hits any object ball to store +25% value for a later "
			+ "pocket. Stores up to three charges (+75%)."
		),
		"color": Color("a788ed"),
		"asset": "patience.png",
		"rarity": Global.RARITY.COMMON
	},
	"TOGETHER_BOUNTY":
	{
		"name": "Bounty",
		"description":
		(
			"Competitive: the table that pockets this on the earliest shot earns 25 match points; "
			+ "tied tables each earn 25. Co-op: pocket within the first three shots for +10 points."
		),
		"color": Color("eb5876"),
		"asset": "bounty.png",
		"rarity": Global.RARITY.COMMON
	},
	"TOGETHER_BANKROLL":
	{
		"name": "Bankroll",
		"description":
		(
			"Bounce this ball off a cushion and pocket it in the same shot for 2 coins. "
			+ "Once per table per round."
		),
		"color": Color("efd44e"),
		"asset": "bankroll.png",
		"rarity": Global.RARITY.COMMON
	},
	"TOGETHER_LIFELINE":
	{
		"name": "Lifeline",
		"description":
		(
			"Pocket to restore 1 health, up to this difficulty's starting health. "
			+ "Once per table per round."
		),
		"color": Color("55ce94"),
		"asset": "lifeline.png",
		"rarity": Global.RARITY.UNCOMMON
	},
	"TOGETHER_ENCORE":
	{
		"name": "Encore",
		"description":
		(
			"Pocket to return the most recently pocketed ordinary ball to the table. "
			+ "Once per table per round."
		),
		"color": Color("518fef"),
		"asset": "encore.png",
		"rarity": Global.RARITY.UNCOMMON
	},
	"TOGETHER_DOMINO":
	{
		"name": "Domino",
		"description":
		(
			"Pocket to give the next ordinary ball pocketed in this shot +100% value. "
			+ "Once per table per round."
		),
		"color": Color("e783bb"),
		"asset": "domino.png",
		"rarity": Global.RARITY.UNCOMMON
	}
}

var _active = false
var _stock_key = ""
var _resources: Dictionary = {}


func register_balls() -> bool:
	if not _resources.is_empty():
		return _resources.size() == BALLS.size()
	var database = get_node("/root/BallDatabase")
	for id in BALLS:
		var definition: Dictionary = BALLS[id]
		var resource = BallResource.new()
		resource.id = id
		resource.name = definition.name
		resource.description = definition.description
		resource.main_color = definition.color
		resource.texture = _load_texture(definition.asset)
		if resource.texture == null:
			return false
		resource.base_score = 2
		resource.start_level = 1
		resource.rarity = definition.rarity
		resource.tags = []
		resource.from_set = "TOGETHER"
		resource.can_drop = _active
		resource.upgradeable = false
		database.id_to_ball[id] = resource
		database.balls.append(resource)
		database.plain_ball_ids.append(id.to_lower())
		_resources[id] = resource
	return true


func set_active(enabled: bool) -> void:
	register_balls()
	if _active == enabled:
		return
	_active = enabled
	_stock_key = ""
	for resource in _resources.values():
		resource.can_drop = enabled


func prepare_deck(deck: Resource) -> Resource:
	register_balls()
	var result = deck.duplicate(true)
	if result.balls.size() < STARTER_IDS.size():
		result.balls.resize(STARTER_IDS.size())
	for index in STARTER_IDS.size():
		result.balls[index] = STARTER_IDS[index]
	return result


func ensure_shop_offer(shop) -> void:
	if not _active or not is_instance_valid(shop) or not shop.is_open:
		return
	var game = get_node("/root/Global").gameManager
	var stock_key = (
		"%d:%d:%d" % [shop.get_instance_id(), game.rounds_played, shop.times_rerolled_total]
	)
	if stock_key == _stock_key:
		return
	for slot in shop.shop_slots:
		if is_instance_valid(slot.ball) and _resources.has(slot.ball.ball_item.data.id):
			_stock_key = stock_key
			return
	for slot in shop.shop_slots:
		if not is_instance_valid(slot.ball) or slot.ball.is_queued_for_deletion():
			continue
		var offer_index = maxi(0, game.rounds_played - 1) + shop.times_rerolled_total
		var item = BallItem.new()
		item.data = _resources[OFFER_IDS[offer_index % OFFER_IDS.size()]]
		item.base_score = item.data.base_score
		item.level = 1
		slot.ball.ball_item = item
		slot.ball.update_upgrade_status(false)
		slot.set_ball(slot.ball)
		AchievementManager.mark_ball_as_seen(item)
		game.track_ball_seen(item)
		_stock_key = stock_key
		get_node("/root/SaveManager").save_run_state()
		return


func _load_texture(asset: String) -> ImageTexture:
	var path = get_script().resource_path.get_base_dir().path_join("assets/balls").path_join(asset)
	var source = Image.new()
	if source.load(path) != OK or source.get_width() != source.get_height() * 2:
		push_error("Missing or invalid multiplayer ball art: " + asset)
		return null
	var face = source.get_region(Rect2i(0, 0, source.get_height(), source.get_height()))
	face.convert(Image.FORMAT_RGBA8)
	face.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	var atlas = Image.create(512, 384, false, Image.FORMAT_RGBA8)
	atlas.fill(face.get_pixel(0, 0))
	# Native sphere shaders sample the six faces of a 4-by-3 cube cross.
	for cell in [
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(2, 1),
		Vector2i(3, 1),
		Vector2i(1, 2)
	]:
		atlas.blit_rect(face, Rect2i(0, 0, 128, 128), cell * 128)
	atlas.generate_mipmaps()
	return ImageTexture.create_from_image(atlas)

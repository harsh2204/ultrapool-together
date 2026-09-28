extends Node

const SET_ID = "TOGETHER"

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
			"#POCKET: [k]+50% value[/k] after a [friend]teammate[/friend] touched this ball "
			+ "on an earlier shot.[br]In Score PvP or solo, any later shot qualifies."
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
			"#POCKET: [k]+100% value[/k] in the [friend]called pocket[/friend] on the next shot. "
			+ "The previous shooter chooses the pocket."
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
			"Survive a shot that hits any object ball to store [k]+25% value[/k] for a later "
			+ "#POCKET.[br]Stores up to [k]3 charges (+75%)[/k]."
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
			"#POCKET: Score PvP's earliest shot earns [k]25 match points[/k] per tied table. "
			+ "Co-op/Race: [k]+10 run points[/k] within [k]3 match shots[/k]."
		),
		"color": Color("eb5876"),
		"asset": "bounty.png",
		"rarity": Global.RARITY.RARE
	},
	"TOGETHER_BANKROLL":
	{
		"name": "Bankroll",
		"description":
		(
			"#POCKET: [money]+2 coins[/money] after this ball hits a [k]cushion[/k] in the same shot. "
			+ "[br][k]Once per table per round.[/k]"
		),
		"color": Color("efd44e"),
		"asset": "bankroll.png",
		"rarity": Global.RARITY.UNCOMMON
	},
	"TOGETHER_LIFELINE":
	{
		"name": "Lifeline",
		"description":
		(
			"#POCKET: restore [tgood]1 health[/tgood], up to this difficulty's starting health. "
			+ "[br][k]Once per table per round.[/k]"
		),
		"color": Color("55ce94"),
		"asset": "lifeline.png",
		"rarity": Global.RARITY.RARE
	},
	"TOGETHER_ENCORE":
	{
		"name": "Encore",
		"description":
		(
			"#POCKET: return the latest potted [friend]ordinary ball[/friend]. "
			+ "[br][k]Once per table per round.[/k]"
		),
		"color": Color("518fef"),
		"asset": "encore.png",
		"rarity": Global.RARITY.LEGENDARY
	},
	"TOGETHER_DOMINO":
	{
		"name": "Domino",
		"description":
		(
			"#POCKET: the next [friend]ordinary ball[/friend] potted this shot earns [k]+100% value[/k]. "
			+ "[br][k]Once per table per round.[/k]"
		),
		"color": Color("e783bb"),
		"asset": "domino.png",
		"rarity": Global.RARITY.UNCOMMON
	}
}

var _active = false
var _stock_key = ""
var _resources: Dictionary = {}
var _collection: Node


func register_balls() -> bool:
	if not _resources.is_empty():
		return _resources.size() == BALLS.size()
	var database = get_node("/root/BallDatabase")
	# PERF-026/030: prepare the complete bounded catalog before publishing it.
	# A missing asset must not leave duplicate partial database registration.
	var prepared: Dictionary = {}
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
		resource.from_set = SET_ID
		resource.can_drop = _active
		resource.upgradeable = false
		prepared[id] = resource
	for id in prepared:
		var resource = prepared[id]
		database.id_to_ball[id] = resource
		database.balls.append(resource)
		database.plain_ball_ids.append(id.to_lower())
	_resources = prepared
	_register_collection_set(database)
	_collection = (
		load(get_script().resource_path.get_base_dir().path_join("multiplayer_collection.gd")).new()
	)
	add_child(_collection)
	_collection.setup(self)
	return true


func _register_collection_set(database: Node) -> void:
	var ball_set = BallSet.new()
	ball_set.id = SET_ID
	ball_set.name = "Together"
	ball_set.description = "Eight shop-only balls. Enable Multiplayer balls in Mod settings to find them during a run."
	ball_set.main_color = Color("29c7d8")
	# Registration is permanent presentation; shop eligibility remains separate.
	ball_set.can_be_chosen_by_shop = false
	ball_set.available_in_demo = true
	var native_set = database.get_set_by_id("CLASSIC")
	if native_set != null:
		ball_set.poster = native_set.poster
		ball_set.small_icon = native_set.small_icon
	database.id_to_set[SET_ID] = ball_set


static func concepts_for(id: String) -> Array:
	var concepts: Array = []
	match id:
		"TOGETHER_RELAY":
			concepts = [
				_concept(
					"Teammate",
					"Another player at your table must touch this ball on an [k]earlier shot[/k]. Same-shot contact does not count.",
					"friend"
				)
			]
		"TOGETHER_CALL":
			concepts = [
				_concept(
					"Called pocket",
					"The previous shooter selects this ball and [k]clicks a fixed pocket[/k] before the next shot. One shot only.",
					"pocket"
				)
			]
		"TOGETHER_PATIENCE":
			concepts = [
				_concept(
					"Charges",
					"Store [k]one charge[/k] per completed shot that hits an object while Patience survives. Its own pot adds none.",
					"lvl"
				)
			]
		"TOGETHER_BOUNTY":
			concepts = [
				_concept(
					"Match points",
					"Score PvP: earliest Bounty [k]shot number[/k] wins. Each tied table gets 25.",
					"star"
				),
				_concept(
					"Run points",
					"Co-op/Race: +10 round points within this table's [k]first 3 match shots[/k].",
					"pocket"
				)
			]
		"TOGETHER_BANKROLL":
			concepts = [
				_concept(
					"Cushion",
					"[k]Bankroll itself[/k] must hit a rail before its pot in the same shot. Another ball's bounce does not count.",
					"pocket"
				),
				_round_limit()
			]
		"TOGETHER_LIFELINE":
			concepts = [_round_limit()]
		"TOGETHER_ENCORE":
			concepts = [
				_concept(
					"Ordinary ball",
					"Latest non-fleeting ball [k]without multiplayer effects[/k]. Excludes cue balls and snacks.",
					"friend"
				),
				_round_limit()
			]
		"TOGETHER_DOMINO":
			concepts = [
				_concept(
					"Ordinary ball",
					"An object ball [k]without multiplayer effects[/k]. Only the next eligible pot in this shot gets the bonus.",
					"friend"
				),
				_round_limit()
			]
	return concepts


static func _round_limit() -> Dictionary:
	return _concept(
		"Once per round",
		"All players, extra copies and mixes share [k]one reward per table per round[/k].",
		"lvl"
	)


static func _concept(title: String, description: String, icon: String) -> Dictionary:
	var path = (
		"res://effects/star_particle.png" if icon == "star" else "res://ui/tag-icons/%s.png" % icon
	)
	return {"title": title, "description": description, "color": "#286e7b", "icon": path}


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
	# Multiplayer balls stay in the shared shop rotation; the selected deck racks as-is.
	return deck


# Opt-in shops: roughly one in six stocks/rerolls rolls a multiplayer offer.
# Deterministic on stock_key so host and reconnects stay consistent.
const SHOP_OFFER_CHANCE = 6


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
	# Rare appearance: most stocks stay fully native.
	if absi(hash(stock_key)) % SHOP_OFFER_CHANCE != 0:
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
	face.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var atlas = Image.create(1024, 768, false, Image.FORMAT_RGBA8)
	atlas.fill(face.get_pixel(0, 0))
	# Match native 256px cube faces: the sphere shader uses a fixed mip-level scale.
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

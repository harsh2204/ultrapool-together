extends Node
## TIDE — cushion-vs-pocket pressure. Height 0–3 rises on walls, falls on pockets.

const CatalogUtil = preload("catalog_util.gd")
const SET_ID = "TIDE"
const OFFER_IDS = [
	"TIDE_DRIFTWOOD",
	"TIDE_BREAKER",
	"TIDE_BUOY",
	"TIDE_RIPTIDE",
	"TIDE_MAELSTROM",
	"TIDE_UNDERTOW",
	"TIDE_HARBOR",
	"TIDE_TSUNAMI"
]
const BALLS = {
	"TIDE_DRIFTWOOD":
	{
		"name": "Driftwood",
		"description": "Pocket at Tide 1 or lower for +50% value.",
		"color": Color("8c6e46"),
		"asset": "tide_driftwood.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2
	},
	"TIDE_BREAKER":
	{
		"name": "Breaker",
		"description":
		"Cushion bounce raises Tide. At Tide 3, gain +1 temp instead.",
		"color": Color("3264a0"),
		"asset": "tide_breaker.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 1
	},
	"TIDE_BUOY":
	{
		"name": "Buoy",
		"description":
		"Once per round: set Tide to 2 and grant +25% to the next ordinary pocket.",
		"color": Color("c88c32"),
		"asset": "tide_buoy.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"TIDE_RIPTIDE":
	{
		"name": "Riptide",
		"description": "Pocket at Tide 3 to launch the nearest ordinary ball.",
		"color": Color("28508c"),
		"asset": "tide_riptide.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"TIDE_MAELSTROM":
	{
		"name": "Maelstrom",
		"description": "First cushion bounce each shot is a free Tide +1.",
		"color": Color("1e3264"),
		"asset": "tide_maelstrom.png",
		"rarity": Global.RARITY.RARE,
		"base_score": 2
	},
	"TIDE_UNDERTOW":
	{
		"name": "Undertow",
		"description": "Pocket at Tide 2 or higher for +25% value.",
		"color": Color("3c5a78"),
		"asset": "tide_undertow.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2
	},
	"TIDE_HARBOR":
	{
		"name": "Harbor",
		"description": "Once per round: pocket lowers Tide by 1 and pays 1 coin.",
		"color": Color("50828c"),
		"asset": "tide_harbor.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"TIDE_TSUNAMI":
	{
		"name": "Tsunami",
		"description": "Pocket at Tide 3 for +100% value once per ball per round.",
		"color": Color("284682"),
		"asset": "tide_tsunami.png",
		"rarity": Global.RARITY.RARE,
		"base_score": 2
	}
}

var _active = false
var _stock_key: Dictionary = {}
var _resources: Dictionary = {}


func register_balls() -> bool:
	return CatalogUtil.register_balls(self, BALLS, SET_ID, _resources, _active)


func set_active(enabled: bool) -> void:
	register_balls()
	if _active == enabled:
		return
	_active = enabled
	_stock_key.clear()
	CatalogUtil.set_active(_resources, enabled)


func ensure_shop_offer(shop) -> void:
	CatalogUtil.ensure_shop_offer(self, shop, _active, _resources, OFFER_IDS, _stock_key)


func kind_ids() -> Array:
	return OFFER_IDS.duplicate()

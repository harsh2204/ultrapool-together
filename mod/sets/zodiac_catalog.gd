extends Node
## ZODIAC — elemental Alignment. Aspect at 2, Grand Trine at 3 living signs of an element.

const CatalogUtil = preload("catalog_util.gd")
const SET_ID = "ZODIAC"
const OFFER_IDS = [
	"ZODIAC_ARIES",
	"ZODIAC_TAURUS",
	"ZODIAC_GEMINI",
	"ZODIAC_CANCER",
	"ZODIAC_LEO",
	"ZODIAC_VIRGO",
	"ZODIAC_LIBRA",
	"ZODIAC_SCORPIO",
	"ZODIAC_SAGITTARIUS",
	"ZODIAC_CAPRICORN",
	"ZODIAC_AQUARIUS",
	"ZODIAC_PISCES"
]
const BALLS = {
	"ZODIAC_ARIES":
	{
		"name": "Aries",
		"description":
		"+25% on pocket. Fire Aspect: next pocket +25%. Fire Grand Trine: next pocket +50%.",
		"color": Color("c8503c"),
		"asset": "zodiac_aries.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2,
		"tags": ["fire"]
	},
	"ZODIAC_TAURUS":
	{
		"name": "Taurus",
		"description":
		"Cue hit: +1 temp (cap +3). Earth Aspect raises the cap to +5. Trine also grants +1 weight.",
		"color": Color("789650"),
		"asset": "zodiac_taurus.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2,
		"tags": ["earth"]
	},
	"ZODIAC_GEMINI":
	{
		"name": "Gemini",
		"description":
		"Pocket: Air Aspect shares +25% of pre-mult value as temp to a random other Air sign.",
		"color": Color("b4b464"),
		"asset": "zodiac_gemini.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 1,
		"tags": ["air"]
	},
	"ZODIAC_CANCER":
	{
		"name": "Cancer",
		"description":
		"Survive a shot for +1 charge (max 2) only under Water Aspect. Pocket pays +50% × charges.",
		"color": Color("648cb4"),
		"asset": "zodiac_cancer.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2,
		"tags": ["water"]
	},
	"ZODIAC_LEO":
	{
		"name": "Leo",
		"description":
		"While Fire Grand Trine: first Fire pocket each shot gains +100% once.",
		"color": Color("dc8c28"),
		"asset": "zodiac_leo.png",
		"rarity": Global.RARITY.RARE,
		"base_score": 2,
		"tags": ["fire"]
	},
	"ZODIAC_VIRGO":
	{
		"name": "Virgo",
		"description":
		"Pocket under Earth Aspect locks a random non-Zodiac ball until end of shot.",
		"color": Color("8ca064"),
		"asset": "zodiac_virgo.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2,
		"tags": ["earth"]
	},
	"ZODIAC_LIBRA":
	{
		"name": "Libra",
		"description":
		"First cushion bounce this shot under Air Aspect grants +1 temp.",
		"color": Color("b4a08c"),
		"asset": "zodiac_libra.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2,
		"tags": ["air"]
	},
	"ZODIAC_SCORPIO":
	{
		"name": "Scorpio",
		"description":
		"Pocket under Water Aspect: consume nearest lower-base ordinary for +25% × its level.",
		"color": Color("643250"),
		"asset": "zodiac_scorpio.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2,
		"tags": ["water"]
	},
	"ZODIAC_SAGITTARIUS":
	{
		"name": "Sagittarius",
		"description":
		"Pocket under Fire Aspect launches the nearest ordinary ball.",
		"color": Color("c86432"),
		"asset": "zodiac_sagittarius.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2,
		"tags": ["fire"]
	},
	"ZODIAC_CAPRICORN":
	{
		"name": "Capricorn",
		"description":
		"Once per table per round under Earth Aspect: pocket pays 2 coins.",
		"color": Color("64785a"),
		"asset": "zodiac_capricorn.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2,
		"tags": ["earth"]
	},
	"ZODIAC_AQUARIUS":
	{
		"name": "Aquarius",
		"description":
		"Once per table per round under Air Aspect: pocket spawns a fleeting 0-score Echo.",
		"color": Color("508cb4"),
		"asset": "zodiac_aquarius.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2,
		"tags": ["air"]
	},
	"ZODIAC_PISCES":
	{
		"name": "Pisces",
		"description":
		"Once per table per round under Water Aspect: pocket restores 1 health.",
		"color": Color("5a78aa"),
		"asset": "zodiac_pisces.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2,
		"tags": ["water"]
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

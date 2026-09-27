extends Node
## PHASES — moon-phase clock. Shop-only; host advances phase on ordinary pockets.

const CatalogUtil = preload("catalog_util.gd")
const SET_ID = "PHASES"
const OFFER_IDS = [
	"PHASES_CRESCENT",
	"PHASES_FULL_MOON",
	"PHASES_NEW_MOON",
	"PHASES_ECLIPSE",
	"PHASES_APOGEE",
	"PHASES_GIBBOUS",
	"PHASES_UMBRA",
	"PHASES_PENUMBRA"
]
const BALLS = {
	"PHASES_CRESCENT":
	{
		"name": "Crescent",
		"description": "Pocket during Waxing or Waning for +50% value.",
		"color": Color("2a3772"),
		"asset": "phases_crescent.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2
	},
	"PHASES_FULL_MOON":
	{
		"name": "Full Moon",
		"description":
		"During Full phase, when hit: grant +1 temp score to a random ordinary ball.",
		"color": Color("dcd8c8"),
		"asset": "phases_full_moon.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 1
	},
	"PHASES_NEW_MOON":
	{
		"name": "New Moon",
		"description":
		(
			"Pocket during New to store a Silent Charge (max 2). "
			+ "Spend a charge on a later Phase pocket for +100% value."
		),
		"color": Color("191928"),
		"asset": "phases_new_moon.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"PHASES_ECLIPSE":
	{
		"name": "Eclipse",
		"description":
		(
			"Once per table per round: briefly close the top-multiplier pocket for this shot. "
			+ "If you still pocket Eclipse, gain 2 coins."
		),
		"color": Color("3c2850"),
		"asset": "phases_eclipse.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"PHASES_APOGEE":
	{
		"name": "Apogee",
		"description":
		(
			"First time each shot a Phase ball survives an object-ball hit, "
			+ "the moon phase advances an extra step."
		),
		"color": Color("8c64b4"),
		"asset": "phases_apogee.png",
		"rarity": Global.RARITY.RARE,
		"base_score": 2
	},
	"PHASES_GIBBOUS":
	{
		"name": "Gibbous",
		"description": "Pocket during Waxing or Full for +25% value.",
		"color": Color("b4bed2"),
		"asset": "phases_gibbous.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2
	},
	"PHASES_UMBRA":
	{
		"name": "Umbra",
		"description":
		"During New or Waning, survive a cushion bounce to gain +1 temp once per ball per round.",
		"color": Color("322d46"),
		"asset": "phases_umbra.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"PHASES_PENUMBRA":
	{
		"name": "Penumbra",
		"description":
		"While Full or New: the next ordinary pocket this shot gains +50% once per table per round.",
		"color": Color("5a5570"),
		"asset": "phases_penumbra.png",
		"rarity": Global.RARITY.UNCOMMON,
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

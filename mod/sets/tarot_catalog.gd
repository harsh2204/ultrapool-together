extends Node
## TAROT — Major Arcana Spread. No shop redraw UI; orientations flip on cushions.

const CatalogUtil = preload("catalog_util.gd")
const SET_ID = "TAROT"
const OFFER_IDS = [
	"TAROT_FOOL",
	"TAROT_WHEEL",
	"TAROT_TOWER",
	"TAROT_DEATH",
	"TAROT_STAR",
	"TAROT_MAGICIAN",
	"TAROT_SUN",
	"TAROT_TEMPERANCE",
	"TAROT_HANGED",
	"TAROT_STRENGTH"
]
const BALLS = {
	"TAROT_FOOL":
	{
		"name": "The Fool",
		"description":
		"Upright: +100% once per ball per round. Reversed: 0 score but +2 coins once per table per round.",
		"color": Color("c8be96"),
		"asset": "tarot_fool.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 1
	},
	"TAROT_WHEEL":
	{
		"name": "Wheel of Fortune",
		"description":
		"Upright: rerolls its bonus among +25/+50/+100%. Reversed: forces the lowest (+25%).",
		"color": Color("b4783c"),
		"asset": "tarot_wheel.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2
	},
	"TAROT_TOWER":
	{
		"name": "The Tower",
		"description":
		(
			"Once per table per round. Upright: clear all temp score, +3 to this pocket. "
			+ "Reversed: strip one ball's temp and grant +1 to two others."
		),
		"color": Color("783c32"),
		"asset": "tarot_tower.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"TAROT_DEATH":
	{
		"name": "Death",
		"description":
		(
			"Upright: consume nearest lower-base ordinary ball for +50% × its level. "
			+ "Reversed: transform it into a fleeting 0-score Shade."
		),
		"color": Color("32323c"),
		"asset": "tarot_death.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"TAROT_STAR":
	{
		"name": "The Star",
		"description":
		"While upright in the Spread: first ordinary pocket each shot gains +25%.",
		"color": Color("648cc8"),
		"asset": "tarot_star.png",
		"rarity": Global.RARITY.RARE,
		"base_score": 2
	},
	"TAROT_MAGICIAN":
	{
		"name": "The Magician",
		"description": "Upright: +50% value. Reversed: +1 coin.",
		"color": Color("8c50a0"),
		"asset": "tarot_magician.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2
	},
	"TAROT_SUN":
	{
		"name": "The Sun",
		"description":
		"Upright: +100% once per ball per round. Reversed: clears this ball's temp score.",
		"color": Color("dca032"),
		"asset": "tarot_sun.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"TAROT_TEMPERANCE":
	{
		"name": "Temperance",
		"description":
		"Upright: +25% and arm +25% for the next ordinary pocket. Reversed: +25% only.",
		"color": Color("64a08c"),
		"asset": "tarot_temperance.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2
	},
	"TAROT_HANGED":
	{
		"name": "The Hanged Man",
		"description":
		"Upright: survive a shot to store a charge (max 1); pocket pays +50%. Reversed: 0 score.",
		"color": Color("5a6e8c"),
		"asset": "tarot_hanged.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"TAROT_STRENGTH":
	{
		"name": "Strength",
		"description":
		"While upright in the Spread: first cushion bounce on any Arcana grants +1 temp once per shot.",
		"color": Color("b45a46"),
		"asset": "tarot_strength.png",
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

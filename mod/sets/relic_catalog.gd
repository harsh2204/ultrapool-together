extends Node
## RELIC — excavation charges accrued by surviving shots / walls, spent on pocket.

const CatalogUtil = preload("catalog_util.gd")
const SET_ID = "RELIC"
const OFFER_IDS = [
	"RELIC_SHARD",
	"RELIC_IDOL",
	"RELIC_CHEST",
	"RELIC_CURSE",
	"RELIC_CROWN",
	"RELIC_DUST",
	"RELIC_RELIQUARY",
	"RELIC_KEYSTONE"
]
const BALLS = {
	"RELIC_SHARD":
	{
		"name": "Shard",
		"description":
		"Survive an object-ball shot to gain +1 dig (max 4). Pocket pays +25% per dig.",
		"color": Color("b4a064"),
		"asset": "relic_shard.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 1
	},
	"RELIC_IDOL":
	{
		"name": "Idol",
		"description":
		"When any Relic gains a dig, Idol gains +1 temp (cap +3 per round).",
		"color": Color("a0783c"),
		"asset": "relic_idol.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2
	},
	"RELIC_CHEST":
	{
		"name": "Sealed Chest",
		"description":
		"Once per round: pocket while any Relic has dig ≥2 for 2 coins and clear 1 dig.",
		"color": Color("785a32"),
		"asset": "relic_chest.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"RELIC_CURSE":
	{
		"name": "Curse Tablet",
		"description":
		"Pocket locks a random non-Relic ball until the end of the shot.",
		"color": Color("50325a"),
		"asset": "relic_curse.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"RELIC_CROWN":
	{
		"name": "Crown Relic",
		"description": "Dig charges on Relics persist between shots this round.",
		"color": Color("c8aa32"),
		"asset": "relic_crown.png",
		"rarity": Global.RARITY.RARE,
		"base_score": 2
	},
	"RELIC_DUST":
	{
		"name": "Dust",
		"description": "Cushion bounce grants +1 dig once per shot (max 4).",
		"color": Color("96908c"),
		"asset": "relic_dust.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2
	},
	"RELIC_RELIQUARY":
	{
		"name": "Reliquary",
		"description": "Pocket pays +50% if any Relic has dig ≥3.",
		"color": Color("826446"),
		"asset": "relic_reliquary.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"RELIC_KEYSTONE":
	{
		"name": "Keystone",
		"description":
		"Pocket with dig ≥1: every Relic gains +1 dig (still capped at 4).",
		"color": Color("64506e"),
		"asset": "relic_keystone.png",
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

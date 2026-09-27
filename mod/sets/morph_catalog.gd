extends Node
## MORPH — intentional transformation kit. Forms cycle on cue-ball hits.

const CatalogUtil = preload("catalog_util.gd")
const SET_ID = "MORPH"
const OFFER_IDS = [
	"MORPH_VESSEL",
	"MORPH_HEAVY",
	"MORPH_PHASEFORM",
	"MORPH_SPLITTER",
	"MORPH_PRIME",
	"MORPH_SHIELD",
	"MORPH_CATALYST",
	"MORPH_FLUX"
]
const BALLS = {
	"MORPH_VESSEL":
	{
		"name": "Vessel",
		"description":
		"Cycles Idle → Sprinter on cue hits. Sprinter stores +25% on the next cushion bounce.",
		"color": Color("5a8ca0"),
		"asset": "morph_vessel.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 1
	},
	"MORPH_HEAVY":
	{
		"name": "Heavy Form",
		"description":
		"While Heavy is active: +1 weight. Pocket grants +1 flat score to the next ball pocketed this shot.",
		"color": Color("645046"),
		"asset": "morph_heavy.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2
	},
	"MORPH_PHASEFORM":
	{
		"name": "Phaseform",
		"description":
		"First cushion bounce this shot marks it. Pocket after the mark for +100% once per ball per round.",
		"color": Color("785ab4"),
		"asset": "morph_phaseform.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"MORPH_SPLITTER":
	{
		"name": "Splitter",
		"description":
		"Pocket in Splitter form respawns a fleeting 0-score Echo. Once per table per round.",
		"color": Color("b46450"),
		"asset": "morph_splitter.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 1
	},
	"MORPH_PRIME":
	{
		"name": "Prime Morph",
		"description":
		"After three form changes in a round, the next pocket pays +150% once.",
		"color": Color("c8a03c"),
		"asset": "morph_prime.png",
		"rarity": Global.RARITY.RARE,
		"base_score": 2
	},
	"MORPH_SHIELD":
	{
		"name": "Shield Form",
		"description":
		"Cycles Idle → Guard. While Guard: the first cushion bounce this shot grants +1 temp.",
		"color": Color("467896"),
		"asset": "morph_shield.png",
		"rarity": Global.RARITY.COMMON,
		"base_score": 2
	},
	"MORPH_CATALYST":
	{
		"name": "Catalyst",
		"description":
		"Pocket in Catalyst form: +1 temp to every Morph ball once per table per round.",
		"color": Color("a0508c"),
		"asset": "morph_catalyst.png",
		"rarity": Global.RARITY.UNCOMMON,
		"base_score": 2
	},
	"MORPH_FLUX":
	{
		"name": "Flux Core",
		"description":
		"Form changes on this ball count double toward Prime Morph's threshold.",
		"color": Color("50a078"),
		"asset": "morph_flux.png",
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

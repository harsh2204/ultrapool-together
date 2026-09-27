extends RefCounted
## Thin registry of shop-only expansion sets. Each set is default-off and never
## enters id_to_deck / starting racks.

const SET_IDS = ["PHASES", "MORPH", "TIDE", "RELIC", "TAROT", "ZODIAC"]

const SET_LABELS = {
	"PHASES": "Phases",
	"MORPH": "Morph",
	"TIDE": "Tide",
	"RELIC": "Relic",
	"TAROT": "Tarot",
	"ZODIAC": "Zodiac"
}


static func default_flags() -> Dictionary:
	var flags: Dictionary = {}
	for set_id in SET_IDS:
		flags[set_id] = false
	return flags


static func normalize_flags(raw) -> Dictionary:
	var flags = default_flags()
	if not raw is Dictionary:
		return flags
	for set_id in SET_IDS:
		flags[set_id] = bool(raw.get(set_id, false))
	return flags


static func any_enabled(flags: Dictionary) -> bool:
	for set_id in SET_IDS:
		if bool(flags.get(set_id, false)):
			return true
	return false


static func shop_only_set_ids() -> Array:
	## Excluded from between-round set voting (with TOGETHER).
	return SET_IDS.duplicate()

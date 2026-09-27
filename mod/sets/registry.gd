extends RefCounted
## Thin registry of shop-only expansion sets. Each set is default-off and never
## enters id_to_deck / starting racks. Lobby starting-set select is limited to
## the eight native base decks below.

const SET_IDS = ["PHASES", "MORPH", "TIDE", "RELIC", "TAROT", "ZODIAC"]

const SET_LABELS = {
	"PHASES": "Phases",
	"MORPH": "Morph",
	"TIDE": "Tide",
	"RELIC": "Relic",
	"TAROT": "Tarot",
	"ZODIAC": "Zodiac"
}

## Native lobby / between-round set names (BallSet ids and deck-id suffixes).
const NATIVE_LOBBY_SETS = [
	"CLASSIC",
	"NATURE",
	"TECH",
	"SPOOKY",
	"FRIENDS",
	"FOOD",
	"SPACE",
	"GACHA"
]


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


## Master-off forces every set inactive even if a stale per-set flag is on.
static func effective_flags(master_enabled: bool, raw) -> Dictionary:
	if not master_enabled:
		return default_flags()
	return normalize_flags(raw)


static func shop_only_set_ids() -> Array:
	## Excluded from between-round set voting (with TOGETHER).
	return SET_IDS.duplicate()


static func is_native_lobby_set(set_id: String) -> bool:
	var id = str(set_id).strip_edges().to_upper()
	return id in NATIVE_LOBBY_SETS


static func is_native_lobby_deck(deck_id: String) -> bool:
	var id = str(deck_id).strip_edges().to_upper()
	if id.is_empty() or id == "DAILY" or id == "TOGETHER" or id in SET_IDS:
		return false
	if id in NATIVE_LOBBY_SETS:
		return true
	for name in NATIVE_LOBBY_SETS:
		if id.ends_with("_" + name):
			return true
	return false

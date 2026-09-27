extends RefCounted

# Mirrors the fields native SaveManager.get_run_state() fills for a normal run.
# Peers exchange this plain data instead of native share codes: those decode into
# a binary resource file, which must never be loaded from another player.
const Inventory = preload("player_inventory_sync.gd")
const INTEGERS = {
	"money": [-1000000000000, 1000000000000],
	"hp": [0, 1000],
	"seed": [0, 2147483647],
	"rounds_played": [0, 1000],
	"level_number": [0, 1000],
	"winstreak": [0, 1000000],
	"cocktail_charges_spent": [0, 1000000],
	"snack_tickets": [0, 1000000],
	"cocktail_tickets": [0, 1000000],
	"times_rerolled": [0, 1000000],
	"times_rerolled_total": [0, 1000000],
	"snack_tickets_used": [0, 1000000],
	"total_gacha_rolls": [0, 1000000],
	"total_astrolabe_rolls": [0, 1000000],
	"total_scrap_rolls": [0, 1000000],
	"ach_data_upgraded_scrap_count": [0, 1000000],
	"ach_data_planted_flowers_count": [0, 1000000]
}
const TEXT = {"seed_text": 64, "chosen_deck_id": 128, "chosen_difficulty_id": 128, "run_id": 64}
const ITEM_LIMITS = {
	"current_build": 64,
	"current_passives": 8,
	"current_cubes": 64,
	"shop_balls": 16,
	"shop_passives": 8,
	"cocktail_bar_items": 3
}
const PASSIVE_GROUPS = ["current_passives", "shop_passives"]
const MAX_SETS = 32
const MAX_GAME_TIME = 1.0e9


static func capture(state) -> Dictionary:
	if state == null or state.is_daily() or state.is_replay:
		return {}
	var data = {
		"is_run_seeded": state.is_run_seeded,
		"game_time": float(state.game_time),
		"chosen_sets": state.chosen_sets.map(func(id): return str(id))
	}
	for key in INTEGERS:
		data[key] = state.get(key)
	for key in TEXT:
		data[key] = str(state.get(key))
	for group in ITEM_LIMITS:
		var items: Array = []
		for item in state.get(group):
			if item == null:
				items.append(null)
				continue
			# Hats have no stable catalog identity; skip rather than drop one.
			if item.hat != null:
				return {}
			items.append(Inventory.capture_item(item))
		data[group] = items
	return data


static func valid(data, database: Node) -> bool:
	if not data is Dictionary or not data.get("is_run_seeded") is bool:
		return false
	var game_time = data.get("game_time")
	if not game_time is float or not is_finite(game_time):
		return false
	if game_time < 0 or game_time > MAX_GAME_TIME:
		return false
	for key in INTEGERS:
		var value = data.get(key)
		if not value is int or value < INTEGERS[key][0] or value > INTEGERS[key][1]:
			return false
	for key in TEXT:
		if not data.get(key) is String or data[key].length() > TEXT[key]:
			return false
	if (
		data.chosen_deck_id == "DAILY"
		or not database.id_to_deck.has(data.chosen_deck_id)
		or not database.id_to_difficulty.has(data.chosen_difficulty_id)
	):
		return false
	var sets = data.get("chosen_sets")
	if not sets is Array or sets.size() > MAX_SETS:
		return false
	for id in sets:
		if not id is String or _set_key(id, database) == null:
			return false
	for group in ITEM_LIMITS:
		var items = data.get(group)
		if not items is Array or items.size() > ITEM_LIMITS[group]:
			return false
		var resources: Dictionary = _catalog(group, database)
		for item in items:
			if item == null:
				continue
			if not item is Dictionary or not Inventory.valid_item(item, resources):
				return false
			if group == "current_cubes" and resources[item.data].from_set != &"NEGATIVE":
				return false
	return true


static func to_run_state(data: Dictionary, database: Node) -> RunState:
	var state = RunState.new()
	for key in INTEGERS:
		state.set(key, data[key])
	for key in TEXT:
		state.set(key, data[key])
	state.is_run_seeded = data.is_run_seeded
	state.game_time = data.game_time
	var sets: Array = []
	for id in data.chosen_sets:
		sets.append(_set_key(id, database))
	state.chosen_sets = sets
	for group in ITEM_LIMITS:
		var resources: Dictionary = _catalog(group, database)
		var items: Array[BallItem] = []
		for entry in data[group]:
			items.append(Inventory.build_item(entry, resources) if entry != null else null)
		state.set(group, items)
	return state


static func _catalog(group: String, database: Node) -> Dictionary:
	return database.id_to_passive if group in PASSIVE_GROUPS else database.id_to_ball


# Native sets are keyed by their resource IDs; reuse that exact key value.
static func _set_key(id: String, database: Node):
	for key in database.id_to_set:
		if str(key) == id:
			return key
	return null

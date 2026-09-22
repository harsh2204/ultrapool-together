extends RefCounted

const SLOT_LIMITS = {"build": 64, "passives": 4, "cubes": 64}
const SLOT_MINIMUMS = {"build": 16, "passives": 4, "cubes": 0}
const NUMBERS = {
	"base_score": [-1.0e18, 1.0e18],
	"temp_extra_score": [-1.0e18, 1.0e18],
	"level": [1, 1000000],
	"weight_state": [0, 3]
}
const FLAGS = ["flaming", "fleeting", "star_power", "shielded", "shield_broken", "locked"]


static func capture(info: Node) -> Dictionary:
	var result = {"snacks": info.snack_tickets, "cocktails": info.cocktail_tickets}
	for group in SLOT_LIMITS:
		var slots: Array = []
		for item in info.get(group):
			if item == null:
				slots.append(null)
				continue
			var entry = {
				"data": str(item.data.id),
				"mixed": str(item.mixed_data.id) if item.mixed_data != null else ""
			}
			for key in NUMBERS:
				entry[key] = item.get(key)
			for key in FLAGS:
				entry[key] = item.get(key)
			slots.append(entry)
		result[group] = slots
	return result


static func valid(data, database: Node) -> bool:
	if not data is Dictionary:
		return false
	for key in ["snacks", "cocktails"]:
		if not data.get(key) is int or data[key] < 0 or data[key] > 1000000:
			return false
	for group in SLOT_LIMITS:
		if (
			not data.get(group) is Array
			or data[group].size() < SLOT_MINIMUMS[group]
			or data[group].size() > SLOT_LIMITS[group]
		):
			return false
		var resources: Dictionary = (
			database.id_to_passive if group == "passives" else database.id_to_ball
		)
		for item in data[group]:
			if item == null:
				continue
			if not item is Dictionary or not _valid_item(item, resources):
				return false
			if group == "cubes" and resources[item.data].from_set != &"NEGATIVE":
				return false
	return true


static func apply(info: Node, data: Dictionary, database: Node) -> void:
	info.snack_tickets = data.snacks
	info.cocktail_tickets = data.cocktails
	for group in SLOT_LIMITS:
		var slots: Array[BallItem] = []
		var resources: Dictionary = (
			database.id_to_passive if group == "passives" else database.id_to_ball
		)
		for entry in data[group]:
			if entry == null:
				slots.append(null)
				continue
			var item = BallItem.new()
			item.data = resources[entry.data]
			if entry.mixed != "":
				item.mixed_data = resources[entry.mixed]
			for key in NUMBERS:
				item.set(key, entry[key])
			for key in FLAGS:
				item.set(key, entry[key])
			slots.append(item)
		info.set(group, slots)


static func _valid_item(item: Dictionary, resources: Dictionary) -> bool:
	if (
		not item.get("data") is String
		or not resources.has(item.data)
		or not item.get("mixed") is String
		or (item.mixed != "" and not resources.has(item.mixed))
	):
		return false
	for key in NUMBERS:
		if not item.get(key) is int or item[key] < NUMBERS[key][0] or item[key] > NUMBERS[key][1]:
			return false
	for key in FLAGS:
		if not item.get(key) is bool:
			return false
	return true

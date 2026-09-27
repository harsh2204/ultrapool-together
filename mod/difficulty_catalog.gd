extends RefCounted

## Registers the Together single-table All Nighter difficulty by cloning native
## `diff_6` (All Nighter / `6_all_nighter.tres`) and forces one table in the lobby.

const SetRegistry = preload("sets/registry.gd")
const NATIVE_ALL_NIGHTER_ID = "diff_6"
const TOGETHER_ALL_NIGHTER_ID = "diff_together_nighter"
const TOGETHER_ALL_NIGHTER_TITLE = "All Nighter (One Table)"


static func together_nighter_id() -> String:
	return TOGETHER_ALL_NIGHTER_ID


static func forces_single_table(difficulty_id: String) -> bool:
	return difficulty_id == TOGETHER_ALL_NIGHTER_ID


static func is_registered(database) -> bool:
	return database != null and database.id_to_difficulty.has(TOGETHER_ALL_NIGHTER_ID)


static func register(database, menu = null) -> bool:
	if database == null or not database.id_to_difficulty.has(NATIVE_ALL_NIGHTER_ID):
		return false
	if is_registered(database):
		_ensure_menu(menu, database.id_to_difficulty[TOGETHER_ALL_NIGHTER_ID])
		return true
	var base = database.id_to_difficulty[NATIVE_ALL_NIGHTER_ID]
	var clone = base.duplicate(true)
	clone.id = TOGETHER_ALL_NIGHTER_ID
	clone.can_be_chosen = true
	_apply_title(clone)
	database.id_to_difficulty[TOGETHER_ALL_NIGHTER_ID] = clone
	if database.get("difficulties") is Array and not database.difficulties.has(clone):
		database.difficulties.append(clone)
	_ensure_menu(menu, clone)
	return true


static func choosable_decks(database) -> Array:
	var entries: Array = []
	if database == null:
		return entries
	for deck in database.id_to_deck.values():
		if deck == null or not deck.can_be_chosen:
			continue
		var deck_id = str(deck.id)
		if not SetRegistry.is_native_lobby_deck(deck_id):
			continue
		entries.append({"id": deck_id, "label": _resource_label(deck, deck_id)})
	entries.sort_custom(func(a, b): return a.label < b.label)
	return entries


static func choosable_difficulties(database) -> Array:
	var entries: Array = []
	if database == null:
		return entries
	register(database)
	for difficulty in database.id_to_difficulty.values():
		if difficulty == null or not difficulty.can_be_chosen:
			continue
		entries.append(
			{"id": str(difficulty.id), "label": _resource_label(difficulty, str(difficulty.id))}
		)
	entries.sort_custom(func(a, b): return a.label < b.label)
	return entries


static func _apply_title(difficulty) -> void:
	# Set every present label field. Lobby cards read `resource.name` via run_setup
	# (#13); stopping after the first field left native "All Nighter" on `name`.
	for field in ["title", "name", "display_name"]:
		if _has_property(difficulty, field):
			difficulty.set(field, TOGETHER_ALL_NIGHTER_TITLE)


static func _resource_label(resource, fallback: String) -> String:
	for field in ["title", "name", "display_name"]:
		if not _has_property(resource, field):
			continue
		var value = str(resource.get(field)).strip_edges()
		if not value.is_empty() and not value.begins_with("DIFF_") and value != str(resource.id):
			return value
	if str(resource.id) == TOGETHER_ALL_NIGHTER_ID:
		return TOGETHER_ALL_NIGHTER_TITLE
	if str(resource.id) == NATIVE_ALL_NIGHTER_ID:
		return "All Nighter"
	return fallback


static func _has_property(object, property_name: String) -> bool:
	if object == null:
		return false
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false


static func _ensure_menu(menu, difficulty) -> void:
	if menu == null or difficulty == null:
		return
	if menu.get("difficulties") is Array and not menu.difficulties.has(difficulty):
		menu.difficulties.append(difficulty)

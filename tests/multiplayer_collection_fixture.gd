extends RefCounted

## Native collection/inspection coverage in the existing authorized capture.
## Invoke from the menu before starting a run; no gameplay or save unlocks.
const Catalog = preload("../mod/multiplayer_ball_catalog.gd")
const SLOT_PROPERTIES = ["slots_common", "slots_uncommon", "slots_rare", "slots_legendary"]
const INSPECT_CAPTURES = {
	"TOGETHER_BANKROLL": "collection-together-bankroll",
	"TOGETHER_BOUNTY": "collection-together-bounty",
	"TOGETHER_ENCORE": "collection-together-encore",
}


func run(mod: Node, capture: Callable, check: Callable) -> bool:
	var catalog = mod.multiplayer_balls.catalog
	var global = mod.get_node("/root/Global")
	var database = mod.get_node("/root/BallDatabase")
	var achievements = mod.get_node("/root/AchievementManager")
	var ui = mod.get_node("/root/UIManager")
	var active_before: bool = catalog._active
	var seen: Dictionary = {}
	for id in Catalog.BALLS:
		seen[id] = achievements.has_seen_ball(database.get_ball_by_id(id))
	catalog.set_active(false)
	var native_ball_count: int = database.balls.size()
	check.call(
		catalog.register_balls() and database.balls.size() == native_ball_count,
		"collection: repeated registration retains resource count"
	)
	check.call(
		database.get_set_by_id("TOGETHER").get_formatted_name() == "Together",
		"collection: production set has the distinct Together label"
	)
	check.call(
		not database.get_all_sets().has("TOGETHER"),
		"collection: Together never enters native shop-set selection"
	)
	mod._set_panel(false)
	global.go_to_gallery()
	var gallery = await _wait_scene(mod, "res://gallery.tscn")
	if not check.call(is_instance_valid(gallery), "collection: native gallery opens"):
		catalog.set_active(active_before)
		return false
	var manager = gallery.tab_manager
	var page = manager.get_node_or_null("TogetherCollection")
	if not check.call(page != null, "collection: startup adds Together while multiplayer is off"):
		await _return_menu(mod)
		catalog.set_active(active_before)
		return false
	var page_count: int = manager.get_child_count()
	check.call(catalog._collection.attach_gallery(gallery), "collection: reattach is accepted")
	check.call(
		manager.get_child_count() == page_count and gallery.tab_selector.count == page_count,
		"collection: reattach does not duplicate pages or desynchronize navigation"
	)
	check.call(
		not page.visible and page.process_mode == Node.PROCESS_MODE_DISABLED,
		"collection: offscreen page disables native hover and rotation processing"
	)
	var slots = _shown_slots(page)
	check.call(slots.size() == Catalog.BALLS.size(), "collection: exactly eight unlocked mod balls")
	for id in Catalog.BALLS:
		var resource = database.get_ball_by_id(id)
		check.call(not resource.can_drop, "collection: disabled shop drop gate for " + id)
		check.call(slots.has(id), "collection: production page includes " + id)
		if not slots.has(id):
			continue
		var slot = slots[id]
		check.call(
			not slot.is_locked and slot.has_hover and slot.ball_item.data == resource,
			"collection: " + id + " uses its real native inspectable resource"
		)
		check.call(
			slot.get_node("visuals/ball").visible and not slot.get_node("visuals/pip").visible,
			"collection: " + id + " restores visible art instead of pending dots"
		)
		check.call(
			resource.get_formatted_name() == Catalog.BALLS[id].name,
			"collection: " + id + " production label matches the catalog"
		)
		check.call(
			resource.rarity == Catalog.BALLS[id].rarity,
			"collection: " + id + " native rarity matches its catalog"
		)
		check.call(
			slot.ball_item.get_buy_price() == [3, 4, 6, 9][int(resource.rarity)],
			"collection: " + id + " uses its native rarity price"
		)
		var native = manager.get_child(0)
		check.call(
			not native.get("slots_common").has(slot),
			"collection: " + id + " has a clone-owned slot"
		)
	_check_native_materials(manager, page, database, check)
	catalog.set_active(true)
	check.call(_all_drop(database, true), "collection: run opt-in enables drop resources")
	catalog.set_active(false)
	check.call(
		_all_drop(database, false) and _shown_slots(page).size() == Catalog.BALLS.size(),
		"collection: disabling drops retains every visible collection entry"
	)
	gallery.tab_selector.idx = page.get_index()
	manager.switch_to(page.get_index(), 1)
	await _frames(mod, 8)
	await capture.call(
		"collection-together",
		"Together collection · all eight balls visible with Multiplayer balls disabled"
	)
	var info = ui.info_display
	var panel_ids: Array = info.keyword_panels.map(func(panel): return panel.get_instance_id())
	for id in Catalog.BALLS:
		if not slots.has(id):
			continue
		var slot = slots[id]
		slot.set_process(false)
		global.clear_hovered_item()
		slot.on_hover()
		await _frames(mod, 6)
		check.call(
			info.ball_item == slot.ball_item and info.showing,
			"collection: " + id + " native hover opens its inspection"
		)
		check.call(
			(
				info.desc_label.text
				== TextFormatter.format(slot.ball_item.get_formatted_description())
			),
			"collection: " + id + " applies native magic text to the production description"
		)
		check.call(
			(
				info.rarity_label.text
				== str(global.get_rarity_name(slot.ball_item.data.rarity)).to_upper()
			),
			"collection: " + id + " shows the native localized rarity"
		)
		for concept in Catalog.concepts_for(id):
			var found = false
			for panel in info.keyword_panels:
				if panel.visible and panel.l_name.text.contains(concept.title):
					found = panel.l_desc.text == TextFormatter.format(concept.description)
			check.call(found, "collection: " + id + " explains " + concept.title)
		if INSPECT_CAPTURES.has(id):
			await capture.call(
				INSPECT_CAPTURES[id],
				(
					Catalog.BALLS[id].name
					+ " · native rarity, highlighted description and concept helpers"
				)
			)
		global.clear_hovered_item()
		slot.set_process(true)
	check.call(
		(
			info.keyword_panels.size() == 4
			and info.keyword_panels.map(func(panel): return panel.get_instance_id()) == panel_ids
		),
		"collection: all inspections reuse the same four native helper panels"
	)
	if slots.has("TOGETHER_BOUNTY"):
		var mixed_slot = slots.TOGETHER_BOUNTY
		mixed_slot.set_process(false)
		mixed_slot.ball_item.mixed_data = database.get_ball_by_id("TOGETHER_ENCORE")
		mixed_slot.on_hover()
		await _frames(mod, 6)
		check.call(
			info.keyword_panels.filter(func(panel): return panel.visible).size() == 4,
			"collection: two multiplayer effects fill at most four retained helpers"
		)
		mixed_slot.ball_item.mixed_data = mixed_slot.ball_item.data
		info.update()
		check.call(
			info.keyword_panels.filter(func(panel): return panel.visible).size() == 2,
			"collection: a same-ball mix deduplicates concept helpers"
		)
		for resource in database.balls:
			if Catalog.BALLS.has(str(resource.id)):
				continue
			var keywords = TextFormatter.extract_keywords(resource.get_formatted_description(1))
			var native_titles: Array = []
			for keyword in keywords.slice(0, 4):
				var definition: Dictionary = TextFormatter.KEYWORD_CONFIG[keyword]
				if definition.has("title_key"):
					native_titles.append(mod.tr(definition.title_key))
			if native_titles.is_empty():
				continue
			mixed_slot.ball_item.mixed_data = resource
			info.update()
			for title in native_titles:
				check.call(
					info.keyword_panels.any(
						func(panel): return panel.visible and panel.l_name.text.contains(title)
					),
					"collection: mixed inspection retains native helper priority for " + title
				)
			check.call(
				info.keyword_panels.filter(func(panel): return panel.visible).size() <= 4,
				"collection: native and multiplayer mixed helpers stay within four panels"
			)
			break
		mixed_slot.ball_item.mixed_data = null
		global.clear_hovered_item()
		mixed_slot.set_process(true)
	await _check_vanilla_cleanup(mod, gallery, page, capture, check)
	for id in seen:
		check.call(
			achievements.has_seen_ball(database.get_ball_by_id(id)) == seen[id],
			"collection: browsing does not mark " + id + " discovered"
		)
	await _return_menu(mod)
	global.go_to_gallery()
	var reopened = await _wait_scene(mod, "res://gallery.tscn")
	var reopen_ok: bool = is_instance_valid(reopened)
	if reopen_ok:
		var fresh_page = reopened.tab_manager.get_node_or_null("TogetherCollection")
		reopen_ok = fresh_page != null and _shown_slots(fresh_page).size() == Catalog.BALLS.size()
		check.call(
			reopened.tab_manager.get_child_count() == page_count,
			"collection: reopening recreates exactly one Together page"
		)
	check.call(
		reopen_ok, "collection: close/reopen preserves all eight balls without enabling shops"
	)
	var menu_ok = await _return_menu(mod)
	catalog.set_active(active_before)
	return menu_ok and reopen_ok


func _shown_slots(page: Node) -> Dictionary:
	var result: Dictionary = {}
	for property in SLOT_PROPERTIES:
		for slot in page.get(property):
			if (
				slot.visible
				and slot.ball_item != null
				and Catalog.BALLS.has(str(slot.ball_item.data.id))
			):
				result[str(slot.ball_item.data.id)] = slot
	return result


func _all_drop(database: Node, expected: bool) -> bool:
	for id in Catalog.BALLS:
		if database.get_ball_by_id(id).can_drop != expected:
			return false
	return true


func _check_native_materials(manager: Node, added: Node, database: Node, check: Callable) -> void:
	for page in manager.get_children():
		if page == added or not page.get("slots_common") is Array:
			continue
		for property in SLOT_PROPERTIES:
			for slot in page.get(property):
				if slot.ball_item == null:
					continue
				var data = slot.ball_item.data
				var expected = (
					database.get_ball_by_id("LOCKED").texture if slot.is_locked else data.texture
				)
				check.call(
					slot.get_node("visuals/ball").material.get_shader_parameter("tex") == expected,
					"collection: appended page preserves native shader texture for " + str(data.id)
				)


func _check_vanilla_cleanup(
	mod: Node, gallery: Node, page: Node, capture: Callable, check: Callable
) -> void:
	var global = mod.get_node("/root/Global")
	var info = mod.get_node("/root/UIManager").info_display
	var native = gallery.tab_manager.get_child(0)
	var slot = native.slots_common[0]
	gallery.tab_selector.idx = 0
	gallery.tab_manager.switch_to(0, -1)
	await _frames(mod, 6)
	slot.set_process(false)
	slot.set_data(slot.display_resource, true)
	global.clear_hovered_item()
	slot.on_hover()
	await _frames(mod, 6)
	var expected = TextFormatter.format(slot.ball_item.get_formatted_description())
	check.call(
		info.desc_label.text == expected, "collection: vanilla inspection retains native formatting"
	)
	var own_titles: Array = []
	for id in Catalog.BALLS:
		for concept in Catalog.concepts_for(id):
			own_titles.append(concept.title)
	for panel in info.keyword_panels:
		if panel.visible:
			for title in own_titles:
				check.call(
					not panel.l_name.text.contains(title),
					"collection: vanilla clears helper " + title
				)
	check.call(
		not page.visible and page.process_mode == Node.PROCESS_MODE_DISABLED,
		"collection: switching away suspends the Together page"
	)
	await capture.call(
		"collection-vanilla-after-together",
		"Native collection inspection · multiplayer concept panels cleared"
	)
	global.clear_hovered_item()
	slot.set_process(true)


func _return_menu(mod: Node) -> bool:
	mod.get_node("/root/Global").clear_hovered_item()
	mod.get_node("/root/Global").go_to_main_menu()
	return is_instance_valid(await _wait_scene(mod, "res://main_menu.tscn"))


func _wait_scene(mod: Node, path: String) -> Node:
	for _frame in 90:
		await mod.get_tree().process_frame
		var scene = mod.get_tree().current_scene
		if (
			is_instance_valid(scene)
			and scene.scene_file_path == path
			and scene.is_node_ready()
			and not mod.get_node("/root/Global").transitioning
		):
			return scene
	return null


func _frames(mod: Node, count: int) -> void:
	for _frame in count:
		await mod.get_tree().process_frame

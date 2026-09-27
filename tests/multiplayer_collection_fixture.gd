extends RefCounted

## Native collection/inspection coverage in the existing authorized capture.
## Invoke from the menu before starting a run; no gameplay or save unlocks.
const Catalog = preload("../mod/multiplayer_ball_catalog.gd")
const SLOT_PROPERTIES = ["slots_common", "slots_uncommon", "slots_rare", "slots_legendary"]
const SET_LIST_PATH = "ShopBalls/ScrollContainer/MarginContainer/VBoxContainer"
const SET_DISPLAY_PATH = "Control/GallerySetDisplay"
const INSPECT_CAPTURES = {
	"TOGETHER_RELAY": "collection-together-relay",
	"TOGETHER_CALL": "collection-together-called-shot",
	"TOGETHER_PATIENCE": "collection-together-patience",
	"TOGETHER_BANKROLL": "collection-together-bankroll",
	"TOGETHER_BOUNTY": "collection-together-bounty",
	"TOGETHER_LIFELINE": "collection-together-lifeline",
	"TOGETHER_ENCORE": "collection-together-encore",
	"TOGETHER_DOMINO": "collection-together-domino",
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
	var container = manager.get_node_or_null(SET_LIST_PATH)
	var set_panel = container.get_node_or_null("TogetherCollection") if container != null else null
	var page = set_panel.get_node_or_null(SET_DISPLAY_PATH) if set_panel != null else null
	if not check.call(page != null, "collection: startup adds Together while multiplayer is off"):
		_describe_gallery(manager)
		await _return_menu(mod)
		catalog.set_active(active_before)
		return false
	var panel_count: int = container.get_child_count()
	var major_tab_count: int = manager.get_child_count()
	var native_displays = _set_displays(container).filter(func(display): return display != page)
	check.call(
		major_tab_count == 2 and gallery.tab_selector.count == 2,
		"collection: native ball and board-customization tabs remain unchanged"
	)
	check.call(
		(
			set_panel.get_index() > 0
			and (
				container.get_child(set_panel.get_index() - 1).get_node_or_null(SET_DISPLAY_PATH)
				!= null
			)
			and container.get_node("PlanetsDisplay").get_index() == set_panel.get_index() + 1
		),
		"collection: Together follows native ball sets and precedes planets"
	)
	check.call(catalog._collection.attach_gallery(gallery), "collection: reattach is accepted")
	check.call(
		(
			container.get_child_count() == panel_count
			and container.get_node("TogetherCollection") == set_panel
			and manager.get_child_count() == major_tab_count
			and gallery.tab_selector.count == major_tab_count
		),
		"collection: reattach retains one set panel and native major-tab navigation"
	)
	var slots = _shown_slots(page)
	var heading = page.get_node("TogetherCollectionTitle")
	var poster = page.get_node("Poster")
	var poster_size: Vector2 = poster.get_rect().size * poster.scale.abs()
	check.call(
		(
			heading.get_minimum_size().x <= poster_size.x + 1.0
			and heading.get_minimum_size().y <= poster_size.y + 1.0
		),
		"collection: complete Together heading fits the native poster footprint"
	)
	check.call(
		heading.tooltip_text.contains("Mod settings") and heading.text.contains("Shop-only"),
		"collection: heading explains shop-only availability and the opt-in setting"
	)
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
		check.call(
			(
				page.is_ancestor_of(slot)
				and not native_displays.any(func(display): return display.is_ancestor_of(slot))
			),
			"collection: " + id + " has a clone-owned slot"
		)
	_check_native_materials(container, page, database, check)
	catalog.set_active(true)
	check.call(_all_drop(database, true), "collection: run opt-in enables drop resources")
	catalog.set_active(false)
	check.call(
		_all_drop(database, false) and _shown_slots(page).size() == Catalog.BALLS.size(),
		"collection: disabling drops retains every visible collection entry"
	)
	gallery.toggle_selector.select(manager.get_node("BoardCustom").get_index())
	await _frames(mod, 8)
	check.call(
		not set_panel.is_visible_in_tree() and not page.can_process(),
		"collection: native board-customization tab suspends Together hover and rotation"
	)
	gallery.toggle_selector.select(manager.get_node("ShopBalls").get_index())
	await _frames(mod, 8)
	check.call(
		set_panel.is_visible_in_tree() and page.can_process(),
		"collection: returning to native balls tab restores Together processing"
	)
	check.call(
		await _scroll_into_view(mod, gallery, set_panel),
		"collection: native scrolling brings the complete Together panel into view"
	)
	var slot_processing = _suspend_collection_processing(container)
	global.clear_hovered_item()
	_check_collection_bounds(set_panel, page, slots, check)
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
		global.clear_hovered_item()
		slot.on_hover()
		check.call(
			await _wait_inspection(mod, info),
			"collection: " + id + " inspection settles at full size"
		)
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
		_check_inspection_bounds(info, check, id)
		if INSPECT_CAPTURES.has(id):
			await capture.call(
				INSPECT_CAPTURES[id],
				(
					Catalog.BALLS[id].name
					+ " · native rarity, highlighted description and concept helpers"
				)
			)
		global.clear_hovered_item()
	check.call(
		(
			info.keyword_panels.size() == 4
			and info.keyword_panels.map(func(panel): return panel.get_instance_id()) == panel_ids
		),
		"collection: all inspections reuse the same four native helper panels"
	)
	if slots.has("TOGETHER_BOUNTY"):
		var mixed_slot = slots.TOGETHER_BOUNTY
		mixed_slot.ball_item.mixed_data = database.get_ball_by_id("TOGETHER_ENCORE")
		mixed_slot.on_hover()
		check.call(
			await _wait_inspection(mod, info), "collection: four-helper mixed inspection settles"
		)
		check.call(
			info.keyword_panels.filter(func(panel): return panel.visible).size() == 4,
			"collection: two multiplayer effects fill at most four retained helpers"
		)
		_check_inspection_bounds(info, check, "Bounty + Encore mix")
		await capture.call(
			"collection-together-mixed-four-helpers",
			"Bounty + Encore · complete mixed inspection and four native concept panels"
		)
		mixed_slot.ball_item.mixed_data = mixed_slot.ball_item.data
		info.update()
		check.call(
			await _wait_inspection(mod, info), "collection: same-ball mixed inspection settles"
		)
		check.call(
			info.keyword_panels.filter(func(panel): return panel.visible).size() == 2,
			"collection: a same-ball mix deduplicates concept helpers"
		)
		_check_inspection_bounds(info, check, "Bounty + Bounty mix")
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
			check.call(
				await _wait_inspection(mod, info),
				"collection: native-keyword mixed inspection settles"
			)
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
			_check_inspection_bounds(info, check, "Bounty + " + str(resource.id))
			break
		mixed_slot.ball_item.mixed_data = null
		global.clear_hovered_item()
	_restore_slot_processing(slot_processing)
	await _check_vanilla_cleanup(mod, gallery, container, page, capture, check)
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
		var fresh_container = reopened.tab_manager.get_node_or_null(SET_LIST_PATH)
		var fresh_panel = (
			fresh_container.get_node_or_null("TogetherCollection")
			if fresh_container != null
			else null
		)
		var fresh_page = (
			fresh_panel.get_node_or_null(SET_DISPLAY_PATH) if fresh_panel != null else null
		)
		reopen_ok = fresh_page != null and _shown_slots(fresh_page).size() == Catalog.BALLS.size()
		check.call(
			(
				fresh_container != null
				and fresh_container.get_child_count() == panel_count
				and reopened.tab_manager.get_child_count() == major_tab_count
				and reopened.tab_selector.count == major_tab_count
			),
			"collection: reopening recreates one Together set without adding a major tab"
		)
	check.call(
		reopen_ok, "collection: close/reopen preserves all eight balls without enabling shops"
	)
	var menu_ok = await _return_menu(mod)
	catalog.set_active(active_before)
	return menu_ok and reopen_ok


func _describe_gallery(manager: Node) -> void:
	# Bounded diagnostics for unsupported native gallery hierarchy changes.
	var pending: Array = [[manager, 0]]
	var visited = 0
	while not pending.is_empty() and visited < 300:
		var entry: Array = pending.pop_front()
		var node: Node = entry[0]
		var depth: int = entry[1]
		var script = node.get_script()
		var script_path: String = script.resource_path if script is Script else ""
		if depth <= 5 or script_path == "res://gallery_set_display.gd":
			print(
				"COLLECTION_LAYOUT ",
				manager.get_path_to(node),
				" script=",
				script_path,
				" class=",
				node.get_class(),
				" position=",
				node.position if node is Control or node is Node2D else Vector2.ZERO,
				" minimum_size=",
				node.get_combined_minimum_size() if node is Control else Vector2.ZERO
			)
		visited += 1
		if depth < 8:
			for child in node.get_children().slice(0, 30):
				pending.append([child, depth + 1])


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


func _set_displays(container: Node) -> Array:
	var result: Array = []
	for panel in container.get_children():
		var display = panel.get_node_or_null(SET_DISPLAY_PATH)
		if display == null:
			continue
		var script = display.get_script()
		if script is Script and script.resource_path == "res://gallery_set_display.gd":
			result.append(display)
	return result


func _suspend_collection_processing(container: Node) -> Array:
	# All native sets and planets share the active balls tab. Suspend their
	# DisplayItemBall nodes so cursor hover cannot replace a forced inspection.
	var previous: Array = []
	var pending: Array = [[container, 0]]
	var visited = 0
	while not pending.is_empty() and visited < 2000:
		var entry: Array = pending.pop_back()
		var node: Node = entry[0]
		var depth: int = entry[1]
		visited += 1
		if node is DisplayItemBall:
			previous.append({"slot": node, "processing": node.is_processing()})
			node.set_process(false)
		elif depth < 8:
			for child in node.get_children():
				pending.append([child, depth + 1])
	return previous


func _restore_slot_processing(previous: Array) -> void:
	for entry in previous:
		if is_instance_valid(entry.slot):
			entry.slot.set_process(entry.processing)


func _scroll_into_view(mod: Node, gallery: Node, panel: Control) -> bool:
	var scroll = gallery.tab_manager.get_node("ShopBalls/ScrollContainer")
	await _frames(mod, 2)
	for _frame in 24:
		if not scroll._bounds_dirty and panel.size.y > 0.0:
			break
		await mod.get_tree().process_frame
	if scroll._bounds_dirty or panel.size.y <= 0.0:
		return false
	var transform: Transform2D = (
		scroll.get_global_transform().affine_inverse() * panel.get_global_transform()
	)
	var bounds: Rect2 = transform * Rect2(Vector2.ZERO, panel.size)
	var target_top: float = maxf(0.0, (scroll.size.y - bounds.size.y) * 0.5)
	scroll.velocity = 0.0
	scroll.dragging = false
	scroll._scroll_by(target_top - bounds.position.y)
	await _frames(mod, 3)
	transform = scroll.get_global_transform().affine_inverse() * panel.get_global_transform()
	bounds = transform * Rect2(Vector2.ZERO, panel.size)
	return Rect2(Vector2.ZERO, scroll.size).grow(1.0).encloses(bounds)


func _all_drop(database: Node, expected: bool) -> bool:
	for id in Catalog.BALLS:
		if database.get_ball_by_id(id).can_drop != expected:
			return false
	return true


func _rendered_bounds(item: CanvasItem) -> Rect2:
	var local_bounds = Rect2()
	if item is Control:
		local_bounds = Rect2(Vector2.ZERO, item.size)
	elif item is Sprite2D:
		local_bounds = item.get_rect()
	# Includes the native CanvasLayer offset and camera transform. Global
	# positions alone would compare the gallery and inspector in different spaces.
	return item.get_global_transform_with_canvas() * local_bounds


func _check_enclosed(outer: Rect2, inner: Rect2, check: Callable, label: String) -> void:
	var fits = inner.size.x > 0.0 and inner.size.y > 0.0 and outer.grow(1.0).encloses(inner)
	if not fits:
		print("COLLECTION_BOUNDS ", label, " rendered=", inner, " enclosing=", outer)
	check.call(fits, "collection: " + label)


func _check_collection_bounds(
	section: Control, page: Node, slots: Dictionary, check: Callable
) -> void:
	var section_bounds = _rendered_bounds(section)
	check.call(
		section.size.is_equal_approx(Vector2(400.0, 400.0)),
		"collection: Together retains the native 400 by 400 set section"
	)
	_check_enclosed(
		section.get_viewport().get_visible_rect(),
		section_bounds,
		check,
		"Together section fits viewport"
	)
	var heading: Label = page.get_node("TogetherCollectionTitle")
	var heading_bounds = _rendered_bounds(heading)
	_check_enclosed(
		section_bounds, heading_bounds, check, "actual heading stays within its set section"
	)
	_check_enclosed(
		_rendered_bounds(page.get_node("Poster")),
		heading_bounds,
		check,
		"actual heading stays within the native poster footprint"
	)
	_check_text_fit(heading, check, "Together heading")
	var ball_bounds: Dictionary = {}
	for id in slots:
		var art = slots[id].get_node("visuals/ball")
		check.call(art.is_visible_in_tree(), "collection: " + id + " renders its ball artwork")
		ball_bounds[id] = _rendered_bounds(art)
		_check_enclosed(
			section_bounds,
			ball_bounds[id],
			check,
			id + " actual ball artwork stays within its set section"
		)
		_check_separated(
			heading_bounds,
			ball_bounds[id],
			check,
			id + " art does not overlap the Together heading"
		)
	var ids = ball_bounds.keys()
	for first in ids.size():
		for second in range(first + 1, ids.size()):
			_check_separated(
				ball_bounds[ids[first]],
				ball_bounds[ids[second]],
				check,
				ids[first] + " and " + ids[second] + " artwork do not overlap"
			)
	_check_native_edges(section.get_parent(), page, check)


func _check_native_edges(container: Node, added: Node, check: Callable) -> void:
	# Native edge shaders draw a small outline inside a much larger transparent
	# quad. Its get_rect() is not the visible outline footprint. Check retained
	# native geometry/shader instead; captures establish visible outline fit.
	var sources = _set_displays(container).filter(func(display): return display != added)
	if not check.call(not sources.is_empty(), "collection: native outline reference exists"):
		return
	var source = sources[0]
	for property in SLOT_PROPERTIES:
		var slots: Array = added.get(property)
		var native_slots: Array = source.get(property)
		for index in slots.size():
			var slot = slots[index]
			if not slot.visible or slot.ball_item == null:
				continue
			var id = str(slot.ball_item.data.id)
			if not Catalog.BALLS.has(id):
				continue
			if not check.call(
				index < native_slots.size(), "collection: " + id + " outline reference slot exists"
			):
				continue
			var edge = slot.get_node("visuals/edge")
			var native_slot = native_slots[index]
			var native_edge = native_slot.get_node("visuals/edge")
			# Compare local transforms beneath each slot; far-apart scroll positions
			# otherwise introduce avoidable global-inverse rounding differences.
			var relative: Transform2D = edge.get_parent().get_transform() * edge.get_transform()
			var native_relative: Transform2D = (
				native_edge.get_parent().get_transform() * native_edge.get_transform()
			)
			check.call(
				(
					edge.is_visible_in_tree()
					and relative.is_equal_approx(native_relative)
					and edge.texture == native_edge.texture
				),
				"collection: " + id + " retains native visible outline geometry"
			)
			var own_material = edge.material
			var native_material = native_edge.material
			check.call(
				(
					own_material is ShaderMaterial
					and native_material is ShaderMaterial
					and own_material != native_material
					and own_material.shader == native_material.shader
					and (
						own_material.get_shader_parameter("selout_color")
						== lerp(slot.ball_item.data.main_color, Color.BLACK, 0.3)
					)
				),
				"collection: " + id + " uses its isolated native outline shader and resource color"
			)


func _check_separated(first: Rect2, second: Rect2, check: Callable, label: String) -> void:
	var separated = not first.intersects(second)
	if not separated:
		print("COLLECTION_OVERLAP ", label, " first=", first, " second=", second)
	check.call(separated, "collection: " + label)


func _wait_inspection(mod: Node, info: Node) -> bool:
	# Native inspection waits 0.1 seconds, grows in, then repositions after
	# container layout. Check the final scale, never a temporarily shrunken panel.
	for _frame in 32:
		await mod.get_tree().process_frame
		if (
			info.showing
			and info.delay <= 0.0
			and info.reposition_frames == 0
			and info.scale_value >= 0.999
			and info.main_panel.is_visible_in_tree()
		):
			return true
	return false


func _check_inspection_bounds(info: Node, check: Callable, label: String) -> void:
	var viewport_bounds: Rect2 = info.get_viewport().get_visible_rect()
	var main_bounds = _rendered_bounds(info.main_panel)
	_check_enclosed(viewport_bounds, main_bounds, check, label + " main inspector fits viewport")
	if info.level.is_visible_in_tree():
		var badge = info.level.get_node_or_null("Panel")
		if check.call(badge is Control, "collection: " + label + " has the native level badge"):
			var badge_bounds = _rendered_bounds(badge)
			_check_enclosed(
				viewport_bounds, badge_bounds, check, label + " level badge fits viewport"
			)
			_check_enclosed(
				badge_bounds,
				_rendered_bounds(info.level_label),
				check,
				label + " level text stays within its badge"
			)
			_check_text_fit(info.level_label, check, label + " level badge")
	for text_label in [info.name_label, info.desc_label]:
		_check_enclosed(
			main_bounds,
			_rendered_bounds(text_label),
			check,
			label + " " + str(text_label.name) + " stays within main inspector"
		)
		_check_text_fit(text_label, check, label + " " + str(text_label.name))
	for index in info.keyword_panels.size():
		var helper = info.keyword_panels[index]
		if not helper.visible:
			continue
		var helper_label = label + " helper " + str(index + 1)
		check.call(helper.is_visible_in_tree(), "collection: " + helper_label + " is rendered")
		var helper_bounds = _rendered_bounds(helper)
		_check_enclosed(viewport_bounds, helper_bounds, check, helper_label + " fits viewport")
		for text_label in [helper.l_name, helper.l_desc]:
			_check_enclosed(
				helper_bounds,
				_rendered_bounds(text_label),
				check,
				helper_label + " " + str(text_label.name) + " stays within its panel"
			)
			_check_text_fit(text_label, check, helper_label + " " + str(text_label.name))


func _check_text_fit(text_label: Control, check: Callable, label: String) -> void:
	var minimum = text_label.get_minimum_size()
	var required_height: float = minimum.y
	if text_label is RichTextLabel:
		required_height = maxf(required_height, text_label.get_content_height())
	var fits = minimum.x <= text_label.size.x + 1.0 and required_height <= text_label.size.y + 1.0
	if not fits:
		print(
			"COLLECTION_TEXT_FIT ",
			label,
			" size=",
			text_label.size,
			" minimum=",
			minimum,
			" content_height=",
			required_height
		)
	check.call(fits, "collection: " + label + " text fits without clipping")


func _check_native_materials(container: Node, added: Node, database: Node, check: Callable) -> void:
	for page in _set_displays(container):
		if page == added:
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
	mod: Node, gallery: Node, container: Node, added: Node, capture: Callable, check: Callable
) -> void:
	var global = mod.get_node("/root/Global")
	var info = mod.get_node("/root/UIManager").info_display
	var native_displays = _set_displays(container).filter(func(display): return display != added)
	if not check.call(not native_displays.is_empty(), "collection: native set remains available"):
		return
	var native = native_displays[0]
	var slot = native.slots_common[0]
	var native_panel = native.get_parent().get_parent()
	check.call(
		await _scroll_into_view(mod, gallery, native_panel),
		"collection: native scrolling returns to a complete vanilla set"
	)
	var slot_processing = _suspend_collection_processing(container)
	slot.set_data(slot.display_resource, true)
	global.clear_hovered_item()
	slot.on_hover()
	check.call(await _wait_inspection(mod, info), "collection: vanilla control inspection settles")
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
	_check_inspection_bounds(info, check, "vanilla control")
	await capture.call(
		"collection-vanilla-after-together",
		"Native collection inspection · multiplayer concept panels cleared"
	)
	global.clear_hovered_item()
	_restore_slot_processing(slot_processing)


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

extends Node

## PERF-026/030: append one native collection page at scene readiness. Never
## poll/rebuild the gallery or alter native Play-menu arrays, discovery or saves.
const SET_ID = "TOGETHER"
const PAGE_NAME = "TogetherCollection"
const GALLERY_SCRIPT = "res://gallery.gd"
const SET_SCRIPT = "res://gallery_set_display.gd"
const INFO_SCRIPT = "res://info_display.gd"
const SLOT_PROPERTIES = ["slots_common", "slots_uncommon", "slots_rare", "slots_legendary"]
const MAX_SLOTS = 64
const MAX_GALLERIES = 2

var _catalog: Node
var _info_script: Script
var _info_native_script: Script
var _info_display: WeakRef
var _pages: Array[WeakRef] = []


func setup(catalog: Node) -> void:
	_catalog = catalog
	_info_script = load(
		get_script().resource_path.get_base_dir().path_join("multiplayer_info_display.gd")
	)
	get_tree().node_added.connect(_node_added)
	var ui = get_node_or_null("/root/UIManager")
	if ui != null and is_instance_valid(ui.info_display):
		_hook_info(ui.info_display)
	var scene = get_tree().current_scene
	if is_instance_valid(scene):
		_node_added(scene)


func _node_added(node: Node) -> void:
	var script = node.get_script()
	if not script is Script:
		return
	if script.resource_path == GALLERY_SCRIPT:
		if node.is_node_ready():
			attach_gallery(node)
		else:
			node.ready.connect(attach_gallery.bind(node), CONNECT_ONE_SHOT)
	elif script.resource_path == INFO_SCRIPT:
		if node.is_node_ready():
			_hook_info(node)
		else:
			node.ready.connect(_hook_info.bind(node), CONNECT_ONE_SHOT)


func _hook_info(node: Node) -> void:
	if not is_instance_valid(node) or node.get_script() == _info_script:
		return
	var script = node.get_script()
	if not script is Script or script.resource_path != INFO_SCRIPT:
		return
	_restore_info()
	_info_display = weakref(node)
	_info_native_script = script
	_replace_script(node, _info_script)


func _replace_script(node: Node, script: Script) -> void:
	# Preserve initialized native @onready fields, including its four panels.
	# Their containers are borrowed and are never cleared or recreated here.
	var values: Dictionary = {}
	for property in node.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = node.get(property.name)
	node.set_script(script)
	for property in node.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and values.has(property.name):
			node.set(property.name, values[property.name])


func attach_gallery(gallery: Node) -> bool:
	if not is_instance_valid(gallery) or not gallery.is_node_ready():
		return false
	var manager = gallery.get("tab_manager")
	var selector = gallery.get("tab_selector")
	if not is_instance_valid(manager) or not is_instance_valid(selector):
		return false
	if manager.get_node_or_null(PAGE_NAME) != null:
		return true
	_pages = _pages.filter(func(reference): return is_instance_valid(reference.get_ref()))
	if _pages.size() >= MAX_GALLERIES:
		push_warning("Together collection: two native gallery views are already attached.")
		return false
	var template: Node
	for child in manager.get_children():
		var script = child.get_script()
		if script is Script and script.resource_path == SET_SCRIPT:
			template = child
			break
	if template == null:
		push_warning("Together collection: native set-page template was not found.")
		return false
	var page = template.duplicate(Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	page.name = PAGE_NAME
	page.ball_set = get_node("/root/BallDatabase").get_set_by_id(SET_ID)
	page.only_can_drop = false
	var slots = _own_slots(page)
	if slots.is_empty() or not _has_capacity(slots):
		page.free()
		push_warning("Together collection: unsupported native rarity-slot layout.")
		return false
	# Native prefab materials are mutable. Isolate the clone before its _ready
	# or set_data writes shader fields, even if its source page was already ready.
	for row in slots:
		for slot in row:
			for path in ["visuals/ball", "visuals/edge"]:
				var art = slot.get_node_or_null(path)
				if art != null and art.material != null:
					art.material = art.material.duplicate()
	manager.add_child(page)
	var database = get_node("/root/BallDatabase")
	for rarity in slots.size():
		var resources: Array = []
		for id in _catalog.BALLS:
			var resource = database.get_ball_by_id(id)
			if int(resource.rarity) == rarity:
				resources.append(resource)
		for index in slots[rarity].size():
			var slot = slots[rarity][index]
			if index < resources.size():
				slot.set_data(resources[index], true)
				slot.has_hover = true
				# A duplicated source slot may previously have been PENDING. Native
				# set_data does not undo those child visibility overrides itself.
				for path in ["visuals/ball", "visuals/edge", "visuals/shadowTransform/shadow"]:
					var art = slot.get_node_or_null(path)
					if art != null:
						art.show()
				var pip = slot.get_node_or_null("visuals/pip")
				if pip != null:
					pip.hide()
				slot.show()
				slot.set_process(true)
			else:
				slot.has_hover = false
				slot.hide()
				slot.set_process(false)
	_build_heading(page)
	manager.set_tab_state(page, false)
	# set_count() resets idx to zero; preserve current page/selector agreement.
	selector.count = manager.get_child_count()
	_pages.append(weakref(page))
	return true


func _own_slots(page: Node) -> Array:
	var rows: Array = []
	var total = 0
	for property in SLOT_PROPERTIES:
		var original = page.get(property)
		if not original is Array:
			return []
		var row = original.duplicate()
		total += row.size()
		if total > MAX_SLOTS:
			return []
		for slot in row:
			if not is_instance_valid(slot) or not page.is_ancestor_of(slot):
				return []
		page.set(property, row)
		rows.append(row)
	return rows


func _has_capacity(rows: Array) -> bool:
	var needed = [0, 0, 0, 0]
	for definition in _catalog.BALLS.values():
		needed[int(definition.rarity)] += 1
	for rarity in needed.size():
		if rows[rarity].size() < needed[rarity]:
			return false
	return true


func _build_heading(page: Node) -> void:
	var poster = page.get_node_or_null("Poster")
	if not poster is Sprite2D:
		return
	var heading = Label.new()
	heading.name = "TogetherCollectionTitle"
	var bounds: Rect2 = poster.get_rect()
	heading.position = poster.position + bounds.position * poster.scale
	heading.size = bounds.size * poster.scale.abs()
	heading.text = "TOGETHER\n8 multiplayer balls"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Color("fff1d2"))
	heading.add_theme_color_override("font_outline_color", Color("39291f"))
	heading.add_theme_constant_override("outline_size", 5)
	var ui = get_node_or_null("/root/UIManager")
	if ui != null:
		heading.add_theme_font_override("font", ui.FONT_LATIN)
	page.add_child(heading)
	poster.hide()


func _restore_info() -> void:
	if _info_display != null:
		var display = _info_display.get_ref()
		if is_instance_valid(display) and display.get_script() == _info_script:
			_replace_script(display, _info_native_script)
	_info_display = null
	_info_native_script = null


func _exit_tree() -> void:
	_restore_info()
	for reference in _pages:
		var page = reference.get_ref()
		if not is_instance_valid(page) or page.is_queued_for_deletion():
			continue
		var manager = page.get_parent()
		if not is_instance_valid(manager) or not manager.is_inside_tree():
			continue
		var gallery = manager.owner
		if manager.cur == page.get_index():
			manager.cur = 0
			manager.set_tab_state(manager.get_child(0), true)
		manager.remove_child(page)
		page.queue_free()
		if is_instance_valid(gallery) and is_instance_valid(gallery.get("tab_selector")):
			gallery.tab_selector.count = manager.get_child_count()
			gallery.tab_selector.idx = manager.cur
	_pages.clear()

extends RefCounted


static func create(scene: PackedScene) -> Node:
	return _copy_state(scene.get_state())


static func copy_live(source: Node) -> Node:
	var node = _visual_node(source.get_class())
	node.name = source.name
	node.set_meta("native_type", source.get_class())
	var properties: Dictionary = {}
	for property in node.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and property.name != "script":
			properties[property.name] = true
	for property in source.get_property_list():
		if not properties.has(property.name):
			continue
		var value = source.get(property.name)
		if value is Material:
			value = value.duplicate()
		node.set(property.name, value)
	for child in source.get_children():
		node.add_child(copy_live(child))
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CanvasItem:
		node.set_as_top_level(false)
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func exported(scene: PackedScene, property: StringName):
	var state = scene.get_state()
	while state != null:
		for index in state.get_node_property_count(0):
			if state.get_node_property_name(0, index) == property:
				return state.get_node_property_value(0, index)
		state = state.get_base_scene_state()
	return null


static func _copy_state(state: SceneState) -> Node:
	var base = state.get_base_scene_state()
	var root = _copy_state(base) if base != null else null
	for index in state.get_node_count():
		var path = state.get_node_path(index)
		var node = root.get_node_or_null(path) if root != null else null
		if node == null:
			var instance = state.get_node_instance(index)
			node = (
				create(instance) if instance != null else _visual_node(state.get_node_type(index))
			)
			node.name = state.get_node_name(index)
			if state.get_node_type(index) != "":
				node.set_meta("native_type", state.get_node_type(index))
			if index == 0:
				root = node
			else:
				root.get_node(state.get_node_path(index, true)).add_child(node)
		var properties: Dictionary = {}
		for property in node.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name != "script":
				properties[property.name] = true
		for property in state.get_node_property_count(index):
			var key = state.get_node_property_name(index, property)
			var theme_override = node is Control and str(key).begins_with("theme_override")
			if not properties.has(key) and not theme_override:
				continue
			var value = state.get_node_property_value(index, property)
			if value is Material:
				value = value.duplicate()
			node.set(key, value)
		node.process_mode = Node.PROCESS_MODE_DISABLED
		if node is CanvasItem:
			node.set_as_top_level(false)
		if node is Control:
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return root


static func _visual_node(type: StringName) -> Node:
	match type:
		"Sprite2D":
			return Sprite2D.new()
		"Polygon2D":
			return Polygon2D.new()
		"MeshInstance2D":
			return MeshInstance2D.new()
		"CanvasGroup":
			return CanvasGroup.new()
		"Line2D":
			return Line2D.new()
		"Label":
			return Label.new()
		"TextureRect":
			return TextureRect.new()
		"NinePatchRect":
			return NinePatchRect.new()
		"ColorRect":
			return ColorRect.new()
		"Panel":
			return Panel.new()
		"PanelContainer":
			return PanelContainer.new()
		"MarginContainer":
			return MarginContainer.new()
		"HBoxContainer":
			return HBoxContainer.new()
		"VBoxContainer":
			return VBoxContainer.new()
	if ClassDB.is_parent_class(type, "Control"):
		return Control.new()
	if ClassDB.is_parent_class(type, "Node2D"):
		return Node2D.new()
	return Node.new()

extends RefCounted
## Native shop balls ship an Upgradebar ("MERGED n") that defaults visible at level 1
## in the packed scene. Host-native flow hides it until the ball is upgraded past
## BallResource.start_level; guest set_item / update_level_spark paths can leave it
## showing on base-level balls (#32). Drive visibility from start_level, change-only.

static func start_level_of(item) -> int:
	if item == null:
		return 1
	var data = item.get("data") if item is Object else null
	if data != null and data.get("start_level") != null:
		return int(data.start_level)
	return 1


static func should_show_upgrade(level: int, start_level: int) -> bool:
	return level > start_level


static func apply_upgrade_badge(node: Node, level: int, start_level: int = -1) -> void:
	if not is_instance_valid(node):
		return
	var start: int = start_level if start_level >= 0 else 1
	if start_level < 0 and node.has_method("get_item"):
		start = start_level_of(node.get_item())
	var show: bool = should_show_upgrade(level, start)
	var bar = node.get_node_or_null("Upgradebar")
	if bar == null:
		bar = node.find_child("Upgradebar", true, false)
	if bar is CanvasItem and bar.visible != show:
		bar.visible = show
	if show and bar != null:
		var label = bar.get_node_or_null("Level/Label")
		if label is Label and label.text != str(level):
			label.text = str(level)
	for arrow_name in ["ArrowsUp"]:
		var arrows = node.get_node_or_null(arrow_name)
		if arrows == null:
			arrows = node.find_child(arrow_name, true, false)
		if arrows is CanvasItem and arrows.visible != show:
			arrows.visible = show

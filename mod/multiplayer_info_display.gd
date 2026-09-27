extends "res://info_display.gd"

## PERF-026: reuse the native four helper panels at its description-update seam.
## The catalog installs this script while preserving native initialized fields;
## do not call native _ready again or allocate another panel/hover process.
const MultiplayerCatalog = preload("multiplayer_ball_catalog.gd")
const MAX_HELPER_PANELS = 4
const MAX_CONCEPTS_PER_BALL = 2


func parse_and_show_description(raw_text: String) -> void:
	# Native formatting and native keyword explanations always take precedence.
	# This also clears helpers left by the previously inspected multiplayer ball.
	super.parse_and_show_description(raw_text)
	if ball_item == null:
		return
	var panel_limit = mini(MAX_HELPER_PANELS, keyword_panels.size())
	var panel_index = 0
	var shown: Dictionary = {}
	for resource in [ball_item.data, ball_item.mixed_data]:
		if resource == null or not MultiplayerCatalog.BALLS.has(str(resource.id)):
			continue
		var concepts: Array = MultiplayerCatalog.concepts_for(str(resource.id))
		for index in mini(MAX_CONCEPTS_PER_BALL, concepts.size()):
			var concept: Dictionary = concepts[index]
			var title = tr(str(concept.get("title", "")))
			var description = tr(str(concept.get("description", "")))
			var key = title + "\n" + description
			if title.is_empty() or description.is_empty() or shown.has(key):
				continue
			while panel_index < panel_limit and keyword_panels[panel_index].visible:
				panel_index += 1
			if panel_index >= panel_limit:
				return
			shown[key] = true
			var color = str(concept.get("color", "#dd5c9f"))
			var icon = str(concept.get("icon", ""))
			var heading = "[color=%s]%s[/color]" % [color, title]
			if not icon.is_empty():
				heading = "[img=24x24 color=%s]%s[/img] " % [color, icon] + heading
			keyword_panels[panel_index].set_info(heading, TextFormatter.format(description))
			keyword_panels[panel_index].show()
			panel_index += 1

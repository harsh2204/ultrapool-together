extends RefCounted

## Host-authoritative view/navigation location for shared screens (#16).
## Purchases and selections stay authoritative elsewhere; this only syncs what
## screen / shop counter everyone should be looking at.

const PLACES := ["lobby", "table", "shop", "snack_bar", "set_vote"]
const SHOP_SECTIONS := ["balls", "mix", "snacks", "cues"]


static func host_place(controller: Node) -> String:
	if controller == null:
		return "table"
	if bool(controller.panel.visible):
		return "lobby"
	if controller.set_voting != null and controller.set_voting.active():
		return "set_vote"
	if controller.shop_sync != null and controller.shop_sync.is_open():
		if controller.shop_sync.current_section() == "snacks":
			return "snack_bar"
		return "shop"
	return "table"


static func capture(controller: Node, section: String = "", focus: String = "") -> Dictionary:
	var place := host_place(controller)
	var shop_section := ""
	if place in ["shop", "snack_bar"]:
		shop_section = section if section in SHOP_SECTIONS else "balls"
		if place == "snack_bar":
			shop_section = "snacks"
	return {
		"place": place,
		"section": shop_section,
		"focus": focus if focus is String else ""
	}


static func valid(data) -> bool:
	if not data is Dictionary:
		return false
	if not data.get("place") in PLACES:
		return false
	var section = data.get("section", "")
	if not section is String or (section != "" and section not in SHOP_SECTIONS):
		return false
	var focus = data.get("focus", "")
	if not focus is String or focus.length() > 128:
		return false
	if focus != "" and not focus.contains(":"):
		return false
	return true


static func signature(data: Dictionary) -> Array:
	return [data.get("place", ""), data.get("section", ""), data.get("focus", "")]

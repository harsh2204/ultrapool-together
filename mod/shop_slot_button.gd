extends Button

signal drop_requested(source: String, destination: String, revision: int, item_id: int)

var slot_key = ""
var revision = 0
var item_id = 0


func _get_drag_data(_position: Vector2):
	if disabled or item_id == 0:
		return null
	var preview = Label.new()
	preview.text = tooltip_text.get_slice("\n", 0)
	set_drag_preview(preview)
	return {"shop_slot": slot_key, "revision": revision, "item_id": item_id}


func _can_drop_data(_position: Vector2, data) -> bool:
	return (
		not disabled
		and data is Dictionary
		and data.get("shop_slot") is String
		and data.get("revision") is int
		and data.get("item_id") is int
	)


func _drop_data(_position: Vector2, data):
	drop_requested.emit(data.shop_slot, slot_key, data.revision, data.item_id)

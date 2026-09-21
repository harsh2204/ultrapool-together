extends Button

signal drop_requested(source: String, destination: String, revision: int, item_id: int)

var slot_key = ""
var revision = 0
var item_id = 0
var preview_texture: Texture2D
var preview_material: Material


func _draw() -> void:
	if button_pressed:
		draw_arc(size * 0.5, size.x * 0.46, 0, TAU, 48, Color(0.4, 1.0, 0.8), 2.0, true)


func _get_drag_data(_position: Vector2):
	if disabled or item_id == 0:
		return null
	var preview = TextureRect.new()
	preview.texture = preview_texture
	preview.material = preview_material
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(48, 48)
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


func _drop_data(_position: Vector2, data) -> void:
	drop_requested.emit(data.shop_slot, slot_key, data.revision, data.item_id)

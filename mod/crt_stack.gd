extends Object

## Places Together CanvasLayers under the native CRT overlay so mod UI receives
## the same post-process treatment as vanilla HUD. Spectator fixtures already
## require `layer < EffectManager.crt_overlay.get_parent().layer`.

const FALLBACK_OVERLAY_LAYER := 100
const OFFSET_PRESENCE := 1
const OFFSET_HUD := 2
const OFFSET_SHOP_NOTICE := 3
const OFFSET_SPECTATOR := 10


static func overlay_layer(from_node: Node) -> int:
	if from_node == null:
		return FALLBACK_OVERLAY_LAYER
	var effects = from_node.get_node_or_null("/root/EffectManager")
	if effects == null:
		return FALLBACK_OVERLAY_LAYER
	var overlay = effects.get("crt_overlay")
	if overlay == null or not is_instance_valid(overlay):
		return FALLBACK_OVERLAY_LAYER
	var parent = overlay.get_parent()
	if parent is CanvasLayer:
		return maxi(int(parent.layer), 1)
	return FALLBACK_OVERLAY_LAYER


static func place_under(layer: CanvasLayer, from_node: Node, offset: int) -> void:
	if layer == null:
		return
	layer.layer = overlay_layer(from_node) - maxi(offset, 1)


static func under_overlay(from_node: Node, layer_value: int) -> bool:
	return layer_value < overlay_layer(from_node)

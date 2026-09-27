extends Button
## Mod-owned settings gear shared by lobby and in-game HUD (PERF-026).
## Geometry is drawn only on Control redraws; no asset imports or frame polling.


func _ready() -> void:
	text = ""
	custom_minimum_size = Vector2(40, 40)
	focus_mode = Control.FOCUS_ALL
	accessibility_name = "Mod settings"
	accessibility_description = "Open personal view preferences and shared match settings."
	if tooltip_text.is_empty():
		tooltip_text = "Mod settings"
	add_theme_stylebox_override("normal", _slate(Color("15292f"), Color("49656a")))
	add_theme_stylebox_override("hover", _slate(Color("24424a"), Color("a7c1c1")))
	add_theme_stylebox_override("pressed", _slate(Color("0c2026"), Color("35d5ab")))
	add_theme_stylebox_override("disabled", _slate(Color("142327"), Color("34464b")))
	var focus = _slate(Color.TRANSPARENT, Color("e8b861"))
	focus.set_border_width_all(2)
	add_theme_stylebox_override("focus", focus)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var center = size * 0.5
	var ink = Color("eaf0e7") if not disabled else Color("71858a")
	if is_pressed():
		center.y += 1.0
	var outline = PackedVector2Array()
	for tooth in 8:
		for corner in 4:
			var angle = TAU * (float(tooth) + float(corner) * 0.25) / 8.0
			var radius = 11.0 if corner in [1, 2] else 8.5
			outline.append(center + Vector2.from_angle(angle) * radius)
	outline.append(outline[0])
	draw_polyline(outline, ink, 1.5, true)
	draw_arc(center, 3.5, 0.0, TAU, 24, ink, 1.5, true)


func _slate(fill: Color, edge: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style

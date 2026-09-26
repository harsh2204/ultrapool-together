extends Button

# PERF-026: retain the option, native texture, styles, and voter presentation.
# Vote snapshots update these only when their bounded presentation changes.
const INK = Color("eaf0e7")
const MUTED = Color("8baeb2")
const GOLD = Color("e8b861")
const FELT = Color("35d5ab")
const DECK_SIZE = Vector2(80, 112)
const COMPACT_SIZE = Vector2(130, 62)
const MAX_VOTERS = 8

var choice_id: String = ""
var voter_ids: Array[int] = []

var _field = ""
var _choice_label = ""
var _texture: Texture2D
var _label: Label
var _font: Font
var _voters: Array[Dictionary] = []
var _selected = false
var _winning = false
var _locked = false


func _init() -> void:
	toggle_mode = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("normal", _box(Color("14282d"), Color("35535a"), 1))
	add_theme_stylebox_override("hover", _box(Color("203c40"), MUTED, 1))
	add_theme_stylebox_override("pressed", _box(Color("173e38"), FELT, 2))
	add_theme_stylebox_override("hover_pressed", _box(Color("204b43"), FELT, 2))
	add_theme_stylebox_override("disabled", _box(Color("17282c"), Color("35535a"), 1))
	var focus_style = _box(Color.TRANSPARENT, INK, 2)
	focus_style.expand_margin_left = 3
	focus_style.expand_margin_right = 3
	focus_style.expand_margin_top = 3
	focus_style.expand_margin_bottom = 3
	add_theme_stylebox_override("focus", focus_style)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.clip_text = true
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", INK)
	add_child(_label)
	resized.connect(_layout_label)


func _ready() -> void:
	_font = get_theme_font("font")
	_layout_label()
	queue_redraw()


func configure(field: String, choice: String, label: String, texture: Texture2D) -> void:
	if _field == field and choice_id == choice and _choice_label == label and _texture == texture:
		return
	_field = field
	choice_id = choice
	_choice_label = label
	accessibility_name = label
	_texture = texture
	custom_minimum_size = DECK_SIZE if field == "deck" else COMPACT_SIZE
	_label.text = label
	_label.visible = field != "deck" or texture == null
	_layout_label()
	_update_tooltip()
	queue_redraw()


func render_votes(voters: Array[Dictionary], selected: bool, winning: bool, locked: bool) -> void:
	if _voters == voters and _selected == selected and _winning == winning and _locked == locked:
		# The native Button may have toggled before its authoritative response arrived.
		if button_pressed != selected:
			set_pressed_no_signal(selected)
		return
	_voters.clear()
	voter_ids.clear()
	for voter in voters:
		if _voters.size() == MAX_VOTERS:
			break
		_voters.append(voter.duplicate())
		voter_ids.append(int(voter.get("id", 0)))
	_selected = selected
	_winning = winning
	_locked = locked
	set_pressed_no_signal(selected)
	disabled = locked
	mouse_default_cursor_shape = (Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND)
	_update_tooltip()
	queue_redraw()


func _layout_label() -> void:
	if not is_instance_valid(_label):
		return
	if _field == "deck":
		_label.position = Vector2(6, 23)
		_label.size = Vector2(maxf(0, size.x - 12), 48)
	else:
		var inset = 35.0 if _texture != null else 16.0
		_label.position = Vector2(inset, 5)
		_label.size = Vector2(maxf(0, size.x - inset - 14), 30)


func _draw() -> void:
	if _font == null:
		return
	var radio_position = Vector2(10, 10)
	draw_arc(radio_position, 4, 0, TAU, 16, FELT if button_pressed else MUTED, 1, true)
	if button_pressed:
		draw_circle(radio_position, 2, FELT)
		# Keep the local vote visible even when the native disabled style is active.
		if disabled:
			draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), FELT, false, 2)
	if _winning:
		var center = Vector2(size.x - 10, 10)
		draw_colored_polygon(
			PackedVector2Array(
				[
					center + Vector2(0, -4),
					center + Vector2(4, 0),
					center + Vector2(0, 4),
					center + Vector2(-4, 0)
				]
			),
			GOLD
		)
	if _texture != null:
		var image_size = Vector2(49, 56) if _field == "deck" else Vector2(24, 24)
		var image_position = (
			Vector2((size.x - image_size.x) / 2, 19) if _field == "deck" else Vector2(8, 15)
		)
		draw_texture_rect(_texture, Rect2(image_position, image_size), false)
	_draw_voters()


func _draw_voters() -> void:
	var is_deck = _field == "deck"
	if _voters.is_empty():
		_draw_centered("No votes", Vector2(size.x / 2, 94 if is_deck else 54), 10, MUTED)
		return
	var columns = 4 if is_deck else MAX_VOTERS
	var spacing = 15.0 if is_deck else 14.0
	for index in _voters.size():
		var row = index / columns
		var column = index % columns
		var row_count = mini(columns, _voters.size() - row * columns)
		var x = size.x / 2 + (column - (row_count - 1) / 2.0) * spacing
		var y = 86.0 + row * 15 if is_deck else 49.0
		if is_deck and _voters.size() <= columns:
			y += 6
		var voter: Dictionary = _voters[index]
		var tint: Color = voter.get("color", MUTED)
		var initial = str(voter.get("name", "?")).strip_edges().left(1).to_upper()
		if initial.is_empty():
			initial = "?"
		draw_circle(Vector2(x, y), 6, tint)
		_draw_centered(initial, Vector2(x, y + 3.5), 10, Color("10282a"))


func _draw_centered(value: String, baseline: Vector2, font_size: int, color: Color) -> void:
	var width = _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(
		_font,
		baseline - Vector2(width / 2, 0),
		value,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)


func _update_tooltip() -> void:
	var lines: Array[String] = [_choice_label]
	if _selected:
		lines.append("Your vote · selected radio button")
	if _winning:
		lines.append("Current result · gold diamond")
	if _voters.is_empty():
		lines.append("No votes yet")
	else:
		var names: Array[String] = []
		for voter in _voters:
			names.append(str(voter.get("name", "Player")))
		lines.append(
			"%d vote%s: %s" % [_voters.size(), "" if _voters.size() == 1 else "s", ", ".join(names)]
		)
	tooltip_text = "\n".join(lines)
	accessibility_description = tooltip_text


func _box(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(6)
	return style

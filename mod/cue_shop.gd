extends Node2D

## Fourth world-space counter. Parent beside TapasBar under ShopSlider/ShopCamera;
## shop_sync positions it at the next counter and owns navigation/transactions.
## PERF-026/034/036: build/cache once, retain controls, keep previews local while pending.

signal action_requested(action: String, model_id: String, finish_id: String)
signal close_requested

const CueCatalog = preload("cue_catalog.gd")
const CueModels = preload("cue_models.gd")
const CueVisuals = preload("cue_visuals.gd")
const INK = Color("39291f")
const PAPER = Color("f4e7cb")
const WOOD = Color("844b2d")
const GOLD = Color("edc86b")
const PURPLE = Color("6427a4")
const GREEN = Color("519655")


class CuePreview:
	extends Control

	var art: Texture2D
	var finish: Dictionary = {}
	var model_id = "house"

	func update_cue(texture: Texture2D, entry: Dictionary, model: String) -> void:
		if art == texture and finish == entry and model_id == model:
			return
		art = texture
		finish = entry
		model_id = model
		queue_redraw()

	func _draw() -> void:
		var tint: Color = finish.get("modulate", Color.WHITE)
		if art != null:
			# The full stick establishes its silhouette; a second, magnified crop
			# makes its wrap/inlays readable at native counter scale. Both draw the
			# same cached texture, with no image allocation or resource work.
			var detail_space = Rect2(6, 0, maxf(1.0, size.x - 12), size.y * 0.64)
			var grip = Rect2(art.get_width() * 0.58, 0, art.get_width() * 0.42, art.get_height())
			var detail = _fit_rect(grip.size, detail_space)
			draw_texture_rect_region(art, detail, grip, tint)
			var rule_y = size.y * 0.72
			draw_line(
				Vector2(8, rule_y), Vector2(size.x - 8, rule_y), Color(0.93, 0.78, 0.49, 0.16)
			)
			var full_space = Rect2(2, size.y * 0.78, maxf(1.0, size.x - 4), size.y * 0.22)
			draw_texture_rect(art, _fit_rect(art.get_size(), full_space), false, tint)
			return
		# Readable fallback if optional loose-file artwork is absent.
		var left = Vector2(12, size.y * 0.5)
		var right = Vector2(size.x - 12, left.y)
		var joint = left.lerp(right, 0.4)
		var shaft: Color = finish.get("shaft", Color("c4a574"))
		var butt: Color = finish.get("butt", Color("5a3c28"))
		draw_line(left, right, Color("281d18"), 12, true)
		draw_line(left, joint, butt, 9, true)
		draw_line(joint, right, shaft, 6, true)
		draw_line(joint - Vector2(3, 0), joint + Vector2(3, 0), Color("e9d9b8"), 10)
		draw_line(right - Vector2(4, 0), right, Color("75bdce"), 7)
		if model_id != "house":
			var accent = Color("75bdce") if model_id == "finesse" else Color("db9d50")
			for point in [0.1, 0.18, 0.26]:
				var center = left.lerp(right, point)
				draw_line(center - Vector2(2, 0), center + Vector2(2, 0), accent, 9)

	func _fit_rect(source_size: Vector2, space: Rect2) -> Rect2:
		var factor = minf(space.size.x / source_size.x, space.size.y / source_size.y)
		var target_size = source_size * factor
		return Rect2(space.position + (space.size - target_size) * 0.5, target_size)


var _built = false
var _skin: RefCounted
var _textures: Dictionary = {}
var _styles: Dictionary = {}
var _cards: Dictionary = {}
var _swatches: Dictionary = {}
var _entries: Array = []
var _root: Control
var _title: Label
var _description: Label
var _wallet: Label
var _finish_label: Label
var _status: Label
var _action: Button
var _back: Button
var _previous_page: Button
var _next_page: Button
var _page_label: Label
var _page = 0
var _active = false
var _signature: Array = []
var _selected_model = "house"
var _selected_finish = "native"
var _player: Dictionary = {}
var _money = 0.0
var _pending = false
var _blocked = false
var _error = ""
var _has_rendered = false


func setup(skin: RefCounted) -> void:
	if _built:
		return
	_skin = skin
	_entries = CueModels.entries()
	_cache_art()
	_build()
	_built = true
	_update_focus_access()
	set_process(false)
	set_process_unhandled_input(false)


func _cache_art() -> void:
	# Shared with table cues: decoded and alpha-trimmed once at controller startup.
	# Reopening the native shop never decodes the fifteen cue sprites again.
	for entry in _entries:
		var art: Texture2D = CueVisuals.texture(str(entry.id))
		if art != null:
			_textures[str(entry.asset)] = art


func _build() -> void:
	_root = Control.new()
	_root.name = "CounterControls"
	_root.position = Vector2(-210, 8)
	_root.size = Vector2(1020, 480)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _theme()
	add_child(_root)

	var sign = PanelContainer.new()
	sign.position = Vector2(340, 0)
	sign.size = Vector2(340, 58)
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sign_style = _skin.style("header_plank", [18, 5, 18, 5]) if _skin != null else null
	sign.add_theme_stylebox_override("panel", sign_style if sign_style != null else _wood_style())
	_root.add_child(sign)
	var heading = _label("CUE WORKSHOP", 30, Color("fff3d4"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_outline_color", INK)
	heading.add_theme_constant_override("outline_size", 4)
	sign.add_child(heading)
	_previous_page = _button("‹", PURPLE)
	_previous_page.name = "PreviousCues"
	_previous_page.tooltip_text = "Previous cue rack"
	_previous_page.position = Vector2(48, 8)
	_previous_page.size = Vector2(60, 46)
	_previous_page.pressed.connect(_change_page.bind(-1))
	_root.add_child(_previous_page)
	_page_label = _label("Rack 1 / 1", 21, Color("fff1d2"))
	_page_label.position = Vector2(116, 8)
	_page_label.size = Vector2(126, 46)
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.add_theme_color_override("font_outline_color", INK)
	_page_label.add_theme_constant_override("outline_size", 4)
	_root.add_child(_page_label)
	_next_page = _button("›", PURPLE)
	_next_page.name = "NextCues"
	_next_page.tooltip_text = "Next cue rack"
	_next_page.position = Vector2(250, 8)
	_next_page.size = Vector2(60, 46)
	_next_page.pressed.connect(_change_page.bind(1))
	_root.add_child(_next_page)

	var cards = HBoxContainer.new()
	cards.name = "Models"
	cards.position = Vector2(48, 66)
	cards.size = Vector2(924, 144)
	cards.add_theme_constant_override("separation", 12)
	_root.add_child(cards)
	for entry in _entries:
		_build_card(cards, entry)
	_update_page()

	var paper = PanelContainer.new()
	paper.name = "SelectionDetails"
	paper.position = Vector2(48, 216)
	paper.size = Vector2(924, 190)
	paper.add_theme_stylebox_override("panel", _paper_style())
	_root.add_child(paper)
	var details = VBoxContainer.new()
	details.add_theme_constant_override("separation", 3)
	paper.add_child(details)
	var headline = HBoxContainer.new()
	details.add_child(headline)
	_title = _label("House cue", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.add_child(_title)
	_wallet = _label("Shared money: 0€", 21)
	headline.add_child(_wallet)
	_description = _label("", 18)
	_description.custom_minimum_size = Vector2(0, 64)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_description)
	var finish_row = HBoxContainer.new()
	finish_row.add_theme_constant_override("separation", 7)
	details.add_child(finish_row)
	_finish_label = _label("Finish: Native", 18)
	_finish_label.custom_minimum_size = Vector2(184, 42)
	_finish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	finish_row.add_child(_finish_label)
	for entry in CueCatalog.entries():
		var swatch = Button.new()
		swatch.name = "Finish_" + str(entry.id)
		swatch.custom_minimum_size = Vector2(58, 42)
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch.toggle_mode = true
		swatch.tooltip_text = str(entry.label) + " finish · free cosmetic recolor"
		swatch.add_theme_stylebox_override("normal", _swatch_style(entry.shaft, false))
		swatch.add_theme_stylebox_override(
			"hover", _swatch_style(entry.shaft.lightened(0.15), false)
		)
		swatch.add_theme_stylebox_override("pressed", _swatch_style(entry.shaft, true))
		swatch.pressed.connect(_select_finish.bind(str(entry.id)))
		finish_row.add_child(swatch)
		_swatches[entry.id] = swatch
	var note = _label(
		"Personal cues last this run. Finishes are free. Purchases use shared money.", 16
	)
	note.add_theme_color_override("font_color", Color("70553d"))
	details.add_child(note)

	_back = _button("‹  Snacks", PURPLE)
	_back.name = "BackToSnacks"
	_back.position = Vector2(48, 414)
	_back.size = Vector2(182, 58)
	_back.pressed.connect(func(): close_requested.emit())
	_root.add_child(_back)
	_status = _label("", 17, Color("fff4d8"))
	_status.position = Vector2(246, 412)
	_status.size = Vector2(420, 64)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_outline_color", INK)
	_status.add_theme_constant_override("outline_size", 4)
	_root.add_child(_status)
	_action = _button("Equipped", GREEN)
	_action.name = "CueAction"
	_action.position = Vector2(686, 414)
	_action.size = Vector2(286, 58)
	_action.pressed.connect(_submit)
	_root.add_child(_action)
	_link_focus()


func _build_card(parent: HBoxContainer, entry: Dictionary) -> void:
	var card = Button.new()
	card.name = "Model_" + str(entry.id)
	card.custom_minimum_size = Vector2(300, 144)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.toggle_mode = true
	card.tooltip_text = str(entry.label) + ": " + str(entry.description)
	card.add_theme_stylebox_override("normal", _card_style(false))
	card.add_theme_stylebox_override("hover", _card_style(true))
	card.add_theme_stylebox_override("pressed", _card_style(true))
	card.pressed.connect(_select_model.bind(str(entry.id)))
	parent.add_child(card)
	var content = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 14
	content.offset_right = -14
	content.offset_top = 10
	content.offset_bottom = -10
	content.add_theme_constant_override("separation", 2)
	var label = _label(str(entry.label).to_upper(), 23, Color("fff1d2"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(label)
	var preview = CuePreview.new()
	preview.name = "CueArt"
	preview.custom_minimum_size = Vector2(0, 58)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(preview)
	preview.resized.connect(preview.queue_redraw)
	var ownership = _label("", 18, GOLD)
	ownership.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(ownership)
	_cards[entry.id] = {"button": card, "preview": preview, "ownership": ownership, "entry": entry}


func render(
	data: Dictionary, local_id: int, pending: bool, blocked: bool, error: String = ""
) -> void:
	if not _built:
		return
	var player: Dictionary = {
		"id": local_id, "owned": ["house"], "equipped": "house", "finish": "native"
	}
	for row in data.get("cues", {}).get("players", []):
		if int(row.get("id", 0)) == local_id:
			player = row
			break
	var signature = [player, data.get("money", 0), pending, blocked, error]
	if signature == _signature:
		return
	_signature = signature.duplicate(true)
	var identity_changed: bool = int(_player.get("id", 0)) != local_id
	_player = player.duplicate(true)
	_money = float(data.get("money", 0))
	_pending = pending
	_blocked = blocked
	_error = error
	if not _has_rendered or identity_changed:
		_selected_model = str(player.get("equipped", "house"))
		_selected_finish = str(player.get("finish", "native"))
		_page = maxi(0, _entries.map(func(entry): return entry.id).find(_selected_model)) / 3
		_update_page()
		_link_focus()
		_has_rendered = true
	_refresh()


func _refresh() -> void:
	var finish = CueCatalog.style(_selected_finish)
	for id in _cards:
		var card: Dictionary = _cards[id]
		if card.button.button_pressed != (id == _selected_model):
			card.button.set_pressed_no_signal(id == _selected_model)
		var entry: Dictionary = card.entry
		var filename = str(entry.get("asset", str(id) + ".png"))
		card.preview.update_cue(_textures.get(filename), finish, id)
		var owned: bool = id in _player.get("owned", ["house"])
		var label = "Equipped" if id == _player.get("equipped", "house") else "Owned · equip free"
		if not owned:
			label = "%d€ · for this run" % int(entry.price)
		_set_text(card.ownership, label)
	for id in _swatches:
		if _swatches[id].button_pressed != (id == _selected_finish):
			_swatches[id].set_pressed_no_signal(id == _selected_finish)
		_set_text(_swatches[id], "✓" if id == _selected_finish else "")
	var selected: Dictionary = _cards.get(_selected_model, _cards.house).entry
	_set_text(_title, "%s cue" % selected.label)
	_set_text(_description, str(selected.description))
	if _description.tooltip_text != str(selected.description):
		_description.tooltip_text = str(selected.description)
	_set_text(_wallet, "Shared money: %s€" % str(snappedf(_money, 0.01)))
	_set_text(_finish_label, "Finish: " + str(finish.label))
	var owned: bool = _selected_model in _player.get("owned", ["house"])
	var equipped: bool = _selected_model == _player.get("equipped", "house")
	var same_finish: bool = _selected_finish == _player.get("finish", "native")
	var action_text = "Buy & equip · %d€" % int(selected.price)
	if owned:
		action_text = "Equip cue · free"
	if equipped:
		action_text = "Equipped" if same_finish else "Apply finish · free"
	if _pending:
		action_text = "Waiting for table…"
	_set_text(_action, action_text)
	var action_disabled: bool = (
		_pending
		or _blocked
		or (equipped and same_finish)
		or (not owned and _money < float(selected.price))
	)
	if _action.disabled != action_disabled:
		_action.disabled = action_disabled
	var status = "Pick a cue, try a finish, then equip."
	if _error != "":
		status = _error
	elif _pending:
		status = "Confirming your choice. You can keep browsing."
	elif _blocked:
		status = "Browsing only while the table finishes its action."
	elif not owned and _money < float(selected.price):
		status = "The table needs %d€ to buy this cue." % int(selected.price)
	elif equipped and same_finish:
		status = "Your equipped cue. Ready for the next round."
	_set_text(_status, status)


func _select_model(id: String) -> void:
	_selected_model = id
	_refresh()
	_play_button_sound()


func _select_finish(id: String) -> void:
	_selected_finish = id
	_refresh()
	_play_button_sound()


func _submit() -> void:
	if _action.disabled:
		return
	var action = "cue_buy"
	if _selected_model in _player.get("owned", ["house"]):
		action = "cue_equip"
	if _selected_model == _player.get("equipped", "house"):
		action = "cue_finish"
	action_requested.emit(action, _selected_model, _selected_finish)


func focus_default() -> void:
	if _built and is_visible_in_tree():
		_cards.get(_selected_model, _cards.house).button.grab_focus()


func set_active(active: bool) -> void:
	# The rack stays visible in the scrolling world; keyboard input belongs only
	# to the currently visited counter, never merely to an offscreen visible node.
	if _active == active:
		return
	_active = active
	set_process_unhandled_input(active)
	_update_focus_access()
	if active:
		focus_default()
	elif _built:
		var focused = get_viewport().gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused):
			focused.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _active and is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func _link_focus() -> void:
	var models: Array = []
	for card in _cards.values():
		if card.button.visible:
			models.append(card.button)
	var finishes: Array = _swatches.values()
	var controls: Array = [_previous_page, _next_page] + models + finishes + [_back, _action]
	for index in controls.size():
		var button: Control = controls[index]
		button.focus_next = button.get_path_to(controls[(index + 1) % controls.size()])
		button.focus_previous = button.get_path_to(controls[posmod(index - 1, controls.size())])
	for index in models.size():
		models[index].focus_neighbor_bottom = models[index].get_path_to(finishes[index * 3])
	for index in finishes.size():
		finishes[index].focus_neighbor_top = finishes[index].get_path_to(
			models[mini(index / 3, models.size() - 1)]
		)
		finishes[index].focus_neighbor_bottom = finishes[index].get_path_to(
			_back if index < 5 else _action
		)


func _change_page(direction: int) -> void:
	_page = posmod(_page + direction, maxi(1, ceili(float(_entries.size()) / 3.0)))
	_selected_model = str(_entries[_page * 3].id)
	_update_page()
	_link_focus()
	_refresh()


func _update_page() -> void:
	var pages = maxi(1, ceili(float(_entries.size()) / 3.0))
	for index in _entries.size():
		var card: Button = _cards[_entries[index].id].button
		var shown: bool = index / 3 == _page
		if card.visible != shown:
			card.visible = shown
	_set_text(_page_label, "Rack %d / %d" % [_page + 1, pages])
	_previous_page.disabled = pages <= 1
	_next_page.disabled = pages <= 1


func _update_focus_access() -> void:
	if not _built:
		return
	var controls: Array = _cards.values().map(func(card): return card.button)
	controls.append_array(_swatches.values())
	controls.append_array([_previous_page, _next_page, _back, _action])
	for control in controls:
		control.focus_mode = Control.FOCUS_ALL if _active else Control.FOCUS_NONE
		control.mouse_filter = Control.MOUSE_FILTER_STOP if _active else Control.MOUSE_FILTER_IGNORE


func _play_button_sound() -> void:
	var audio = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play"):
		audio.play("button_pos")


func _theme() -> Theme:
	var result = Theme.new()
	var ui = get_node_or_null("/root/UIManager")
	if ui != null:
		result.default_font = ui.FONT_LATIN
	result.default_font_size = 20
	result.set_color("font_color", "Label", INK)
	result.set_stylebox("focus", "Button", _focus_style())
	return result


func _label(text: String, font_size: int, color: Color = INK) -> Label:
	var label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, color: Color) -> Button:
	var button = Button.new()
	button.text = text
	button.pressed.connect(_play_button_sound)
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("d6cab6"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill = color
		if state == "hover":
			fill = color.lightened(0.16)
		elif state == "pressed":
			fill = color.darkened(0.12)
		elif state == "disabled":
			fill = color.lerp(Color("746d61"), 0.65)
		var style = _flat(fill, Color("2a1c18"), 3, 8)
		style.shadow_color = Color(0, 0, 0, 0.65)
		style.shadow_size = 2
		style.shadow_offset = Vector2(0, 4 if state != "pressed" else 1)
		button.add_theme_stylebox_override(state, style)
	return button


func _set_text(control, value: String) -> void:
	if control.text != value:
		control.text = value


func _flat(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _paper_style() -> StyleBox:
	if not _styles.has("paper"):
		var style = _flat(PAPER, Color("744b32"), 3, 8)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		style.shadow_size = 3
		style.shadow_color = Color(0, 0, 0, 0.35)
		style.shadow_offset = Vector2(0, 3)
		_styles.paper = style
	return _styles.paper


func _wood_style() -> StyleBox:
	if not _styles.has("wood"):
		_styles.wood = _flat(WOOD, INK, 3, 7)
	return _styles.wood


func _card_style(selected: bool) -> StyleBox:
	var key = "card_selected" if selected else "card"
	if not _styles.has(key):
		var fill = Color("644630") if selected else Color("453529")
		_styles[key] = _flat(fill, GOLD if selected else Color("9a7350"), 3, 7)
	return _styles[key]


func _swatch_style(color: Color, selected: bool) -> StyleBox:
	return _flat(color, INK if selected else Color("ae9370"), 4 if selected else 2, 5)


func _focus_style() -> StyleBox:
	var style = _flat(Color.TRANSPARENT, Color("fff3a3"), 3, 6)
	style.draw_center = false
	style.expand_margin_left = 3
	style.expand_margin_top = 3
	style.expand_margin_right = 3
	style.expand_margin_bottom = 3
	return style

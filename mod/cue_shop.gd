extends Node2D

## Fourth retained counter beside TapasBar; shop_sync owns transactions.
## PERF-026/034/036: lifecycle artwork cache, local previews, authoritative case.
## One bounded rack tween is killed and retargeted; no queued transitions.

signal action_requested(action: String, model_id: String, finish_id: String)
signal close_requested

const CueCatalog = preload("cue_catalog.gd")
const CueModels = preload("cue_models.gd")
const CueVisuals = preload("cue_visuals.gd")
const CueShopArt = preload("cue_shop_art.gd")
const CueSeller = preload("cue_seller.gd")
const INK = Color("39291f")
const PAPER = Color("f4e7cb")
const WOOD = Color("844b2d")
const GOLD = Color("edc86b")
const PURPLE = Color(0.27450982, 0, 0.5647059, 1)
const CARD_SIZE = Vector2(171, 344)
const CARD_STEP = 182.0


class CuePreview:
	extends Control

	var art: Texture2D
	var texture: Texture2D:
		get:
			return art
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
			# Cached source runs tip-to-butt from left to right. Keep the entire
			# silhouette, rotated upright without cropping or stretching.
			var factor = minf((size.y - 12.0) / art.get_width(), (size.x - 20.0) / art.get_height())
			var extent = art.get_size() * maxf(0.01, factor)
			draw_set_transform(Vector2(size.x * 0.5, (size.y - extent.x) * 0.5), PI * 0.5)
			draw_texture_rect(art, Rect2(Vector2(0, -extent.y * 0.5), extent), false, tint)
			draw_set_transform(Vector2.ZERO)
			return
		var top = Vector2(size.x * 0.5, 8)
		var bottom = Vector2(top.x, size.y - 8)
		var joint = top.lerp(bottom, 0.6)
		draw_line(top, bottom, Color("281d18"), 13, true)
		draw_line(top, joint, finish.get("shaft", Color("c4a574")), 7, true)
		draw_line(joint, bottom, finish.get("butt", Color("5a3c28")), 10, true)
		draw_line(joint - Vector2(0, 3), joint + Vector2(0, 3), Color("e9d9b8"), 11)
		draw_line(top, top + Vector2(0, 4), finish.get("tip", Color("75bdce")), 8)


class RackTrim:
	extends Control

	func _draw() -> void:
		var trim = Color("b88c4b")
		var corners = [
			Vector2(8, 8), Vector2(size.x - 8, 8), Vector2(8, size.y - 8), size - Vector2(8, 8)
		]
		for corner in corners:
			var inward = Vector2(
				1 if corner.x < size.x * 0.5 else -1, 1 if corner.y < size.y * 0.5 else -1
			)
			draw_line(corner, corner + Vector2(inward.x * 12, 0), trim, 2)
			draw_line(corner, corner + Vector2(0, inward.y * 12), trim, 2)
			draw_circle(corner + inward * 3, 1.5, trim)


var _built = false
var _skin: RefCounted
var _textures: Dictionary = {}
var _styles: Dictionary = {}
var _cards: Dictionary = {}
var _swatches: Dictionary = {}
var _entries: Array = []
var _root: Control
var _seller: Node2D
var _rack: Control
var _title: Label
var _description: Label
var _finish_label: Label
var _status: Label
var _action: Button
var _back: Button
var _previous_page: Button
var _next_page: Button
var _page_label: Label
var _equipped_case: Control
var _equipped_preview: CuePreview
var _equipped_label: Label
var _equipped_signature: Array = []
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
var _rack_tween: Tween
var _rack_transitioning = false
var _rack_generation = 0
var _restore_card_focus = false
var _layout_size = Vector2.ZERO


func setup(skin: RefCounted) -> void:
	if _built:
		return
	_skin = skin
	_entries = CueModels.entries()
	_cache_art()
	_build()
	_built = true
	fit_to_viewport(get_viewport_rect().size)
	_update_focus_access()
	set_process(false)
	set_process_unhandled_input(false)


## PERF-026: resize only retained presentation, leaving native inventory untouched.
func fit_to_viewport(viewport_size: Vector2) -> void:
	if not _built or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	if viewport_size == _layout_size:
		return
	_layout_size = viewport_size
	# Match the installed camera's landscape/portrait world-size policy.
	var portrait = viewport_size.x < viewport_size.y
	var target = Vector2(645, 1330) if portrait else Vector2(1145, 930)
	var native_zoom = minf(viewport_size.x / target.x, viewport_size.y / target.y)
	var visible_width = viewport_size.x / native_zoom
	var factor = minf(1.0, (visible_width - 32.0) / 1485.0)
	var offset = Vector2.ZERO
	if factor < 1.0:
		# Content spans x=-415..1070; center it on native CameraTarget.x=300.
		# Scale about the counter edge so Rook's base remains at y=414.
		offset = Vector2(300.0 - 327.5 * factor, 414.0 * (1.0 - factor))
	_root.scale = Vector2.ONE * factor
	_root.position = offset
	_seller.scale = Vector2.ONE * factor
	_seller.position = Vector2(-30, 5) * factor + offset
	# Portrait has no lateral inventory margin. Keep the case above y=510
	# before the shared fit, clear of the native lower inventory surface.
	_equipped_case.scale = Vector2.ONE * (0.45 if portrait else 1.0)


func _cache_art() -> void:
	CueShopArt.warm(get_script().resource_path.get_base_dir().path_join("assets/cues/shop"))
	for entry in _entries:
		var art: Texture2D = CueVisuals.texture(str(entry.id))
		if art != null:
			_textures[str(entry.asset)] = art
	for name in ["arrow", "arrow_right"]:
		var path = "res://ui/%s.png" % name
		if _skin != null:
			_textures[name] = _skin.native_texture(path)
		else:
			_textures[name] = load(path) if ResourceLoader.exists(path) else null


func _build() -> void:
	_seller = CueSeller.new()
	_seller.name = "Rook"
	_seller.position = Vector2(-30, 5)
	_seller.z_index = -6
	add_child(_seller)
	_seller.setup(_skin)
	_seller.set_active(false)
	_root = Control.new()
	_root.name = "CounterControls"
	_root.size = Vector2(1080, 825)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _theme()
	add_child(_root)
	_build_header()
	var clip = Control.new()
	clip.name = "RackWindow"
	clip.position = Vector2(300, 70)
	clip.size = Vector2(535, 344)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(clip)
	_rack = Control.new()
	_rack.name = "RetainedRack"
	_rack.size = clip.size
	_rack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_rack)
	for index in _entries.size():
		_build_card(_rack, _entries[index], index % 3)
	_build_details()
	_build_finishes()
	_build_equipped_case()
	_update_page()


func _build_header() -> void:
	var sign = PanelContainer.new()
	sign.position = Vector2(300, 0)
	sign.size = Vector2(260, 60)
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = _skin.style("header_plank", [18, 5, 18, 5]) if _skin != null else null
	sign.add_theme_stylebox_override("panel", style if style != null else _wood_style())
	_root.add_child(sign)
	var heading = _label("CUES", 32, Color("fff3d4"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(heading)
	sign.add_child(heading)
	_previous_page = _arrow_button(false, "Previous cue rack")
	_previous_page.name = "PreviousCues"
	_previous_page.position = Vector2(584, 4)
	_previous_page.size = Vector2(52, 52)
	_previous_page.pressed.connect(_change_page.bind(-1))
	_root.add_child(_previous_page)
	_page_label = _label("1 / 5", 27, Color("fff1d2"))
	_page_label.position = Vector2(644, 4)
	_page_label.size = Vector2(128, 52)
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(_page_label)
	_root.add_child(_page_label)
	_next_page = _arrow_button(true, "Next cue rack")
	_next_page.name = "NextCues"
	_next_page.position = Vector2(780, 4)
	_next_page.size = Vector2(52, 52)
	_next_page.pressed.connect(_change_page.bind(1))
	_root.add_child(_next_page)


func _build_card(parent: Control, entry: Dictionary, column: int) -> void:
	var card = Button.new()
	card.name = "Model_" + str(entry.id)
	card.position = Vector2(column * CARD_STEP, 0)
	card.size = CARD_SIZE
	card.toggle_mode = true
	card.tooltip_text = str(entry.label) + ": " + str(entry.description)
	card.add_theme_stylebox_override("normal", _card_style(false))
	card.add_theme_stylebox_override("hover", _card_style(true))
	card.add_theme_stylebox_override("pressed", _card_style(true))
	card.add_theme_stylebox_override("disabled", _card_style(false))
	card.pressed.connect(_select_model.bind(str(entry.id)))
	parent.add_child(card)
	var trim = RackTrim.new()
	trim.size = CARD_SIZE
	trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(trim)
	var preview = CuePreview.new()
	preview.name = "CueArt"
	preview.position = Vector2(16, 15)
	preview.size = Vector2(139, 244)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(preview)
	var tag = Panel.new()
	tag.position = Vector2(11, 270)
	tag.size = Vector2(149, 62)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_stylebox_override("panel", _paper_style())
	card.add_child(tag)
	var label = _label(str(entry.label).to_upper(), 20)
	label.position = Vector2(4, 5)
	label.size = Vector2(141, 26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_child(label)
	var ownership = _label("", 19)
	ownership.position = Vector2(4, 31)
	ownership.size = Vector2(141, 24)
	ownership.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_child(ownership)
	_cards[entry.id] = {"button": card, "preview": preview, "ownership": ownership, "entry": entry}


func _build_details() -> void:
	var paper = Panel.new()
	paper.name = "SelectionDetails"
	paper.position = Vector2(-415, 160)
	paper.size = Vector2(300, 222)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_theme_stylebox_override("panel", _paper_style())
	_root.add_child(paper)
	_title = _label("House", 27)
	_title.position = Vector2(18, 10)
	_title.size = Vector2(264, 36)
	paper.add_child(_title)
	_description = _label("", 17)
	_description.position = Vector2(18, 50)
	_description.size = Vector2(264, 124)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paper.add_child(_description)
	_action = _button("Equipped", Color("bb804d"))
	_action.name = "CueAction"
	_action.position = Vector2(18, 179)
	_action.size = Vector2(264, 36)
	_action.add_theme_font_size_override("font_size", 21)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_action.add_theme_color_override(state, INK)
	_action.tooltip_text = "Buy and equip using the table's money. Cues last for this run; switching owned cues and finishes is free."
	_action.pressed.connect(_submit)
	paper.add_child(_action)
	_status = _label("", 17, Color("fff4d8"))
	_status.position = Vector2(-405, 397)
	_status.size = Vector2(284, 46)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outline(_status)
	_root.add_child(_status)


func _build_finishes() -> void:
	_back = _arrow_button(false, "Back to the snack counter")
	_back.name = "BackToSnacks"
	_back.position = Vector2(-78, 437)
	_back.size = Vector2(56, 56)
	_back.pressed.connect(_close)
	_root.add_child(_back)
	_finish_label = _label("Finish: Native", 19, Color("fff1d2"))
	_finish_label.position = Vector2(22, 422)
	_finish_label.size = Vector2(520, 25)
	_outline(_finish_label)
	_root.add_child(_finish_label)
	var index = 0
	for entry in CueCatalog.entries():
		var swatch = Button.new()
		swatch.name = "Finish_" + str(entry.id)
		swatch.position = Vector2(22 + index * 51, 452)
		swatch.size = Vector2(44, 42)
		swatch.toggle_mode = true
		swatch.tooltip_text = str(entry.label) + " finish · free cosmetic recolor"
		swatch.add_theme_stylebox_override("normal", _swatch_style(entry.shaft, false))
		swatch.add_theme_stylebox_override(
			"hover", _swatch_style(entry.shaft.lightened(0.15), false)
		)
		swatch.add_theme_stylebox_override("pressed", _swatch_style(entry.shaft, true))
		swatch.pressed.connect(_select_finish.bind(str(entry.id)))
		_root.add_child(swatch)
		_swatches[entry.id] = swatch
		index += 1


func _build_equipped_case() -> void:
	_equipped_case = Control.new()
	_equipped_case.name = "ConfirmedCueCase"
	_equipped_case.position = Vector2(850, 255)
	_equipped_case.size = Vector2(210, 565)
	_equipped_case.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equipped_case.visible = false
	_root.add_child(_equipped_case)
	var art: Texture2D = CueShopArt.texture("cue_equipped_case")
	var fitted = Rect2(28, 30, 154, 500)
	var cue_center = 105.0
	if art != null:
		var factor = minf(210.0 / art.get_width(), 500.0 / art.get_height())
		var extent = art.get_size() * factor
		fitted = Rect2(Vector2((210.0 - extent.x) * 0.5, 30), extent)
		# The opened lid occupies the left of the artwork; the felt channel
		# is at 65% of the fitted silhouette, not the center of this panel.
		cue_center = fitted.position.x + fitted.size.x * 0.65
		var background = TextureRect.new()
		background.name = "CueCaseArt"
		# Suppress the texture's native minimum before assigning it. Otherwise
		# the control retains the source PNG's size despite the fitted rectangle.
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.texture = art
		background.position = fitted.position
		background.size = fitted.size
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_equipped_case.add_child(background)
	else:
		var background = Panel.new()
		background.position = fitted.position
		background.size = fitted.size
		background.add_theme_stylebox_override("panel", _card_style(false))
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_equipped_case.add_child(background)
	var heading = _label("EQUIPPED", 18, Color("fff1d2"))
	heading.size = Vector2(210, 25)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(heading)
	_equipped_case.add_child(heading)
	_equipped_preview = CuePreview.new()
	_equipped_preview.name = "ConfirmedCue"
	_equipped_preview.position = Vector2(cue_center - 36, fitted.position.y + fitted.size.y * 0.09)
	_equipped_preview.size = Vector2(72, fitted.size.y * 0.83)
	_equipped_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equipped_case.add_child(_equipped_preview)
	_equipped_label = _label("House · Native", 17, Color("fff1d2"))
	_equipped_label.position = Vector2(-10, 532)
	_equipped_label.size = Vector2(230, 30)
	_equipped_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(_equipped_label)
	_equipped_case.add_child(_equipped_label)


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
	var equipment_changed: bool = (
		not identity_changed
		and _has_rendered
		and (
			_player.get("equipped", "house") != player.get("equipped", "house")
			or _player.get("finish", "native") != player.get("finish", "native")
		)
	)
	var rejected: bool = error != "" and error != _error
	_player = player.duplicate(true)
	_money = float(data.get("money", 0))
	_pending = pending
	_blocked = blocked
	_error = error
	if not _has_rendered or identity_changed:
		_cancel_rack_animation()
		_selected_model = str(player.get("equipped", "house"))
		_selected_finish = str(player.get("finish", "native"))
		_page = maxi(0, _entries.map(func(entry): return entry.id).find(_selected_model)) / 3
		_update_page()
		_has_rendered = true
	_refresh()
	_refresh_equipped_case()
	if _active and rejected:
		_seller.say("That didn't go through. Give it another try.")
	elif _active and equipment_changed:
		_seller.say("All yours. Make it count.")


func _refresh_equipped_case() -> void:
	var model = str(_player.get("equipped", "house"))
	var finish_id = str(_player.get("finish", "native"))
	var signature = [model, finish_id]
	if signature == _equipped_signature:
		return
	_equipped_signature = signature
	var entry: Dictionary = _cards.get(model, _cards.house).entry
	var finish = CueCatalog.style(finish_id)
	_equipped_preview.update_cue(_textures.get(str(entry.asset)), finish, model)
	_set_text(_equipped_label, "%s · %s" % [entry.label, finish.label])


## Exposes the rendered case, never the local selection, for inspection.
func confirmed_equipment() -> Dictionary:
	return {
		"model": _equipped_preview.model_id,
		"finish": str(_equipped_preview.finish.get("id", "native")),
		"texture": _equipped_preview.art,
		"tint": _equipped_preview.finish.get("modulate", Color.WHITE),
		"label": _equipped_label.text,
	}


func _refresh() -> void:
	var focused = get_viewport().gui_get_focus_owner()
	var finish = CueCatalog.style(_selected_finish)
	for id in _cards:
		var card: Dictionary = _cards[id]
		if card.button.button_pressed != (id == _selected_model):
			card.button.set_pressed_no_signal(id == _selected_model)
		card.preview.update_cue(_textures.get(str(card.entry.asset)), finish, id)
		var owned: bool = id in _player.get("owned", ["house"])
		var label = "Equipped" if id == _player.get("equipped", "house") else "Owned"
		if not owned:
			label = "%d€" % int(card.entry.price)
		_set_text(card.ownership, label)
	for id in _swatches:
		if _swatches[id].button_pressed != (id == _selected_finish):
			_swatches[id].set_pressed_no_signal(id == _selected_finish)
		_set_text(_swatches[id], "✓" if id == _selected_finish else "")
	var selected: Dictionary = _cards.get(_selected_model, _cards.house).entry
	_set_text(_title, str(selected.label))
	var description = str(selected.description)
	if float(selected.get("bonus_rate", 0.0)) > 0.0:
		description = description.replace(CueModels.BONUS_LIMITS, "").strip_edges()
		description += "\nFirst qualifying pot per shot.\nYour round limit: +4 across cues."
	_set_text(_description, description)
	if _description.tooltip_text != str(selected.description):
		_description.tooltip_text = str(selected.description)
	_set_text(_finish_label, "Finish: %s" % str(finish.label))
	var owned: bool = _selected_model in _player.get("owned", ["house"])
	var equipped: bool = _selected_model == _player.get("equipped", "house")
	var same_finish: bool = _selected_finish == _player.get("finish", "native")
	var action_text = "Buy · %d€" % int(selected.price)
	if owned:
		action_text = "Equip"
	if equipped:
		action_text = "Equipped" if same_finish else "Apply finish"
	if _pending:
		action_text = "Confirming…"
	_set_text(_action, action_text)
	_action.disabled = (
		_pending
		or _blocked
		or _rack_transitioning
		or (equipped and same_finish)
		or (not owned and _money < float(selected.price))
	)
	var status = ""
	if _error != "":
		status = _error
	elif not _pending:
		if _blocked:
			status = "Available when the table finishes."
		elif not owned and _money < float(selected.price):
			status = "Not enough money."
	_set_text(_status, status)
	_status.visible = not status.is_empty()
	_update_focus_access()
	_link_focus()
	if (
		_active
		and focused != null
		and is_ancestor_of(focused)
		and (focused.focus_mode == Control.FOCUS_NONE or not focused.is_visible_in_tree())
	):
		focus_default()


func _select_model(id: String) -> void:
	if _rack_transitioning or not _cards.has(id) or not _cards[id].button.visible:
		return
	_selected_model = id
	_refresh()
	_play_button_sound()


func _select_finish(id: String) -> void:
	_selected_finish = id
	_refresh()
	_play_button_sound()


func _submit() -> void:
	if not _active or _action.disabled or _rack_transitioning:
		return
	var action = "cue_buy"
	if _selected_model in _player.get("owned", ["house"]):
		action = "cue_equip"
	if _selected_model == _player.get("equipped", "house"):
		action = "cue_finish"
	action_requested.emit(action, _selected_model, _selected_finish)


func _close() -> void:
	settle_rack()
	close_requested.emit()


func focus_default() -> void:
	if _built and _active and is_visible_in_tree():
		if _rack_transitioning:
			_next_page.grab_focus()
		else:
			_cards.get(_selected_model, _cards[_entries[_page * 3].id]).button.grab_focus()


func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	set_process_unhandled_input(active)
	if not _built:
		return
	_seller.set_active(active)
	_equipped_case.visible = active
	if not active:
		_cancel_rack_animation()
		var focused = get_viewport().gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused):
			focused.release_focus()
	_update_focus_access()
	_link_focus()
	if active:
		_refresh()
		focus_default()


func _unhandled_input(event: InputEvent) -> void:
	if _active and is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _change_page(direction: int) -> void:
	if direction == 0 or not _built:
		return
	var focused = get_viewport().gui_get_focus_owner()
	var card_had_focus = _restore_card_focus
	for card in _cards.values():
		card_had_focus = card_had_focus or card.button == focused
	_cancel_rack_animation()
	_page = posmod(_page + direction, maxi(1, ceili(float(_entries.size()) / 3.0)))
	_selected_model = str(_entries[_page * 3].id)
	if not _active:
		_update_page()
		_refresh()
		return
	_restore_card_focus = card_had_focus
	_rack_transitioning = true
	_refresh()
	if card_had_focus:
		(_next_page if direction > 0 else _previous_page).grab_focus()
	var generation = _rack_generation
	_rack_tween = create_tween()
	(
		_rack_tween
		. tween_property(_rack, "position:x", -signi(direction) * 30.0, 0.10)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	_rack_tween.parallel().tween_property(_rack, "modulate:a", 0.0, 0.10)
	_rack_tween.tween_callback(_switch_rack_page.bind(direction, generation))
	(
		_rack_tween
		. tween_property(_rack, "position:x", 0.0, 0.18)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	_rack_tween.parallel().tween_property(_rack, "modulate:a", 1.0, 0.14)
	_rack_tween.finished.connect(_finish_rack_animation.bind(generation))


func _switch_rack_page(direction: int, generation: int) -> void:
	if generation != _rack_generation:
		return
	_update_page()
	_rack.position.x = signi(direction) * 38.0
	_rack.modulate.a = 0.0


func _finish_rack_animation(generation: int) -> void:
	if generation != _rack_generation:
		return
	_rack_tween = null
	_rack_transitioning = false
	_rack.position = Vector2.ZERO
	_rack.modulate = Color.WHITE
	_refresh()
	if _restore_card_focus and _active:
		focus_default()
	_restore_card_focus = false


func _cancel_rack_animation() -> void:
	_rack_generation += 1
	if _rack_tween != null and _rack_tween.is_valid():
		_rack_tween.kill()
	_rack_tween = null
	_rack_transitioning = false
	_restore_card_focus = false
	if _rack != null:
		_rack.position = Vector2.ZERO
		_rack.modulate = Color.WHITE
		_update_page()


## Snap to the latest requested rack; also used by lifecycle/fixture inspection.
func settle_rack() -> void:
	var restore_focus = _restore_card_focus
	_cancel_rack_animation()
	if _built:
		_refresh()
		if restore_focus and _active:
			focus_default()


func _exit_tree() -> void:
	# Descendants may already be leaving the tree. Cancel work without touching
	# their presentation or focus during teardown.
	_rack_generation += 1
	if _rack_tween != null and _rack_tween.is_valid():
		_rack_tween.kill()
	_rack_tween = null
	_rack_transitioning = false
	if is_instance_valid(_seller):
		_seller.set_active(false)


func _update_page() -> void:
	var pages = maxi(1, ceili(float(_entries.size()) / 3.0))
	for index in _entries.size():
		var card: Button = _cards[_entries[index].id].button
		var shown: bool = index / 3 == _page
		if card.visible != shown:
			card.visible = shown
	_set_text(_page_label, "%d / %d" % [_page + 1, pages])
	_previous_page.disabled = pages <= 1
	_next_page.disabled = pages <= 1
	_update_focus_access()


func _update_focus_access() -> void:
	if not _built:
		return
	for card in _cards.values():
		var enabled: bool = _active and card.button.visible and not _rack_transitioning
		card.button.disabled = not enabled
		_access(card.button, enabled)
	for control in _swatches.values() + [_previous_page, _next_page, _back, _action]:
		_access(control, _active and not control.disabled)


func _access(control: Control, enabled: bool) -> void:
	control.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	control.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _link_focus() -> void:
	if not _built or not _active:
		return
	var controls: Array = [_previous_page, _next_page]
	for card in _cards.values():
		if card.button.visible and not card.button.disabled:
			controls.append(card.button)
	controls.append_array(_swatches.values())
	if not _action.disabled:
		controls.append(_action)
	controls.append(_back)
	for index in controls.size():
		var button: Control = controls[index]
		var next: NodePath = button.get_path_to(controls[(index + 1) % controls.size()])
		var previous: NodePath = button.get_path_to(controls[posmod(index - 1, controls.size())])
		button.focus_next = next
		button.focus_previous = previous
		button.focus_neighbor_right = next
		button.focus_neighbor_left = previous
		button.focus_neighbor_bottom = next
		button.focus_neighbor_top = previous


func _arrow_button(right: bool, tooltip: String) -> Button:
	var button = _button("", PURPLE)
	button.icon = _textures.get("arrow_right" if right else "arrow")
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 26)
	button.tooltip_text = tooltip
	return button


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


func _outline(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 3)


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
		var style = _flat(fill, Color("2a1c18"), 3, 5)
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
		var style = _flat(PAPER, Color("744b32"), 3, 5)
		style.shadow_size = 3
		style.shadow_color = Color(0, 0, 0, 0.35)
		style.shadow_offset = Vector2(0, 3)
		_styles.paper = style
	return _styles.paper


func _wood_style() -> StyleBox:
	if not _styles.has("wood"):
		_styles.wood = _flat(WOOD, INK, 3, 5)
	return _styles.wood


func _card_style(selected: bool) -> StyleBox:
	var key = "card_selected" if selected else "card"
	if not _styles.has(key):
		var fill = Color("493725") if selected else Color("302921")
		_styles[key] = _flat(fill, GOLD if selected else Color("95633d"), 4 if selected else 3, 5)
	return _styles[key]


func _swatch_style(color: Color, selected: bool) -> StyleBox:
	return _flat(color, Color("fff0a3") if selected else INK, 3, 4)


func _focus_style() -> StyleBox:
	var style = _flat(Color.TRANSPARENT, Color("fff3a3"), 3, 5)
	style.draw_center = false
	style.expand_margin_left = 2
	style.expand_margin_top = 2
	style.expand_margin_right = 2
	style.expand_margin_bottom = 2
	return style

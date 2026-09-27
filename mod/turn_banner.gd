extends Control
## Host-authoritative turn owner banner for all clients (#30).
## Change-driven: only mutates nodes when owner/name/color/visibility inputs change.
## Cleared by the controller on disconnect, scene change, and rematch.
## Centered at top via CenterContainer — size flags are ignored on a plain Control parent.

const HudPrefs = preload("hud_prefs.gd")

var _panel: PanelContainer
var _label: Label
var _style: StyleBoxFlat
var _owner_id: int = 0
var _text: String = ""
var _color: Color = Color.TRANSPARENT
var _want_visible: bool = false
var _prefs_on: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_top = 56
	offset_bottom = 104
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	# CenterContainer fills the top strip so the banner sits top-center (#30).
	var center = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_panel)
	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_panel.add_child(margin)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	margin.add_child(_label)
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.08, 0.1, 0.12, 0.82)
	_style.border_color = Color(0.85, 0.85, 0.85, 0.9)
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(6)
	_style.content_margin_left = 4
	_style.content_margin_right = 4
	_style.content_margin_top = 2
	_style.content_margin_bottom = 2
	_panel.add_theme_stylebox_override("panel", _style)
	_panel.hide()
	_prefs_on = HudPrefs.turn_banner_enabled()


func clear() -> void:
	_owner_id = 0
	_text = ""
	_color = Color.TRANSPARENT
	_want_visible = false
	if is_instance_valid(_panel) and _panel.visible:
		_panel.hide()


func set_prefs_enabled(enabled: bool) -> void:
	var on: bool = bool(enabled)
	if _prefs_on == on:
		return
	_prefs_on = on
	_apply_visibility()


func present(owner_id: int, text: String, color: Color, show: bool) -> void:
	var next_show: bool = show and not text.is_empty()
	var color_changed: bool = (
		_color.r != color.r
		or _color.g != color.g
		or _color.b != color.b
		or _color.a != color.a
	)
	if (
		_owner_id == owner_id
		and _text == text
		and not color_changed
		and _want_visible == next_show
	):
		return
	_owner_id = owner_id
	_text = text
	_color = color
	_want_visible = next_show
	if _label.text != text:
		_label.text = text
	if color_changed:
		_style.border_color = Color(color.r, color.g, color.b, 0.95)
		_label.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 1.0))
	_apply_visibility()


func _apply_visibility() -> void:
	var visible_now: bool = _want_visible and _prefs_on
	if _panel.visible == visible_now:
		return
	_panel.visible = visible_now

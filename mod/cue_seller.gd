extends Node2D
## Rook follows native Npc/NpcBody presentation: blink, talk, idle bob, nudge.
## PERF-026/034: cached cels and retained controls; all motion stops offscreen.

const ShopArt = preload("cue_shop_art.gd")
const BODY_SIZE = Vector2(330, 409)
const INK = Color("39291f")
const GREETINGS = [
	"A little edge. All you.",
	"Good wood. A steady hand.",
	"Find one that feels like yours.",
]
const NUDGES = ["Careful. Fresh chalk.", "The cues are over there.", "Still got it."]

var _built = false
var _active = false
var _body: Sprite2D
var _body_origin = Vector2.ZERO
var _hit: Button
var _dialog: PanelContainer
var _words: RichTextLabel
var _nameplate: PanelContainer
var _speech_tween: Tween
var _rng = RandomNumberGenerator.new()
var _time = 0.0
var _blink_at = 4.0
var _blink_remaining = 0.0
var _talk_remaining = 0.0
var _dialog_remaining = 0.0
var _speech_tick = 0.0
var _nudge = 0.0
var _greeting = 0
var _nudge_line = 0


func setup(skin: RefCounted) -> void:
	if _built:
		return
	_built = true
	set_process(false)
	_rng.randomize()
	ShopArt.warm(get_script().resource_path.get_base_dir().path_join("assets/cues/shop"))
	var clip = Control.new()
	clip.name = "CounterOcclusion"
	clip.size = BODY_SIZE
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	_body = Sprite2D.new()
	_body.name = "RookCels"
	_body.texture = ShopArt.texture("rook_states")
	_body.centered = false
	_body.hframes = 2
	_body.vframes = 2
	if _body.texture != null:
		var bounds = ShopArt.rook_bounds()
		if bounds.size.x <= 0 or bounds.size.y <= 0:
			bounds = Rect2(Vector2.ZERO, _body.texture.get_size() / 2.0)
		var factor = minf(BODY_SIZE.x / bounds.size.x, BODY_SIZE.y / bounds.size.y)
		_body.scale = Vector2.ONE * factor
		_body_origin = Vector2(
			(BODY_SIZE.x - bounds.size.x * factor) * 0.5 - bounds.position.x * factor,
			BODY_SIZE.y - bounds.end.y * factor
		)
	_body.position = _body_origin
	clip.add_child(_body)
	_hit = Button.new()
	_hit.name = "NudgeRook"
	_hit.position = Vector2(45, 30)
	_hit.size = Vector2(250, 375)
	_hit.tooltip_text = "Rook · cue maker"
	_hit.flat = true
	_hit.focus_mode = Control.FOCUS_NONE
	_hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_hit.pressed.connect(nudge)
	clip.add_child(_hit)
	_build_dialog()
	_build_nameplate(skin)


func _build_dialog() -> void:
	_dialog = PanelContainer.new()
	_dialog.name = "RookDialogue"
	_dialog.position = Vector2(-350, 45)
	_dialog.custom_minimum_size = Vector2(300, 96)
	_dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper = StyleBoxFlat.new()
	paper.bg_color = Color("f2f0e7")
	paper.border_color = Color("c8c4b9")
	paper.set_border_width_all(2)
	paper.set_corner_radius_all(7)
	paper.content_margin_left = 14
	paper.content_margin_right = 14
	paper.content_margin_top = 12
	paper.content_margin_bottom = 12
	_dialog.add_theme_stylebox_override("panel", paper)
	add_child(_dialog)
	_words = RichTextLabel.new()
	_words.custom_minimum_size = Vector2(270, 68)
	_words.fit_content = true
	_words.scroll_active = false
	_words.bbcode_enabled = false
	_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_words.add_theme_color_override("default_color", INK)
	_words.add_theme_font_size_override("normal_font_size", 22)
	var ui = get_node_or_null("/root/UIManager") if is_inside_tree() else null
	if ui != null:
		_words.add_theme_font_override("normal_font", ui.FONT_LATIN)
	_dialog.add_child(_words)
	_dialog.hide()
	# Native speech boxes point toward their speaker. This small tail is retained
	# geometry, not an additional texture or per-frame draw operation.
	var tail = Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(299, 32), Vector2(312, 44), Vector2(299, 55)])
	tail.color = paper.bg_color
	_dialog.add_child(tail)


func _build_nameplate(skin: RefCounted) -> void:
	_nameplate = PanelContainer.new()
	_nameplate.name = "RookNameplate"
	_nameplate.position = Vector2(100, 384)
	_nameplate.size = Vector2(130, 34)
	_nameplate.z_index = 8
	_nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wood: StyleBox = skin.style("header_plank", [8, 2, 8, 2]) if skin != null else null
	if wood == null:
		var fallback = StyleBoxFlat.new()
		fallback.bg_color = Color("a56b3c")
		fallback.border_color = INK
		fallback.set_border_width_all(2)
		wood = fallback
	_nameplate.add_theme_stylebox_override("panel", wood)
	add_child(_nameplate)
	var label = Label.new()
	label.text = "ROOK"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", Color("fff0cc"))
	var ui = get_node_or_null("/root/UIManager") if is_inside_tree() else null
	if ui != null:
		label.add_theme_font_override("font", ui.FONT_LATIN)
	_nameplate.add_child(label)


func set_active(active: bool) -> void:
	if not _built or _active == active:
		return
	_active = active
	set_process(active)
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if active:
		say(GREETINGS[_greeting % GREETINGS.size()])
		_greeting = (_greeting + 1) % GREETINGS.size()
	else:
		_stop_speech()
		_nudge = 0.0
		_blink_remaining = 0.0
		_body.position = _body_origin
		_body.frame = 0


func say(text: String) -> void:
	if not _active or not _built or text.is_empty():
		return
	if _speech_tween != null:
		_speech_tween.kill()
	_words.text = text.left(180)
	_words.visible_ratio = 0.0
	_dialog.show()
	_talk_remaining = clampf(float(_words.text.length()) * 0.025, 0.3, 3.0)
	_dialog_remaining = _talk_remaining + 3.0
	_speech_tick = 0.0
	_speech_tween = create_tween()
	_speech_tween.tween_property(_words, "visible_ratio", 1.0, _talk_remaining)
	_nudge = 0.3
	_play("speech_popup")


func nudge() -> void:
	if not _active:
		return
	_nudge = 1.0
	_blink_remaining = 0.15
	say(NUDGES[_nudge_line % NUDGES.size()])
	_nudge_line = (_nudge_line + 1) % NUDGES.size()
	_nudge = 1.0
	var effects = get_node_or_null("/root/EffectManager")
	if effects != null and effects.has_method("spawn"):
		effects.spawn("nudge", get_global_mouse_position())


func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree():
		return
	_time = fmod(_time + delta * (1.7 if _talk_remaining > 0.0 else 1.0), TAU * 100.0)
	_nudge = move_toward(_nudge, 0.0, delta * 4.0)
	_body.position.y = _body_origin.y + sin(_time * 3.0) * 2.0 - sin(_nudge * PI) * 12.0
	_blink_at -= delta
	_blink_remaining = maxf(0.0, _blink_remaining - delta)
	if _blink_at <= 0.0:
		_blink_at = _rng.randf_range(3.0, 8.0)
		_blink_remaining = 0.15
	_talk_remaining = maxf(0.0, _talk_remaining - delta)
	var frame = (1 if _blink_remaining > 0.0 else 0) + (2 if _talk_remaining > 0.0 else 0)
	if _body.frame != frame:
		_body.frame = frame
	if _talk_remaining > 0.0:
		_speech_tick -= delta
		if _speech_tick <= 0.0:
			_speech_tick = 0.1
			_play("speech")
	if _dialog_remaining > 0.0:
		_dialog_remaining = maxf(0.0, _dialog_remaining - delta)
		if _dialog_remaining == 0.0:
			_dialog.hide()


func _stop_speech() -> void:
	if _speech_tween != null:
		_speech_tween.kill()
		_speech_tween = null
	_talk_remaining = 0.0
	_dialog_remaining = 0.0
	_dialog.hide()


func _play(sound: String) -> void:
	var audio = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play"):
		audio.play(sound)


func _exit_tree() -> void:
	if _built:
		_stop_speech()

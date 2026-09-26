extends RefCounted

# The mod runs from loose files, so Godot's import step never sees these images. They are
# decoded once when the controller builds its UI and shared afterwards: lobby renders rebuild
# table cards (PERF-026), and must reuse these textures and styles rather than touch the disk.
# A missing file leaves that piece null so callers keep their flat fallback styles.

const FILES = [
	"backdrop.jpg",
	"logo.png",
	"panel_chalk.png",
	"header_plank.png",
	"plaque_brass.png",
	"slot_chalk.png",
	"button_dark_normal.png",
	"button_dark_hover.png",
	"button_dark_pressed.png",
	"button_green_normal.png",
	"button_green_hover.png",
	"button_green_pressed.png",
	"field_text.png",
	"field_dropdown.png",
	"field_number.png",
	"hud_tag_orange.png",
	"hud_tag_blue.png",
	"hud_tag_purple.png",
	"ribbon_strip_orange.png",
	"chip_voter.png",
	"chip_voter_small.png",
	"marker_result_small.png",
	"chalk_check_small.png",
	"icon_copy.png",
	"icon_invite.png",
	"icon_close.png",
	"icon_leave.png",
	"icon_return.png",
	"icon_approve.png",
	"icon_deny.png",
	"icon_disconnected.png",
	"icon_finished.png",
	"icon_race.png",
	"icon_trophy.png"
]
# Texture-pixel 9-slice margins (left, top, right, bottom); they match the exported image scale.
const MARGINS = {
	"panel_chalk": [16, 16, 16, 16],
	"header_plank": [22, 14, 22, 14],
	"plaque_brass": [20, 13, 20, 13],
	"slot_chalk": [8, 8, 8, 8],
	"button_dark_normal": [16, 16, 16, 16],
	"button_dark_hover": [19, 19, 19, 19],
	"button_dark_pressed": [16, 16, 16, 16],
	"button_green_normal": [16, 16, 16, 16],
	"button_green_hover": [19, 19, 19, 19],
	"button_green_pressed": [16, 16, 16, 16],
	"field_text": [9, 9, 9, 9],
	"field_dropdown": [9, 9, 21, 9],
	"field_number": [10, 10, 27, 10],
	"hud_tag_orange": [21, 18, 24, 18],
	"hud_tag_blue": [21, 18, 24, 18],
	"hud_tag_purple": [21, 18, 24, 18],
	"ribbon_strip_orange": [30, 17, 30, 17]
}
# The hover art includes a glow outside the button body.
const HOVER_GLOW = [4, 4, 4, 3]
const DISABLED_TINT = Color(0.62, 0.62, 0.62, 0.85)

var _textures: Dictionary = {}
var _styles: Dictionary = {}
var _native: Dictionary = {}
var _blank: ImageTexture


func _init(directory: String) -> void:
	var missing: Array[String] = []
	for file in FILES:
		var path = directory.path_join(file)
		var image = Image.new()
		if not FileAccess.file_exists(path) or image.load(path) != OK:
			missing.append(file)
			continue
		_textures[file.get_basename()] = ImageTexture.create_from_image(image)
	if not missing.is_empty():
		push_warning("[Together] UI art missing, using flat styles for: " + ", ".join(missing))


func has_art() -> bool:
	return _textures.has("panel_chalk") and _textures.has("button_dark_normal")


func texture(name: String) -> Texture2D:
	return _textures.get(name)


func native_texture(path: String) -> Texture2D:
	if not _native.has(path):
		_native[path] = load(path) if ResourceLoader.exists(path) else null
	return _native[path]


func blank() -> Texture2D:
	if _blank == null:
		_blank = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	return _blank


# Returns a shared 9-slice style, or null when its art is unavailable.
func style(
	name: String, content: Array = [], tint: Color = Color.WHITE, glow: Array = []
) -> StyleBox:
	var key = "%s|%s|%s|%s" % [name, content, tint, glow]
	if _styles.has(key):
		return _styles[key]
	var art: Texture2D = texture(name)
	if art == null or not MARGINS.has(name):
		return null
	var margins: Array = MARGINS[name]
	var box = StyleBoxTexture.new()
	box.texture = art
	box.texture_margin_left = margins[0]
	box.texture_margin_top = margins[1]
	box.texture_margin_right = margins[2]
	box.texture_margin_bottom = margins[3]
	box.modulate_color = tint
	if content.size() == 4:
		box.content_margin_left = content[0]
		box.content_margin_top = content[1]
		box.content_margin_right = content[2]
		box.content_margin_bottom = content[3]
	if glow.size() == 4:
		box.expand_margin_left = glow[0]
		box.expand_margin_top = glow[1]
		box.expand_margin_right = glow[2]
		box.expand_margin_bottom = glow[3]
	_styles[key] = box
	return box


func disabled(name: String, content: Array = []) -> StyleBox:
	return style(name, content, DISABLED_TINT)


# Wood-and-chalk button states; variant is "dark" or "green".
func button_style(variant: String, state: String, content: Array) -> StyleBox:
	match state:
		"hover":
			return style("button_%s_hover" % variant, content, Color.WHITE, HOVER_GLOW)
		"pressed":
			return style("button_%s_pressed" % variant, content)
		"disabled":
			return disabled("button_%s_normal" % variant, content)
		_:
			return style("button_%s_normal" % variant, content)

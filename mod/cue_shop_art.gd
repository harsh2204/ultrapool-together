extends RefCounted
## PERF-026/034: two immutable shop textures, decoded once at construction.
## No frame, rack change, snapshot, or character animation touches the disk.

const FILES = {
	"rook_states": "rook_states.png",
	"cue_equipped_case": "cue_equipped_case.png",
}
# Atlas coordinates exclude the generator's imperceptible alpha fringe while
# leaving every visible outline intact. Source PNGs remain unmodified.
const ROOK_SHEET_SIZE = Vector2i(1086, 1448)
const ROOK_CEL_BOUNDS = Rect2(30, 120, 501, 552)
const CASE_IMAGE_SIZE = Vector2i(1024, 1536)
const CASE_REGION = Rect2i(234, 45, 522, 1404)
static var _warmed = false
static var _textures: Dictionary = {}
static var _rook_bounds = Rect2()


static func warm(directory: String) -> void:
	if _warmed:
		return
	_warmed = true
	for key in FILES:
		var path = directory.path_join(FILES[key])
		var art = Image.new()
		if FileAccess.file_exists(path) and art.load(path) == OK:
			if key == "rook_states":
				var cell = Rect2i(0, 0, art.get_width() / 2, art.get_height() / 2)
				_rook_bounds = (
					ROOK_CEL_BOUNDS
					if art.get_size() == ROOK_SHEET_SIZE
					else Rect2(art.get_region(cell).get_used_rect())
				)
			else:
				var used = CASE_REGION if art.get_size() == CASE_IMAGE_SIZE else art.get_used_rect()
				if used.size.x > 0 and used.size.y > 0:
					art = art.get_region(used)
			_textures[key] = ImageTexture.create_from_image(art)


static func texture(key: String) -> Texture2D:
	return _textures.get(key)


static func rook_bounds() -> Rect2:
	return _rook_bounds

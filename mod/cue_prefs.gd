extends RefCounted
## Local cue preference for Ultrapool Together.
## Uses the mod's isolated user:// folder (custom_user_dir_name=UltrapoolTogether).
## Disk I/O only on load and when the player changes selection — never in frame hot paths.

const PATH = "user://together_cue.cfg"
const SECTION = "cosmetics"
const KEY = "cue_id"

const CueCatalog = preload("cue_catalog.gd")

static var _loaded = false
static var _cue_id: String = CueCatalog.DEFAULT_ID


static func cue_id() -> String:
	if not _loaded:
		reload()
	return _cue_id


static func set_cue_id(value: String) -> String:
	var normalized: String = CueCatalog.normalize(value)
	if _loaded and _cue_id == normalized:
		return _cue_id
	_cue_id = normalized
	_loaded = true
	var cfg = ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(SECTION, KEY, normalized)
	cfg.save(PATH)
	return _cue_id


static func reload() -> String:
	var cfg = ConfigFile.new()
	var err = cfg.load(PATH)
	if err == OK:
		_cue_id = CueCatalog.normalize(str(cfg.get_value(SECTION, KEY, CueCatalog.DEFAULT_ID)))
	else:
		_cue_id = CueCatalog.DEFAULT_ID
	_loaded = true
	return _cue_id


static func reset_for_tests() -> void:
	_loaded = false
	_cue_id = CueCatalog.DEFAULT_ID

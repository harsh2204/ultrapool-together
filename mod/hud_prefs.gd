extends RefCounted
## Local HUD presentation prefs for Ultrapool Together.
## Disk I/O only on load and when the player changes a toggle — never in frame hot paths.

const PATH = "user://together_hud.cfg"
const SECTION = "hud"
const TURN_BANNER_KEY = "turn_banner"

static var _loaded = false
static var _turn_banner = true


static func turn_banner_enabled() -> bool:
	if not _loaded:
		reload()
	return _turn_banner


static func set_turn_banner_enabled(enabled: bool) -> bool:
	var value: bool = bool(enabled)
	if _loaded and _turn_banner == value:
		return _turn_banner
	_turn_banner = value
	_loaded = true
	var cfg = ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(SECTION, TURN_BANNER_KEY, value)
	cfg.save(PATH)
	return _turn_banner


static func reload() -> bool:
	var cfg = ConfigFile.new()
	var err = cfg.load(PATH)
	if err == OK:
		_turn_banner = bool(cfg.get_value(SECTION, TURN_BANNER_KEY, true))
	else:
		_turn_banner = true
	_loaded = true
	return _turn_banner


static func reset_for_tests() -> void:
	_loaded = false
	_turn_banner = true

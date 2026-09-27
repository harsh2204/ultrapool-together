extends RefCounted
## Local HUD and shop-view presentation prefs for Ultrapool Together.
## Disk I/O only on load and when the player changes a toggle — never in frame hot paths.

const PATH = "user://together_hud.cfg"
const SECTION = "hud"
const TURN_BANNER_KEY = "turn_banner"
const FOLLOW_SHOP_VIEW_KEY = "follow_shop_view"

static var _loaded = false
static var _turn_banner = true
static var _follow_shop_view = false


static func turn_banner_enabled() -> bool:
	if not _loaded:
		reload()
	return _turn_banner


static func set_turn_banner_enabled(enabled: bool) -> bool:
	if not _loaded:
		reload()
	var value: bool = bool(enabled)
	if _turn_banner == value:
		return _turn_banner
	_turn_banner = value
	_loaded = true
	var cfg = ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(SECTION, TURN_BANNER_KEY, value)
	cfg.save(PATH)
	return _turn_banner


static func follow_shop_view_enabled() -> bool:
	if not _loaded:
		reload()
	return _follow_shop_view


static func set_follow_shop_view_enabled(enabled: bool) -> bool:
	if not _loaded:
		reload()
	if _follow_shop_view == enabled:
		return _follow_shop_view
	_follow_shop_view = enabled
	var cfg = ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(SECTION, FOLLOW_SHOP_VIEW_KEY, enabled)
	cfg.save(PATH)
	return _follow_shop_view


static func reload() -> bool:
	var cfg = ConfigFile.new()
	var err = cfg.load(PATH)
	if err == OK:
		_turn_banner = bool(cfg.get_value(SECTION, TURN_BANNER_KEY, true))
		var follow = cfg.get_value(SECTION, FOLLOW_SHOP_VIEW_KEY, false)
		_follow_shop_view = follow is bool and follow
	else:
		_turn_banner = true
		_follow_shop_view = false
	_loaded = true
	return _turn_banner


static func reset_for_tests() -> void:
	_loaded = false
	_turn_banner = true
	_follow_shop_view = false

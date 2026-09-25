extends SceneTree

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var base = get_script().resource_path.get_base_dir()
	var lobby_ui = load(base.path_join("../mod/lobby_scene.gd"))
	var shop = load(base.path_join("../mod/shop_sync.gd"))
	_check(lobby_ui != null and lobby_ui.can_instantiate(), "lobby scene script loads")
	_check(shop != null, "shop sync script loads")

	var seat_a = lobby_ui.player_color_for(0, 0, 10)
	var seat_b = lobby_ui.player_color_for(0, 1, 20)
	var seat_c = lobby_ui.player_color_for(0, 2, 30)
	_check(seat_a != seat_b and seat_b != seat_c and seat_a != seat_c, "same-table seats get distinct cursor colors")
	_check(seat_a == lobby_ui.TABLE_COLORS[0], "seat 0 uses the first shared palette color")
	_check(seat_b == lobby_ui.TABLE_COLORS[1], "seat 1 uses the second shared palette color")
	_check(
		lobby_ui.player_color_for(0, 0, 99) == seat_a,
		"cursor color follows seat, not Steam or ENet id"
	)
	_check(
		lobby_ui.player_color_for(1, 0, 40) == seat_a,
		"matching seats reuse the palette entry across tables"
	)

	var unseated = lobby_ui.player_color_for(-1, -1, 55)
	var other = lobby_ui.player_color_for(-1, -1, 56)
	_check(
		unseated == Color.from_hsv(posmod(hash(str(55)), 360) / 360.0, 0.55, 1.0),
		"unseated players fall back to a stable id hash color"
	)
	_check(unseated != other, "unseated fallback colors still differ by id")

	var offer = shop.presence_slot_key("offer", 2)
	var build = shop.presence_slot_key("build", 0)
	_check(offer == "offer:2" and build == "build:0", "shop presence targets use group:index keys")
	var slots = {offer: true, build: true}
	_check(
		shop.presence_target_resolves(slots, offer, true),
		"known shop presence targets resolve while the shop is open"
	)
	_check(
		not shop.presence_target_resolves(slots, offer, false),
		"shop presence targets do not resolve when the shop panel is hidden"
	)
	_check(
		not shop.presence_target_resolves(slots, "snack:9", true),
		"unknown shop presence targets do not resolve"
	)
	_check(
		not shop.presence_target_resolves(slots, "", true),
		"empty shop presence targets do not resolve"
	)

	print("PRESENCE_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

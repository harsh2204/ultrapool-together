extends SceneTree

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var base = get_script().resource_path.get_base_dir()
	var UiNav = load(base.path_join("../mod/ui_nav.gd"))
	var CrtStack = load(base.path_join("../mod/crt_stack.gd"))
	_check(UiNav != null, "ui_nav script loads")
	_check(CrtStack != null, "crt_stack script loads")

	_check(UiNav.PLACES.has("snack_bar"), "snack bar is a host UI place")
	_check(UiNav.SHOP_SECTIONS.has("snacks"), "snacks is a shop section")
	_check(UiNav.valid({"place": "snack_bar", "section": "snacks", "focus": "snack:0"}), "snack bar nav is valid")
	_check(UiNav.valid({"place": "shop", "section": "balls", "focus": ""}), "shop balls nav is valid")
	_check(UiNav.valid({"place": "lobby", "section": "", "focus": ""}), "lobby nav is valid")
	_check(UiNav.valid({"place": "set_vote", "section": "", "focus": ""}), "set vote nav is valid")
	_check(not UiNav.valid({"place": "kitchen", "section": "", "focus": ""}), "unknown place is rejected")
	_check(not UiNav.valid({"place": "shop", "section": "vault", "focus": ""}), "unknown section is rejected")
	_check(not UiNav.valid({"place": "shop", "section": "balls", "focus": "nope"}), "malformed focus is rejected")
	_check(not UiNav.valid({"place": "shop", "section": "balls", "focus": "x".repeat(200)}), "oversized focus is rejected")

	var sig_a = UiNav.signature({"place": "snack_bar", "section": "snacks", "focus": "offer:1"})
	var sig_b = UiNav.signature({"place": "snack_bar", "section": "snacks", "focus": "offer:2"})
	_check(sig_a != sig_b, "focus changes dirty the ui_nav signature")
	_check(
		UiNav.signature({"place": "shop", "section": "balls", "focus": ""})
		!= UiNav.signature({"place": "snack_bar", "section": "snacks", "focus": ""}),
		"place/section changes dirty the ui_nav signature"
	)

	_check(CrtStack.FALLBACK_OVERLAY_LAYER == 100, "CRT fallback layer matches spectator fixture band")
	_check(CrtStack.OFFSET_PRESENCE < CrtStack.OFFSET_HUD, "cursors draw above the HUD under CRT")
	_check(CrtStack.OFFSET_HUD < CrtStack.OFFSET_SHOP_NOTICE, "shop notice stays under HUD under CRT")
	_check(CrtStack.OFFSET_SPECTATOR > CrtStack.OFFSET_SHOP_NOTICE, "spectator stays deepest under CRT")

	var layer = CanvasLayer.new()
	# A null context explicitly exercises the fallback, including when this probe
	# runs inside the native screenshot process with a real EffectManager present.
	CrtStack.place_under(layer, null, CrtStack.OFFSET_HUD)
	_check(
		layer.layer == CrtStack.FALLBACK_OVERLAY_LAYER - CrtStack.OFFSET_HUD,
		"place_under uses the fallback overlay when EffectManager is absent"
	)
	_check(
		CrtStack.under_overlay(null, layer.layer),
		"placed layers report as under the overlay"
	)
	layer.free()

	print("UI_NAV_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

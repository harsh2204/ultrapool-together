extends SceneTree

var checks = 0
var failures: Array[String] = []


class NavController:
	extends Node
	var host = false

	func is_table_host() -> bool:
		return host


class NavView:
	extends Node
	var state = 0
	var changes = 0
	var grabbed_ball: Node
	var grabbed_passive: Node
	var selected_ball: Node
	var selected_passive: Node
	var cocktail_bar = Control.new()
	var tapas_bar = Control.new()

	func _init():
		add_child(cocktail_bar)
		add_child(tapas_bar)

	func moving() -> bool:
		return false

	func set_state(value: int):
		state = value
		changes += 1

	func select_ball(body: Node):
		selected_ball = body


class NavShop:
	extends "../mod/shop_sync.gd"
	var cancellations = 0

	# Only substitute native cleanup, which requires the real Global singleton.
	# Queueing, preference, interaction guards, section and focus logic stay real.
	func _cancel_native_drag():
		cancellations += 1
		_view.selected_ball = null
		_view.selected_passive = null


func _initialize() -> void:
	var base = get_script().resource_path.get_base_dir()
	var UiNav = load(base.path_join("../mod/ui_nav.gd"))
	var CrtStack = load(base.path_join("../mod/crt_stack.gd"))
	_check(UiNav != null, "ui_nav script loads")
	_check(CrtStack != null, "crt_stack script loads")

	_check(UiNav.PLACES.has("snack_bar"), "snack bar is a host UI place")
	_check(UiNav.SHOP_SECTIONS.has("snacks"), "snacks is a shop section")
	_check(
		UiNav.valid({"place": "snack_bar", "section": "snacks", "focus": "snack:0"}),
		"snack bar nav is valid"
	)
	_check(
		UiNav.valid({"place": "shop", "section": "balls", "focus": ""}), "shop balls nav is valid"
	)
	_check(UiNav.valid({"place": "lobby", "section": "", "focus": ""}), "lobby nav is valid")
	_check(UiNav.valid({"place": "set_vote", "section": "", "focus": ""}), "set vote nav is valid")
	_check(
		not UiNav.valid({"place": "kitchen", "section": "", "focus": ""}),
		"unknown place is rejected"
	)
	_check(
		not UiNav.valid({"place": "shop", "section": "vault", "focus": ""}),
		"unknown section is rejected"
	)
	_check(
		not UiNav.valid({"place": "shop", "section": "balls", "focus": "nope"}),
		"malformed focus is rejected"
	)
	_check(
		not UiNav.valid({"place": "shop", "section": "balls", "focus": "x".repeat(200)}),
		"oversized focus is rejected"
	)

	var sig_a = UiNav.signature({"place": "snack_bar", "section": "snacks", "focus": "offer:1"})
	var sig_b = UiNav.signature({"place": "snack_bar", "section": "snacks", "focus": "offer:2"})
	_check(sig_a != sig_b, "focus changes dirty the ui_nav signature")
	_check(
		(
			UiNav.signature({"place": "shop", "section": "balls", "focus": ""})
			!= UiNav.signature({"place": "snack_bar", "section": "snacks", "focus": ""})
		),
		"place/section changes dirty the ui_nav signature"
	)

	_check(
		CrtStack.FALLBACK_OVERLAY_LAYER == 100, "CRT fallback layer matches spectator fixture band"
	)
	_check(CrtStack.OFFSET_PRESENCE < CrtStack.OFFSET_HUD, "cursors draw above the HUD under CRT")
	_check(
		CrtStack.OFFSET_HUD < CrtStack.OFFSET_SHOP_NOTICE, "shop notice stays under HUD under CRT"
	)
	_check(
		CrtStack.OFFSET_SPECTATOR > CrtStack.OFFSET_SHOP_NOTICE, "spectator stays deepest under CRT"
	)

	var layer = CanvasLayer.new()
	# A null context explicitly exercises the fallback, including when this probe
	# runs inside the native screenshot process with a real EffectManager present.
	CrtStack.place_under(layer, null, CrtStack.OFFSET_HUD)
	_check(
		layer.layer == CrtStack.FALLBACK_OVERLAY_LAYER - CrtStack.OFFSET_HUD,
		"place_under uses the fallback overlay when EffectManager is absent"
	)
	_check(CrtStack.under_overlay(null, layer.layer), "placed layers report as under the overlay")
	layer.free()
	_check_follow_shop_view(base)

	print("UI_NAV_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check_follow_shop_view(base: String):
	# Preference writes belong only to the capture runner's isolated profile.
	if not OS.get_user_data_dir().contains("UltrapoolTogetherRenderTest"):
		_check(false, "shop-follow preference checks require the isolated capture profile")
		return
	var prefs = load(base.path_join("../mod/hud_prefs.gd"))
	var existed = FileAccess.file_exists(prefs.PATH)
	var saved = FileAccess.get_file_as_bytes(prefs.PATH) if existed else PackedByteArray()
	var config = ConfigFile.new()
	config.set_value(prefs.SECTION, prefs.TURN_BANNER_KEY, false)
	config.save(prefs.PATH)
	prefs.reset_for_tests()
	_check(not prefs.follow_shop_view_enabled(), "missing shop-follow preference defaults off")
	_check(
		not prefs.turn_banner_enabled(), "loading follow preference preserves turn-banner choice"
	)

	var sync = NavShop.new()
	var controller = NavController.new()
	var view = NavView.new()
	var body = Node.new()
	view.add_child(body)
	sync._controller = controller
	sync._view = view
	sync._view_slots = {"build:0": {"ball": body}}
	sync._authoritative_state = {"open": true, "section": "snacks", "focus": "build:0", "money": 42}
	var authority = sync._authoritative_state.duplicate(true)
	_check(sync.show_section("mix"), "manual shop section remains available with follow off")
	sync._queue_host_nav(sync._authoritative_state)
	sync._try_apply_queued_nav()
	_check(
		(
			sync.current_section() == "mix"
			and view.selected_ball == null
			and sync._queued_nav.is_empty()
		),
		"default off preserves manual section and inspection"
	)
	_check(sync.shared_shop_sync_active(), "default view-follow off preserves shared shop access")
	sync.set_follow_host_view(true)
	_check(
		sync.current_section() == "snacks" and view.selected_ball == body,
		"opting in follows latest host section and focus without another update"
	)
	prefs.reset_for_tests()
	_check(prefs.follow_shop_view_enabled(), "shop-follow opt-in persists after reload")
	_check(
		not prefs.turn_banner_enabled(), "shop-follow persistence preserves turn-banner preference"
	)

	view.grabbed_ball = body
	var cancellations: int = sync.cancellations
	sync._queue_host_nav({"open": true, "section": "balls", "focus": ""})
	sync._queue_host_nav({"open": true, "section": "mix", "focus": ""})
	_check(
		(
			sync.current_section() == "snacks"
			and sync.cancellations == cancellations
			and sync._queued_nav.section == "mix"
		),
		"active drag defers navigation and retains only the latest host target"
	)
	view.grabbed_ball = null
	sync._try_apply_queued_nav()
	_check(sync.current_section() == "mix", "latest host view applies after drag ends")
	sync._pending = true
	sync._queue_host_nav({"open": true, "section": "balls", "focus": "build:0"})
	_check(sync.current_section() == "mix", "pending transaction defers host view")
	sync.set_follow_host_view(false)
	_check(
		sync._queued_nav.is_empty() and sync._applied_nav.is_empty() and sync._pending,
		"turning follow off clears both navigation caches without cancelling a transaction"
	)
	sync._pending = false
	sync._try_apply_queued_nav()
	_check(sync.current_section() == "mix", "disabled follow never applies the old deferred target")
	sync._authoritative_state.section = "snacks"
	sync._authoritative_state.focus = ""
	sync._pending = true
	sync.set_follow_host_view(true)
	_check(
		sync.current_section() == "mix" and sync._queued_nav.section == "snacks",
		"re-enabling uses current host view and still respects pending transaction"
	)
	sync._pending = false
	sync._try_apply_queued_nav()
	_check(sync.current_section() == "snacks", "current view applies after transaction resolves")
	_check(
		sync._authoritative_state.money == authority.money and sync._revision == 0,
		"view preference leaves shared money and transaction revision unchanged"
	)
	sync._shared_sync_latched = false
	sync._queue_host_nav({"open": true, "section": "mix", "focus": ""})
	_check(sync.current_section() == "snacks", "follow cannot bypass disabled shared shop access")
	sync._exclusive_shopper = 1
	sync.set_follow_host_view(false)
	sync._queue_host_nav({"open": true, "section": "mix", "focus": ""})
	_check(
		sync.shared_shop_sync_active() and sync.current_section() == "snacks",
		"exclusive shopping preserves shared access but cannot force personal view follow"
	)
	sync.free()
	view.free()
	controller.free()

	# Changing another preference before a read must hydrate all persisted fields.
	config.set_value(prefs.SECTION, prefs.FOLLOW_SHOP_VIEW_KEY, true)
	config.save(prefs.PATH)
	prefs.reset_for_tests()
	prefs.set_turn_banner_enabled(true)
	_check(prefs.follow_shop_view_enabled(), "turn-banner setter preserves a saved follow opt-in")
	config.set_value(prefs.SECTION, prefs.FOLLOW_SHOP_VIEW_KEY, "true")
	config.save(prefs.PATH)
	prefs.reload()
	_check(not prefs.follow_shop_view_enabled(), "malformed follow preference does not opt in")
	if existed:
		var file = FileAccess.open(prefs.PATH, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else:
		DirAccess.remove_absolute(prefs.PATH)
	prefs.reset_for_tests()
	prefs.reload()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

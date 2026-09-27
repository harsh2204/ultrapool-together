extends SceneTree

## Static probe for custom cue catalog / lobby field / apply guards (Refs #20).
## No game launch. Success prints CUE_PROBE PASS.

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var base = get_script().resource_path.get_base_dir().path_join("../mod")
	var catalog = load(base.path_join("cue_catalog.gd"))
	var prefs = load(base.path_join("cue_prefs.gd"))
	var lobby_script = load(base.path_join("lobby_state.gd"))

	_check(catalog.DEFAULT_ID == "native", "default cue id is native")
	_check(catalog.entries().size() >= 6 and catalog.entries().size() <= 12, "starter roster is 6–12 cues")
	_check(catalog.normalize("") == "native", "empty cue normalizes to native")
	_check(catalog.normalize("EMERALD") == "emerald", "cue ids normalize case")
	_check(not catalog.is_known("copyrighted-pro-stick"), "unknown cue ids are rejected")
	_check(catalog.normalize("copyrighted-pro-stick") == "native", "unknown ids coerce to native for apply")

	var native = catalog.style("native")
	_check(native.modulate == Color.WHITE, "native style uses identity modulate")
	_check(catalog.tip_color("ice") != catalog.tip_color("coral"), "cue tip colors differ across styles")

	prefs.reset_for_tests()
	_check(prefs.cue_id() == "native", "prefs default to native before first save")
	_check(prefs.set_cue_id("gold") == "gold", "prefs accept a catalog id")
	_check(prefs.cue_id() == "gold", "prefs remember the last choice in-process")
	prefs.reset_for_tests()

	var lobby = lobby_script.new()
	_check(lobby.setup(10, "Host"), "lobby hosts for cue checks")
	_check(_find(lobby, 10).cue == "native", "new players default to the native cue")
	_check(lobby.add_player(20, "Guest"), "guest joins for cue checks")
	_check(lobby.set_cue(20, "violet"), "guest can choose their own cue")
	_check(_find(lobby, 20).cue == "violet", "guest cue is stored on the player record")
	_check(not lobby.set_cue(20, "not-a-real-cue"), "unknown cue ids are rejected by lobby state")
	_check(_find(lobby, 20).cue == "violet", "rejected cue leaves the prior choice intact")
	_check(not lobby.set_cue(999, "gold"), "unknown sender cannot set a cue")
	var revision: int = lobby.revision
	_check(lobby.set_cue(20, "violet"), "repeating the same cue is accepted")
	_check(lobby.revision == revision, "unchanged cue does not bump lobby revision")
	_check(lobby.set_ready(10, true), "host can ready with a cosmetic cue set")
	_check(lobby.set_cue(10, "amber"), "cue changes do not require unready")
	_check(_find(lobby, 10).ready, "cue change preserves readiness")
	_check(
		catalog.cue_for_player(lobby.snapshot(), 20) == "violet",
		"cue_for_player reads the lobby snapshot"
	)

	var root = Node2D.new()
	root.modulate = Color.WHITE
	var pivot = Node2D.new()
	pivot.name = "CuePivot"
	pivot.modulate = Color.TRANSPARENT
	var cue = Sprite2D.new()
	cue.name = "Cue"
	cue.modulate = Color.WHITE
	var shadow = Sprite2D.new()
	shadow.name = "CueShadow"
	shadow.modulate = Color(0.2, 0.2, 0.2, 0.4)
	cue.add_child(shadow)
	pivot.add_child(cue)
	root.add_child(pivot)
	catalog.apply(root, "emerald")
	_check(root.get_meta("together_cue_id") == "emerald", "apply stamps cue meta")
	_check(root.modulate == Color.WHITE, "apply leaves ball-root modulate alone")
	_check(cue.modulate != Color.WHITE, "apply tints the Cue child")
	_check(pivot.modulate == Color.TRANSPARENT, "cue finish preserves native idle pivot fade")
	_check(shadow.modulate == Color(0.2, 0.2, 0.2, 0.4), "cue finish preserves native shadow")
	var before = cue.modulate
	catalog.apply(root, "emerald")
	_check(cue.modulate == before, "identical apply is idempotent")
	# Simulate replica overwrite of root modulate (#22).
	root.modulate = Color(0.8, 0.8, 0.8, 1)
	catalog.apply(root, "emerald")
	_check(cue.modulate == before, "re-apply keeps cue tint after root modulate wipe")
	cue.modulate = Color.WHITE
	catalog.apply(root, "emerald")
	_check(cue.modulate != Color.WHITE, "diverged child tint is restored")
	# A snapshot/turn change can recolor between native process frames. Neither the
	# same finish nor a different one may revive idle art or reset an active fade.
	pivot.modulate = Color(1.0, 1.0, 1.0, 0.35)
	cue.modulate.a = 0.0
	catalog.apply(root, "emerald")
	_check(is_zero_approx(cue.modulate.a), "identical finish leaves a hidden cue transparent")
	catalog.apply(root, "coral")
	_check(is_zero_approx(cue.modulate.a), "new finish leaves a hidden cue transparent")
	_check(is_equal_approx(pivot.modulate.a, 0.35), "finish change preserves in-progress native fade")
	catalog.apply(root, "native")
	_check(cue.modulate == Color(1, 1, 1, 0), "native apply restores base RGB without revealing cue")
	root.free()

	# Bare cue root (no ball children) still tints itself for lobby swatches / tests.
	var bare = Node2D.new()
	bare.modulate = Color.WHITE
	catalog.apply(bare, "emerald")
	_check(bare.modulate != Color.WHITE, "bare cue root still receives tint")
	bare.free()

	if failures.is_empty():
		print("CUE_PROBE PASS (%d checks)" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("CUE_PROBE FAIL: ", failure)
		print("CUE_PROBE FAIL (%d/%d)" % [failures.size(), checks])
		quit(1)


func _find(lobby, id: int) -> Dictionary:
	for player in lobby.snapshot().players:
		if player.id == id:
			return player
	return {}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

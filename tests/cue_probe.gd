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
	catalog.apply(root, "emerald")
	_check(root.get_meta("together_cue_id") == "emerald", "apply stamps cue meta")
	_check(root.modulate != Color.WHITE, "apply tints the cue root")
	var before = root.modulate
	catalog.apply(root, "emerald")
	_check(root.modulate == before, "identical apply is idempotent")
	catalog.apply(root, "native")
	_check(root.modulate == Color.WHITE, "native apply restores the base modulate")
	root.free()

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

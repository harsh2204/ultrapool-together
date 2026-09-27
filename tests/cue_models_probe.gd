extends SceneTree
## Cue handling model assertions. Run only in an explicitly authorized harness.

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var models = load(get_script().resource_path.get_base_dir().path_join("../mod/cue_models.gd"))
	_check(models.is_known("house"), "the starter model is recognized")
	_check(not models.is_known("Finesse"), "wire model identifiers are exact")
	_check(not models.is_known("unknown"), "unknown models are rejected by catalog validation")
	_check(models.entry("unknown").id == "house", "unknown presentation falls back to House")
	_check(models.entry("house").price == 0, "the native handling model needs no purchase")
	_check(
		models.entry("finesse").price > 0
		and models.entry("finesse").price == models.entry("firm").price,
		"opposite sidegrades share a positive purchase price"
	)
	var catalog: Array = models.entries()
	catalog[0].label = "changed"
	catalog.clear()
	var model: Dictionary = models.entry("finesse")
	model.bias = 10.0
	_check(models.entry("house").label == "House", "catalog callers cannot mutate stored entries")
	_check(
		models.shot_vector(Vector2(80.0, 0.0), "finesse").x < 80.0,
		"entry callers cannot reverse Finesse handling"
	)
	for id in models.ids():
		_check(models.is_known(id), "%s is a valid catalog identifier" % id)
		for endpoint in [50.0, 125.0, 200.0]:
			var vector = Vector2.RIGHT.rotated(0.63) * endpoint
			_check(
				models.shot_vector(vector, id).is_equal_approx(vector),
				"%s preserves native power anchor %.0f" % [id, endpoint]
			)
		_check(models.shot_vector(Vector2.ZERO, id) == Vector2.ZERO, "%s keeps zero safe" % id)
		_check(
			models.shot_vector(Vector2(30.0, -10.0), id) == Vector2(30.0, -10.0),
			"%s never promotes below-threshold input into a shot" % id
		)
		for invalid in [Vector2(NAN, 0.0), Vector2(0.0, INF), Vector2(-INF, INF)]:
			_check(
				models.shot_vector(invalid, id) == Vector2.ZERO,
				"%s fails closed for nonfinite input" % id
			)
		_check(
			is_equal_approx(models.shot_vector(Vector2(300.0, -400.0), id).length(), 200.0),
			"%s caps oversized vectors at native maximum" % id
		)
		_check_curve(models, id)
	for vector in [Vector2(51.0, 0.0), Vector2(60.0, -80.0), Vector2(-180.0, 25.0)]:
		_check(models.shot_vector(vector, "house") == vector, "House preserves accepted native input")
		_check(models.shot_vector(vector, "unknown") == vector, "unknown handling is native identity")
	_check(
		models.shot_vector(Vector2(80.0, 0.0), "finesse").x < 80.0
		and models.shot_vector(Vector2(170.0, 0.0), "finesse").x > 170.0,
		"Finesse trades gentler light shots for firmer heavy shots"
	)
	_check(
		models.shot_vector(Vector2(80.0, 0.0), "firm").x > 80.0
		and models.shot_vector(Vector2(170.0, 0.0), "firm").x < 170.0,
		"Firm makes the opposite handling tradeoff"
	)
	_finish()


func _check_curve(models, id: String) -> void:
	var previous = 50.0
	var monotonic = true
	var bounded = true
	var direction_preserved = true
	var mirror_profiles = true
	for sample in range(1, 1001):
		var strength = 50.0 + 150.0 * sample / 1000.0
		var direction = Vector2.RIGHT.rotated(sample * 0.137)
		var vector: Vector2 = direction * strength
		var result: Vector2 = models.shot_vector(vector, id)
		var power = result.length()
		monotonic = monotonic and power > previous
		bounded = bounded and result.is_finite() and power > 50.0 and power <= 200.001
		bounded = bounded and absf(power - strength) < 4.34
		direction_preserved = direction_preserved and result.normalized().is_equal_approx(direction)
		var finesse: Vector2 = models.shot_vector(vector, "finesse")
		var firm: Vector2 = models.shot_vector(vector, "firm")
		mirror_profiles = mirror_profiles and (finesse + firm).is_equal_approx(vector * 2.0)
		previous = power
	_check(monotonic, "%s rewards increasing input with increasing power" % id)
	_check(bounded, "%s remains native-bounded with at most 2.17%% full-power variation" % id)
	_check(direction_preserved, "%s leaves aim direction unchanged at every power" % id)
	_check(mirror_profiles, "handling profiles are equal and opposite around native power")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("CUE_MODELS_PROBE PASS (%d checks)" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("CUE_MODELS_PROBE FAIL: ", failure)
		print("CUE_MODELS_PROBE FAIL (%d/%d)" % [failures.size(), checks])
		quit(1)

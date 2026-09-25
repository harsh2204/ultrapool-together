extends SceneTree

var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	var base = get_script().resource_path.get_base_dir()
	var native_shop = load(base.path_join("../mod/native_shop.gd"))
	_check(native_shop != null, "native shop script loads")

	var host_slots = [
		{"key": "offer:0", "group": "offer", "index": 0, "id": 1},
		{"key": "build:0", "group": "build", "index": 0, "id": 0},
		{"key": "build:1", "group": "build", "index": 1, "id": 2},
		{"key": "snack:0", "group": "snack", "index": 0, "id": 0},
		{"key": "passive:0", "group": "passive", "index": 0, "id": 0},
		{"key": "mix:0", "group": "mix", "index": 0, "id": 0},
		{"key": "mix:1", "group": "mix", "index": 1, "id": 0},
		{"key": "mix:2", "group": "mix", "index": 2, "id": 0}
	]
	# Guest replica often builds remote_slots in _ready before host inventory arrives.
	var stale_guest = {"offer:0": true, "build:0": true, "mix:0": true, "mix:1": true, "mix:2": true}
	_check(
		not native_shop.remote_slots_cover(stale_guest, host_slots),
		"stale guest layout missing host build/snack/passive keys is rejected"
	)

	var rebuilt_guest = {}
	for entry in host_slots:
		rebuilt_guest[entry.key] = true
	# Extra local unlocks must not block a host-authoritative layout.
	rebuilt_guest["build:15"] = true
	rebuilt_guest["passive:3"] = true
	_check(
		native_shop.remote_slots_cover(rebuilt_guest, host_slots),
		"guest layout that covers every host key is accepted"
	)
	_check(
		not native_shop.remote_slots_cover(rebuilt_guest, host_slots + [{"key": "build:16"}]),
		"guest layout missing a host key is still rejected"
	)
	_check(
		native_shop.remote_slots_cover({}, []),
		"empty host shop has no slot coverage requirements"
	)
	_check(
		not native_shop.remote_slots_cover({"offer:0": true}, [{"group": "offer", "index": 0}]),
		"entries without a key cannot cover the host layout"
	)

	print("SHOP_LAYOUT_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

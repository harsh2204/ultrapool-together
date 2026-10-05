extends SceneTree
## Authored, unrun native-resource/filesystem coverage. Requires an explicitly
## authorized native harness; every write stays in a fresh fixture directory.
## Does not invoke the public importer or touch either real progression profile.

const Importer = preload("../mod/progress_import.gd")


class SaveOwner:
	extends Node
	signal save_loaded
	var save: Resource
	var notifications = 0


class Cache:
	extends RefCounted
	var manager: Node
	var save: Resource
	var refreshes = 0

	func _cache_save_refs() -> void:
		save = manager.save
		refreshes += 1


class FailingImporter:
	extends "../mod/progress_import.gd"
	var fail_at = ""
	var also_fail_at = ""
	var remove_before_failure = false
	var operations: Array[String] = []

	func _before_operation(operation: String) -> Error:
		operations.append(operation)
		if operation == fail_at or operation == also_fail_at:
			return ERR_FILE_CANT_WRITE
		return OK

	func _replace(source: String, target: String, operation: String) -> Error:
		if remove_before_failure and operation == fail_at:
			operations.append(operation)
			DirAccess.remove_absolute(target)
			return ERR_FILE_CANT_WRITE
		return super._replace(source, target, operation)


var checks = 0
var failures: Array[String] = []
var _root = ""


func _initialize() -> void:
	var profile_name = str(
		ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	)
	if not profile_name.begins_with("UltrapoolTogetherRenderTest-"):
		_check(false, "filesystem probe requires the isolated Capture-Screens profile")
		_finish()
		return
	# This rejects before constructing or reading any normal profile save file.
	_check(
		not Importer.new().source_info().ok, "public importer rejects the isolated render profile"
	)
	_root = ProjectSettings.globalize_path("user://").path_join(
		"progress-import-fixture-" + Crypto.new().generate_random_bytes(16).hex_encode()
	)
	if DirAccess.make_dir_absolute(_root) != OK:
		_check(false, "isolated fixture root can be created")
		_finish()
		return
	_check_copy_and_reimport()
	_check_rejected_sources()
	_check_failures()
	_check_destructive_rename_failure()
	_check_empty_destination_rollback()
	_check_incomplete_rollback()
	_check_links()
	_remove_fixture(_root)
	_finish()


func _fixture(name: String, existing: bool = true) -> Dictionary:
	var directory = _root.path_join(name)
	var source_dir = directory.path_join("steam")
	var profile = directory.path_join("together")
	DirAccess.make_dir_recursive_absolute(source_dir)
	DirAccess.make_dir_recursive_absolute(profile)
	var native_script = load(Importer.SAVE_SCRIPT)
	var source: Resource = native_script.new()
	source.set("settings", {"origin": "steam", "volume": 0.91})
	source.set("total_runs_played", 71)
	source.set("customization", {"fixture": "steam cosmetics"})
	source.set("daily_leaderboard_submitted", true)
	source.set("full_game_unlocked", true)
	var source_path = source_dir.path_join("save.tres")
	_check(ResourceSaver.save(source, source_path) == OK, name + ": native source serializes")
	var manager = SaveOwner.new()
	manager.save = native_script.new()
	manager.save.set("settings", {"origin": "local", "volume": 0.23})
	manager.save.set("total_runs_played", 9)
	manager.save.set("customization", {"fixture": "local cosmetics"})
	manager.save.set("daily_leaderboard_submitted", false)
	manager.save.set("full_game_unlocked", false)
	manager.save_loaded.connect(func(): manager.notifications += 1)
	if existing:
		_check(
			ResourceSaver.save(manager.save, profile.path_join("save.tres")) == OK,
			name + ": existing primary serializes"
		)
		# Existing recovery bytes deliberately differ from the primary.
		var recovery: Resource = manager.save.duplicate(true)
		recovery.set("total_runs_played", 8)
		_check(
			ResourceSaver.save(recovery, profile.path_join("save.bak.tres")) == OK,
			name + ": existing recovery serializes"
		)
		_write(profile.path_join(Importer.MARKER), '{"schema":1,"fixture":"old marker"}')
	_write(source_dir.path_join("save.bak.tres"), "vanilla recovery stays unchanged")
	_write(source_dir.path_join("run_data.tres"), "unfinished vanilla run")
	_write(source_dir.path_join("daily_data.tres"), "unfinished vanilla daily")
	_write(profile.path_join("run_data.tres"), "unfinished Together run")
	_write(profile.path_join("daily_data.tres"), "unfinished Together daily")
	_write(profile.path_join("together_hud.cfg"), "personal mod preferences")
	var cache = Cache.new()
	cache.manager = manager
	cache.save = manager.save
	return {
		"directory": directory,
		"source": source_path,
		"profile": profile,
		"manager": manager,
		"cache": cache,
		"old_save": manager.save,
		"old_settings": manager.save.settings,
		"before": _protected_snapshot(source_dir, profile),
	}


func _check_copy_and_reimport() -> void:
	var fixture = _fixture("success")
	# New progress has not yet reached save.tres; both recovery points matter.
	fixture.manager.save.total_runs_played = 10
	var service = Importer.new()
	var result = service._import_paths(
		fixture.source, fixture.profile, fixture.manager, [fixture.cache]
	)
	_check(result.ok, "an explicit import succeeds despite an existing one-time marker")
	if not result.ok:
		fixture.manager.free()
		return
	var current: Resource = fixture.manager.save
	_check(
		current != fixture.old_save and current.total_runs_played == 71,
		"native memory adopts Steam progress"
	)
	_check(
		current.customization == {"fixture": "steam cosmetics"},
		"native memory adopts Steam cosmetics"
	)
	_check(
		is_same(current.settings, fixture.old_settings),
		"local settings retain their existing Dictionary identity"
	)
	_check(not current.daily_leaderboard_submitted, "local daily bookkeeping survives import")
	_check(not current.full_game_unlocked, "local entitlement state is not imported")
	_check(fixture.manager.notifications == 0, "import never emits display-changing save_loaded")
	_check(
		fixture.cache.refreshes == 1 and fixture.cache.save == current,
		"progression cache rebinds once after commit"
	)
	var pair = _target_snapshot(fixture.profile)
	_check(
		pair["save.tres"] == pair["save.bak.tres"],
		"both recovery files receive the same prepared progress"
	)
	var disk = ResourceLoader.load(
		fixture.profile.path_join("save.tres"), "", ResourceLoader.CACHE_MODE_IGNORE
	)
	_check(
		disk.settings == fixture.old_settings and disk.total_runs_played == 71,
		"prepared disk state keeps settings and imports progress"
	)
	for name in Importer.TARGETS:
		_check(
			(
				FileAccess.get_file_as_bytes(result.backup.path_join(name))
				== fixture.before["target/" + name]
			),
			"backup preserves exact previous " + name
		)
	var memory_backup = ResourceLoader.load(
		result.backup.path_join("current-memory.tres"), "", ResourceLoader.CACHE_MODE_IGNORE
	)
	_check(
		memory_backup.total_runs_played == 10,
		"backup also preserves newer native in-memory progress"
	)
	_check_non_targets(fixture, "success")
	var marker = JSON.parse_string(
		FileAccess.get_file_as_string(fixture.profile.path_join(Importer.MARKER))
	)
	_check(
		marker.mode == "manual" and marker.previous_mod_progress == result.backup,
		"completion marker identifies manual backup"
	)
	var source: Resource = load(Importer.SAVE_SCRIPT).new()
	source.total_runs_played = 72
	ResourceSaver.save(source, fixture.source)
	var second = service._import_paths(
		fixture.source, fixture.profile, fixture.manager, [fixture.cache]
	)
	_check(
		second.ok and second.backup != result.backup,
		"reimport makes a fresh backup instead of honoring one-time skip"
	)
	_check(
		fixture.manager.save.total_runs_played == 72,
		"reimport loads fresh source rather than cached SaveData"
	)
	_check(
		FileAccess.get_file_as_bytes(second.backup.path_join("save.tres")) == pair["save.tres"],
		"reimport backs up the preceding imported progress"
	)
	_check(
		_no_stages(result.backup) and _no_stages(second.backup),
		"successful imports leave no transaction staging files"
	)
	fixture.manager.free()


func _check_rejected_sources() -> void:
	for kind in ["missing", "header", "oversize", "resource", "same_profile", "directory"]:
		var fixture = _fixture("reject-" + kind)
		var source: String = fixture.source
		match kind:
			"missing":
				DirAccess.remove_absolute(source)
			"header":
				_write(source, "not native progression")
			"oversize":
				var file = FileAccess.open(source, FileAccess.READ_WRITE)
				file.seek(Importer.MAX_SAVE_BYTES)
				file.store_8(0)
				file.close()
			"resource":
				# Header alone must not admit a resource with the wrong native type.
				_write(
					source,
					'[gd_resource type="Resource" script_class="SaveData" format=3]\n\n[resource]\n'
				)
			"same_profile":
				source = fixture.profile.path_join("save.tres")
			"directory":
				DirAccess.remove_absolute(fixture.profile.path_join("save.bak.tres"))
				DirAccess.make_dir_absolute(fixture.profile.path_join("save.bak.tres"))
		var before = _target_snapshot(fixture.profile)
		var result = Importer.new()._import_paths(
			source, fixture.profile, fixture.manager, [fixture.cache]
		)
		_check(not result.ok, kind + ": unsafe source/profile rejects")
		_check(_target_snapshot(fixture.profile) == before, kind + ": target files stay unchanged")
		_check(
			fixture.manager.save == fixture.old_save and fixture.cache.refreshes == 0,
			kind + ": native state stays unchanged"
		)
		fixture.manager.free()


func _check_failures() -> void:
	for operation in [
		"stage:source",
		"serialize",
		"backup:current-memory",
		"backup:save.bak.tres",
		"backup:save.tres",
		"backup:" + Importer.MARKER,
		"backup:manifest",
		"rollback-stage:save.tres",
		"stage:save.bak.tres",
		"stage:save.tres",
		"stage:" + Importer.MARKER,
		"commit:save.bak.tres",
		"commit:save.tres",
		"commit:" + Importer.MARKER,
	]:
		var fixture = _fixture("fail-" + operation.replace(":", "-"))
		var service = FailingImporter.new()
		service.fail_at = operation
		var before = _target_snapshot(fixture.profile)
		var result = service._import_paths(
			fixture.source, fixture.profile, fixture.manager, [fixture.cache]
		)
		_check(
			not result.ok and service.operations.has(operation),
			operation + ": injected production operation fails"
		)
		_check(
			_target_snapshot(fixture.profile) == before,
			operation + ": all target bytes are restored"
		)
		_check(result.get("rollback_ok", true), operation + ": rollback reports complete")
		_check(
			fixture.manager.save == fixture.old_save and fixture.cache.refreshes == 0,
			operation + ": no premature in-memory adoption"
		)
		_check_non_targets(fixture, operation)
		_check(_no_stages(result.backup), operation + ": known staging files cleaned")
		fixture.manager.free()


func _check_destructive_rename_failure() -> void:
	var fixture = _fixture("destructive-rename")
	var service = FailingImporter.new()
	service.fail_at = "commit:save.tres"
	service.remove_before_failure = true
	var before = _target_snapshot(fixture.profile)
	var result = service._import_paths(
		fixture.source, fixture.profile, fixture.manager, [fixture.cache]
	)
	_check(
		not result.ok and result.get("rollback_ok", false),
		"Windows-style remove-then-fail rename rolls back"
	)
	_check(
		_target_snapshot(fixture.profile) == before,
		"rollback restores the failing target as well as previous commits"
	)
	_check(
		fixture.manager.save == fixture.old_save,
		"failed destructive rename preserves native memory"
	)
	fixture.manager.free()


func _check_empty_destination_rollback() -> void:
	var fixture = _fixture("initially-absent", false)
	var service = FailingImporter.new()
	service.fail_at = "commit:" + Importer.MARKER
	var result = service._import_paths(
		fixture.source, fixture.profile, fixture.manager, [fixture.cache]
	)
	_check(
		not result.ok and result.get("rollback_ok", false), "new-profile commit failure rolls back"
	)
	_check(
		_target_snapshot(fixture.profile).is_empty(),
		"rollback restores absence instead of creating old placeholder files"
	)
	_check_non_targets(fixture, "new-profile rollback")
	fixture.manager.free()


func _check_incomplete_rollback() -> void:
	var fixture = _fixture("incomplete-rollback")
	var service = FailingImporter.new()
	service.fail_at = "commit:" + Importer.MARKER
	service.also_fail_at = "rollback:save.tres"
	var result = service._import_paths(
		fixture.source, fixture.profile, fixture.manager, [fixture.cache]
	)
	_check(
		not result.ok and not result.get("rollback_ok", true),
		"rollback failure is reported honestly"
	)
	_check(
		fixture.manager.save == fixture.old_save, "failed rollback never adopts partial new state"
	)
	for name in Importer.TARGETS:
		_check(
			(
				FileAccess.get_file_as_bytes(result.backup.path_join(name))
				== fixture.before["target/" + name]
			),
			"incomplete rollback retains manual recovery copy of " + name
		)
	fixture.manager.free()


func _check_links() -> void:
	var fixture = _fixture("symlink")
	var link = fixture.directory.path_join("linked-source.tres")
	var directory = DirAccess.open(fixture.directory)
	var result = directory.create_link(fixture.source, link)
	if result == OK:
		var before = _target_snapshot(fixture.profile)
		var copied = Importer.new()._import_paths(link, fixture.profile, fixture.manager)
		_check(
			not copied.ok and _target_snapshot(fixture.profile) == before,
			"symbolic source links reject before mutation"
		)
		DirAccess.remove_absolute(link)
	else:
		print("PROGRESS_IMPORT_PROBE: symlink creation unavailable; platform link case unverified")
	fixture.manager.free()


func _protected_snapshot(source_dir: String, profile: String) -> Dictionary:
	var result: Dictionary = {}
	for name in ["save.tres", "save.bak.tres", "run_data.tres", "daily_data.tres"]:
		result["source/" + name] = FileAccess.get_file_as_bytes(source_dir.path_join(name))
	for name in ["run_data.tres", "daily_data.tres", "together_hud.cfg"]:
		result["other/" + name] = FileAccess.get_file_as_bytes(profile.path_join(name))
	for name in _target_snapshot(profile):
		result["target/" + name] = FileAccess.get_file_as_bytes(profile.path_join(name))
	return result


func _target_snapshot(profile: String) -> Dictionary:
	var result: Dictionary = {}
	for name in Importer.TARGETS:
		if FileAccess.file_exists(profile.path_join(name)):
			result[name] = FileAccess.get_file_as_bytes(profile.path_join(name))
	return result


func _check_non_targets(fixture: Dictionary, label: String) -> void:
	var now = _protected_snapshot(fixture.source.get_base_dir(), fixture.profile)
	for key in fixture.before:
		if not key.begins_with("target/"):
			_check(now[key] == fixture.before[key], label + ": preserves " + key)


func _no_stages(path: String) -> bool:
	if path.is_empty():
		return true
	var directory = DirAccess.open(path)
	if directory == null:
		return false
	for name in directory.get_files():
		if (
			name.begins_with("next-")
			or name.begins_with("rollback-")
			or name.ends_with("-stage.tres")
		):
			return false
	return true


func _write(path: String, contents: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()


func _remove_fixture(path: String) -> void:
	if not path.begins_with(_root) or path == _root.get_base_dir():
		_check(false, "cleanup stays inside isolated fixture root")
		return
	var directory = DirAccess.open(path)
	if directory == null:
		return
	for name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in directory.get_directories():
		if directory.is_link(name):
			DirAccess.remove_absolute(path.path_join(name))
		else:
			_remove_fixture(path.path_join(name))
	DirAccess.remove_absolute(path)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("PROGRESS_IMPORT_PROBE PASS (%d checks)" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("PROGRESS_IMPORT_PROBE FAIL: ", failure)
		print("PROGRESS_IMPORT_PROBE FAIL (%d/%d)" % [failures.size(), checks])
		quit(1)

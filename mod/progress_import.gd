extends RefCounted
## Explicit, local progression replacement. No networking, run files or native
## save_data/flush_all callbacks are involved. Observed replacement errors roll
## back the pair and marker, including a failed rename that removed its target.
## Godot's Windows rename may remove first: this is not crash-atomic.

const MAX_SAVE_BYTES = 8 * 1024 * 1024
const PROFILE = "UltrapoolTogether"
const MARKER = "ultrapool-together-progress-import.json"
const SAVE_SCRIPT = "res://saves/SaveData.gd"
const TARGETS = ["save.bak.tres", "save.tres", MARKER]

var _busy = false


func source_info() -> Dictionary:
	var paths = _production_paths()
	if not paths.ok:
		return paths
	var problem = _paths_problem(paths.source, paths.profile)
	if problem != "":
		return _failure(problem)
	return _source_header(paths.source)


func import_progress(save_manager: Node) -> Dictionary:
	var paths = _production_paths()
	if not paths.ok:
		return paths
	if not is_instance_valid(save_manager):
		return _failure("Progress is not ready. Return to the main menu and try again.")
	var caches: Array = []
	for name in ["AchievementManager", "TutorialManager"]:
		var cache = save_manager.get_node_or_null("/root/" + name)
		if cache == null or not cache.has_method("_cache_save_refs"):
			return _failure("This game version cannot safely refresh imported progress.")
		caches.append(cache)
	return _import_paths(paths.source, paths.profile, save_manager, caches)


func _production_paths() -> Dictionary:
	if OS.get_name() not in ["Windows", "macOS"]:
		return _failure("Copying Steam progress is supported on Windows and macOS.")
	var profile = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var expected = OS.get_data_dir().path_join(PROFILE).simplify_path()
	if (
		not ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
		or ProjectSettings.get_setting("application/config/custom_user_dir_name", "") != PROFILE
		or not _same_path(profile, expected)
	):
		return _failure("Copying progress requires the installed Ultrapool Together save profile.")
	return {
		"ok": true,
		"profile": profile,
		"source": OS.get_data_dir().path_join("Godot/app_userdata/Ultrapool/save.tres"),
	}


## Private filesystem seam: fixtures supply only their own isolated directories,
## a fake save owner and fake cache listeners. Never a network entry point.
func _import_paths(
	source: String, profile: String, save_manager: Node, caches: Array = []
) -> Dictionary:
	if _busy:
		return _failure("A progress copy is already in progress.")
	_busy = true
	var result = _import_checked(
		source.simplify_path(), profile.simplify_path(), save_manager, caches
	)
	_busy = false
	return result


func _import_checked(
	source: String, profile: String, save_manager: Node, caches: Array
) -> Dictionary:
	var problem = _paths_problem(source, profile)
	if problem != "":
		return _failure(problem)
	var header = _source_header(source)
	if not header.ok:
		return header
	if not is_instance_valid(save_manager) or not _is_native_save(save_manager.get("save")):
		return _failure("Current progress is unavailable; nothing was replaced.")
	for cache in caches:
		if not is_instance_valid(cache) or not cache.has_method("_cache_save_refs"):
			return _failure("Progress listeners are unavailable; nothing was replaced.")
	var original: Resource = save_manager.get("save")
	if not original.get("settings") is Dictionary:
		return _failure("Current settings are unavailable; nothing was replaced.")
	var source_read = _read_bytes(source)
	if not source_read.ok:
		return _failure("Steam progress could not be read safely; nothing was replaced.")
	if not _valid_header(source_read.bytes):
		return _failure("Steam progress changed or is not a recognized SaveData file.")
	var old: Dictionary = {}
	for name in TARGETS:
		var path = profile.path_join(name)
		var entry = (
			_read_bytes(path) if FileAccess.file_exists(path) else {"ok": true, "absent": true}
		)
		if not entry.ok:
			return _failure("Existing progress could not be backed up; nothing was replaced.")
		old[name] = entry
	var random = Crypto.new().generate_random_bytes(16)
	if random.size() != 16:
		return _failure("Could not create a unique backup identity; nothing was replaced.")
	var backup_root = profile.path_join("save-import-backups")
	var backup = backup_root.path_join(
		str(int(Time.get_unix_time_from_system())) + "-" + random.hex_encode()
	)
	if (
		DirAccess.make_dir_recursive_absolute(backup_root) != OK
		or DirAccess.make_dir_absolute(backup) != OK
	):
		return _failure("Could not create the progress backup; nothing was replaced.")
	var stages: Array[String] = []
	var source_stage = backup.path_join("source-stage.tres")
	stages.append(source_stage)
	if _write_bytes(source_stage, source_read.bytes, "stage:source") != OK:
		return _abandon("Could not prepare Steam progress; nothing was replaced.", backup, stages)
	var candidate = ResourceLoader.load(source_stage, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not _is_native_save(candidate):
		return _abandon("Steam progress is not a valid native SaveData resource.", backup, stages)
	# Keep the exact Dictionary identity used by native Settings/Audio/EffectManager.
	# save_loaded would reapply window/display settings even when values match.
	candidate.set("settings", original.get("settings"))
	# These are local daily-session bookkeeping, separate from unlocks/statistics.
	candidate.set("last_daily", original.get("last_daily"))
	candidate.set("daily_leaderboard_submitted", original.get("daily_leaderboard_submitted"))
	# Billing is not progression, and BillingManager retains this local value.
	candidate.set("full_game_unlocked", original.get("full_game_unlocked"))
	var prepared = backup.path_join("prepared-stage.tres")
	stages.append(prepared)
	if _before_operation("serialize") != OK or ResourceSaver.save(candidate, prepared) != OK:
		return _abandon(
			"Could not prepare imported progress; nothing was replaced.", backup, stages
		)
	var prepared_read = _read_bytes(prepared)
	if not prepared_read.ok or not _valid_header(prepared_read.get("bytes", PackedByteArray())):
		return _abandon(
			"Prepared progress exceeded its limit or could not be verified.", backup, stages
		)
	var record = {
		"schema": 1,
		"imported_at": Time.get_datetime_string_from_system(true) + "Z",
		"source": source,
		"source_sha256": _hash(source_read.bytes),
		"imported_sha256": _hash(prepared_read.bytes),
		"previous_mod_progress": backup,
		"mode": "manual",
		"local_settings_retained": true,
		"local_daily_state_retained": true,
	}
	var previous: Dictionary = {}
	# Native memory can contain progress newer than the last focus/exit save. Keep
	# that additional recovery point without invoking native save_data/flush_all.
	var memory_backup = backup.path_join("current-memory.tres")
	if (
		_before_operation("backup:current-memory") != OK
		or ResourceSaver.save(original, memory_backup) != OK
	):
		return _abandon("Could not back up current progress; nothing was replaced.", backup, stages)
	var memory_read = _read_bytes(memory_backup)
	if not memory_read.ok or not _valid_header(memory_read.get("bytes", PackedByteArray())):
		return _abandon(
			"Current progress backup could not be verified; nothing was replaced.", backup, stages
		)
	previous["current-memory.tres"] = {"existed": true, "sha256": _hash(memory_read.bytes)}
	var rollback: Dictionary = {}
	for name in TARGETS:
		var entry: Dictionary = old[name]
		previous[name] = {"existed": not entry.get("absent", false)}
		if entry.get("absent", false):
			continue
		previous[name]["sha256"] = _hash(entry.bytes)
		if _write_bytes(backup.path_join(name), entry.bytes, "backup:" + name) != OK:
			return _abandon("Could not complete the backup; nothing was replaced.", backup, stages)
		var rollback_path = backup.path_join("rollback-" + name)
		stages.append(rollback_path)
		rollback[name] = rollback_path
		if _write_bytes(rollback_path, entry.bytes, "rollback-stage:" + name) != OK:
			return _abandon("Could not prepare rollback; nothing was replaced.", backup, stages)
	if (
		_write_bytes(
			backup.path_join("previous-files.json"),
			(JSON.stringify(previous, "\t") + "\n").to_utf8_buffer(),
			"backup:manifest"
		)
		!= OK
	):
		return _abandon(
			"Could not complete the backup record; nothing was replaced.", backup, stages
		)
	var incoming: Dictionary = {}
	for name in TARGETS:
		var stage = backup.path_join("next-" + name)
		stages.append(stage)
		incoming[name] = stage
		var bytes: PackedByteArray = (
			(JSON.stringify(record, "\t") + "\n").to_utf8_buffer()
			if name == MARKER
			else prepared_read.bytes
		)
		if _write_bytes(stage, bytes, "stage:" + name) != OK:
			return _abandon(
				"Could not stage imported progress; nothing was replaced.", backup, stages
			)
	# Recheck path links and the previous file contents before replacing anything.
	# A change from another process aborts rather than overwriting its newer save.
	problem = _paths_problem(source, profile)
	if problem != "" or not _unchanged(profile, old):
		return _abandon(
			"Progress paths or files changed during copying. Try again.", backup, stages
		)
	var changed: Array[String] = []
	for name in TARGETS:
		# On Windows a failed native rename can already have removed its target.
		# Roll back every attempted target, including the one returning an error.
		changed.append(name)
		if _replace(incoming[name], profile.path_join(name), "commit:" + name) != OK:
			var restored = _rollback(profile, old, rollback, changed)
			var result = _abandon(
				(
					"Copy failed; previous progress was restored."
					if restored
					else "Copy failed and rollback was incomplete. Restore the retained backup before playing."
				),
				backup,
				stages
			)
			result["rollback_ok"] = restored
			return result
	# No await/event yield between disk commit and adoption: focus/exit saves must
	# see the imported object. Refresh only progression aliases, not display/audio.
	save_manager.set("save", candidate)
	for cache in caches:
		cache.call("_cache_save_refs")
	_cleanup(stages)
	return {
		"ok": true,
		"message": "Steam progress copied. Your local settings and saved runs were kept.",
		"backup": backup,
	}


func _rollback(
	profile: String, old: Dictionary, rollback: Dictionary, changed: Array[String]
) -> bool:
	var ok = true
	changed.reverse()
	for name in changed:
		var target = profile.path_join(name)
		if old[name].get("absent", false):
			if DirAccess.dir_exists_absolute(target):
				ok = false
			elif (
				FileAccess.file_exists(target)
				and (
					_before_operation("rollback-remove:" + name) != OK
					or DirAccess.remove_absolute(target) != OK
				)
			):
				ok = false
		elif _replace(rollback[name], target, "rollback:" + name) != OK:
			ok = false
	return ok and _unchanged(profile, old)


func _unchanged(profile: String, old: Dictionary) -> bool:
	for name in TARGETS:
		var path = profile.path_join(name)
		if old[name].get("absent", false):
			if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
				return false
		else:
			var read = _read_bytes(path)
			if not read.ok or read.bytes != old[name].bytes:
				return false
	return true


func _source_header(source: String) -> Dictionary:
	if not FileAccess.file_exists(source):
		return _failure("No Steam progress was found. Play and close the normal game first.")
	var file = FileAccess.open(source, FileAccess.READ)
	if file == null:
		return _failure("Steam progress could not be opened.")
	var length = file.get_length()
	var header = file.get_buffer(mini(length, 4096))
	file.close()
	if length <= 0 or length > MAX_SAVE_BYTES or not _valid_header(header):
		return _failure("Steam progress is empty, unrecognized, or larger than 8 MiB.")
	return {"ok": true, "message": "Steam progress is available to copy."}


func _valid_header(bytes: PackedByteArray) -> bool:
	var first = bytes.get_string_from_utf8().trim_prefix("\ufeff").get_slice("\n", 0).strip_edges()
	return first.begins_with("[gd_resource ") and 'script_class="SaveData"' in first


func _is_native_save(value) -> bool:
	return value is Resource and value.get_script() == load(SAVE_SCRIPT)


func _paths_problem(source: String, profile: String) -> String:
	if not source.is_absolute_path() or not profile.is_absolute_path():
		return "Progress paths must be absolute."
	if (
		_same_path(source.get_base_dir(), profile)
		or _same_path(source, profile.path_join("save.tres"))
	):
		return "Steam and Together must use different save profiles."
	if not DirAccess.dir_exists_absolute(profile):
		return "The Together save profile is unavailable."
	var paths: Array = [source, profile, profile.path_join("save-import-backups")]
	for name in TARGETS:
		paths.append(profile.path_join(name))
	for path in paths:
		if not _plain_path(path):
			return "Symbolic links or inaccessible progress paths cannot be copied safely."
	for path in [
		source,
		profile.path_join("save.tres"),
		profile.path_join("save.bak.tres"),
		profile.path_join(MARKER)
	]:
		if DirAccess.dir_exists_absolute(path):
			return "An expected progress file is a directory; nothing was replaced."
	if FileAccess.file_exists(profile.path_join("save-import-backups")):
		return "The progress backup folder is unavailable."
	return ""


func _plain_path(path: String) -> bool:
	var current = path.simplify_path().trim_suffix("/")
	for depth in 64:
		var parent = current.get_base_dir()
		if parent == current or parent.is_empty():
			return true
		if DirAccess.dir_exists_absolute(parent):
			var directory = DirAccess.open(parent)
			if directory == null or directory.is_link(current.get_file()):
				return false
		current = parent
	return false


func _same_path(left: String, right: String) -> bool:
	var a = left.replace("\\", "/").simplify_path().trim_suffix("/")
	var b = right.replace("\\", "/").simplify_path().trim_suffix("/")
	return a.to_lower() == b.to_lower() if OS.get_name() == "Windows" else a == b


func _read_bytes(path: String) -> Dictionary:
	var before = FileAccess.get_modified_time(path)
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_SAVE_BYTES:
		return {"ok": false}
	var length = file.get_length()
	var bytes = file.get_buffer(length)
	var error = file.get_error()
	var stable = file.get_length() == length
	file.close()
	return {
		"ok":
		(
			error == OK
			and stable
			and bytes.size() == length
			and before == FileAccess.get_modified_time(path)
		),
		"bytes": bytes,
	}


func _write_bytes(path: String, bytes: PackedByteArray, operation: String) -> Error:
	var injected = _before_operation(operation)
	if injected != OK:
		return injected
	if bytes.size() > MAX_SAVE_BYTES or not _plain_path(path):
		return ERR_INVALID_DATA
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		return error
	var read = _read_bytes(path)
	return OK if read.ok and read.bytes == bytes else ERR_FILE_CORRUPT


func _replace(source: String, target: String, operation: String) -> Error:
	var injected = _before_operation(operation)
	if injected != OK:
		return injected
	if not _plain_path(source) or not _plain_path(target):
		return ERR_INVALID_DATA
	return DirAccess.rename_absolute(source, target)


## Override only in isolated fixtures to fail an actual filesystem transaction.
func _before_operation(_operation: String) -> Error:
	return OK


func _hash(bytes: PackedByteArray) -> String:
	var hashing = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func _cleanup(paths: Array[String]) -> void:
	for path in paths:
		if _plain_path(path) and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _abandon(message: String, backup: String, stages: Array[String]) -> Dictionary:
	_cleanup(stages)
	var result = _failure(message)
	result["backup"] = backup
	return result


func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "backup": ""}

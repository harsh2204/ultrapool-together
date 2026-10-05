extends RefCounted
## Authored native UI coverage; run only inside the authorized capture harness.


class ImportDouble:
	extends RefCounted
	var reads = 0
	var copies = 0
	var available = true
	var succeeds = false

	func source_info() -> Dictionary:
		reads += 1
		return {"ok": available, "message": "No Steam progression save was found."}

	func import_progress(_manager: Node) -> Dictionary:
		copies += 1
		return {
			"ok": succeeds,
			"message":
			"Steam progress copied." if succeeds else "Fixture copy failed; progress kept.",
			"backup": "isolated fixture backup"
		}


func check(mod: Node, record: Callable, capture: Callable) -> void:
	if not record.call(
		OS.get_user_data_dir().contains("UltrapoolTogetherRenderTest"),
		"save settings: native UI fixture requires the isolated capture profile"
	):
		return
	if not record.call(
		mod.run_setup.at_main_menu() and not mod.active and not mod.transport.session_open(),
		"save settings: begins at the native main menu without a room"
	):
		return
	var original_importer = mod._progress_importer
	var importer = ImportDouble.new()
	mod._progress_importer = importer
	var menu = mod.get_tree().current_scene
	var menu_id = menu.get_instance_id()
	var menu_mode = menu.process_mode
	var ui = mod.get_node("/root/UIManager")
	var ui_mode = ui.process_mode
	mod.settings_button.pressed.emit()
	await mod.get_tree().process_frame
	record.call(
		mod.panel.visible and mod.panel.is_settings_only() and mod.panel.is_mod_options_open(),
		"save settings: HUD gear opens settings directly from the native main menu"
	)
	record.call(
		not mod.panel.get_node("Margin").visible and not mod.transport.session_open(),
		"save settings: lobby chrome stays hidden and no multiplayer room is opened"
	)
	record.call(importer.reads == 0, "save settings: opening preferences performs no save I/O")
	record.call(
		not mod._progress_import_button.disabled,
		"save settings: main menu copy action is available"
	)
	var options: Control = mod.panel.get_node("%ModOptions")
	var section: Control = mod.panel.get_node("%ModOptionsColumn/ProgressImport")
	record.call(
		mod.panel.get_global_rect().encloses(options.get_global_rect()),
		"save settings: standalone slate fits the viewport"
	)
	mod.panel.get_node("%ModOptionsScroll").ensure_control_visible(section)
	await mod.get_tree().process_frame
	var copy_button: Button = mod._progress_import_button
	record.call(
		copy_button.size.x >= copy_button.get_minimum_size().x,
		"save settings: the complete copy action label fits"
	)
	await capture.call(
		"mod-settings-steam-progress", "Mod settings · copy Steam progress without a lobby"
	)

	mod._progress_import_button.pressed.emit()
	record.call(
		importer.reads == 1 and importer.copies == 0 and mod._progress_import_confirmation.visible,
		"save settings: first click previews replacement without copying"
	)
	mod._progress_import_cancel.pressed.emit()
	record.call(
		importer.copies == 0 and not mod._progress_import_confirmation.visible,
		"save settings: Cancel leaves progress untouched"
	)
	importer.available = false
	mod._progress_import_button.pressed.emit()
	record.call(
		(
			mod._progress_import_status.text.contains("No Steam")
			and not mod._progress_import_confirmation.visible
		),
		"save settings: missing source reports an actionable error without confirmation"
	)
	importer.available = true
	mod._progress_import_button.pressed.emit()
	mod._progress_import_confirm.pressed.emit()
	record.call(
		mod._progress_import_busy, "save settings: confirmation gives immediate pending state"
	)
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	mod.panel._input(escape)
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	record.call(
		importer.copies == 0 and not mod.panel.visible and not mod._progress_import_busy,
		"save settings: dismissal during pending feedback cancels before disk mutation"
	)
	record.call(
		menu.process_mode == menu_mode and ui.process_mode == ui_mode,
		"save settings: Escape restores the native menu and UI processing"
	)

	mod.settings_button.pressed.emit()
	mod._progress_import_button.pressed.emit()
	mod._progress_import_confirm.pressed.emit()
	mod.active = true
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	record.call(importer.copies == 0, "save settings: new match guard is rechecked after yielding")
	mod.active = false
	mod._refresh_progress_import_options(true)
	mod._progress_import_button.pressed.emit()
	mod._progress_import_confirm.pressed.emit()
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	record.call(
		(
			importer.copies == 1
			and mod._progress_import_status.text.contains("progress kept")
			and not mod._progress_import_busy
			and not mod._progress_import_button.disabled
		),
		"save settings: failure stays visible and allows retry"
	)
	mod.panel.get_node("%ModOptions/SettingsHeader/CloseSettings").pressed.emit()
	record.call(
		not mod.panel.visible and menu.process_mode == menu_mode and ui.process_mode == ui_mode,
		"save settings: Close dismisses the entire standalone shell"
	)
	mod._set_panel(true)
	record.call(
		not mod.panel.is_settings_only() and mod.panel.get_node("Margin").visible,
		"save settings: opening the lobby later restores its chrome"
	)
	mod._set_panel(false)
	importer.succeeds = true
	mod.settings_button.pressed.emit()
	mod._progress_import_button.pressed.emit()
	mod._progress_import_confirm.pressed.emit()
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	record.call(
		(
			importer.copies == 2
			and mod._progress_refresh_menu_pending
			and mod._progress_import_button.disabled
			and mod._progress_import_status.text.contains("Steam progress copied")
		),
		"save settings: success reports completion and waits for dismissal before menu refresh"
	)
	mod.panel.get_node("%ModOptions/SettingsHeader/CloseSettings").pressed.emit()
	record.call(
		not mod.panel.visible and not mod._progress_refresh_menu_pending,
		"save settings: closing after success schedules the native menu refresh"
	)
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	record.call(
		(
			mod.get_tree().current_scene != null
			and mod.get_tree().current_scene.get_instance_id() != menu_id
		),
		"save settings: successful import rebuilds the native main menu on close"
	)
	mod._progress_importer = original_importer

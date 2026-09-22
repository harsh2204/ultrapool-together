extends RefCounted


class Controller:
	extends Node
	var active = true
	var table_id = 0
	var lobby = {"table_count": 3}
	var ui_root: Control
	var abandoned: Array[int] = []

	func _table_abandoned(table: int) -> bool:
		return abandoned.has(table)


var checks: Array = []


func capture(mod: Node, snapshot: Dictionary, screenshot: Callable) -> Array:
	var original_game = mod.get_node("/root/Global").gameManager
	var original_camera = mod.get_node("/root/Global").camera
	var physics = mod.get_node("/root/GlobalPhysics")
	var original_balls = physics.balls.duplicate()
	var original_shapes = physics.shapes.duplicate()
	var controller = Controller.new()
	controller.ui_root = mod.ui_root
	mod.add_child(controller)
	var spectator = (
		load(get_script().resource_path.get_base_dir().path_join("../mod/table_spectator.gd")).new()
	)
	controller.add_child(spectator)
	spectator.setup(controller)
	var original_spectator = mod.spectator
	mod.spectator = spectator
	spectator.watch_changed.connect(func(_table: int): _refresh_home_ui(mod))
	_refresh_home_ui(mod)
	var home_visibility = _home_visibility(mod)
	_check(spectator.watch(1), "another table can be watched without changing seats")
	_check(
		(
			mod.is_spectating()
			and not mod.turn_label.visible
			and not mod.score_label.visible
			and not mod.pass_button.visible
			and not mod.multiplayer_balls._ui._overlay.visible
			and not mod.multiplayer_balls._ui._hint.visible
		),
		"watching hides the local turn controls, score, and ball selection markers"
	)
	spectator.apply_snapshot(1, snapshot)
	spectator.tick(0.0)
	await mod.get_tree().process_frame
	_check(spectator._balls.size() == snapshot.balls.size(), "watcher renders every received ball")
	_check(
		_visual_only(spectator._world), "watcher creates no gameplay scripts, bodies, or cameras"
	)
	_check(
		(
			mod.get_node("/root/Global").gameManager == original_game
			and mod.get_node("/root/Global").camera == original_camera
			and physics.balls == original_balls
			and physics.shapes == original_shapes
		),
		"watching preserves the running game and physics registration"
	)
	var textured = true
	for ball in snapshot.balls:
		var sphere = spectator._balls[ball.id].sphere
		textured = (
			textured
			and (
				sphere.material.get_shader_parameter("tex")
				== mod.get_node("/root/BallDatabase").id_to_ball[ball.item.data].texture
			)
		)
	_check(textured, "watcher spheres use each ball's native texture")
	var native_felt: Sprite2D = original_game.table.get_node("TableCustomization").table_main
	var copied_felt = spectator._table.get_node(original_game.table.get_path_to(native_felt))
	_check(
		copied_felt.is_visible_in_tree() and copied_felt.texture == native_felt.texture,
		"watcher keeps the native felt visible"
	)
	var native_floor = original_game.table.get_node("TableCustomization").shop_floor
	if native_floor == null:
		native_floor = original_game.shop.get_node("%ShopFloor")
	_check(
		(
			spectator._floor.texture == native_floor.texture
			and spectator._floor.region_rect == native_floor.region_rect
			and spectator._floor.texture_repeat == native_floor.texture_repeat
			and spectator._floor.is_visible_in_tree()
		),
		"watcher uses the configured native floor with its repeat and coverage"
	)
	_check(
		spectator._layer.layer < mod.get_node("/root/EffectManager").crt_overlay.get_parent().layer,
		"watcher stays underneath the native configured screen effects"
	)
	var hud_visible = true
	for name in ["ScoreDisplay", "RoundText", "ShotsInfo", "hpInfo", "MoneyLabel", "ScoreLabel"]:
		hud_visible = (
			hud_visible and spectator._table.find_child(name, true, false).is_visible_in_tree()
		)
	_check(hud_visible, "watcher retains the complete native table HUD")
	var updated = snapshot.duplicate(true)
	updated.score = 123
	updated.required_score = 456
	updated.money = 78
	updated.hp = 1
	updated.shots = 2
	spectator._update_table_ui(updated)
	_check(
		(
			spectator._table.get_node("ScoreDisplay/CurrentScore").text == "123"
			and spectator._table.get_node("ScoreDisplay/TargetScore").text == "/456"
			and spectator._table.find_child("MoneyLabel", true, false).text == "78€"
			and spectator._table.get_node("ShotsInfo/PipsHolder").get_child_count() == 2
			and spectator._table.get_node("hpInfo/heart/HeartFull").visible
			and not spectator._table.get_node("hpInfo/heart2/HeartFull").visible
		),
		"watcher updates native score, money, hearts, and shot pips from the watched table"
	)
	spectator._update_table_ui(snapshot)
	_check(
		(
			copied_felt.texture != null
			and copied_felt.get_rect().has_area()
			and spectator._root.get_node("Background").z_index < copied_felt.z_index
		),
		"native felt has drawing geometry in front of the opaque background"
	)
	var pocket_positions_match = true
	var pockets = spectator._table.get_node("Pockets").get_children()
	for pocket in snapshot.pockets:
		if pocket.base_index >= 0:
			pocket_positions_match = (
				pocket_positions_match
				and pockets[pocket.base_index].global_position.is_equal_approx(
					spectator._world.to_global(pocket.position - snapshot.table_position)
				)
			)
	_check(pocket_positions_match, "watcher pockets align with the received world positions")
	for ball in snapshot.balls:
		if ball.player:
			_check(
				spectator._balls[ball.id].node.get_child_count() == 1,
				"read-only cue ball excludes native aiming and shoot controls"
			)
	_check(
		spectator._status.text.begins_with("Round %d" % (snapshot.round + 1)),
		"watcher uses the game's one-based round label"
	)
	var dormant_hidden = true
	for name in ["Pentagram", "graveyard"]:
		for effect in spectator._table.find_children(name, "CanvasItem", true, false):
			dormant_hidden = dormant_hidden and not effect.is_visible_in_tree()
	_check(dormant_hidden, "watcher hides effects whose runtime state is not synchronized")
	await screenshot.call("spectate-table", "Watch another table while your own run continues")
	var board_image = mod.get_viewport().get_texture().get_image()
	var board_center: Vector2 = spectator._world.to_global(spectator._bounds.get_center())
	var center_color = board_image.get_pixelv(Vector2i(board_center))
	var background: Color = spectator._root.get_node("Background").color
	_check(
		(
			Vector3(center_color.r, center_color.g, center_color.b).distance_to(
				Vector3(background.r, background.g, background.b)
			)
			> 0.1
		),
		"rendered felt center is visible above the background"
	)
	var floor_color = board_image.get_pixel(100, 360)
	_check(
		(
			Vector3(floor_color.r, floor_color.g, floor_color.b).distance_to(
				Vector3(background.r, background.g, background.b)
			)
			> 0.03
		),
		"rendered spectator background contains the native floor instead of a flat backdrop"
	)
	await _check_customization(mod, spectator, original_game, screenshot)
	var shopping = snapshot.duplicate(true)
	shopping.in_shop = true
	spectator.apply_snapshot(1, shopping)
	spectator.tick(0.0)
	_check(
		spectator._status.text.contains("Shopping"), "shopping is shown as a read-only table status"
	)
	await screenshot.call("spectate-shopping", "Shopping table keeps its last board visible")
	var before = snapshot.duplicate(true)
	var after = snapshot.duplicate(true)
	if not before.balls.is_empty():
		var id = before.balls[0].id
		after.balls[0].position += Vector2(40, 0)
		spectator._render_balls(before, after, 0.5)
		var expected: Vector2 = before.balls[0].position - before.table_position + Vector2(20, 0)
		_check(
			spectator._balls[id].node.position.is_equal_approx(expected),
			"watcher interpolates ball movement between snapshots"
		)
	var frames = spectator._frames.size()
	spectator.apply_snapshot(2, snapshot)
	_check(spectator._frames.size() == frames, "unwatched table cannot replace the visible board")
	var next_round = snapshot.duplicate(true)
	next_round.scene_id += 1
	spectator.apply_snapshot(1, next_round)
	_check(spectator._frames.size() == 1, "new scene clears the previous interpolation buffer")
	controller.abandoned.append(2)
	_check(
		not spectator.watch(2) and spectator.watched_table == 1 and spectator._frames.size() == 1,
		"watching an abandoned table is rejected without clearing the current view"
	)
	spectator._refresh_picker()
	var unavailable_index: int = spectator._table_picker.get_item_index(2)
	_check(
		spectator._table_picker.is_item_disabled(unavailable_index),
		"table picker disables abandoned tables"
	)
	spectator._table_picker.set_item_disabled(unavailable_index, false)
	spectator._table_picker.select(unavailable_index)
	spectator._pick_table(unavailable_index)
	_check(
		(
			spectator.watched_table == 1
			and spectator._table_picker.get_selected_id() == 1
			and spectator._table_picker.is_item_disabled(unavailable_index)
		),
		"a stale table selection restores the current table and refreshes availability"
	)
	controller.abandoned.clear()
	_check(
		spectator.watch(2) and spectator._frames.is_empty(),
		"switching tables clears old board data"
	)
	_check(
		not spectator.watch(0) and not spectator.is_watching(),
		"selecting own table closes watching"
	)
	_check(
		not mod.is_spectating() and _home_visibility(mod) == home_visibility,
		"returning to the home table restores its HUD and ball overlays"
	)
	var ui = mod.get_node("/root/UIManager")
	var was_processing: bool = ui.is_processing()
	var settings_open: bool = ui.is_settings_open()
	spectator.watch(1)
	var escape = InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	Input.action_press("settings")
	spectator._input(escape)
	_check(
		not spectator.is_watching() and not ui.is_processing(),
		"Escape returns to the table without letting native settings consume the same press"
	)
	await mod.get_tree().create_timer(0.05).timeout
	_check(
		ui.is_processing() == was_processing and ui.is_settings_open() == settings_open,
		"native UI polling resumes after Escape without opening settings"
	)
	mod.spectator = original_spectator
	_refresh_home_ui(mod)
	controller.free()
	_check(
		mod.spectator == original_spectator and _home_visibility(mod) == home_visibility,
		"spectator fixture restores the live controller and original HUD visibility"
	)
	return checks


func _refresh_home_ui(mod: Node) -> void:
	mod._update_hud()
	mod.multiplayer_balls._ui.refresh(mod.multiplayer_balls.capture())


func _home_visibility(mod: Node) -> Dictionary:
	return {
		"turn": mod.turn_label.visible,
		"score": mod.score_label.visible,
		"pass": mod.pass_button.visible,
		"balls": mod.multiplayer_balls._ui._overlay.visible,
		"hint": mod.multiplayer_balls._ui._hint.visible
	}


func _check_customization(mod: Node, spectator: Node, game: Node, screenshot: Callable) -> void:
	var save = mod.get_node("/root/SaveManager").save
	var original_customization = save.customization.duplicate(true)
	var customization = mod.get_node("/root/CustomizationManager")
	var database = mod.get_node("/root/BallDatabase")
	var selected: Dictionary = {}
	for type in [
		Cosmetic.COSMETIC_TYPE.TABLE_MAIN,
		Cosmetic.COSMETIC_TYPE.TABLE_WALLS,
		Cosmetic.COSMETIC_TYPE.SHOP_FLOOR,
		Cosmetic.COSMETIC_TYPE.GRADIENT
	]:
		var current = customization.get_cosmetic(type)
		for cosmetic in database.cosmetics:
			if cosmetic.type == type and cosmetic.id != current.id:
				selected[type] = cosmetic
				save.customization[type] = cosmetic.id
				break
	customization.cosmetics_changed.emit()
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame
	_check(
		selected.size() == 4,
		"customization fixture selects non-default felt, rails, floor, and palette"
	)
	var native = game.table.get_node("TableCustomization")
	var felt = spectator._table.get_node(game.table.get_path_to(native.table_main))
	var rails = spectator._table.get_node(game.table.get_path_to(native.table_walls))
	_check(
		(
			felt.texture == selected[Cosmetic.COSMETIC_TYPE.TABLE_MAIN].texture
			and rails.texture == selected[Cosmetic.COSMETIC_TYPE.TABLE_WALLS].texture
			and spectator._floor.texture == selected[Cosmetic.COSMETIC_TYPE.SHOP_FLOOR].texture
			and (
				felt.material.get_shader_parameter("palette_texture")
				== native.table_main.material.get_shader_parameter("palette_texture")
			)
		),
		"watcher applies the user's changed native cosmetics without changing their running board"
	)
	await screenshot.call(
		"spectate-customized", "Spectating with locally selected felt, rails, floor, and palette"
	)
	save.customization = original_customization
	customization.cosmetics_changed.emit()
	await mod.get_tree().process_frame
	await mod.get_tree().process_frame


func _visual_only(node: Node) -> bool:
	if (
		node.get_script() != null
		or node is CollisionObject2D
		or node is Camera2D
		or node is SubViewport
	):
		return false
	for child in node.get_children():
		if not _visual_only(child):
			return false
	return true


func _check(passed: bool, description: String) -> void:
	checks.append({"name": description, "passed": passed})

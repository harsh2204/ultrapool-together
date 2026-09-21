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
	_check(spectator.watch(1), "another table can be watched without changing seats")
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
	controller.free()
	return checks


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

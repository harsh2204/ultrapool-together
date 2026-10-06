extends Node

signal watch_changed(table: int)

const BUFFER_SECONDS = 0.12
const STALE_SECONDS = 3.0
const EYE_ICON = "res://ui/eye.png"
const TITLE_TAG_CONTENT = [46, 9, 20, 12]
const TITLE_EYE_POSITION = Vector2(16, 9)
const TITLE_EYE_SIZE = Vector2(24, 24)
const STATUS_RIBBON_CONTENT = [44, 8, 44, 12]
const BallVisualState = preload("ball_visual_state.gd")
const NativeDrawView = preload("table_native_draw_view.gd")
const TableEffectsView = preload("table_effects_view.gd")
const TableVisualFxView = preload("table_visual_fx_view.gd")
const AbilityOverlay = preload("ability_overlay.gd")
const BountyRace = preload("bounty_race.gd")

var watched_table: int:
	get:
		return _table_id

var _controller: Node
var _scene_reader: Script
var _table_id = -1
var _scene_key = ""
var _frames: Array = []
var _state: Dictionary = {}
var _balls: Dictionary = {}
var _holes: Dictionary = {}
var _layer: CanvasLayer
var _root: Control
var _world: Node2D
var _table: Node2D
var _floor: Sprite2D
var _shots = -1
var _ball_scene: PackedScene
var _player_scene: PackedScene
var _hole_scene: PackedScene
var _title: Label
var _status: Label
var _empty: Label
var _table_picker: OptionButton
var _bounds = Rect2(-320, -240, 640, 480)
var _last_received = 0.0
var _effects_view = TableEffectsView.new()
var _visual_fx_view = TableVisualFxView.new()
var _native_draw_view = NativeDrawView.new()
var _effects_frame: Dictionary = {}
## PERF-022: table HUD nodes resolved once per board, and the last display inputs.
var _ui_nodes: Dictionary = {}
var _ui_state: Array = []
var _layout_size = Vector2.ZERO
## MOD-01..12: watched-table ability indicators from the validated state feed.
var _ability: Control
var _ability_signature: Array = []
var _ability_offset = Vector2.ZERO


func setup(controller: Node) -> void:
	_controller = controller
	_scene_reader = load(get_script().resource_path.get_base_dir().path_join("spectator_scene.gd"))
	var game_scene: PackedScene = get_node("/root/Global").SCENE_GAME
	_ball_scene = _scene_reader.exported(game_scene, "ball_scene")
	_player_scene = _scene_reader.exported(game_scene, "player_ball_scene")
	_hole_scene = _scene_reader.exported(game_scene, "hole_scene")
	_build_ui()
	get_node("/root/CustomizationManager").cosmetics_changed.connect(
		_refresh_cosmetics, CONNECT_DEFERRED
	)


func watch(table: int) -> bool:
	if not _controller.active or table == _controller.table_id:
		close()
		return false
	if table < 0 or table >= int(_controller.lobby.get("table_count", 0)):
		return false
	if _controller._table_abandoned(table):
		return false
	if table == _table_id:
		return true
	_clear_board()
	_table_id = table
	_state.clear()
	_root.show()
	_title.text = "Watching Table %d" % (table + 1)
	_status.text = "Your table keeps playing."
	_empty.text = "Connecting to table…"
	_empty.show()
	_refresh_picker()
	watch_changed.emit(table)
	return true


func close() -> void:
	if not is_watching():
		return
	_table_id = -1
	_root.hide()
	_clear_board()
	_state.clear()
	watch_changed.emit(-1)


func is_watching() -> bool:
	return _table_id >= 0


func apply_snapshot(table: int, data: Dictionary) -> void:
	if table != _table_id or not is_watching():
		return
	_last_received = _now()
	if not data.available:
		_clear_board()
		_empty.text = "Waiting for the next round…"
		_empty.show()
		return
	var key = "%s:%s:%s" % [data.scene_id, data.rounds_played, data.rotated]
	if key != _scene_key:
		_clear_board()
		_scene_key = key
		_create_table(data)
	_frames.append({"time": _last_received, "data": data.duplicate(true)})
	while _frames.size() > 8:
		_frames.pop_front()
	_empty.hide()
	_update_status(data)


func apply_state(table: int, data: Dictionary) -> void:
	if table != _table_id or not is_watching():
		return
	_state = data.duplicate(true)
	if not _frames.is_empty():
		_update_status(_frames.back().data)
	elif _state.get("finished", false):
		_empty.text = "Run finished"


func tick(_delta: float) -> void:
	if not is_watching() or _frames.is_empty():
		return
	var time = _now() - BUFFER_SECONDS
	while _frames.size() > 2 and _frames[1].time <= time:
		_frames.pop_front()
	var before: Dictionary = _frames.front()
	var after: Dictionary = _frames[1] if _frames.size() > 1 else before
	var duration: float = after.time - before.time
	var weight = clampf((time - before.time) / duration, 0.0, 1.0) if duration > 0 else 1.0
	_render_balls(before.data, after.data, weight)
	# Apply each buffered descriptor once; interpolation ticks retain visual nodes.
	# PERF-022: pockets, table HUD and layout depend only on the newest frame.
	if not is_same(_effects_frame, after):
		_effects_frame = after
		_effects_view.apply(after.data.get("effects", {}), after.data.table_position, _scene_key)
		_visual_fx_view.apply(after.data.get("visual_fx", {}), after.data.table_position, _scene_key)
		_native_draw_view.apply(after.data.get("native_draw", {}), after.data.table_position, _scene_key)
		_update_pockets(after.data)
		_update_table_ui(after.data)
		_layout()
	elif _root.size != _layout_size:
		_layout()
	_effects_view.tick()
	_visual_fx_view.tick()
	_native_draw_view.tick()
	_refresh_abilities(after.data)
	if _now() - _last_received > STALE_SECONDS:
		_status.text = "Waiting for table updates… · Your table keeps playing."


func _input(event: InputEvent) -> void:
	if is_watching() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if InputMap.has_action("settings") and event.is_action("settings"):
			Input.action_release("settings")
			var ui = get_node("/root/UIManager")
			var was_processing: bool = ui.is_processing()
			ui.set_process(false)
			get_tree().create_timer(0.0).timeout.connect(ui.set_process.bind(was_processing))
		close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	var CrtStack = preload("crt_stack.gd")
	CrtStack.place_under(_layer, self, CrtStack.OFFSET_SPECTATOR)
	add_child(_layer)
	_root = Control.new()
	_root.theme = _controller.ui_root.theme
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background = ColorRect.new()
	background.name = "Background"
	background.z_index = -4096
	background.color = Color("08080d")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world = Node2D.new()
	_root.add_child(_world)
	_ability = AbilityOverlay.make_overlay(_draw_abilities)
	_ability.z_index = 500
	_root.add_child(_ability)
	_ability.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var header = HBoxContainer.new()
	header.z_index = 1000
	header.add_theme_constant_override("separation", 16)
	_root.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 24
	header.offset_right = -24
	header.offset_top = 16
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_table_picker = OptionButton.new()
	_table_picker.item_selected.connect(_pick_table)
	_table_picker.get_popup().about_to_popup.connect(_refresh_picker)
	header.add_child(_table_picker)
	var back = Button.new()
	back.text = "Back to my table"
	back.pressed.connect(close)
	header.add_child(back)
	_status = Label.new()
	_status.z_index = 1000
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_status)
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -44
	_status.offset_bottom = -16
	var skin: RefCounted = _controller.get("skin")
	if skin != null and skin.has_art():
		_apply_skin(skin, header, back)
	_empty = Label.new()
	_empty.z_index = 1000
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_empty)
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.hide()


# D2 overlay: tags sized to their text instead of spanning the header; built once with the UI.
func _apply_skin(skin: RefCounted, header: HBoxContainer, back: Button) -> void:
	_title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_title.add_theme_stylebox_override("normal", skin.style("hud_tag_orange", TITLE_TAG_CONTENT))
	_title.add_theme_color_override("font_color", Color.WHITE)
	var eye = TextureRect.new()
	eye.texture = skin.native_texture(EYE_ICON)
	eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eye.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	eye.position = TITLE_EYE_POSITION
	eye.size = TITLE_EYE_SIZE
	eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(eye)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	header.move_child(spacer, _title.get_index() + 1)
	back.icon = skin.texture("icon_return")
	var ribbon = skin.style("ribbon_strip_orange", STATUS_RIBBON_CONTENT)
	_status.add_theme_stylebox_override("normal", ribbon)
	_status.add_theme_color_override("font_color", Color.WHITE)
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.offset_left = 0
	_status.offset_right = 0
	_status.offset_top = -58
	_status.offset_bottom = -10


func _refresh_picker() -> void:
	_table_picker.clear()
	for table in int(_controller.lobby.table_count):
		if table == _controller.table_id:
			continue
		_table_picker.add_item("Table %d" % (table + 1), table)
		_table_picker.set_item_disabled(
			_table_picker.item_count - 1, _controller._table_abandoned(table)
		)
		if table == _table_id:
			_table_picker.select(_table_picker.item_count - 1)


func _pick_table(index: int) -> void:
	if not watch(_table_picker.get_item_id(index)):
		_refresh_picker()


func _create_table(data: Dictionary) -> void:
	var game_scene: PackedScene = get_node("/root/Global").SCENE_GAME
	var property = "table_rotated_scene" if data.rotated else "table_scene"
	_table = _scene_reader.create(_scene_reader.exported(game_scene, property))
	_world.add_child(_table)
	_table.position = Vector2.ZERO
	_ui_nodes = {
		"current": _table.get_node("ScoreDisplay/CurrentScore"),
		"target": _table.get_node("ScoreDisplay/TargetScore"),
		"fill": _table.get_node("ScoreDisplay/ScoreFill"),
		"fill2": _table.get_node("ScoreDisplay/ScoreFill2"),
		"score_label": _table.find_child("ScoreLabel", true, false),
		"money_label": _table.find_child("MoneyLabel", true, false),
		"round_text": _table.get_node("RoundText"),
		"hearts": _table.get_node("hpInfo"),
		"hp_panel": _table.find_child("HPPanel", true, false),
		"daily_panel": _table.find_child("DailyMedalPanel", true, false),
		"pips": _table.get_node("ShotsInfo/PipsHolder")
	}
	_ui_state = []
	_refresh_cosmetics()
	_effects_view.setup(_world, game_scene)
	_visual_fx_view.setup(_world, game_scene)
	_native_draw_view.setup(_world, game_scene)
	BallVisualState.prepare()
	var points: Array[Vector2] = []
	for pocket in data.pockets:
		if pocket.base_index >= 0:
			points.append(pocket.position - data.table_position)
	if not points.is_empty():
		_bounds = Rect2(points[0], Vector2.ZERO)
		for point in points:
			_bounds = _bounds.expand(point)
		_bounds = _bounds.grow(56.0)
	_layout()


func _refresh_cosmetics() -> void:
	if not is_instance_valid(_table):
		return
	var game = get_node("/root/Global").gameManager
	if not is_instance_valid(game) or not is_instance_valid(game.table):
		return
	var source_floor = game.table.get_node("TableCustomization").shop_floor
	if source_floor == null:
		source_floor = game.shop.get_node("%ShopFloor")
	if is_instance_valid(_floor):
		_floor.free()
	_floor = _scene_reader.copy_live(source_floor)
	_world.add_child(_floor)
	_floor.position = Vector2.ZERO
	_floor.show()
	for source in game.table.find_children("*", "CanvasItem", true, false):
		var target = _table.get_node_or_null(game.table.get_path_to(source))
		if not target is CanvasItem:
			continue
		target.modulate = source.modulate
		target.self_modulate = source.self_modulate
		target.visible = source.visible
		target.material = source.material.duplicate() if source.material != null else null
		if target is Sprite2D and source is Sprite2D:
			target.texture = source.texture
	var stickers = _table.get_node("StickerLayer")
	for child in stickers.get_children():
		child.free()
	for source in game.table.get_node("StickerLayer").get_children():
		stickers.add_child(_scene_reader.copy_live(source))
	for name in ["EndRoundButton", "Pentagram", "graveyard", "Tutorial", "AimReminder"]:
		_hide_named(_table, name)
	for control in _table.find_children("*", "Control", true, false):
		if ClassDB.is_parent_class(control.get_meta("native_type", "Control"), "BaseButton"):
			control.hide()


func _update_table_ui(data: Dictionary) -> void:
	var global_node = get_node("/root/Global")
	var ui_state: Array = [
		data.score, data.required_score, data.money, data.round, data.daily, data.hp, data.max_hp,
		TranslationServer.get_locale()
	]
	if ui_state == _ui_state:
		_update_shot_pips(data.shots)
		return
	_ui_state = ui_state
	var required = maxf(data.required_score, 1.0)
	var score_text: String = global_node.format_number(data.score, 4, 1)
	var target_text: String = global_node.format_number(required, 4, 1)
	_ui_nodes.current.text = score_text
	_ui_nodes.target.text = "/" + target_text
	_ui_nodes.fill.material.set_shader_parameter("percent", data.score / required)
	_ui_nodes.fill2.material.set_shader_parameter(
		"percent", data.score / maxf(required * 10.0, 100.0)
	)
	_ui_nodes.score_label.text = score_text + " / " + target_text
	_ui_nodes.money_label.text = global_node.format_number(data.money) + "€"
	_ui_nodes.round_text.text = tr("UI_ROUND") + " " + str(data.round + 1)
	var hearts = _ui_nodes.hearts
	hearts.visible = not data.daily
	_ui_nodes.hp_panel.visible = not data.daily
	_ui_nodes.daily_panel.visible = data.daily
	var index = 0
	for heart in hearts.get_children():
		if not heart.has_node("HeartFull"):
			continue
		heart.visible = index < data.max_hp
		var full: bool = index < data.hp
		heart.get_node("HeartFull").visible = full
		heart.get_node("HeartLeft").visible = not full
		heart.get_node("HeartRight").visible = not full
		heart.get_node("HeartLeft").position = Vector2(-2.5, -2.5)
		heart.get_node("HeartRight").position = Vector2(2.5, 2.5)
		heart.modulate.a = 0.75 if full else 0.3
		index += 1
	_update_shot_pips(data.shots)


func _update_shot_pips(shots: int) -> void:
	if _shots == shots:
		return
	_shots = shots
	var holder = _ui_nodes.pips
	for child in holder.get_children():
		child.free()
	holder.position = Vector2(-20.0 * (_shots - 1) * 0.5, 0)
	for pip_index in _shots:
		var pip = _scene_reader.create(load("res://ui/shot_pip.tscn"))
		holder.add_child(pip)
		pip.position = Vector2(pip_index * 20.0, 0)
		pip.scale = Vector2.ONE * 0.4
		pip.material.set_shader_parameter("color", Color.WHITE)


func _render_balls(before: Dictionary, after: Dictionary, weight: float) -> void:
	var previous: Dictionary = {}
	for ball in before.balls:
		previous[ball.id] = ball
	var present: Dictionary = {}
	for ball in after.balls:
		present[ball.id] = true
		if not _balls.has(ball.id):
			_create_ball(ball)
		var visual: Dictionary = _balls[ball.id]
		var old: Dictionary = previous.get(ball.id, ball)
		var start: Vector2 = old.position - before.table_position
		var end: Vector2 = ball.position - after.table_position
		visual.node.position = start.lerp(end, weight)
		visual.node.rotation = lerp_angle(old.rotation, ball.rotation, weight)
		visual.node.visible = ball.visible and not ball.gone
		visual.node.modulate = old.color.lerp(ball.color, weight)
		visual.visuals.scale = old.visual_scale.lerp(ball.visual_scale, weight)
		_apply_item(visual, ball.item, ball.player)
		if visual.get("ball_visual") != ball.get("ball_visual", {}):
			BallVisualState.apply(visual.node, ball.get("ball_visual", {}))
			visual["ball_visual"] = ball.get("ball_visual", {}).duplicate(true)
		var basis = Basis(
			Quaternion.from_euler(old.spin).slerp(Quaternion.from_euler(ball.spin), weight)
		)
		var material: ShaderMaterial = visual.sphere.material
		material.set_shader_parameter("rotation_x", basis.x)
		material.set_shader_parameter("rotation_y", basis.y)
		material.set_shader_parameter("rotation_z", basis.z)
	for id in _balls.keys():
		if not present.has(id):
			_balls[id].node.free()
			_balls.erase(id)


func _create_ball(state: Dictionary) -> void:
	var body = _scene_reader.create(_player_scene if state.player else _ball_scene)
	var visuals: Node2D = body.get_node("visuals")
	var sphere: Sprite2D = visuals.get_node("ball")
	for child in body.get_children():
		if child != visuals:
			child.free()
	visuals.show()
	sphere.show()
	_world.add_child(body)
	for path in ["static/flash", "static/spark", "static/chargeGauge"]:
		var effect = visuals.get_node_or_null(path)
		if effect is CanvasItem:
			effect.hide()
	_balls[state.id] = {"node": body, "visuals": visuals, "sphere": sphere, "item": {}}
	_apply_item(_balls[state.id], state.item, state.player)


func _apply_item(visual: Dictionary, item: Dictionary, is_player: bool = false) -> void:
	if item == visual.item:
		return
	var previous: Dictionary = visual.item
	# PERF-024: only an identity change needs a new ball material. Score, level
	# and status changes update the label and indicators on the retained nodes.
	var identity_changed: bool = (
		previous.get("data") != item.data or previous.get("mixed") != item.mixed
	)
	visual.item = item.duplicate()
	# Item setup can replace a material or change an indicator beneath the same
	# host visual sample; reapply that sample once after this mutation.
	visual.erase("ball_visual")
	var database = get_node("/root/BallDatabase").id_to_ball
	var mixed: bool = item.mixed != ""
	if identity_changed:
		var material: ShaderMaterial = (
			load("res://materials/mixed_ball.tres" if mixed else "res://materials/ball.tres")
			. duplicate()
		)
		material.set_shader_parameter("tex", database[item.data].texture)
		if mixed:
			material.set_shader_parameter("mixed_tex", database[item.mixed].texture)
		visual.sphere.material = material
	var score = item.base_score + item.temp_extra_score
	var numbered: bool = database[item.data].tags.has("TAG_NUMBER") and not mixed
	var label: Label = visual.visuals.get_node("static/Panel/Label")
	label.get_parent().visible = (
		database[item.data].has_card and not (numbered and score > 0 and score <= 8) and score != 1
	)
	label.text = get_node("/root/Global").format_number(score, 4, 0)
	var edge = visual.visuals.get_node_or_null("static/edge")
	if identity_changed and edge != null and edge.material is ShaderMaterial:
		edge.material.set_shader_parameter(
			"selout_color", database[item.data].main_color.darkened(0.4)
		)
	var indicators = {
		"fire_indicator": item.flaming,
		"freeze_indicator": item.locked,
		# Native never draws star chrome on the cue ball (#31).
		"star_indicator": item.star_power and not is_player,
		"shield_indicator": item.shielded,
		"shield_broken_indicator": item.shield_broken
	}
	for indicator in indicators:
		var node = visual.visuals.find_child(indicator, true, false)
		if node is CanvasItem and node.visible != indicators[indicator]:
			node.visible = indicators[indicator]


func _update_pockets(data: Dictionary) -> void:
	var pockets: Array[Node] = _table.get_node("Pockets").get_children()
	var present: Dictionary = {}
	var effect_pockets: Dictionary = {}
	var sampled: Dictionary = {}
	for effect in data.pockets:
		if effect.has("pocket_visual"):
			sampled[effect.id] = true
	for state in data.pockets:
		var pocket: Node2D
		if state.base_index >= 0:
			pocket = pockets[state.base_index]
		else:
			present[state.id] = true
			if not _holes.has(state.id):
				_holes[state.id] = _scene_reader.create(_hole_scene)
				_world.add_child(_holes[state.id])
				_holes[state.id].find_child("BlackHole", true, false).show()
			pocket = _holes[state.id]
		effect_pockets[state.id] = pocket
		pocket.global_position = _world.to_global(state.position - data.table_position)
		pocket.rotation = state.rotation
		pocket.scale = state.scale
		if not sampled.has(state.id):
			pocket.modulate = Color("888888") if state.closed else Color.WHITE
		if not sampled.has(state.id):
			pocket.get_node("Label").text = (
				"×"
				if state.closed and not sampled.has(state.id)
				else "x%s" % get_node("/root/Global").format_number(state.multiplier)
			)
		pocket.get_node("ShieldIndicator").visible = state.shielded
		pocket.get_node("SkullIndicator").visible = state.has_held_balls
		var extra_score = pocket.find_child("ExtraScore", true, false)
		extra_score.visible = state.score != 0
		pocket.find_child("ExtraScoreLabel", true, false).text = (
			("+" if state.score > 0 else "") + str(state.score)
		)
	for id in _holes.keys():
		if not present.has(id):
			_holes[id].free()
			_holes.erase(id)
	_effects_view.apply_pockets(data.get("effects", {}), effect_pockets, data.pockets)


func _ability_states() -> Array:
	var balls = _state.get("multiplayer_balls", {})
	var expansion = _state.get("expansion_balls", {})
	return [balls if balls is Dictionary else {}, expansion if expansion is Dictionary else {}]


func _refresh_abilities(data: Dictionary) -> void:
	if not is_instance_valid(_ability):
		return
	var states: Array = _ability_states()
	_ability_offset = data.table_position
	# Redraw only when display state, a tracked ball or the board transform changed.
	var signature: Array = AbilityOverlay.signature(states[0], states[1], [_world.transform], _state.get("cue_feedback", {}))
	for pair in AbilityOverlay.tracked_balls(states[0], states[1]):
		signature.append(_resolve_ability(pair[0], pair[1] - _ability_offset))
	if signature != _ability_signature:
		_ability_signature = signature
		_ability.queue_redraw()


func _resolve_ability(id: int, raw: Vector2) -> Vector2:
	return _balls[id].node.position if _balls.has(id) else raw


func _spectator_name(id: int) -> String:
	for person in _controller.transport.participants():
		if int(person.get("id", 0)) == id:
			return str(person.get("name", "Player")).left(24)
	return "Player"


func _draw_abilities(canvas: CanvasItem) -> void:
	if not is_instance_valid(_world) or not is_watching() or _frames.is_empty():
		return
	var states: Array = _ability_states()
	AbilityOverlay.draw(
		canvas,
		_title.get_theme_font("font"),
		_world.get_global_transform_with_canvas(),
		_resolve_ability,
		_ability_offset,
		_spectator_name,
		states[0],
		states[1],
		0, false, _state.get("cue_feedback", {})
	)


func _layout() -> void:
	_layout_size = _root.size
	var area = Rect2(Vector2(24, 64), _root.size - Vector2(48, 120))
	var factor = minf(area.size.x / _bounds.size.x, area.size.y / _bounds.size.y)
	_world.scale = Vector2.ONE * factor
	_world.position = area.get_center() - _bounds.get_center() * factor


## Lobby-summary delivery can finalize a Bounty while this table is already
## finished. Reconcile once at that boundary, without scanning every render tick.
func refresh_summary() -> void:
	if is_watching() and not _frames.is_empty():
		_update_status(_frames.back().data)


func _update_status(data: Dictionary) -> void:
	var activity = "Shopping" if data.in_shop else "Playing"
	if _state.get("finished", false):
		activity = "Finished"
	var elapsed: int = maxi(0, int(data.results.game_time))
	var text = "Round %d · %d/%d shots · %d used · %02d:%02d · %s" % [
		data.round + 1, data.shots, data.shots_max, data.shots_used,
		elapsed / 60, elapsed % 60, activity
	]
	if _state.get("finished", false) and _controller.lobby.get("match_mode", "score") == "score":
		for summary in _controller.lobby.get("table_summaries", []):
			if summary is Dictionary and summary.get("table") == _table_id:
				var award: String = BountyRace.award_text(summary)
				if award != "":
					text += " · " + award
				break
	if _status.text != text:
		_status.text = text


func _clear_board() -> void:
	_effects_view.dispose()
	_visual_fx_view.clear()
	_native_draw_view.dispose()
	for child in _world.get_children():
		child.free()
	_table = null
	_floor = null
	_shots = -1
	_ui_nodes.clear()
	_ui_state = []
	_layout_size = Vector2.ZERO
	_ability_signature = []
	if is_instance_valid(_ability):
		_ability.queue_redraw()
	_balls.clear()
	_holes.clear()
	_frames.clear()
	_effects_frame = {}
	_scene_key = ""


func _exit_tree() -> void:
	_effects_view.dispose()
	_visual_fx_view.clear()
	_native_draw_view.dispose()


func _hide_named(root: Node, node_name: String) -> void:
	for child in root.find_children(node_name, "", true, false):
		if child is CanvasItem:
			child.hide()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

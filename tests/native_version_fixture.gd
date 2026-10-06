extends RefCounted

const Inventory = preload("../mod/player_inventory_sync.gd")

var _saved_context: Dictionary = {}
var _marker_item: BallItem
var _marker_node: Node2D
var _marker_run: RunState
var _copied_inventory: Dictionary = {}
var _cleared_inventory: Dictionary = {}


func prime_host_context(mod: Node) -> void:
	_prime_context(mod)


func check_host_context(mod: Node, record: Callable) -> void:
	var global_node = mod.get_node("/root/Global")
	record.call(
		not global_node.creative_run and global_node.force_selected_item == null
		and global_node.force_selected_object == null and global_node.chosen_run_state == null,
		"native version: normal multiplayer startup clears inherited Creative mode and selection"
	)
	record.call(
		not mod.run_setup.validate_config({"deck": "Z_CREATIVE", "difficulty": "diff_3", "seed": 24681}),
		"native version: multiplayer normal-run validation excludes the new Creative deck"
	)
	# Host startup deliberately chooses normal mode; do not reapply the synthetic
	# prior Creative flag before its real native game finishes loading.
	_saved_context = {}
	_clear_markers()


func prime_guest_context(mod: Node) -> void:
	_prime_context(mod)


func check_host_passive_copy(mod: Node, game: Node, record: Callable) -> void:
	var database = mod.get_node("/root/BallDatabase")
	var first = BallItem.new()
	first.data = database.id_to_passive["CRISPS"]
	var brain = BallItem.new()
	brain.data = database.id_to_passive["GUMMY-BRAIN"]
	brain.base_score = 0
	var saved_passives: Array[BallItem] = game.player_info.passives
	var fixture_passives: Array[BallItem] = [first, brain, null, null]
	game.player_info.passives = fixture_passives
	var native_passive = load("res://ui/passives/passive_item.tscn").instantiate()
	game.add_child(native_passive)
	native_passive.hide()
	# Exercise the native copy producer, rather than assigning its result in the
	# fixture. Setup mirrors the first passive's effect identity and count display.
	native_passive.setup(brain)
	native_passive.count_up(17)
	record.call(
		brain.copy_id == "CRISPS" and brain.get_id_side(0) == "CRISPS"
		and brain.get_id_list() == ["CRISPS"] and brain.data.id == "GUMMY-BRAIN"
		and native_passive.get_node("ScoreUI").visible
		and native_passive.get_node("%CountLabel").text == "17",
		"native version: real Gummy Brain setup copies Crisps identity and counter behavior"
	)
	_copied_inventory = Inventory.capture(game.player_info)
	record.call(
		Inventory.valid(_copied_inventory, database)
		and _copied_inventory.passives[1].get("copy_id") == "CRISPS",
		"native version: authoritative inventory captures native copied passive identity"
	)
	# Game.go_shop calls this BallItem method before opening the shop. The round
	# passive visual's similarly named method is not the native transition path.
	brain.clear_copy_id()
	_cleared_inventory = Inventory.capture(game.player_info)
	record.call(
		Inventory.valid(_cleared_inventory, database)
		and _cleared_inventory.passives[1].get("copy_id") == ""
		and brain.get_id_side(0) == "GUMMY-BRAIN",
		"native version: native shop-transition clear produces an explicit empty copied identity"
	)
	game.player_info.passives = saved_passives
	native_passive.free()


func check_guest_passive_copy(mod: Node, baseline: Dictionary, record: Callable) -> void:
	if _copied_inventory.is_empty() or _cleared_inventory.is_empty():
		record.call(false, "native version: host copied passive fixtures are available")
		return
	var game = mod.get_node("/root/Global").gameManager
	var stale_first = BallItem.new()
	stale_first.data = mod.get_node("/root/BallDatabase").id_to_passive["CANDY-CORN"]
	var stale_brain = BallItem.new()
	stale_brain.data = mod.get_node("/root/BallDatabase").id_to_passive["GUMMY-BRAIN"]
	stale_brain.set_copy_id("CANDY-CORN")
	var stale_passives: Array[BallItem] = [stale_first, stale_brain, null, null]
	game.player_info.passives = stale_passives
	var copied = baseline.duplicate(true)
	copied.inventory = _copied_inventory.duplicate(true)
	record.call(mod.table_sync.apply_snapshot(copied), "native version: copied passive snapshot accepted")
	var brain = game.player_info.passives[1]
	record.call(
		brain != null and brain != stale_brain and brain.data.id == "GUMMY-BRAIN"
		and brain.copy_id == "CRISPS" and brain.get_id_side(0) == "CRISPS"
		and brain.get_id_list() == ["CRISPS"] and brain.base_score == 17,
		"native version: full guest hydration keeps host copy and count despite stale local first passive"
	)
	mod.table_sync.apply_snapshot(copied)
	record.call(
		game.player_info.passives[1] == brain and brain.copy_id == "CRISPS"
		and brain.base_score == 17,
		"native version: duplicate copied snapshot retains inventory identity without replaying setup"
	)
	var invalid = copied.duplicate(true)
	invalid.inventory.passives[1].copy_id = "PLAYER"
	record.call(
		not mod.table_sync.apply_snapshot(invalid)
		and game.player_info.passives[1] == brain and brain.copy_id == "CRISPS",
		"native version: invalid copied identity is rejected before guest inventory mutation"
	)
	var cleared = baseline.duplicate(true)
	cleared.inventory = _cleared_inventory.duplicate(true)
	record.call(mod.table_sync.apply_snapshot(cleared), "native version: copied passive clear snapshot accepted")
	brain = game.player_info.passives[1]
	record.call(
		brain != null and brain.copy_id == "" and brain.get_id_side(0) == "GUMMY-BRAIN"
		and brain.get_id_list() == ["GUMMY-BRAIN"] and brain.base_score == 17,
		"native version: guest native getters return Gummy Brain after authoritative clear"
	)
	mod.table_sync.apply_snapshot(copied)
	var legacy = copied.duplicate(true)
	legacy.inventory.passives[1].erase("copy_id")
	record.call(mod.table_sync.apply_snapshot(legacy), "native version: legacy inventory without copy field accepted")
	brain = game.player_info.passives[1]
	record.call(
		brain != null and brain.copy_id == "" and brain.get_id_side(0) == "GUMMY-BRAIN",
		"native version: omitted optional copy field clears a previous copied identity"
	)
	record.call(mod.table_sync.apply_snapshot(baseline), "native version: original guest inventory restored")


func check_guest_context(mod: Node, record: Callable) -> void:
	var global_node = mod.get_node("/root/Global")
	record.call(
		not global_node.creative_run and global_node.force_selected_item == null
		and global_node.force_selected_object == null and global_node.chosen_run_state == null,
		"native version: guest session clears local Creative behavior before native hydration"
	)
	record.call(
		mod.table_sync._saved_global.get("creative_run") == true
		and mod.table_sync._saved_global.get("force_selected_item") == _marker_item
		and mod.table_sync._saved_global.get("force_selected_object") == _marker_node
		and mod.table_sync._saved_global.get("chosen_run_state") == _marker_run,
		"native version: guest lifecycle retains original Creative context for restoration"
	)


func check_guest_shop(mod: Node, shop: Node, record: Callable) -> void:
	var ui = mod.get_node("/root/UIManager")
	var popup = ui.creative_popup
	var game = mod.get_node("/root/Global").gameManager
	var before: Dictionary = Inventory.capture(game.player_info)
	var buttons = [
		shop.get_node_or_null("%CreativeBallsButton"),
		shop.tapas_bar.get_node_or_null("%CreativePassivesButton")
	]
	for index in buttons.size():
		var button = buttons[index]
		record.call(
			button != null and not button.visible and button.disabled,
			"native version: replica hides and disables Creative grant button %d" % index
		)
		if button != null:
			# Emitting a disabled button's signal bypasses its normal input guard.
			# There must be no inherited local inventory-grant callback attached.
			button.pressed.emit()
	shop._on_creative_balls_button_pressed()
	record.call(
		not popup.is_open and Inventory.capture(game.player_info) == before,
		"native version: Creative button signals and direct callback cannot open grants or mutate a replica"
	)
	var normal_price = false
	for item in game.player_info.build:
		if item != null and item.get_buy_price() > 0:
			normal_price = true
			break
	record.call(normal_price, "native version: guest native item prices retain normal-run rules")
	# Native solo resources are untouched: only native_shop.gd replica instances
	# replace these callbacks. This also verifies the new API exists in the pack.
	record.call(
		ui.has_method("open_creative") and popup.has_method("_on_get_button_pressed"),
		"native version: native solo Creative API remains installed"
	)


func check_restored_context(mod: Node, record: Callable) -> void:
	var global_node = mod.get_node("/root/Global")
	record.call(
		global_node.creative_run and global_node.force_selected_item == _marker_item
		and global_node.force_selected_object == _marker_node
		and global_node.chosen_run_state == _marker_run,
		"native version: guest teardown restores the pre-session Creative context"
	)
	cleanup(mod)


func cleanup(mod: Node) -> void:
	if not _saved_context.is_empty():
		var global_node = mod.get_node("/root/Global")
		for field in _saved_context:
			global_node.set(field, _saved_context[field])
		_saved_context = {}
	_clear_markers()


func _prime_context(mod: Node) -> void:
	var global_node = mod.get_node("/root/Global")
	for field in ["creative_run", "force_selected_item", "force_selected_object", "chosen_run_state"]:
		_saved_context[field] = global_node.get(field)
	_marker_item = BallItem.new()
	_marker_item.data = mod.get_node("/root/BallDatabase").id_to_ball["PLAYER"]
	_marker_node = Node2D.new()
	_marker_run = RunState.new()
	_marker_run.is_run_creative = true
	global_node.chosen_run_state = _marker_run
	global_node.set_creative(true)
	global_node.force_selected_item = _marker_item
	global_node.force_selected_object = _marker_node


func _clear_markers() -> void:
	if is_instance_valid(_marker_node):
		_marker_node.free()
	_marker_node = null
	_marker_item = null
	_marker_run = null

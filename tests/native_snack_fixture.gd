extends RefCounted
## Native purchase and count producers, then guest/spectator presentation replay.
## Both guest contexts run serially in the single Capture-Screens process.

const Inventory = preload("../mod/player_inventory_sync.gd")


class WatchController:
	extends Node
	var active = true
	var table_id = 0
	var lobby = {"table_count": 3}
	var ui_root: Control
	var skin: RefCounted

	func _table_abandoned(_table: int) -> bool:
		return false


var bought: Dictionary = {}
var bought_round: Dictionary = {}
var counter_before: Dictionary = {}
var counter_after: Dictionary = {}
var native_art: Dictionary = {}


func record_host_counters(mod: Node, game: Node, record: Callable) -> void:
	var database = mod.get_node("/root/BallDatabase")
	var crisps = BallItem.new()
	crisps.data = database.id_to_passive["CRISPS"]
	var brain = BallItem.new()
	brain.data = database.id_to_passive["GUMMY-BRAIN"]
	var saved: Array[BallItem] = game.player_info.passives
	var items: Array[BallItem] = [crisps, brain, null, null]
	game.player_info.passives = items
	var nodes: Array = []
	for item in items:
		if item == null:
			continue
		var node = load("res://ui/passives/passive_item.tscn").instantiate()
		game.add_child(node)
		node.hide()
		node.setup(item)
		node.count_up(17)
		_remember_art(item.data.id, node)
		nodes.append(node)
	counter_before = Inventory.capture(game.player_info)
	record.call(
		crisps.base_score == 17 and brain.base_score == 17 and brain.copy_id == "CRISPS",
		"snack proof: real native Crisps and copied Gummy Brain count producers reach 17"
	)
	for node in nodes:
		node.count_up(8)
	counter_after = Inventory.capture(game.player_info)
	record.call(
		crisps.base_score == 25 and brain.base_score == 25
		and nodes[0].get_node("%CountLabel").text == "25"
		and nodes[1].get_node("%CountLabel").text == "25",
		"snack proof: real native count_up updates both counters from 17 to 25"
	)
	game.player_info.passives = saved
	for node in nodes:
		node.free()


func record_host_shop(mod: Node, record: Callable, capture: Callable) -> Dictionary:
	var sync = mod.shop_sync
	var state: Dictionary = sync.capture().duplicate(true)
	for entry in state.slots:
		if entry.group == "passive" and entry.id != 0:
			bought = entry.duplicate(true)
			break
	if not record.call(not bought.is_empty(), "snack proof: actual transaction leaves an owned snack"):
		return state
	var body = sync.slot_item(bought.key)
	record.call(
		is_instance_valid(body) and body.get_instance_id() == bought.id
		and str(body.get_item().data.id) == bought.data,
		"snack proof: bought host snack preserves the transaction identity and catalog ID"
	)
	_check_shop_item(mod, bought, record, "host")
	var section: String = sync.current_section()
	sync.show_section("snacks")
	await mod.get_tree().create_timer(0.5).timeout
	await capture.call(
		"snack-host-purchased", "Host · purchased %s in the owned snack slots after the real shared transaction" % bought.data
	)
	sync.show_section(section)
	for frame in 45:
		if not sync.native_shop().moving():
			break
		await mod.get_tree().process_frame
	record.call(not sync.native_shop().moving(), "snack proof: host camera settles before Ready transactions")
	return state


func check_guest_shop(mod: Node, record: Callable, capture: Callable) -> void:
	if not record.call(not bought.is_empty(), "snack proof: recorded purchase is available to guest shop"):
		return
	_check_shop_item(mod, bought, record, "guest")
	var sync = mod.shop_sync
	var ids = _shop_ids(sync)
	var inventory: Dictionary = sync._state.duplicate(true)
	record.call(sync.apply_state(inventory), "snack proof: repeated purchased shop state is accepted")
	record.call(_shop_ids(sync) == ids, "snack proof: unchanged purchased shop state retains native items")
	var section: String = sync.current_section()
	sync.show_section("snacks")
	await mod.get_tree().create_timer(0.5).timeout
	await capture.call(
		"snack-guest-purchased", "Guest · same purchased %s and owned slot from the authoritative shop state" % bought.data
	)
	sync.show_section(section)
	await mod.get_tree().create_timer(0.5).timeout


func record_host_round(mod: Node, record: Callable, capture: Callable) -> void:
	var game = mod.get_node("/root/Global").gameManager
	bought_round = mod.table_sync.capture().duplicate(true)
	if not record.call(not bought.is_empty(), "snack proof: actual purchased identity is available at round start"):
		return
	var inventory: Dictionary = bought_round.inventory
	var slot: int = int(bought.index)
	if not record.call(
		inventory.passives[slot] != null and inventory.passives[slot].data == bought.data,
		"snack proof: real Ready transition moves the purchased snack into authoritative round inventory"
	):
		return
	var manager = game.table.get_cursed_balls_manager()
	var found: Node2D = null
	for node in manager.all_passive_balls:
		if is_instance_valid(node) and node is PassiveItem and str(node.get_item().data.id) == bought.data:
			found = node
			break
	if record.call(found != null and found.is_visible_in_tree(), "snack proof: host native table displays the bought snack plate"):
		_remember_art(bought.data, found)
	await capture.call(
		"snack-host-table", "Host · purchased %s displayed on the native snack rail beside the table" % bought.data
	)


func check_guest(mod: Node, baseline: Dictionary, record: Callable, capture: Callable) -> void:
	if not record.call(not bought_round.is_empty(), "snack proof: real purchased next-round snapshot is recorded"):
		return
	var packet: Dictionary = bytes_to_var(var_to_bytes(bought_round))
	record.call(mod.table_sync.apply_snapshot(packet), "snack proof: first guest accepts serialized purchased-round inventory")
	var game = mod.get_node("/root/Global").gameManager
	_check_view(mod, game.passives_view, packet.inventory, record, "first guest purchased")
	await capture.call(
		"snack-guest-table", "Guest · purchased %s restored from the host snapshot on the same native snack rail" % bought.data
	)
	var before = baseline.duplicate(true)
	before.inventory = counter_before.duplicate(true)
	var after = baseline.duplicate(true)
	after.inventory = counter_after.duplicate(true)
	var side_effects = _side_effects(mod)
	record.call(mod.table_sync.apply_snapshot(before), "snack proof: guest accepts native 17-count inventory")
	_check_view(mod, game.passives_view, before.inventory, record, "guest count 17")
	await capture.call("snack-guest-count-17", "Guest · native Crisps and copied Gummy Brain counters at 17")
	var identities = _ids(game.passives_view)
	record.call(mod.table_sync.apply_snapshot(after), "snack proof: guest accepts native 25-count update")
	_check_view(mod, game.passives_view, after.inventory, record, "guest count 25")
	record.call(_ids(game.passives_view) == identities, "snack proof: counter update retains every native card")
	await capture.call("snack-guest-count-25", "Guest · the same native snack cards update from 17 to 25 without recreation")
	mod.table_sync.apply_snapshot(after)
	record.call(
		_ids(game.passives_view) == identities and Inventory.capture(game.player_info) == after.inventory,
		"snack proof: duplicate snapshot keeps cards, authoritative count and copied identity"
	)
	var reordered = after.duplicate(true)
	reordered.inventory.passives = [after.inventory.passives[1], null, after.inventory.passives[0], null]
	record.call(mod.table_sync.apply_snapshot(reordered), "snack proof: guest accepts snack slot reorder and removal")
	_check_view(mod, game.passives_view, reordered.inventory, record, "guest reordered")
	var next = after.duplicate(true)
	next.rounds_played += 1
	next.inventory.passives[0].base_score = 0
	next.inventory.passives[1].base_score = 0
	record.call(mod.table_sync.apply_snapshot(next), "snack proof: guest accepts authoritative new-round counter reset")
	_check_view(mod, game.passives_view, next.inventory, record, "guest next round")
	var empty = baseline.duplicate(true)
	empty.inventory.passives = [null, null, null, null]
	record.call(mod.table_sync.apply_snapshot(empty), "snack proof: guest accepts complete snack removal")
	record.call(game.passives_view.entries.is_empty(), "snack proof: removal leaves no active snack cards")
	var full = _four_slots(after, packet)
	record.call(mod.table_sync.apply_snapshot(full), "snack proof: guest accepts four native-derived occupied snack slots")
	_check_view(mod, game.passives_view, full.inventory, record, "guest full rail")
	record.call(
		_side_effects(mod) == side_effects,
		"snack proof: guest presentation creates no native event registrations, queued events or achievement changes"
	)
	await _check_spectator(mod, packet, before, after, record, capture)
	record.call(mod.table_sync.apply_snapshot(baseline), "snack proof: guest baseline restored after presentation checks")


func check_routed_guest_round(mod: Node, record: Callable, capture: Callable) -> void:
	var game = mod.get_node("/root/Global").gameManager
	var actual = Inventory.capture(game.player_info)
	record.call(
		not bought_round.is_empty() and actual.passives == bought_round.inventory.passives,
		"snack proof: second fresh guest context receives the bought snack through routed round-flow messages"
	)
	_check_view(mod, game.passives_view, actual, record, "second routed guest purchased")
	await capture.call(
		"snack-guest-routed-table", "Fresh guest replica · the bought snack remains visible after routed Ready and delayed old shop messages"
	)


func _check_spectator(
	mod: Node, purchased: Dictionary, before: Dictionary, after: Dictionary,
	record: Callable, capture: Callable
) -> void:
	var controller = WatchController.new()
	controller.ui_root = mod.ui_root
	controller.skin = mod.skin
	mod.add_child(controller)
	var spectator = load(get_script().resource_path.get_base_dir().path_join("../mod/table_spectator.gd")).new()
	controller.add_child(spectator)
	spectator.setup(controller)
	var side_effects = _side_effects(mod)
	record.call(spectator.watch(1), "snack proof: spectator watches the purchased-snack table")
	_watch_apply(spectator, purchased)
	await mod.get_tree().process_frame
	spectator.tick(0.0)
	_check_view(mod, spectator._passives_view, purchased.inventory, record, "spectator purchased")
	_check_spectator_bounds(spectator, record, "purchased")
	await capture.call(
		"snack-spectator-purchased", "Spectator · the same purchased snack appears on the watched table"
	)
	_watch_apply(spectator, before)
	_check_view(mod, spectator._passives_view, before.inventory, record, "spectator count 17")
	var identities = _ids(spectator._passives_view)
	_watch_apply(spectator, after)
	_check_view(mod, spectator._passives_view, after.inventory, record, "spectator count 25")
	_check_spectator_bounds(spectator, record, "count 25")
	record.call(_ids(spectator._passives_view) == identities, "snack proof: spectator counter update retains cards")
	await capture.call("snack-spectator-count-25", "Spectator · native Crisps and copied Gummy Brain counters update to 25")
	var shopping = after.duplicate(true)
	shopping.in_shop = true
	_watch_apply(spectator, shopping)
	_check_view(mod, spectator._passives_view, shopping.inventory, record, "spectator shopping")
	_check_spectator_bounds(spectator, record, "shopping")
	# Use the existing watcher's native table-variant lifecycle. These synthetic
	# full-slot descriptors reuse real native count/purchase entries; they test the
	# visual scene and do not claim a host gameplay run on the rotated board.
	var full = _four_slots(after, purchased)
	_watch_apply(spectator, full)
	_check_view(mod, spectator._passives_view, full.inventory, record, "spectator full rail")
	_check_spectator_bounds(spectator, record, "full rail")
	for rotated in [not full.rotated, full.rotated]:
		var old_cards: Array = []
		for entry in spectator._passives_view.entries.values():
			old_cards.append(entry.node)
		var variant = full.duplicate(true)
		variant.rotated = rotated
		_watch_apply(spectator, variant)
		var freed = true
		for node in old_cards:
			freed = freed and not is_instance_valid(node)
		record.call(freed, "snack proof: table variant replacement disposes every previous snack card")
		var label = "rotated full rail" if rotated else "standard full rail after rebuild"
		_check_view(mod, spectator._passives_view, variant.inventory, record, label)
		_check_spectator_bounds(spectator, record, label)
		if rotated:
			_check_rotated_scene(mod, spectator, record)
	record.call(_side_effects(mod) == side_effects, "snack proof: watching snacks preserves native events and achievements")
	spectator.watch(2)
	record.call(spectator._passives_view.entries.is_empty(), "snack proof: switching watched tables clears active snack cards")
	spectator.apply_snapshot(2, purchased)
	spectator.tick(0.0)
	_check_view(mod, spectator._passives_view, purchased.inventory, record, "spectator after switch")
	spectator.close()
	record.call(spectator._passives_view.entries.is_empty(), "snack proof: spectator teardown releases its snack view")
	controller.free()


func _four_slots(counted: Dictionary, purchased: Dictionary) -> Dictionary:
	var full = counted.duplicate(true)
	full.inventory.passives[2] = counter_before.passives[0].duplicate(true)
	full.inventory.passives[3] = purchased.inventory.passives[int(bought.index)].duplicate(true)
	return full


func _check_spectator_bounds(spectator: Node, record: Callable, label: String) -> void:
	# Inspect what Godot actually transforms onto the viewport. Do not use the
	# renderer's get_bounds() as the oracle for the layout calculated from it.
	var viewport: Rect2 = spectator.get_viewport().get_visible_rect()
	for slot in spectator._passives_view.entries:
		var entry: Dictionary = spectator._passives_view.entries[slot]
		for field in ["plate", "item", "item_shadow"]:
			var sprite: Sprite2D = entry[field]
			var drawn: Rect2 = sprite.get_global_transform_with_canvas() * sprite.get_rect()
			record.call(
				sprite.is_visible_in_tree() and drawn.has_area() and viewport.encloses(drawn),
				"snack proof: spectator %s slot %d %s artwork is fully onscreen" % [label, slot, field]
			)
		if entry.score_ui.visible:
			var counter: Label = entry.count_label
			var drawn: Rect2 = counter.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, counter.size)
			record.call(
				counter.is_visible_in_tree() and drawn.has_area() and viewport.encloses(drawn),
				"snack proof: spectator %s slot %d counter is fully onscreen" % [label, slot]
			)


func _check_rotated_scene(mod: Node, spectator: Node, record: Callable) -> void:
	record.call(
		not spectator._table.has_node("Tutorial/Intro2")
		and not spectator._table.has_node("Tutorial/Score"),
		"snack proof: rotated scene skips orphan native tutorial overrides instead of manufacturing nodes"
	)
	# Independent native SceneState oracle: a valid inherited override must still
	# apply even though the same rotated asset contains obsolete sibling paths.
	var scene: PackedScene = mod.get_node("/root/Global").gameManager.table_rotated_scene
	var state = scene.get_state()
	var expected = null
	for index in state.get_node_count():
		if str(state.get_node_path(index)).trim_prefix("./") != "Tutorial/Intro/HighlightPoint":
			continue
		for property in state.get_node_property_count(index):
			if state.get_node_property_name(index, property) == "position":
				expected = state.get_node_property_value(index, property)
	var point = spectator._table.get_node_or_null("Tutorial/Intro/HighlightPoint")
	record.call(
		expected is Vector2 and point is Node2D and point.position.is_equal_approx(expected),
		"snack proof: rotated scene preserves the existing tutorial node's native position override"
	)


func _watch_apply(spectator: Node, packet: Dictionary) -> void:
	spectator._frames.clear()
	spectator.apply_snapshot(1, bytes_to_var(var_to_bytes(packet)))
	spectator.tick(0.0)


func _check_view(mod: Node, view, inventory: Dictionary, record: Callable, label: String) -> void:
	var count = 0
	var database = mod.get_node("/root/BallDatabase")
	record.call(
		view._pool.size() == inventory.passives.size(),
		"snack proof: %s native scene prepares a reusable card for every inventory slot" % label
	)
	for slot in inventory.passives.size():
		var item = inventory.passives[slot]
		if item == null:
			record.call(not view.entries.has(slot), "snack proof: %s empty slot %d has no card" % [label, slot])
			continue
		count += 1
		if not record.call(view.entries.has(slot), "snack proof: %s displays owned slot %d" % [label, slot]):
			continue
		var entry: Dictionary = view.entries[slot]
		var resource = database.id_to_passive[item.data]
		var counted = resource.passive_has_number_in_round
		if item.data == "GUMMY-BRAIN":
			counted = item.get("copy_id", "") != "" and database.id_to_passive[item.copy_id].passive_has_number_in_round
		record.call(
			entry.node.is_visible_in_tree() and entry.item.texture == resource.texture
			and entry.item_shadow.texture == resource.texture,
			"snack proof: %s slot %d uses the visible native snack and shadow textures" % [label, slot]
		)
		if native_art.has(item.data):
			record.call(entry.plate.texture == native_art[item.data].plate, "snack proof: %s slot %d preserves native rarity plate" % [label, slot])
		record.call(
			entry.score_ui.visible == counted and (not counted or entry.count_label.text == str(item.base_score)),
			"snack proof: %s slot %d renders the authoritative native counter" % [label, slot]
		)
		record.call(_visual_only(entry.node), "snack proof: %s slot %d has no gameplay scripts or bodies" % [label, slot])
	record.call(view.entries.size() == count and count <= 4, "snack proof: %s renders exactly the bounded owned slots" % label)


func _check_shop_item(mod: Node, entry: Dictionary, record: Callable, label: String) -> void:
	var body = mod.shop_sync.slot_item(entry.key)
	if not record.call(is_instance_valid(body), "snack proof: %s native shop contains the bought owned slot" % label):
		return
	var expected = mod.get_node("/root/BallDatabase").id_to_passive[entry.data]
	var image = body.find_child("Item", true, false)
	record.call(
		str(body.get_item().data.id) == entry.data and image != null
		and image.texture == expected.texture and image.is_visible_in_tree(),
		"snack proof: %s owned shop snack shows its native catalog art" % label
	)


func _remember_art(id: String, node: Node) -> void:
	native_art[id] = {"plate": node.get_node("PassiveVisuals/Plate").texture}


func _shop_ids(sync: Node) -> Dictionary:
	var result = {}
	for entry in sync._state.slots:
		if entry.id != 0:
			var item = sync.slot_item(entry.key)
			if is_instance_valid(item):
				result[entry.key] = item.get_instance_id()
	return result


func _ids(view) -> Dictionary:
	var result = {}
	for slot in view.entries:
		result[slot] = view.entries[slot].node.get_instance_id()
	return result


func _side_effects(mod: Node) -> Array:
	var events = mod.get_node("/root/Global").eventManager
	var event_state: Array = []
	if is_instance_valid(events):
		event_state = [events.get_instance_id(), events._q_tail, events._listener_counts.duplicate(true)]
	var save = mod.get_node("/root/SaveManager").save
	return [event_state, save.achievement_progress.duplicate(true), save.unlocked_achievements.duplicate(true)]


func _visual_only(node: Node) -> bool:
	if node.get_script() != null or node is CollisionObject2D or node is Camera2D:
		return false
	for child in node.get_children():
		if not _visual_only(child):
			return false
	return true

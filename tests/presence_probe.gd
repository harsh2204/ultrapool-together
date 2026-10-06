extends SceneTree

var checks = 0
var failures: Array[String] = []


class ControllerStub:
	extends Node
	var match_id = 4
	var table_id = 0
	var turn_owner = 2
	var context: Array = [7, 2, 3]
	var tables = {1: 0, 2: 0, 3: 1}

	func player_table(actor: int) -> int:
		return tables.get(actor, -1)

	func aim_view_context() -> Array:
		return context


class TransportStub:
	extends Node
	const MAX_PLAYERS = 8
	var is_host = false
	var sent: Array = []

	func local_id() -> int:
		return 1

	func host_id() -> int:
		return 9

	func connected_peers() -> Array:
		return [2, 3]

	func send_to(actor: int, message: Dictionary, unreliable: bool) -> void:
		sent.append([actor, message.duplicate(true), unreliable])


func _initialize() -> void:
	var base = get_script().resource_path.get_base_dir()
	var lobby_ui = load(base.path_join("../mod/lobby_scene.gd"))
	var shop = load(base.path_join("../mod/shop_sync.gd"))
	_check(lobby_ui != null and lobby_ui.can_instantiate(), "lobby scene script loads")
	_check(shop != null, "shop sync script loads")

	var seat_a = lobby_ui.player_color_for(0, 0, 10)
	var seat_b = lobby_ui.player_color_for(0, 1, 20)
	var seat_c = lobby_ui.player_color_for(0, 2, 30)
	_check(seat_a != seat_b and seat_b != seat_c and seat_a != seat_c, "same-table seats get distinct cursor colors")
	_check(seat_a == lobby_ui.TABLE_COLORS[0], "seat 0 uses the first shared palette color")
	_check(seat_b == lobby_ui.TABLE_COLORS[1], "seat 1 uses the second shared palette color")
	_check(
		lobby_ui.player_color_for(0, 0, 99) == seat_a,
		"cursor color follows seat, not Steam or ENet id"
	)
	_check(
		lobby_ui.player_color_for(1, 0, 40) == seat_a,
		"matching seats reuse the palette entry across tables"
	)

	var unseated = lobby_ui.player_color_for(-1, -1, 55)
	var other = lobby_ui.player_color_for(-1, -1, 56)
	_check(
		unseated == Color.from_hsv(posmod(hash(str(55)), 360) / 360.0, 0.55, 1.0),
		"unseated players fall back to a stable id hash color"
	)
	_check(unseated != other, "unseated fallback colors still differ by id")

	var offer = shop.presence_slot_key("offer", 2)
	var build = shop.presence_slot_key("build", 0)
	_check(offer == "offer:2" and build == "build:0", "shop presence targets use group:index keys")
	var slots = {offer: true, build: true}
	_check(
		shop.presence_target_resolves(slots, offer, true),
		"known shop presence targets resolve while the shop is open"
	)
	_check(
		not shop.presence_target_resolves(slots, offer, false),
		"shop presence targets do not resolve when the shop panel is hidden"
	)
	_check(
		not shop.presence_target_resolves(slots, "snack:9", true),
		"unknown shop presence targets do not resolve"
	)
	_check(
		not shop.presence_target_resolves(slots, "", true),
		"empty shop presence targets do not resolve"
	)
	_check_native_aim_presence(base)

	print("PRESENCE_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check_native_aim_presence(base: String) -> void:
	var presence = load(base.path_join("../mod/presence.gd")).new()
	var controller = ControllerStub.new()
	var transport = TransportStub.new()
	presence._controller = controller
	presence._transport = transport
	var message = {
		"kind": "presence", "match": 4, "table": 0, "actor": 2, "seq": 10,
		"space": "table", "target": "", "aiming": true, "cue": "default",
		"position": Vector2(100, 100), "origin": Vector2(80, 80),
		"vector": Vector2(120, 30), "aim_context": [7, 2, 3]
	}
	# Use the production default ID rather than assuming a catalog key.
	message.cue = presence.CueCatalog.DEFAULT_ID
	presence.receive(9, message)
	_check(presence.remote_aim(2).get("vector") == message.vector, "current owner and committed board context expose native aim")
	controller.turn_owner = 3
	_check(presence.remote_aim(2).is_empty(), "off-turn cursor cannot drive prediction")
	controller.turn_owner = 2
	controller.context = []
	_check(presence.remote_aim(2).is_empty(), "incomplete board hides remote prediction")
	controller.context = [8, 2, 3]
	_check(presence.remote_aim(2).is_empty(), "delayed previous-turn aim cannot draw on the next turn")
	controller.context = [7, 3, 4]
	_check(presence.remote_aim(2).is_empty(), "old-rack aim cannot draw on the next round")
	controller.context = [7, 2, 3]
	controller.match_id = 5
	_check(presence.remote_aim(2).is_empty(), "read-time match change hides old aim before the next presence tick")
	controller.match_id = 4
	controller.table_id = 1
	_check(presence.remote_aim(2).is_empty(), "read-time table change hides old aim before the next presence tick")
	controller.table_id = 0
	controller.tables[2] = 1
	_check(presence.remote_aim(2).is_empty(), "roster reassignment invalidates cached aim immediately")
	controller.tables[2] = 0
	presence._remotes[2].age = presence.STALE_SECONDS
	_check(presence.remote_aim(2).is_empty(), "expired aim hides native prediction")
	var older = message.duplicate(true)
	older.seq = 9
	presence.receive(9, older)
	_check(presence.remote_aim(2).is_empty(), "reordered packet cannot revive expired aim")
	var release = message.duplicate(true)
	release.seq = 11
	release.aiming = false
	release.aim_context = []
	presence.receive(9, release)
	presence.receive(9, message)
	_check(presence.remote_aim(2).is_empty(), "late aim cannot overwrite a newer release")
	var legacy = message.duplicate(true)
	legacy.seq = 12
	legacy.erase("aim_context")
	presence.receive(9, legacy)
	_check(presence._remotes[2].message.seq == 12 and presence.remote_aim(2).is_empty(), "legacy cursor remains compatible without unscoped prediction")
	for invalid in [[7, 2], [7, 2, -1], [7, 2, 3.0], "7,2,3", [7, 2, 3, 4]]:
		var malformed = message.duplicate(true)
		malformed.seq = 13
		malformed.aim_context = invalid
		presence.receive(9, malformed)
		_check(presence._remotes[2].message.seq == 12, "malformed aim context is rejected: %s" % str(invalid))
	var fresh = message.duplicate(true)
	fresh.seq = 13
	presence.receive(2, fresh)
	_check(presence._remotes[2].message.seq == 12, "guests accept presence only from host relay")
	fresh.actor = 3
	presence.receive(9, fresh)
	_check(not presence._remotes.has(3), "other-table identity cannot aim on this board")
	fresh.actor = 2
	fresh.match = 3
	presence.receive(9, fresh)
	_check(presence._remotes[2].message.seq == 12, "old-match packet cannot revive prediction")
	fresh.match = 4
	presence.receive(9, fresh)
	_check(not presence.remote_aim(2).is_empty(), "newer current-context keepalive restores expired aim")
	presence._last_sent = message.duplicate(true)
	presence._send_age = 0.1
	_check(not presence._should_send(message), "unchanged held aim avoids tick-rate traffic")
	presence._send_age = presence.KEEPALIVE_INTERVAL
	_check(presence._should_send(message), "unchanged held aim refreshes before expiration")
	var changed = message.duplicate(true)
	changed.aim_context = [8, 2, 3]
	presence._send_age = 0.0
	_check(presence._should_send(changed), "same coordinates in a new turn send immediately")
	var hidden = release.duplicate(true)
	hidden.space = "none"
	presence._last_sent = hidden
	presence._send_age = 10.0
	_check(not presence._should_send(hidden), "hidden idle presence does not send keepalives")
	controller.table_id = 1
	presence._sync_session()
	_check(presence._remotes.is_empty() and presence._last_sent.is_empty(), "table transition clears old aim and dirty state")
	controller.table_id = 0
	transport.is_host = true
	var spoofed = message.duplicate(true)
	spoofed.actor = 3
	spoofed.table = 1
	presence.receive(2, spoofed)
	_check(presence._remotes.is_empty() and transport.sent.is_empty(), "host rejects a delayed or spoofed table instead of relabeling it")
	spoofed.table = 0
	presence.receive(2, spoofed)
	_check(not presence.remote_aim(2).is_empty() and not presence._remotes.has(3), "host derives actor from authenticated sender on the matching table")
	presence._remove_peer(2, "left")
	_check(presence._remotes.is_empty(), "disconnect removes native aim")
	presence._last_sent = message
	presence.clear()
	_check(presence._last_sent.is_empty() and presence._should_send(message), "clear resends unchanged coordinates after reconnect")
	presence.free()
	controller.free()
	transport.free()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

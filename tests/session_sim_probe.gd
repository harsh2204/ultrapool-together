extends SceneTree

# Several real controllers, transports, lobby models, routers, and recovery
# services exchange encoded packets through a simulated Steam room. Native game
# scenes are replaced by recording stubs, so only session behavior is exercised.
const Transport = preload("../mod/transport.gd")
const LobbyState = preload("../mod/lobby_state.gd")
const TableRouter = preload("../mod/table_router.gd")
const TableRecovery = preload("../mod/table_recovery.gd")
const RunCheckpoint = preload("../mod/run_checkpoint.gd")
const LOBBY_ID = 424242
const ROOM_CODE = "UP9-424242"
const CONFIG = {"deck": "", "difficulty": "", "run_mode": "normal", "seed": 24681}
const PUMP_FRAMES = 60


class SteamRoom:
	extends RefCounted
	var members: Array = []
	var owner = 0
	var data: Dictionary = {}
	var endpoints: Dictionary = {}
	var blocked: Dictionary = {}

	func create(id: int) -> void:
		members = [id]
		owner = id
		data.clear()

	func join(id: int) -> bool:
		if members.is_empty() or members.size() >= 8:
			return false
		if id not in members:
			members.append(id)
		_notify(id, 1)
		return true

	func leave(id: int) -> void:
		if id not in members:
			return
		members.erase(id)
		if owner == id:
			owner = members[0] if not members.is_empty() else 0
		_notify(id, 2)

	func deliver(from: int, to: int, packet: PackedByteArray, channel: int) -> int:
		var target = endpoints.get(to)
		if target == null or blocked.has([from, to]) or from not in members:
			return 1
		target.enqueue(from, packet, channel)
		return 1

	func cut(first: int, second: int) -> void:
		blocked[[first, second]] = true
		blocked[[second, first]] = true

	func heal(first: int, second: int) -> void:
		blocked.erase([first, second])
		blocked.erase([second, first])

	func _notify(changed: int, state: int) -> void:
		for member in members:
			if endpoints.has(member):
				endpoints[member].callbacks.append(["chat", changed, state])


# Match GodotSteam's API spelling.
# gdlint: disable=function-name
class FakeSteam:
	extends RefCounted
	var room: SteamRoom
	var id = 0
	var transport: Node
	var callbacks: Array = []
	var incoming = {47: [], 48: []}
	var accepted: Dictionary = {}
	var requested: Dictionary = {}

	func enqueue(from: int, packet: PackedByteArray, channel: int) -> void:
		incoming[channel].append({"identity": from, "payload": packet})
		if not accepted.has(from) and not requested.has(from):
			requested[from] = true
			callbacks.append(["session", from])

	func run_callbacks() -> void:
		var queued = callbacks
		callbacks = []
		for callback in queued:
			match callback[0]:
				"chat":
					transport._on_lobby_chat_update(LOBBY_ID, callback[1], callback[1], callback[2])
				"session":
					requested.erase(callback[1])
					transport._on_steam_request(callback[1])
				"created":
					transport._on_lobby_created(1, LOBBY_ID)
				"joined":
					transport._on_lobby_joined(LOBBY_ID, 0, false, callback[1])

	func receiveMessagesOnChannel(channel: int, _maximum: int) -> Array:
		var queue: Array = incoming[channel]
		for index in queue.size():
			if accepted.has(queue[index].identity):
				return [queue.pop_at(index)]
		return []

	func acceptSessionWithUser(peer: int) -> void:
		accepted[peer] = true

	func closeChannelWithUser(peer: int, channel: int) -> void:
		accepted.erase(peer)
		incoming[channel] = incoming[channel].filter(func(entry): return entry.identity != peer)

	func sendMessageToUser(to: int, packet: PackedByteArray, _flags: int, channel: int) -> int:
		return room.deliver(id, to, packet, channel)

	func getSteamID() -> int:
		return id

	func getLobbyOwner(_lobby: int) -> int:
		return room.owner

	func getLobbyData(_lobby: int, key: String) -> String:
		return room.data.get(key, "")

	func setLobbyData(_lobby: int, key: String, value: String) -> bool:
		room.data[key] = value
		return true

	func setLobbyJoinable(_lobby: int, _joinable: bool) -> bool:
		return true

	func getNumLobbyMembers(_lobby: int) -> int:
		return room.members.size()

	func getLobbyMemberByIndex(_lobby: int, index: int) -> int:
		return room.members[index]

	func getFriendPersonaName(peer: int) -> String:
		return "Player %d" % peer

	func createLobby(_type: int, _capacity: int) -> void:
		room.create(id)
		callbacks.append(["created"])

	func joinLobby(_lobby: int) -> void:
		callbacks.append(["joined", 1 if room.join(id) else 5])

	func leaveLobby(_lobby: int) -> void:
		room.leave(id)


class SimController:
	extends "../mod/main.gd"

	func _native_blocked() -> bool:
		return false


class AdapterStub:
	extends Node

	func game_data() -> Dictionary:
		return {
			"available": true,
			"table_active": true,
			"can_shoot": false,
			"settled": true,
			"in_shop": true,
			"in_menu": false,
			"game_over": false,
			"round_result_open": false,
			"run_won": false,
			"run_goal_rounds": 10,
			"round_ended": false,
			"round_finalized": false,
			"round": 3,
			"rounds_played": 2,
			"shots_left": 4,
			"score": 0.0
		}

	func begin_session(_controller) -> void:
		pass

	func end_session() -> void:
		pass

	func can_shoot() -> bool:
		return false


class TableStub:
	extends Node
	var guest_begins = 0

	func begin_guest(_config: Dictionary = {}) -> bool:
		guest_begins += 1
		return true

	func end_guest() -> void:
		pass

	func capture() -> Dictionary:
		return {"available": false}

	func _valid_snapshot(data: Dictionary) -> bool:
		return data.get("available") is bool

	func apply_snapshot(data: Dictionary) -> bool:
		return _valid_snapshot(data)


class ShopStub:
	extends Node

	func begin_session(_controller) -> void:
		pass

	func end_session() -> void:
		pass

	func capture() -> Dictionary:
		return {"open": false, "revision": 1}

	func apply_state(_data: Dictionary) -> bool:
		return true

	func apply_result(_accepted, _error, _id, _shop) -> void:
		pass

	func is_open() -> bool:
		return false

	func exclusive_shopper() -> int:
		return 0

	func set_exclusive_shopper(_id: int) -> void:
		pass

	func clear_exclusive_shopper() -> void:
		pass


class BallServiceStub:
	extends Node
	var catalog = null

	func begin_session(_flags = null) -> void:
		pass

	func end_session() -> void:
		pass

	func prepare_shop() -> void:
		pass

	func bounty_shot() -> int:
		return 0

	func capture() -> Dictionary:
		return {}

	func display_signature(_state) -> Array:
		return []

	func valid_state(_state) -> bool:
		return true

	func apply_state(_state) -> bool:
		return true

	func blocks_shot_input() -> bool:
		return false

	func begin_shot(_shot: int, _player: int) -> bool:
		return true

	func finish_shot() -> void:
		pass


class SetVotingStub:
	extends Node

	func begin_session() -> void:
		pass

	func end_session() -> void:
		pass

	func handle_table_message(_actor: int, _message: Dictionary) -> void:
		pass


class PresenceStub:
	extends Node

	func clear() -> void:
		pass

	func receive(_sender: int, _message: Dictionary) -> bool:
		return false


class RunStub:
	extends Node
	var starts: Array = []
	var catalog: Dictionary

	func at_main_menu() -> bool:
		return true

	func available_choices() -> Dictionary:
		return catalog

	func native_defaults() -> Dictionary:
		return {"deck": catalog.deck[0].id, "difficulty": catalog.difficulty[0].id}

	func capture_config(selection: Dictionary) -> Dictionary:
		var config: Dictionary = CONFIG.duplicate()
		config.deck = selection.deck
		config.difficulty = selection.difficulty
		return config

	func validate_config(config: Dictionary) -> bool:
		return config.get("deck") is String and not config.deck.is_empty()

	func start(_config: Dictionary, _catalog = null, run_state = null) -> Error:
		starts.append(run_state)
		return OK

	func ready_for_input() -> bool:
		return true

	func cancel() -> void:
		pass

	func return_menu() -> Error:
		return OK


class SpectatorStub:
	extends Node
	var watched_table = -1

	func is_watching() -> bool:
		return false

	func close() -> void:
		pass


class RunControlsStub:
	extends Node

	func begin_session() -> void:
		pass

	func end_session() -> void:
		pass


class PanelStub:
	extends Control

	func set_status(_value: String) -> void:
		pass

	func set_connection(_code: String, _open: bool, _invite: bool) -> void:
		pass

	func set_rejoin(_code: String) -> void:
		pass

	func render(_lobby: Dictionary, _local_id: int, _host: bool) -> void:
		pass


var checks = 0
var failures: Array[String] = []
var _room: SteamRoom
var _peers: Dictionary = {}
var _database: Node
var _catalog: Dictionary


func _initialize() -> void:
	_database = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("BallDatabase")
	if _database == null:
		_check(false, "session simulation runs with the native catalogs")
		_finish()
		return
	var decks: Array = _database.id_to_deck.keys().filter(func(id): return str(id) != "DAILY")
	_catalog = {
		"deck": [{"id": str(decks[0]), "label": "Deck"}],
		"difficulty": [{"id": str(_database.id_to_difficulty.keys()[0]), "label": "Difficulty"}]
	}
	_match_recovery()
	_lobby_migration_before_start()
	_finish()


func _finish() -> void:
	for id in _peers.keys():
		_crash(id, true)
	print("SESSION_SIM_PROBE %s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _spawn(id: int) -> Node:
	var controller = SimController.new()
	controller.set_process(false)
	var transport = Transport.new()
	var steam = FakeSteam.new()
	steam.room = _room
	steam.id = id
	steam.transport = transport
	transport._steam = steam
	_room.endpoints[id] = steam
	var run = RunStub.new()
	run.catalog = _catalog
	var recovery = TableRecovery.new()
	recovery.rejoin_path = "user://session_sim_rejoin_%d.cfg" % id
	recovery.setup(_database)
	controller.transport = transport
	controller.adapter = AdapterStub.new()
	controller.table_sync = TableStub.new()
	controller.shop_sync = ShopStub.new()
	controller.presence = PresenceStub.new()
	controller.run_setup = run
	controller.spectator = SpectatorStub.new()
	controller.run_controls = RunControlsStub.new()
	controller.recovery = recovery
	controller.multiplayer_balls = BallServiceStub.new()
	controller.expansion_balls = BallServiceStub.new()
	controller.set_voting = SetVotingStub.new()
	controller.panel = PanelStub.new()
	controller.pass_button = Button.new()
	controller.turn_label = Label.new()
	controller.score_label = Label.new()
	for dependency in [
		transport,
		controller.adapter,
		controller.table_sync,
		controller.shop_sync,
		controller.presence,
		run,
		controller.spectator,
		controller.run_controls,
		recovery,
		controller.multiplayer_balls,
		controller.expansion_balls,
		controller.set_voting,
		controller.panel,
		controller.pass_button,
		controller.turn_label,
		controller.score_label
	]:
		controller.add_child(dependency)
	controller.lobby_model = LobbyState.new()
	controller.router = TableRouter.new()
	controller._connect_transport()
	_peers[id] = controller
	return controller


# A crash leaves the Steam room without a goodbye packet and keeps its rejoin memory.
func _crash(id: int, cleanup: bool = false) -> void:
	var controller = _peers.get(id)
	if controller == null:
		return
	_peers.erase(id)
	_room.endpoints.erase(id)
	_room.leave(id)
	if cleanup:
		controller.recovery.forget()
	controller.free()


func _pump(frames: int = PUMP_FRAMES) -> void:
	for _frame in frames:
		for id in _peers.keys():
			if _peers.has(id):
				_peers[id].transport._process(0.016)


func _settle(controller) -> void:
	controller._returning_to_menu = false
	controller._process_pending_begin()
	_pump()


func _reconnect_now(controllers: Array) -> void:
	for controller in controllers:
		controller.transport._reconnect_at = 0
	_pump()


func _checkpoint(controller, revision: int) -> void:
	var state = RunState.new()
	state.money = 10 + controller.table_id
	state.hp = 3
	state.seed = CONFIG.seed
	state.seed_text = str(CONFIG.seed)
	state.level_number = 2
	state.rounds_played = 2
	state.chosen_deck_id = _catalog.deck[0].id
	state.chosen_difficulty_id = _catalog.difficulty[0].id
	state.is_run_seeded = true
	state.run_id = "table-%d" % controller.table_id
	var run = RunCheckpoint.capture(state)
	controller._table_send({"kind": "checkpoint", "revision": revision, "run": run})


func _summary(controller, table: int) -> Dictionary:
	for summary in controller.lobby.get("table_summaries", []):
		if summary.table == table:
			return summary
	return {}


func _expire_takeover(host, table: int) -> void:
	host.recovery._lost_leaders[table].since -= host.recovery.TAKEOVER_GRACE_MS
	host._tick_recovery(Time.get_ticks_msec())
	_pump()


func _open_room(host_id: int, guests: Array, seats: Dictionary, tables: int) -> void:
	_room = SteamRoom.new()
	var host = _spawn(host_id)
	host.transport.host_steam()
	_pump(2)
	for id in guests:
		_spawn(id)._join(ROOM_CODE)
		_pump()
	host._lobby_request({"action": "tables", "count": tables})
	_pump()
	for id in seats:
		_peers[id]._lobby_request({"action": "seat", "table": seats[id][0], "slot": seats[id][1]})
		_pump()
	for id in _peers:
		_peers[id]._ready_requested(true)
		_pump()


func _match_recovery() -> void:
	# Table 0: room host 10 alone. Table 1: 20 leads 30. Table 2: 40 alone.
	_open_room(10, [20, 30, 40], {20: [1, 0], 30: [1, 1], 40: [2, 0]}, 3)
	var host = _peers[10]
	_check(host.lobby_model.can_start(), "simulated room seats four players across three tables")
	host._lobby_request({"action": "start"})
	_pump()
	for id in _peers:
		_check(_peers[id].active, "player %d starts its table" % id)
	_check(
		_peers[20].is_table_host() and not _peers[30].is_table_host(),
		"first seat leads a shared table"
	)
	for id in [10, 20, 40]:
		_checkpoint(_peers[id], 1)
		_peers[id]._publish_state()
	_pump()
	for id in _peers:
		for table in 3:
			if _peers[id].is_table_host() and _peers[id].table_id == table:
				continue
			_check(
				not _peers[id].recovery.checkpoint(table).is_empty(),
				"player %d holds table %d's checkpoint" % [id, table]
			)
	_solo_leader_crashes_and_rejoins()
	_teammate_takes_over_a_crashed_leader()
	_brief_disconnect_keeps_the_leader()
	_room_host_migrates()


func _solo_leader_crashes_and_rejoins() -> void:
	var host = _peers[10]
	_crash(40)
	_pump()
	var paused = _summary(_peers[30], 2)
	_check(
		paused.get("waiting_for") == 40 and paused.status.begins_with("Paused"),
		"everyone sees the solo table pause for its player"
	)
	_check(not _peers[20].table_paused(), "other tables keep playing")
	var returning = _spawn(40)
	_check(returning.recovery.remembered_room() == ROOM_CODE, "crashed player remembers its room")
	returning._rejoin_requested()
	_pump()
	_check(returning._rejoin_pending, "rejoining player waits for its native menu")
	_settle(returning)
	var resumed = (
		returning.run_setup.starts.back() if not returning.run_setup.starts.is_empty() else null
	)
	_check(
		returning.active and returning.is_table_host() and resumed != null,
		"solo leader resumes its own table from the room's checkpoint"
	)
	_check(resumed != null and resumed.money == 12, "resumed run uses that table's checkpoint")
	returning._publish_state()
	_pump()
	_check(not host.recovery.is_waiting(2), "room host stops waiting once the table is back")
	_check(not _summary(host, 2).has("waiting_for"), "standings clear the pause")


func _teammate_takes_over_a_crashed_leader() -> void:
	var host = _peers[10]
	_crash(20)
	_pump()
	_check(_summary(_peers[30], 1).get("takeover_by") == 30, "teammate sees it will take over")
	_check(_peers[30].table_paused(), "teammate's table pauses while the leader is away")
	_expire_takeover(host, 1)
	var successor = _peers[30]
	_check(successor._rejoin_pending, "successor receives the takeover")
	_settle(successor)
	_check(
		successor.is_table_host() and successor.run_setup.starts.back() != null,
		"successor restores the table from its checkpoint"
	)
	_check(host.lobby_model.leader_epoch(1) == 2, "takeover advances the table epoch")
	_checkpoint(successor, 1)
	successor._publish_state()
	_pump()
	_check(
		not host.recovery.checkpoint(1).is_empty() and _summary(host, 1).status != "Waiting",
		"new leader's traffic is accepted under the new epoch"
	)
	var former = _spawn(20)
	former._rejoin_requested()
	_pump()
	_settle(former)
	_check(
		former.active and not former.is_table_host() and former.table_sync.guest_begins == 1,
		"former leader rejoins as its successor's teammate"
	)
	_check(former.run_setup.starts.is_empty(), "former leader does not restart the run")


func _brief_disconnect_keeps_the_leader() -> void:
	var host = _peers[10]
	var leader = _peers[30]
	var starts: int = leader.run_setup.starts.size()
	_room.cut(10, 30)
	var stale = Time.get_ticks_msec() - Transport.PEER_TIMEOUT_MS - 1
	leader.transport._peers[10].last_received = stale
	host.transport._peers[30].last_received = stale
	_pump(2)
	_check(leader._link_lost and leader.table_paused(), "leader pauses while its link is down")
	_check(host.recovery.is_waiting(1), "room host starts the takeover timer")
	_check(leader.transport.session_open(), "leader stays in the Steam room while retrying")
	_room.heal(10, 30)
	_reconnect_now([leader])
	_check(not leader._link_lost and leader.active, "leader reconnects within the grace period")
	_check(not host.recovery.is_waiting(1), "reconnection cancels the takeover")
	_check(
		leader.is_table_host() and leader.run_setup.starts.size() == starts,
		"reconnected leader keeps its live run instead of reloading"
	)


func _room_host_migrates() -> void:
	var host = _peers[10]
	var started_at: int = host._match_started_at
	var match_id: int = host.match_id
	var standings: Array = host.table_summaries.map(func(summary): return summary.table)
	_crash(10)
	_pump(2)
	var promoted = _peers[30]
	_check(promoted.transport.is_host, "Steam's new room owner becomes the room host")
	_check(
		_peers[20]._link_lost and _peers[40]._link_lost,
		"other players pause while the room moves to the new host"
	)
	_reconnect_now([_peers[20], _peers[40]])
	for id in [20, 40]:
		_check(_peers[id].transport.host_id() == 30, "player %d follows the new host" % id)
		_check(_peers[id].lobby.get("host_id") == 30, "player %d receives the restored room" % id)
		_check(not _peers[id]._link_lost, "player %d resumes after migration" % id)
	_check(
		(
			promoted.match_id == match_id
			and promoted.table_summaries.map(func(s): return s.table) == standings
		),
		"new host keeps the match and every table's standings"
	)
	_check(
		absi(promoted._match_started_at - started_at) < 1000,
		"race clock continues from the previous host"
	)
	_check(not _peers[40].table_paused(), "a solo table on another player keeps playing")
	_check(
		_summary(promoted, 0).get("waiting_for") == 10,
		"the departed host's solo table pauses for its return"
	)
	_check(
		not promoted.recovery.checkpoint(0).is_empty(),
		"new host holds the departed table's checkpoint"
	)
	_peers[40]._publish_state()
	_pump()
	_check(
		not promoted.recovery.is_waiting(2), "reconnected leaders are recognized by the new host"
	)
	var returning = _spawn(10)
	returning._rejoin_requested()
	_pump()
	_settle(returning)
	_check(
		returning.active and returning.is_table_host() and not returning.transport.is_host,
		"former room host rejoins as a player and resumes its own table"
	)
	_check(
		returning.run_setup.starts.back() != null and returning.run_setup.starts.back().money == 10,
		"former room host resumes from its table's checkpoint"
	)


func _lobby_migration_before_start() -> void:
	for id in _peers.keys():
		_crash(id, true)
	_open_room(100, [200, 300], {200: [0, 1], 300: [1, 0]}, 2)
	_check(_peers[100].lobby_model.can_start(), "pre-match room is ready to start")
	_crash(100)
	_pump(2)
	var promoted = _peers[200]
	_check(
		promoted.transport.is_host and not promoted.lobby_model.started,
		"pre-match room survives its host leaving"
	)
	_reconnect_now([_peers[300]])
	var seat: Dictionary = {}
	for player in promoted.lobby_model.snapshot().players:
		if player.id == 300:
			seat = player
	_check(
		seat.get("connected") == true and seat.get("table") == 1 and seat.get("ready") == false,
		"reconnected player keeps its seat and readies up again"
	)
	promoted._prune_at = 1
	promoted._tick_recovery(Time.get_ticks_msec())
	_pump()
	_check(
		_peers[300].lobby.players.all(func(player): return player.id != 100),
		"players who never return are removed from the lobby"
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

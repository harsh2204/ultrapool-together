extends Node

const VERSION = "0.5.0"
const GAME_VERSION = "0.15.7"
const SNAPSHOT_INTERVAL = 0.10

var transport: Node
var adapter: Node
var table_sync: Node
var shop_sync: Node
var presence: Node
var run_setup: Node
var multiplayer_balls: Node
var bounty_race: Script
var lobby_model: RefCounted
var router: RefCounted
var ui_root: Control
var panel: Control
var turn_label: Label
var score_label: Label
var pass_button: Button

var supported = true
var active = false
var table_id = -1
var table_leader_id = 0
var match_id = 0
var lobby: Dictionary = {}
var run_config: Dictionary = {}
var table_summaries: Array = []
var turn_owner = 0
var shot_number = 0
var shot_pending = false
var shot_start_score = 0.0
var settle_time = 0.0
var elapsed_shot = 0.0
var total_score = 0.0
var used_shots = 0
var finished = false
var finish_reason = ""
var latest_state: Dictionary = {}
var awaiting_shot_turn = -1
var snapshot_time = 0.0
var state_time = 0.0
var snapshot_id = 0
var last_guest_snapshot = 0
var last_started_turn = -1
var last_shop_state: Dictionary = {}
var roster_time = 0.0
var saw_table = false
var _suspended_menu: Node
var _menu_process_mode = Node.PROCESS_MODE_INHERIT
var _ui_process_mode = Node.PROCESS_MODE_INHERIT
var _returning_to_menu = false
var _local_id = 0


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	var base = get_script().resource_path.get_base_dir()
	lobby_model = load(base.path_join("lobby_state.gd")).new()
	router = load(base.path_join("table_router.gd")).new()
	transport = load(base.path_join("transport.gd")).new()
	adapter = load(base.path_join("game_adapter.gd")).new()
	table_sync = load(base.path_join("table_sync.gd")).new()
	shop_sync = load(base.path_join("shop_sync.gd")).new()
	presence = load(base.path_join("presence.gd")).new()
	run_setup = load(base.path_join("run_setup.gd")).new()
	multiplayer_balls = load(base.path_join("multiplayer_balls.gd")).new()
	bounty_race = load(base.path_join("bounty_race.gd"))
	for service in [
		transport, adapter, table_sync, shop_sync, presence, run_setup, multiplayer_balls
	]:
		add_child(service)
	_build_ui()
	if not multiplayer_balls.setup(self):
		supported = false
		_status("Multiplayer ball art is missing. Reinstall the complete mod package.")
		return
	presence.setup(self, transport, shop_sync)
	shop_sync.request.connect(_shop_request)
	transport.connected.connect(_connected)
	transport.peer_joined.connect(_peer_joined)
	transport.peer_left.connect(_peer_left)
	transport.disconnected.connect(_disconnected)
	transport.received.connect(_received)
	transport.status_changed.connect(_status)
	transport.room_ready.connect(_room_ready)
	if str(ProjectSettings.get_setting("application/config/version", "")) != GAME_VERSION:
		supported = false
		_status("This mod requires Ultrapool " + GAME_VERSION + ".")
		return
	transport.listen_for_invites()
	print("[Together] Ready v", VERSION)


func _build_ui():
	var hud = CanvasLayer.new()
	hud.layer = 120
	add_child(hud)
	ui_root = Control.new()
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = Theme.new()
	ui_root.theme.default_font = get_node("/root/UIManager").FONT_LATIN
	ui_root.theme.default_font_size = 18
	hud.add_child(ui_root)
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dock = VBoxContainer.new()
	ui_root.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dock.offset_left = -350
	dock.offset_right = -16
	dock.offset_top = 72
	dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	dock.add_child(row)
	pass_button = _button("Pass", _request_pass)
	pass_button.hide()
	row.add_child(pass_button)
	row.add_child(_button("Lobby · F8", _toggle_panel))
	turn_label = Label.new()
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dock.add_child(turn_label)
	score_label = Label.new()
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dock.add_child(score_label)
	panel = (
		load(get_script().resource_path.get_base_dir().path_join("lobby_scene.tscn")).instantiate()
	)
	ui_root.add_child(panel)
	panel.host_requested.connect(_host)
	panel.join_requested.connect(_join)
	panel.friends_requested.connect(func(): panel.set_friends(transport.online_friends()))
	panel.invite_requested.connect(func(id): transport.invite_friend(id))
	panel.slot_requested.connect(
		func(table, slot): _lobby_request({"action": "seat", "table": table, "slot": slot})
	)
	panel.ready_requested.connect(_ready_requested)
	panel.table_count_requested.connect(
		func(count): _lobby_request({"action": "tables", "count": count})
	)
	panel.shot_budget_requested.connect(
		func(count): _lobby_request({"action": "budget", "count": count})
	)
	panel.start_requested.connect(func(): _lobby_request({"action": "start"}))
	panel.return_requested.connect(func(): _lobby_request({"action": "reset"}))
	panel.leave_requested.connect(_leave)
	panel.close_requested.connect(func(): _set_panel(false))
	panel.hide()
	_status("Create a lobby, choose your table, and ready up.")


func _button(value: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = value
	button.pressed.connect(action)
	return button


func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_toggle_panel()
		get_viewport().set_input_as_handled()


func _toggle_panel():
	_set_panel(not panel.visible)


func _set_panel(value: bool):
	if (
		value
		and not active
		and run_setup.at_main_menu()
		and get_node("/root/UIManager").is_popup_open()
	):
		_status("Close the game's popup before opening the lobby.")
		return
	panel.visible = value
	if value:
		_render_lobby()
		_suspend_menu()
	else:
		_restore_menu()


func _suspend_menu():
	if active or is_instance_valid(_suspended_menu) or not run_setup.at_main_menu():
		return
	_suspended_menu = get_tree().current_scene
	_menu_process_mode = _suspended_menu.process_mode
	_ui_process_mode = get_node("/root/UIManager").process_mode
	_suspended_menu.process_mode = Node.PROCESS_MODE_DISABLED
	get_node("/root/UIManager").process_mode = Node.PROCESS_MODE_DISABLED


func _restore_menu():
	if is_instance_valid(_suspended_menu):
		_suspended_menu.process_mode = _menu_process_mode
		get_node("/root/UIManager").process_mode = _ui_process_mode
	_suspended_menu = null


func _host():
	if not supported or transport.session_open():
		return
	if not run_setup.at_main_menu():
		_status("Return to the main menu before creating a lobby.")
		return
	if transport.host_steam() != OK:
		_status("Could not create a Steam lobby. Check that Steam is online.")
	_render_lobby()


func _join(code: String):
	if not supported or transport.session_open():
		return
	if not run_setup.at_main_menu():
		_status("Return to the main menu before joining a lobby.")
		return
	if transport.join_steam(code.strip_edges()) != OK:
		_status("Could not join. Everyone needs v0.5 and a new UP5 room code.")
	_render_lobby()


func _room_ready():
	_local_id = transport.local_id()
	lobby_model.setup(transport.local_id(), _transport_name(transport.local_id()))
	_broadcast_lobby()
	_set_panel(true)


func _connected():
	_local_id = transport.local_id()
	if not run_setup.at_main_menu():
		_leave()
		_status("Return to the main menu before joining a lobby.")
		return
	_set_panel(true)
	_status("Connected. Choose an open seat, then ready up.")


func _transport_name(id: int) -> String:
	for member in transport.participants():
		if member.id == id:
			return member.name
	return "Player"


func _peer_joined(id: int):
	if not transport.is_host:
		return
	if not lobby_model.add_player(id, _transport_name(id)):
		transport.send_to(id, {"kind": "room_reject", "reason": lobby_model.last_error})
		transport.disconnect_peer(id, lobby_model.last_error)
		return
	_broadcast_lobby()
	if lobby_model.started:
		transport.send_to(id, {"kind": "match_start", "match": match_id, "config": run_config})


func _peer_left(id: int, reason: String):
	if not transport.is_host:
		return
	if not lobby_model.remove_player(id):
		return
	if lobby_model.started:
		for summary in table_summaries:
			if summary.leader_id == id:
				summary.closed = true
				if not summary.finished:
					summary.finished = true
					summary.status = "Table host disconnected"
	_broadcast_lobby()
	_status(_player_name(id) + " disconnected. " + reason)


func _ready_requested(value: bool):
	if value and not run_setup.at_main_menu():
		_status("Return to the main menu before readying up.")
		return
	_lobby_request({"action": "ready", "ready": value})


func _lobby_request(message: Dictionary):
	message.kind = "lobby_request"
	if transport.is_host:
		_apply_lobby_request(transport.local_id(), message)
	else:
		transport.send(message)


func _apply_lobby_request(sender: int, message: Dictionary):
	var accepted = false
	match message.get("action"):
		"seat":
			if message.get("table") is int and message.get("slot") is int:
				accepted = lobby_model.choose_slot(sender, message.table, message.slot)
		"ready":
			if message.get("ready") is bool:
				accepted = lobby_model.set_ready(sender, message.ready)
		"tables":
			if message.get("count") is int:
				accepted = lobby_model.set_table_count(sender, message.count)
		"budget":
			if message.get("count") is int:
				accepted = lobby_model.set_shot_budget(sender, message.count)
		"start":
			_start_match(sender)
			return
		"reset":
			_reset_match(sender)
			return
	if accepted:
		_broadcast_lobby()
	else:
		_lobby_error(sender, lobby_model.last_error)


func _lobby_error(recipient: int, reason: String):
	if recipient == transport.local_id():
		_status(reason)
	else:
		transport.send_to(recipient, {"kind": "lobby_error", "reason": reason})


func _broadcast_lobby():
	bounty_race.resolve(table_summaries, _competitive())
	lobby = lobby_model.snapshot()
	lobby.table_summaries = table_summaries.duplicate(true)
	lobby.match = match_id
	transport.send({"kind": "lobby_state", "lobby": lobby})
	_roster_changed()


func _render_lobby():
	panel.set_connection(transport.room_code, transport.session_open(), transport.invite_ready())
	panel.render(lobby, transport.local_id(), transport.is_host)


func _start_match(sender: int):
	if sender != transport.local_id() or not lobby_model.can_start():
		_lobby_error(sender, "Every player must be seated and ready, with someone at each table.")
		return
	if not run_setup.at_main_menu():
		_status("Return to the main menu before starting the match.")
		return
	run_config = run_setup.capture_config()
	if not run_setup.validate_config(run_config):
		_status("Choose a standard deck and difficulty before opening the lobby.")
		return
	if not lobby_model.start(sender):
		_status(lobby_model.last_error)
		return
	match_id += 1
	table_summaries.clear()
	for table in range(lobby_model.table_count):
		table_summaries.append(
			{
				"table": table,
				"leader_id": lobby_model.leader_for_table(table),
				"score": 0.0,
				"base_score": 0.0,
				"bounty_shot": 0,
				"bounty_bonus": 0,
				"shots_used": 0,
				"shot_budget": lobby_model.shot_budget,
				"finished": false,
				"status": "Starting"
			}
		)
	_broadcast_lobby()
	transport.send({"kind": "match_start", "match": match_id, "config": run_config})
	_begin_table(run_config)


func _begin_table(config: Dictionary):
	if active or not lobby.get("started", false):
		return
	var assigned_table = player_table(transport.local_id())
	if _table_abandoned(assigned_table):
		_status("Your table host disconnected. Wait for the host to reopen the lobby.")
		_set_panel(true)
		return
	if not run_setup.validate_config(config) or not run_setup.at_main_menu():
		_match_failed("A player could not start a fresh run. Everyone must be at the main menu.")
		return
	if get_tree().paused or get_node("/root/UIManager").is_popup_open():
		_match_failed("Close the game's popup before starting the match.")
		return
	table_id = player_table(transport.local_id())
	table_leader_id = _leader(table_id)
	if table_id < 0 or table_leader_id == 0:
		return
	_set_panel(false)
	turn_owner = table_leader_id
	shot_number = 0
	shot_pending = false
	finished = false
	finish_reason = ""
	total_score = 0.0
	used_shots = 0
	awaiting_shot_turn = -1
	snapshot_id = 0
	last_guest_snapshot = 0
	last_started_turn = -1
	state_time = 0.0
	snapshot_time = 0.0
	saw_table = false
	latest_state.clear()
	last_shop_state.clear()
	presence.clear()
	active = true
	multiplayer_balls.begin_session()
	if not is_table_host() and not table_sync.begin_guest():
		_match_failed("Could not create the table view. Return to the main menu and try again.")
		return
	adapter.begin_session(self)
	shop_sync.begin_session(self)
	if is_table_host():
		if run_setup.start(config, multiplayer_balls.catalog) != OK:
			_match_failed("Could not start the table's run.")
	else:
		_table_send({"kind": "sync_request"})
	_status("Table %d · Take turns and shop together." % (table_id + 1))


func _match_failed(reason: String):
	if transport.is_host:
		_reset_match(transport.local_id())
		transport.send({"kind": "lobby_error", "reason": reason})
	else:
		transport.send({"kind": "match_failed", "match": match_id, "reason": reason})
	_status(reason)
	_set_panel(true)


func _reset_match(sender: int):
	if not lobby_model.reset_lobby(sender):
		_lobby_error(sender, lobby_model.last_error)
		return
	match_id += 1
	table_summaries.clear()
	run_config.clear()
	transport.send({"kind": "match_stop", "match": match_id})
	_end_table()
	_broadcast_lobby()
	_set_panel(true)


func _end_table():
	var return_native = active and is_table_host()
	active = false
	_restore_menu()
	presence.clear()
	shop_sync.end_session()
	multiplayer_balls.end_session()
	adapter.end_session()
	table_sync.end_guest()
	run_setup.cancel()
	shot_pending = false
	awaiting_shot_turn = -1
	latest_state.clear()
	last_shop_state.clear()
	table_id = -1
	table_leader_id = 0
	if return_native:
		_returning_to_menu = true


func _leave():
	transport.close()
	_disconnected("Left the lobby.")


func _disconnected(reason: String):
	_end_table()
	_local_id = 0
	match_id = 0
	lobby_model.clear()
	lobby.clear()
	run_config.clear()
	table_summaries.clear()
	_status(reason)
	_set_panel(true)


func _status(value: String):
	panel.set_status(value)
	print("[Together] ", value)


func is_table_host() -> bool:
	return table_leader_id != 0 and table_leader_id == _local_id


func _table_abandoned(table: int) -> bool:
	for summary in lobby.get("table_summaries", []):
		if summary.table == table:
			return summary.get("closed", false)
	return false


func player_table(id: int) -> int:
	for player in lobby.get("players", []):
		if player.id == id:
			return player.table
	return -1


func _members(table: int, connected_only: bool = true) -> Array:
	var members: Array = []
	for player in lobby.get("players", []):
		if player.table == table and (not connected_only or player.connected):
			members.append(player)
	members.sort_custom(func(a, b): return a.slot < b.slot)
	return members


func _leader(table: int) -> int:
	var members = _members(table, false)
	return members[0].id if not members.is_empty() else 0


func _player_name(id: int) -> String:
	for player in lobby.get("players", []):
		if player.id == id:
			return player.name
	return "Player"


func _next_player() -> int:
	var members = _members(table_id)
	if members.is_empty():
		return 0
	for index in range(members.size()):
		if members[index].id == turn_owner:
			return members[(index + 1) % members.size()].id
	return members[0].id


func _roster_changed():
	if active:
		for summary in lobby.get("table_summaries", []):
			if summary.table == table_id and summary.finished and not finished:
				finished = true
				finish_reason = summary.status
				if summary.get("closed", false):
					shot_pending = false
					awaiting_shot_turn = -1
		if is_table_host() and not shot_pending and not finished:
			if not _members(table_id).any(func(player): return player.id == turn_owner):
				turn_owner = _next_player()
				shot_number += 1
				_publish_state()
	_render_lobby()


func _process(delta):
	if _returning_to_menu:
		_restore_menu()
		if run_setup.return_menu() == OK:
			_returning_to_menu = false
	if panel.visible:
		_suspend_menu()
	presence.tick(delta, active, can_control())
	roster_time += delta
	if roster_time >= 1.0:
		roster_time = 0.0
		_render_lobby()
	if active and is_table_host():
		var state = adapter.game_data()
		if state.available:
			saw_table = true
		if saw_table and not state.available:
			shot_pending = false
			finished = true
			finish_reason = "Run closed"
		if shot_pending:
			elapsed_shot += delta
			settle_time = settle_time + delta if adapter.is_settled() else 0.0
			if state.round_finalized or (elapsed_shot > 1.0 and settle_time >= 0.8):
				_finish_shot()
		if (
			not shot_pending
			and not finished
			and saw_table
			and (state.game_over or not state.available)
		):
			finished = true
			finish_reason = "Run ended"
		state_time += delta
		if state_time >= 0.15:
			state_time = 0.0
			_publish_state()
		snapshot_time += delta
		if snapshot_time >= SNAPSHOT_INTERVAL:
			snapshot_time = 0.0
			_publish_snapshot()
	_update_hud()


func can_control() -> bool:
	if not _turn_ready():
		return false
	if multiplayer_balls != null and multiplayer_balls.blocks_shot_input():
		return false
	if get_node("/root/InputManager").is_controller():
		return true
	var hovered = get_viewport().gui_get_hovered_control()
	return hovered == null or not ui_root.is_ancestor_of(hovered)


func _turn_ready() -> bool:
	if (
		not active
		or panel.visible
		or turn_owner != transport.local_id()
		or shot_pending
		or finished
	):
		return false
	if shop_sync.is_open():
		return false
	if is_table_host():
		return run_setup.ready_for_input() and adapter.can_shoot()
	return (
		awaiting_shot_turn < 0
		and latest_state.get("can_shoot", false)
		and table_sync.ready_for_input()
	)


func submit_shot(vector: Vector2) -> bool:
	if not can_control() or not vector.is_finite() or vector.length() <= 50.0:
		return false
	vector = vector.limit_length(200.0)
	if is_table_host():
		return _take_shot(transport.local_id(), vector, shot_number)
	awaiting_shot_turn = shot_number
	_table_send({"kind": "shot", "x": vector.x, "y": vector.y, "turn": shot_number})
	return true


func _take_shot(player: int, vector: Vector2, expected_turn: int) -> bool:
	if (
		not active
		or not is_table_host()
		or turn_owner != player
		or shot_pending
		or finished
		or expected_turn != shot_number
	):
		return false
	if (
		not run_setup.ready_for_input()
		or not vector.is_finite()
		or vector.length() <= 50.0
		or vector.length() > 200.1
	):
		return false
	shot_start_score = adapter.score()
	var starting_table = table_sync.capture()
	if not adapter.shoot(vector, multiplayer_balls.begin_shot.bind(used_shots + 1, player)):
		return false
	shot_pending = true
	settle_time = 0.0
	elapsed_shot = 0.0
	snapshot_id += 1
	_table_send(
		{
			"kind": "shot_start",
			"turn": shot_number,
			"id": snapshot_id,
			"vector": vector,
			"scene": starting_table
		}
	)
	_publish_state()
	return true


func _finish_shot():
	multiplayer_balls.finish_shot()
	total_score += maxf(0.0, adapter.shot_score() - shot_start_score)
	used_shots += 1
	shot_pending = false
	shot_number += 1
	finished = _competitive() and used_shots >= lobby.shot_budget
	if finished:
		finish_reason = "Finished"
	turn_owner = _next_player()
	_publish_snapshot(true)
	_publish_state()


func _competitive() -> bool:
	return lobby.get("table_count", 1) > 1


func _request_pass():
	if not _turn_ready() or _members(table_id).size() < 2:
		return
	if is_table_host():
		_pass(transport.local_id(), shot_number)
	else:
		awaiting_shot_turn = shot_number
		_table_send({"kind": "pass", "turn": shot_number})


func _pass(player: int, expected_turn: int) -> bool:
	if (
		not active
		or not is_table_host()
		or finished
		or player != turn_owner
		or expected_turn != shot_number
		or shot_pending
		or not adapter.can_shoot()
	):
		return false
	turn_owner = _next_player()
	shot_number += 1
	_publish_state()
	return true


func _update_hud():
	pass_button.visible = (
		active
		and _members(table_id).size() > 1
		and not finished
		and not latest_state.get("in_shop", false)
	)
	pass_button.disabled = not _turn_ready()
	turn_label.text = ""
	score_label.text = ""
	if not active:
		return
	if finished:
		turn_label.text = _result_text()
	elif shot_pending or awaiting_shot_turn >= 0:
		turn_label.text = "Shot in play"
	elif latest_state.get("in_shop", false):
		turn_label.text = "Shared shop · Table %d" % (table_id + 1)
	elif not latest_state.get("table_active", false):
		turn_label.text = "Waiting for the table"
	else:
		turn_label.text = (
			"Your turn"
			if turn_owner == transport.local_id()
			else _player_name(turn_owner) + "'s turn"
		)
	if _competitive():
		var displayed_score = total_score
		for summary in lobby.get("table_summaries", []):
			if summary.table == table_id:
				displayed_score += summary.get("bounty_bonus", 0)
		score_label.text = (
			"Table %d · %.0f points · %d/%d shots"
			% [table_id + 1, displayed_score, used_shots, lobby.shot_budget]
		)
	elif latest_state.get("available", false) and not latest_state.get("in_shop", false):
		score_label.text = (
			"Round %d · %d shots left · Score %.0f"
			% [latest_state.round, latest_state.shots_left, latest_state.score]
		)


func _result_text() -> String:
	if not _competitive():
		return finish_reason
	var summaries: Array = lobby.get("table_summaries", [])
	if summaries.any(func(summary): return not summary.finished):
		return finish_reason + " · Waiting for other tables"
	var best = -1.0
	var winners: Array = []
	for summary in summaries:
		if summary.status == "Table host disconnected":
			continue
		if summary.score > best:
			best = summary.score
			winners = [summary.table]
		elif summary.score == best:
			winners.append(summary.table)
	if winners.has(table_id):
		return "Your table won" if winners.size() == 1 else "Draw"
	return "Match ended · Open lobby for standings"


func _publish_state(target: int = 0):
	if not active or not is_table_host():
		return
	multiplayer_balls.prepare_shop()
	latest_state = adapter.game_data()
	latest_state.can_shoot = latest_state.can_shoot and run_setup.ready_for_input() and not finished
	latest_state.merge(
		{
			"kind": "state",
			"turn_owner": turn_owner,
			"turn": shot_number,
			"pending": shot_pending,
			"total_score": total_score,
			"used_shots": used_shots,
			"bounty_shot": multiplayer_balls.bounty_shot(),
			"multiplayer_balls": multiplayer_balls.capture(),
			"finished": finished,
			"finish_reason": finish_reason
		},
		true
	)
	_table_send(latest_state, target)
	var shop_state = shop_sync.capture()
	if target != 0 or shop_state != last_shop_state:
		if target == 0:
			last_shop_state = shop_state.duplicate(true)
		_table_send({"kind": "shop_state", "shop": shop_state}, target)


func _publish_snapshot(reliable: bool = false, target: int = 0):
	if not active or not is_table_host() or not adapter.game_data().available:
		return
	snapshot_id += 1
	_table_send(
		{"kind": "snapshot", "id": snapshot_id, "scene": table_sync.capture()}, target, reliable
	)


func _shop_request(message: Dictionary):
	if active and not finished:
		_table_send(message)


func _table_send(payload: Dictionary, target: int = 0, reliable: bool = true):
	var envelope = {
		"kind": "table",
		"match": match_id,
		"table": table_id,
		"payload": payload,
		"reliable": reliable
	}
	if target != 0:
		envelope.target = target
	if transport.is_host:
		_route_table(transport.local_id(), envelope)
	else:
		transport.send_to(transport.host_id(), envelope, not reliable)


func _route_table(actor: int, envelope: Dictionary):
	if envelope.get("match") != match_id:
		return
	var routed = router.route(lobby, actor, envelope)
	if routed.is_empty():
		return
	if _table_abandoned(routed.table):
		return
	var payload: Dictionary = routed.payload
	if payload.kind == "state":
		if not _valid_state(payload, routed.table):
			return
		_record_summary(routed.table, payload)
	var message = {
		"kind": "table",
		"match": match_id,
		"table": routed.table,
		"actor": actor,
		"payload": payload
	}
	for recipient in routed.recipients:
		if recipient == transport.local_id():
			_received_table(actor, payload)
		else:
			transport.send_to(recipient, message, routed.unreliable)


func _record_summary(table: int, state: Dictionary):
	var summary = {
		"table": table,
		"leader_id": _leader(table),
		"score": state.total_score,
		"base_score": state.total_score,
		"bounty_shot": state.bounty_shot,
		"bounty_bonus": 0,
		"shots_used": state.used_shots,
		"shot_budget": lobby.shot_budget,
		"finished": state.finished,
		"status":
		(
			state.finish_reason
			if state.finished
			else ("Shopping" if state.in_shop else ("Shot in play" if state.pending else "Playing"))
		)
	}
	for index in range(table_summaries.size()):
		if table_summaries[index].table == table:
			if (
				table_summaries[index].status == "Table host disconnected"
				or (
					table_summaries[index].base_score == summary.base_score
					and table_summaries[index].bounty_shot == summary.bounty_shot
					and table_summaries[index].shots_used == summary.shots_used
					and table_summaries[index].finished == summary.finished
					and table_summaries[index].status == summary.status
				)
			):
				return
			table_summaries[index] = summary
			_broadcast_lobby()
			return


func _received(sender: int, message: Dictionary):
	if presence.receive(sender, message):
		return
	var kind = message.get("kind", "")
	if transport.is_host:
		match kind:
			"lobby_request":
				_apply_lobby_request(sender, message)
			"table":
				_route_table(sender, message)
			"match_failed":
				if (
					lobby.get("started", false)
					and message.get("match") == match_id
					and player_table(sender) >= 0
				):
					_match_failed(
						(
							_player_name(sender)
							+ " could not start the match. Return to the main menu and ready up again."
						)
					)
		return
	if sender != transport.host_id():
		return
	match kind:
		"lobby_state":
			if message.get("lobby") is Dictionary:
				lobby = message.lobby
				_roster_changed()
		"lobby_error":
			if message.get("reason") is String:
				_status(message.reason)
		"room_reject":
			_leave()
			_status(message.get("reason", "The lobby is unavailable."))
		"match_start":
			if (
				message.get("match") is int
				and message.match >= match_id
				and message.get("config") is Dictionary
			):
				match_id = message.match
				run_config = message.config
				_begin_table(run_config)
		"match_stop":
			if message.get("match") is int and message.match > match_id:
				match_id = message.match
				_end_table()
				_set_panel(true)
		"table":
			if (
				active
				and message.get("match") == match_id
				and message.get("table") == table_id
				and message.get("actor") is int
				and message.get("payload") is Dictionary
			):
				_received_table(message.actor, message.payload)


func _received_table(actor: int, message: Dictionary):
	if not active or player_table(actor) != table_id:
		return
	var kind = message.get("kind", "")
	if is_table_host():
		if (
			kind == "shot"
			and _number(message.get("x"))
			and _number(message.get("y"))
			and message.get("turn") is int
		):
			var accepted = _take_shot(actor, Vector2(message.x, message.y), message.turn)
			_table_send({"kind": "shot_result", "turn": message.turn, "accepted": accepted}, actor)
		elif kind == "pass" and message.get("turn") is int:
			var accepted = _pass(actor, message.turn)
			_table_send({"kind": "shot_result", "turn": message.turn, "accepted": accepted}, actor)
		elif kind == "shop_request":
			multiplayer_balls.prepare_shop()
			var accepted = not finished and shop_sync.handle_request(message)
			_table_send(
				{"kind": "shop_result", "accepted": accepted, "error": shop_sync.last_error}, actor
			)
			_publish_state()
		elif kind == "ball_call":
			multiplayer_balls.handle_call(actor, message)
			_publish_state()
		elif kind == "sync_request":
			_publish_state(actor)
			_publish_snapshot(true, actor)
		return
	if actor != table_leader_id:
		return
	if kind == "shop_result" and message.get("accepted") is bool and message.get("error") is String:
		shop_sync.apply_result(message.accepted, message.error)
	elif kind == "shop_state" and message.get("shop") is Dictionary:
		if not shop_sync.apply_state(message.shop):
			_bad_table("shop")
	elif (
		kind == "shot_start"
		and message.get("turn") is int
		and message.turn > last_started_turn
		and message.get("id") is int
		and message.get("vector") is Vector2
		and message.vector.is_finite()
		and message.vector.length() > 50.0
		and message.vector.length() <= 200.1
		and message.get("scene") is Dictionary
	):
		last_started_turn = message.turn
		if message.id > last_guest_snapshot:
			if not table_sync.apply_snapshot(message.scene):
				_bad_table("shot")
				return
			last_guest_snapshot = message.id
			table_sync.begin_shot(message.vector)
	elif kind == "state" and _valid_state(message, table_id):
		multiplayer_balls.apply_state(message.multiplayer_balls)
		latest_state = message
		turn_owner = message.turn_owner
		shot_number = message.turn
		shot_pending = message.pending
		total_score = message.total_score
		used_shots = message.used_shots
		finished = message.finished
		finish_reason = message.finish_reason
		if shot_pending or awaiting_shot_turn != shot_number:
			awaiting_shot_turn = -1
	elif (
		kind == "shot_result"
		and message.get("turn") == awaiting_shot_turn
		and message.get("accepted") == false
	):
		awaiting_shot_turn = -1
	elif (
		kind == "snapshot"
		and message.get("id") is int
		and message.id > last_guest_snapshot
		and message.get("scene") is Dictionary
	):
		if not table_sync.apply_snapshot(message.scene):
			_bad_table("table")
			return
		last_guest_snapshot = message.id


func _bad_table(part: String):
	_leave()
	_status("The table host sent an incompatible " + part + " update.")


func _number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _valid_state(message: Dictionary, table: int) -> bool:
	if (
		not message.get("turn_owner") is int
		or player_table(message.turn_owner) != table
		or not message.get("turn") is int
		or message.turn < 0
	):
		return false
	for key in ["available", "table_active", "can_shoot", "in_shop", "pending", "finished"]:
		if not message.get(key) is bool:
			return false
	for key in ["round", "shots_left", "used_shots", "bounty_shot"]:
		if not message.get(key) is int or message[key] < 0:
			return false
	return (
		_number(message.get("score"))
		and _number(message.get("total_score"))
		and message.total_score >= 0
		and message.bounty_shot <= message.used_shots
		and multiplayer_balls.valid_state(message.get("multiplayer_balls"))
		and message.get("finish_reason") is String
		and message.finish_reason.length() <= 100
	)

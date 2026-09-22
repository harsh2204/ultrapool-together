extends RefCounted

const PLAYER_NAMES = ["Alex", "Bea", "Chen", "Drew", "Erin", "Finley"]
const MAIN_FIELDS = [
	"active",
	"table_id",
	"table_leader_id",
	"_local_id",
	"lobby",
	"turn_owner",
	"shot_pending",
	"awaiting_shot_turn",
	"finished",
	"finish_reason",
	"latest_state",
	"total_score",
	"used_shots"
]

var checks: Array[Dictionary] = []


class CallRecorder:
	extends Node

	var service: Node
	var calls: Array[Dictionary] = []

	func ball_position(id: int, fallback: Vector2) -> Vector2:
		return service.ball_position(id, fallback)

	func request_call(ball: int, pocket: int) -> void:
		calls.append({"ball": ball, "pocket": pocket})


class OfflineTransport:
	extends Node

	var people: Array = []

	func local_id() -> int:
		return 1

	func participants() -> Array:
		return people


func capture_all_menu(mod: Node, capture: Callable) -> void:
	var saved = _save(mod)
	var panel = mod.panel
	panel.show()
	panel.set_status("")
	panel.set_connection("", false, false)
	panel.render({}, 1, true)
	await capture.call("lobby-home", "Create or join a lobby.")

	var coop = _lobby([0, 0, 0, -1], 1)
	coop.players[2].ready = false
	coop.players[3].ready = false
	coop.can_start = false
	panel.set_connection("UP7-RENDER-FIXTURE", true, true)
	panel.render(coop, 1, true)
	await capture.call("lobby-choosing-seats", "Four-player co-op with one player choosing a seat.")
	coop = _lobby([0, 0, 0, 0], 1)
	panel.render(coop, 1, true)
	_record(panel.get_node("%Leave").visible, "host can leave a pre-match lobby")
	await capture.call("lobby-coop-ready", "Four players ready at a shared table.")

	panel.set_friends([{"id": 5, "name": "Erin"}, {"id": 6, "name": "Finley"}])
	var invite = panel.get_node("%Invite")
	var popup = invite.get_popup()
	var viewport = mod.get_viewport()
	var embedded: bool = viewport.gui_embed_subwindows
	viewport.gui_embed_subwindows = true
	var anchor: Rect2 = invite.get_global_rect()
	popup.popup(Rect2i(Vector2i(anchor.position + Vector2(0, anchor.size.y)), Vector2i(280, 0)))
	await capture.call("lobby-friends", "The in-game invite menu with offline fixture friends.")
	popup.hide()
	viewport.gui_embed_subwindows = embedded

	panel.render(_lobby([0, 1, 2, 3, 3, 3], 4), 1, true)
	await capture.call("lobby-four-tables", "A 1v1v1v3 match with equal shot budgets per table.")
	var race = _lobby([0, 0, 1, 1], 2)
	race.match_mode = "race"
	panel.render(race, 1, true)
	await capture.call("lobby-race", "Race mode · two teams racing to finish the full run")
	race.started = true
	race.table_summaries = [
		{
			"table": 0,
			"round": 12,
			"run_goal_rounds": 20,
			"elapsed_ms": 382000,
			"finish_order": 0,
			"finished": false,
			"status": "Shopping"
		},
		{
			"table": 1,
			"round": 14,
			"run_goal_rounds": 20,
			"elapsed_ms": 382000,
			"finish_order": 0,
			"finished": false,
			"status": "Playing"
		}
	]
	race.return_vote = {
		"active": true, "proposer": 1, "eligible": [1, 2, 3, 4], "ready": [1, 2], "revision": 2
	}
	panel.render(race, 1, true)
	_record(
		not panel.get_node("%Leave").visible, "host cannot close an unfinished match through Leave"
	)
	_record(
		not panel.get_node("%Return").visible, "pending vote replaces the host's end-match proposal"
	)
	panel.render(race, 3, false)
	_record(panel.get_node("%Leave").visible, "guest can leave an active match voluntarily")
	_record(
		panel.get_node("%ApproveReturn").visible and not panel.get_node("%ApproveReturn").disabled,
		"eligible teammate can approve a pending return vote"
	)
	await capture.call("lobby-return-vote", "End-match vote · every connected player must approve")
	race.return_vote.active = false
	race.table_summaries[1].finished = true
	race.table_summaries[1].run_won = true
	race.table_summaries[1].round = 20
	race.table_summaries[1].finish_order = 1
	race.table_summaries[1].status = "Run completed"
	panel.render(race, 1, true)
	await capture.call(
		"lobby-race-finish", "Race standings · first finisher and a team still playing"
	)
	var results = _results()
	results.return_vote = {
		"active": true, "proposer": 1, "eligible": [1, 2, 3, 4], "ready": [1], "revision": 3
	}
	panel.render(results, 1, true)
	_record(
		panel.get_node("%Return").visible and panel.get_node("%Return").text == "Return to lobby",
		"completed match exposes immediate host return even with a pending vote"
	)
	_record(
		(
			not panel.get_node("%ApproveReturn").visible
			and not panel.get_node("%CancelReturn").visible
		),
		"completed match removes obsolete end-run voting controls"
	)
	_record(panel.get_node("%Leave").visible, "host can close a completed match")
	await capture.call("lobby-standings", "Completed table standings, including the Bounty award.")
	_restore(mod, saved)


func clipped_players(mod: Node) -> Array[String]:
	var clipped: Array[String] = []
	var labels = mod.panel.get_node("%Tables").find_children("*", "Label", true, false)
	labels.append_array(mod.panel.get_node("%Unassigned").find_children("*", "Label", true, false))
	var area: Rect2 = mod.panel.get_node("%Body").get_global_rect()
	for player in mod.panel._state.get("players", []):
		var visible_name = false
		for label in labels:
			if label.text == player.name and label.is_visible_in_tree():
				visible_name = area.encloses(label.get_global_rect())
				break
		if not visible_name:
			clipped.append(player.name)
	return clipped


func capture_table_states(mod: Node, capture: Callable) -> void:
	var saved = _save(mod)
	_set_table(mod)
	var data: Dictionary = mod.multiplayer_balls.capture().duplicate(true)
	data.last_shooter = 2
	data.pending = false
	data.call = {}
	var called_ball = 0
	for ball in data.get("balls", []):
		if "TOGETHER_RELAY" in ball.kinds:
			ball.marker = 2
		if "TOGETHER_PATIENCE" in ball.kinds:
			ball.charge = 3
		if "TOGETHER_CALL" in ball.kinds:
			called_ball = ball.id
	_check_call_input(mod, data, called_ball)
	mod.multiplayer_balls._ui.refresh(data)
	mod._update_hud()
	await capture.call("table-your-turn", "Your turn with Relay, Patience and Bounty markers.")

	mod.turn_owner = 2
	data.last_shooter = 1
	var game = mod.get_node("/root/Global").gameManager
	var origin: Vector2 = game.player_ball.global_position
	_cursor(mod, 2, "table", origin + Vector2(70, -100), origin, Vector2(70, -100))
	mod.multiplayer_balls._ui.refresh(data)
	mod._update_hud()
	await capture.call(
		"table-teammate-aim", "Teammate turn, shared aim preview and a call made on the table."
	)

	data.call = {"ball": called_ball, "pocket": 4, "actor": 1}
	mod.multiplayer_balls._ui._selected_ball = called_ball
	mod.multiplayer_balls._ui.refresh(data)
	await capture.call(
		"called-shot-selected", "Called Shot selects a ball and highlights pocket five."
	)

	mod.presence.clear()
	mod.lobby = _results()
	mod.finished = true
	mod.finish_reason = "Shot budget used"
	mod.total_score = 260.0
	mod.used_shots = 6
	mod.multiplayer_balls._ui.refresh(data)
	mod._update_hud()
	await capture.call("table-match-result", "The winning table's end-of-match HUD.")
	_restore(mod, saved)


func capture_shop_presence(mod: Node, capture: Callable) -> void:
	var saved = _save(mod)
	_set_table(mod)
	mod.latest_state.in_shop = true
	mod._update_hud()
	mod.multiplayer_balls._ui.refresh({})
	var shop = mod.shop_sync
	var selection: String = shop._selected
	var section: String = shop.current_section()
	_record(shop.show_section("balls"), "native ball shop is available")
	await mod.get_tree().create_timer(0.6).timeout
	_cursor(mod, 2, "shop", Vector2(0.3, 0.35))
	_cursor(mod, 3, "shop", Vector2(0.72, 0.55))
	await capture.call(
		"shop-shared", "Native shared shop, player cursors and multiplayer ball offers."
	)

	var inspected = false
	for slot in shop._state.get("slots", []):
		if slot.get("data", "") == "TOGETHER_CALL":
			inspected = shop.inspect_slot(slot.key)
			break
	_record(inspected, "native shop displays Called Shot inspection")
	if inspected:
		await mod.get_tree().create_timer(0.45).timeout
		await capture.call(
			"shop-ball-details", "A multiplayer ball's native description and shop actions."
		)
	mod.get_node("/root/UIManager").info_display.hide_info()
	var snacks: bool = shop.show_section("snacks")
	_record(snacks, "native snack counter is available")
	if snacks:
		await mod.get_tree().create_timer(0.6).timeout
		await capture.call("shop-snacks", "The native snack counter, shared by the table.")
	var mixing: bool = shop.show_section("mix")
	_record(mixing, "native cocktail counter is available")
	if mixing:
		await mod.get_tree().create_timer(0.6).timeout
		await capture.call(
			"shop-mixing", "The native cocktail counter for mixing the table's balls."
		)
	shop.show_section(section)
	await mod.get_tree().create_timer(0.6).timeout
	shop._selected = selection
	_restore(mod, saved)


func _check_call_input(mod: Node, data: Dictionary, ball_id: int) -> void:
	var ui = mod.multiplayer_balls._ui
	var recorder = CallRecorder.new()
	recorder.service = ui._service
	ui._service = recorder
	var state = data.duplicate(true)
	state.last_shooter = 1
	state.pending = false
	state.call = {}
	ui.refresh(state)
	var pocket: Dictionary = state.pockets[4]
	var transform: Transform2D = mod.get_viewport().get_canvas_transform()
	var position: Vector2 = transform * pocket.position
	_record(ui._choose_at(position), "Called Shot accepts its caller's pocket click")
	_record(
		recorder.calls == [{"ball": ball_id, "pocket": pocket.index}],
		"Called Shot requests the selected ball and clicked pocket"
	)
	state.last_shooter = 2
	ui.refresh(state)
	_record(
		not ui._choose_at(position) and recorder.calls.size() == 1,
		"non-callers cannot call a pocket"
	)
	state.last_shooter = 1
	state.pending = true
	ui.refresh(state)
	_record(
		not ui._choose_at(position) and recorder.calls.size() == 1,
		"pending ball state blocks calls"
	)
	state.pending = false
	mod.shot_pending = true
	ui.refresh(state)
	_record(
		not ui._choose_at(position) and recorder.calls.size() == 1, "a shot in play blocks calls"
	)
	mod.shot_pending = false

	var second: Dictionary = {}
	for ball in state.balls:
		if ball.id == ball_id:
			second = ball.duplicate(true)
			break
	second.id = 999999999
	second.position += Vector2(70, 0)
	state.balls.append(second)
	state.call = {"ball": ball_id, "pocket": pocket.index, "actor": 1}
	ui.refresh(state)
	_record(ui._choose_at(transform * second.position), "another Called Shot ball can be selected")
	ui.refresh(state)
	_record(ui._selected_ball == second.id, "unchanged call state preserves a new ball selection")
	ui._choose_at(position)
	_record(
		recorder.calls.size() == 2 and recorder.calls.back().ball == second.id,
		"the next pocket click requests the newly selected ball"
	)
	ui._service = recorder.service
	recorder.free()
	ui.refresh(data)


func _record(passed: bool, name: String) -> void:
	checks.append({"name": name, "passed": passed})


func _lobby(tables: Array, count: int) -> Dictionary:
	var players: Array = []
	var seats: Dictionary = {}
	for index in tables.size():
		var table: int = tables[index]
		var slot: int = seats.get(table, 0)
		seats[table] = slot + 1
		players.append(
			{
				"id": index + 1,
				"name": PLAYER_NAMES[index],
				"table": table,
				"slot": slot,
				"ready": true,
				"connected": true,
				"leader": slot == 0 and table >= 0
			}
		)
	return {
		"host_id": 1,
		"capacity": 8,
		"players": players,
		"table_count": count,
		"shot_budget": 6,
		"match_mode": "score",
		"started": false,
		"can_start": true,
		"table_summaries": []
	}


func _results() -> Dictionary:
	var state = _lobby([0, 1, 2, 3, 3, 3], 4)
	state.started = true
	state.can_start = false
	for table in 4:
		state.table_summaries.append(
			{
				"table": table,
				"leader_id": table + 1,
				"score": [285, 240, 210, 255][table],
				"shots_used": 6,
				"shot_budget": 6,
				"status": "Finished",
				"finished": true,
				"bounty_shot": [2, 4, 0, 3][table],
				"bounty_bonus": 25 if table == 0 else 0
			}
		)
	return state


func _set_table(mod: Node) -> void:
	mod.active = true
	mod.table_id = 0
	mod.table_leader_id = 1
	mod._local_id = 1
	mod.lobby = _lobby([0, 0, 0, 0], 1)
	mod.lobby.started = true
	mod.turn_owner = 1
	mod.shot_pending = false
	mod.awaiting_shot_turn = -1
	mod.finished = false
	mod.panel.hide()
	mod.latest_state = mod.adapter.game_data()
	mod.presence.clear()


func _cursor(
	mod: Node,
	id: int,
	space: String,
	position: Vector2,
	origin = Vector2.ZERO,
	vector = Vector2.ZERO
) -> void:
	mod.presence._names[id] = PLAYER_NAMES[id - 1]
	mod.presence._remotes[id] = {
		"age": 0.0,
		"position": position,
		"origin": origin,
		"vector": vector,
		"message":
		{
			"space": space,
			"position": position,
			"origin": origin,
			"vector": vector,
			"table": 0,
			"target": "",
			"aiming": vector != Vector2.ZERO
		}
	}
	mod.presence._overlay.queue_redraw()


func _save(mod: Node) -> Dictionary:
	var panel = mod.panel
	var saved = {
		"process": mod.is_processing(),
		"input": mod.is_processing_input(),
		"transport": mod.transport,
		"ball_process": mod.multiplayer_balls.is_processing(),
		"ball_ui": mod.multiplayer_balls._ui._data.duplicate(true),
		"ball_last_call": mod.multiplayer_balls._ui._last_call.duplicate(true),
		"ball_choice": mod.multiplayer_balls._ui._selected_ball,
		"ball_names": mod.multiplayer_balls._ui._names.duplicate(),
		"presence": mod.presence._remotes.duplicate(true),
		"names": mod.presence._names.duplicate(),
		"panel_visible": panel.visible,
		"panel_state": panel._state.duplicate(true),
		"panel_local": panel._local_id,
		"panel_host": panel._is_host,
		"panel_code": panel._code,
		"panel_open": panel._room_open,
		"panel_invite": not panel.get_node("%Invite").disabled,
		"panel_status": panel.get_node("%Status").text,
		"panel_signals": panel.is_blocking_signals(),
		"friends": []
	}
	var popup = panel.get_node("%Invite").get_popup()
	for index in popup.item_count:
		if not popup.is_item_disabled(index):
			saved.friends.append(
				{"id": popup.get_item_metadata(index), "name": popup.get_item_text(index)}
			)
	for field in MAIN_FIELDS:
		var value = mod.get(field)
		saved[field] = value.duplicate(true) if value is Dictionary else value
	mod.set_process(false)
	mod.set_process_input(false)
	mod.multiplayer_balls.set_process(false)
	panel.set_block_signals(true)
	var offline = OfflineTransport.new()
	offline.people = _lobby([0, 0, 0, 0], 1).players
	mod.transport = offline
	mod.multiplayer_balls._ui._names_at = 0
	return saved


func _restore(mod: Node, saved: Dictionary) -> void:
	mod.transport.free()
	mod.transport = saved.transport
	for field in MAIN_FIELDS:
		mod.set(field, saved[field])
	var panel = mod.panel
	panel.set_connection(saved.panel_code, saved.panel_open, saved.panel_invite)
	panel.render(saved.panel_state, saved.panel_local, saved.panel_host)
	panel.set_status(saved.panel_status)
	panel.set_friends(saved.friends)
	panel.visible = saved.panel_visible
	panel.set_block_signals(saved.panel_signals)
	mod.presence._remotes = saved.presence
	mod.presence._names = saved.names
	mod.presence._overlay.queue_redraw()
	mod.multiplayer_balls._ui._names_at = 0
	mod.multiplayer_balls._ui.refresh(saved.ball_ui)
	mod.multiplayer_balls._ui._selected_ball = saved.ball_choice
	mod.multiplayer_balls._ui._last_call = saved.ball_last_call
	mod.multiplayer_balls._ui._names = saved.ball_names
	mod.multiplayer_balls.set_process(saved.ball_process)
	mod._update_hud()
	mod.set_process_input(saved.input)
	mod.set_process(saved.process)

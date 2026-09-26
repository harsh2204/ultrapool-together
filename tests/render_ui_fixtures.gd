extends RefCounted

const PLAYER_NAMES = ["Alex", "Bea", "Chen", "Drew", "Erin", "Finley", "Gio", "Harper"]
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


class OfflineTransport:
	extends Node

	var people: Array = []
	var is_host = true
	var room_code = "UP8-RENDER-FIXTURE"
	var sent: Array = []

	func session_open() -> bool:
		return true

	func invite_ready() -> bool:
		return false

	func send(message: Dictionary):
		sent.append(message.duplicate(true))

	func send_to(_id: int, message: Dictionary):
		send(message)

	func local_id() -> int:
		return 1

	func participants() -> Array:
		return people


func check_native_run_votes(mod: Node, capture: Callable) -> void:
	var saved = _save(mod)
	var previous_model = mod.lobby_model
	mod.active = false
	mod._local_id = 1
	mod.lobby_model = (
		load(get_script().resource_path.get_base_dir().path_join("../mod/lobby_state.gd")).new()
	)
	var options: Dictionary = mod.run_setup.available_choices()
	var defaults: Dictionary = mod.run_setup.native_defaults()
	_record(
		not options.deck.is_empty() and not options.difficulty.is_empty(),
		"native host unlock catalog contains starting sets and difficulties"
	)
	_record(
		mod.run_setup.validate_config(mod.run_setup.capture_config(defaults)),
		"native menu defaults produce a valid shared run config"
	)
	mod.lobby_model.setup(1, "Host")
	mod.lobby_model.add_player(2, "Guest")
	mod.lobby_model.set_table_count(1, 2)
	mod.lobby_model.choose_slot(2, 1, 0)
	var configured: bool = mod.lobby_model.configure_run_options(1, options, defaults)
	_record(configured, "native catalog publishes through the real lobby model")
	if configured:
		mod.panel.show()
		mod.panel.set_block_signals(false)
		mod._broadcast_lobby()
		for field in ["deck", "difficulty", "match_mode"]:
			for player in [1, 2]:
				mod.lobby_model.set_ready(player, true)
			mod._broadcast_lobby()
			var generation: int = mod.lobby.ready_generation
			var choice: String
			if field == "match_mode":
				var control: OptionButton = mod.panel.get_node("%MatchMode")
				choice = control.get_item_metadata(2)
				control.select(2)
				control.item_selected.emit(2)
			else:
				choice = options[field][0].id
				var button: Button = mod.panel.vote_button(field, choice)
				_record(button != null, "native " + field + " choice has a visible button")
				if button == null:
					continue
				button.pressed.emit()
			_record(
				(
					mod.lobby.run_vote.counts[field].get(choice, 0) == 1
					and mod.lobby.run_vote.selected[field] == choice
				),
				"native " + field + " selector sends its ballot through the controller"
			)
			_record(
				(
					mod.lobby.ready_generation > generation
					and mod.lobby.players.all(func(player): return not player.ready)
				),
				"native " + field + " ballot invalidates everyone's old Ready"
			)
		for field in ["deck", "difficulty"]:
			await _check_vote_cards(mod, field, options[field][0].id)
		var generation: int = mod.lobby.ready_generation
		mod.panel.get_node("%Ready").pressed.emit()
		_record(
			mod.lobby.players[0].ready and not mod.lobby.players[1].ready,
			"native Ready button approves the current vote generation through the controller"
		)
		mod._apply_lobby_request(2, {"action": "ready", "ready": true, "generation": generation})
		_record(mod.lobby.can_start, "guest Ready on the same generation makes the lobby startable")
		_record(
			mod.run_setup.validate_config(
				mod.run_setup.capture_config(mod.lobby.run_vote.selected)
			),
			"native vote result hydrates a valid shared run config"
		)
		await capture.call(
			"lobby-native-vote-input", "Native run votes and Ready travel through the controller."
		)
	mod.lobby_model = previous_model
	_restore(mod, saved)


func _check_vote_cards(mod: Node, field: String, choice: String) -> void:
	var panel = mod.panel
	var button = panel.vote_button(field, choice)
	var abstain: Button = panel.vote_button(field, "")
	if button == null or abstain == null:
		_record(false, field + " cards include their choice and no-preference button")
		return
	_record(
		button.choice_id == choice and button.voter_ids == [1],
		field + " card identifies the host's live ballot"
	)
	_record(
		_pressed_choices(panel, field, mod.lobby) == [choice],
		field + " radio group selects exactly the local ballot"
	)
	var identity = button.get_instance_id()
	button.grab_focus()
	await mod.get_tree().process_frame
	_record(button.has_focus(), field + " card accepts keyboard focus")
	mod._apply_lobby_request(2, _vote_request(mod, field, choice))
	_record(
		panel.vote_button(field, choice).get_instance_id() == identity,
		field + " remote ballot updates the existing card"
	)
	_record(button.has_focus(), field + " remote ballot preserves focused card")
	_record(
		(
			button.voter_ids == [1, 2]
			and "Host" in button.tooltip_text
			and "Guest" in button.tooltip_text
		),
		field + " card exposes both live voter identities"
	)
	_record(
		(
			not button.accessibility_name.is_empty()
			and "Host" in button.accessibility_description
			and "Guest" in button.accessibility_description
		),
		field + " remote ballot refreshes accessible voter names"
	)
	panel.render(mod.lobby, 2, false)
	_record(
		_pressed_choices(panel, field, mod.lobby) == [choice] and not button.disabled,
		field + " guest sees their own selected ballot and can vote"
	)
	_record(button.voter_ids == [1, 2], field + " host and guest see the same live voters")
	var disconnected: Dictionary = mod.lobby.duplicate(true)
	disconnected.players[1].connected = false
	disconnected.run_vote.counts[field][choice] = 1
	panel.render(disconnected, 1, true)
	_record(
		button.voter_ids == [1] and "Guest" not in button.tooltip_text,
		field + " disconnected voter is removed from the card"
	)
	mod._apply_lobby_request(2, _vote_request(mod, field, ""))
	abstain.pressed.emit()
	_record(
		_pressed_choices(panel, field, mod.lobby) == [""] and button.voter_ids.is_empty(),
		field + " no-preference button clears the local ballot and prior voter markers"
	)
	_record(
		mod.lobby.players.all(func(player): return not player.run_votes.has(field)),
		field + " cleared ballots reconcile through the real lobby model"
	)
	panel.render(mod.lobby, 2, false)
	_record(
		_pressed_choices(panel, field, mod.lobby) == [""],
		field + " guest with no ballot sees no preference selected"
	)
	var frozen: Dictionary = mod.lobby.duplicate(true)
	frozen.started = true
	panel.render(frozen, 1, true)
	var disabled = abstain.disabled
	for entry in frozen.run_vote.options[field]:
		disabled = disabled and panel.vote_button(field, entry.id).disabled
	_record(disabled, field + " entire radio group locks when the match starts")
	mod._broadcast_lobby()
	button.pressed.emit()
	_record(
		_pressed_choices(panel, field, mod.lobby) == [choice] and not button.disabled,
		field + " lobby presentation restores a single active vote after frozen display"
	)


func _vote_request(mod: Node, field: String, choice: String) -> Dictionary:
	return {
		"action": "run_vote",
		"field": field,
		"choice": choice,
		"catalog_revision": mod.lobby.run_vote.catalog_revision,
		"match": mod.match_id
	}


func _pressed_choices(panel: Control, field: String, state: Dictionary) -> Array[String]:
	var choices: Array[String] = []
	var abstain: Button = panel.vote_button(field, "")
	if abstain != null and abstain.button_pressed:
		choices.append("")
	for entry in state.run_vote.options[field]:
		var button: Button = panel.vote_button(field, entry.id)
		if button != null and button.button_pressed:
			choices.append(entry.id)
	return choices


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
	panel.set_connection("UP8-RENDER-FIXTURE", true, true)
	panel.render(coop, 1, true)
	await capture.call("lobby-choosing-seats", "Four-player co-op with one player choosing a seat.")
	coop = _lobby([0, 0, 0, 0], 1)
	panel.render(coop, 1, true)
	_record(panel.get_node("%Leave").visible, "host can leave a pre-match lobby")
	await capture.call("lobby-coop-ready", "Four players ready at a shared table.")

	var choices = coop.duplicate(true)
	choices.can_start = false
	for index in choices.players.size():
		var player: Dictionary = choices.players[index]
		player.ready = false
		player.run_votes.deck = "1_CLASSIC" if index == 0 else "2_NATURE"
		player.run_votes.difficulty = "diff_1" if index == 0 else "diff_2"
	_recount_votes(choices)
	panel.render(choices, 1, true)
	await capture.call(
		"lobby-native-run-vote",
		"Native starting-set cards and difficulty buttons show live voters."
	)
	await _capture_full_catalog(mod, capture)
	panel.render(coop, 1, true)

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
	for player in race.players:
		player.run_votes.match_mode = "race"
	_recount_votes(race)
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
	await capture.call(
		"lobby-standings", "Completed table standings with authoritative native scores."
	)
	_restore(mod, saved)


func _capture_full_catalog(mod: Node, capture: Callable) -> void:
	# GAP-002 / PERF-026: this presentation fixture intentionally ignores profile
	# unlocks, so an empty isolated save still exercises every selectable native card.
	var state = _lobby([0, 0, 1, 1, 2, 2, 3, 3], 4)
	var database = mod.get_node("/root/BallDatabase")
	var catalog: Dictionary = state.run_vote.options
	catalog.deck = []
	catalog.difficulty = []
	for resource in database.id_to_deck.values():
		if resource.can_be_chosen and str(resource.id) != "DAILY":
			catalog.deck.append({"id": str(resource.id), "label": tr(str(resource.name))})
	for resource in database.id_to_difficulty.values():
		if resource.can_be_chosen:
			catalog.difficulty.append({"id": str(resource.id), "label": tr(str(resource.name))})
	for field in ["deck", "difficulty"]:
		catalog[field].sort_custom(func(a, b): return a.id < b.id)
	_record(catalog.deck.size() == 8, "full native card fixture includes all eight starting sets")
	_record(
		catalog.difficulty.size() == 5,
		"full native button fixture includes all five selectable difficulties"
	)
	if catalog.deck.is_empty() or catalog.difficulty.is_empty():
		return
	state.run_vote.catalog_revision += 1
	state.can_start = false
	for index in state.players.size():
		var player: Dictionary = state.players[index]
		player.ready = false
		player.run_votes = {
			"deck": catalog.deck[index % catalog.deck.size()].id,
			"difficulty": catalog.difficulty[index % catalog.difficulty.size()].id,
			"match_mode": "score"
		}
	_recount_votes(state)
	mod.panel.render(state, 1, true)
	await mod.get_tree().process_frame
	for field in ["deck", "difficulty"]:
		var seen: Array[int] = []
		var unclipped = true
		var area: Rect2 = mod.panel.get_node("%Body").get_global_rect()
		for entry in catalog[field]:
			var button = mod.panel.vote_button(field, entry.id)
			if button == null:
				unclipped = false
				continue
			if field == "deck":
				var deck: Resource = database.id_to_deck[entry.id]
				var poster: Texture2D = database.get_set_by_id(deck.ball_set).poster
				_record(
					poster != null and button._texture == poster,
					"starting-set card uses the native shop poster for " + entry.id
				)
			unclipped = (
				unclipped
				and button.is_visible_in_tree()
				and area.encloses(button.get_global_rect())
			)
			seen.append_array(button.voter_ids)
		seen.sort()
		_record(unclipped, "full native " + field + " catalog fits the lobby at 1280 by 720")
		_record(
			seen == [1, 2, 3, 4, 5, 6, 7, 8],
			"full native " + field + " catalog shows every player's live vote once"
		)
	_record(clipped_players(mod).is_empty(), "full native catalog leaves all eight players visible")
	await capture.call(
		"lobby-full-native-catalog",
		"Every native starting-set card and difficulty with eight players across four tables."
	)
	var selected_deck: String = catalog.deck[0].id
	var selected_difficulty: String = catalog.difficulty[0].id
	for player in state.players:
		player.run_votes.deck = selected_deck
		player.run_votes.difficulty = selected_difficulty
	_recount_votes(state)
	mod.panel.render(state, 8, false)
	for field in ["deck", "difficulty"]:
		var selected: String = state.run_vote.selected[field]
		var button = mod.panel.vote_button(field, selected)
		_record(
			(
				button.voter_ids == [1, 2, 3, 4, 5, 6, 7, 8]
				and PLAYER_NAMES.all(func(player_name): return player_name in button.tooltip_text)
			),
			field + " consensus retains all eight voter identities"
		)
		_record(
			_pressed_choices(mod.panel, field, state) == [selected],
			field + " consensus selects the eighth guest's ballot"
		)
	await capture.call(
		"lobby-eight-player-consensus",
		"Eight-player agreement remains visible from a guest's view."
	)


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
	mod._update_hud()
	await capture.call("table-your-turn", "Your turn with the selected native starting set.")

	mod.turn_owner = 2
	var game = mod.get_node("/root/Global").gameManager
	var origin: Vector2 = game.player_ball.global_position
	_cursor(mod, 2, "table", origin + Vector2(70, -100), origin, Vector2(70, -100))
	mod._update_hud()
	await capture.call("table-teammate-aim", "Teammate turn with the shared native aim preview.")

	mod.presence.clear()
	mod.lobby = _results()
	mod.finished = true
	mod.finish_reason = "Shot budget used"
	mod.total_score = 260.0
	mod.used_shots = 6
	mod._update_hud()
	await capture.call("table-match-result", "The winning table's end-of-match HUD.")
	_restore(mod, saved)


func capture_shop_presence(mod: Node, capture: Callable, input: Node) -> void:
	var saved = _save(mod)
	_set_table(mod)
	mod.latest_state.in_shop = true
	mod._update_hud()
	var shop = mod.shop_sync
	var section: String = shop.current_section()
	_record(shop.show_section("balls"), "native ball shop is available")
	await mod.get_tree().create_timer(0.6).timeout
	_cursor(mod, 2, "shop", Vector2(0.3, 0.35))
	_cursor(mod, 3, "shop", Vector2(0.72, 0.55))
	await capture.call("shop-shared", "Native shared shop, player cursors and native ball offers.")

	var inspected = false
	input.begin(shop.native_shop())
	for slot in shop._state.get("slots", []):
		if slot.get("group", "") == "build" and slot.get("id", 0) != 0:
			await input.hover(shop.slot_item(slot.key))
			inspected = shop.native_shop().selected_ball == shop.slot_item(slot.key)
			break
	_record(inspected, "native shop displays selected starter inspection")
	if inspected:
		await mod.get_tree().create_timer(0.45).timeout
		_record(
			mod.get_node("/root/UIManager").info_display.main_panel.is_visible_in_tree(),
			"native shop inspection card is visibly rendered"
		)
		await capture.call("shop-ball-details", "A native starter's description and shop actions.")
	input.finish()
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
	_restore(mod, saved)


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
				"leader": slot == 0 and table >= 0,
				"run_votes": {"deck": "1_CLASSIC", "difficulty": "diff_1", "match_mode": "score"}
			}
		)
	var state = {
		"host_id": 1,
		"capacity": 8,
		"players": players,
		"table_count": count,
		"shot_budget": 6,
		"match_mode": "score",
		"run_vote":
		{
			"catalog_revision": 1,
			"options":
			{
				"deck":
				[{"id": "1_CLASSIC", "label": "Classic"}, {"id": "2_NATURE", "label": "Nature"}],
				"difficulty":
				[
					{"id": "diff_1", "label": "Chill Pool Night"},
					{"id": "diff_2", "label": "Wine Mixer"}
				],
				"match_mode":
				[{"id": "race", "label": "Race"}, {"id": "score", "label": "Score PvP"}]
			},
			"counts": {},
			"selected": {"deck": "1_CLASSIC", "difficulty": "diff_1", "match_mode": "score"}
		},
		"started": false,
		"can_start": true,
		"table_summaries": []
	}
	_recount_votes(state)
	return state


func _recount_votes(state: Dictionary) -> void:
	for field in state.run_vote.options:
		var counts: Dictionary = {}
		for player in state.players:
			if not player.get("connected", true):
				continue
			var choice: String = player.get("run_votes", {}).get(field, "")
			if not choice.is_empty():
				counts[choice] = counts.get(choice, 0) + 1
		state.run_vote.counts[field] = counts
		var highest = 0
		for entry in state.run_vote.options[field]:
			var count: int = counts.get(entry.id, 0)
			if count > highest:
				highest = count
				state.run_vote.selected[field] = entry.id


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
				"finished": true
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
	panel.set_block_signals(true)
	var offline = OfflineTransport.new()
	offline.people = _lobby([0, 0, 0, 0], 1).players
	mod.transport = offline
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
	mod._update_hud()
	mod.set_process_input(saved.input)
	mod.set_process(saved.process)

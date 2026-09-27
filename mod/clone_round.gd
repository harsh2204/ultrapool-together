extends RefCounted

## Clone-table special rounds.
##
## Reuses solo-table control semantics: each seated member is assigned their own
## instance of the shared table layout for the round. Scores are compared like
## Score PvP table summaries, then only the winner may use the following shared
## shop. Normal turn-taking and shared shopping resume after that one shop.
## Exclusive to Together All Nighter (`diff_together_nighter`).

const DifficultyCatalog = preload("difficulty_catalog.gd")


static func difficulty_id(lobby: Dictionary) -> String:
	var run_vote = lobby.get("run_vote", {})
	if run_vote is Dictionary:
		var selected = run_vote.get("selected", {})
		if selected is Dictionary and selected.has("difficulty"):
			return str(selected.difficulty)
	return str(lobby.get("difficulty", ""))


static func allowed_for_difficulty(lobby: Dictionary) -> bool:
	return difficulty_id(lobby) == DifficultyCatalog.together_nighter_id()


static func enabled(lobby: Dictionary) -> bool:
	return bool(lobby.get("clone_rounds", false)) and allowed_for_difficulty(lobby)


static func should_run(lobby: Dictionary, member_ids: Array) -> bool:
	return enabled(lobby) and member_ids.size() >= 2


static func assign_instances(member_ids: Array) -> Array:
	var sorted: Array = []
	for id in member_ids:
		sorted.append(int(id))
	sorted.sort()
	var instances: Array = []
	for index in sorted.size():
		instances.append(
			{"player_id": sorted[index], "instance_id": index, "score": 0.0, "finished": false}
		)
	return instances


static func find_index(instances: Array, player_id: int) -> int:
	for index in instances.size():
		if int(instances[index].player_id) == player_id:
			return index
	return -1


static func has_instance(instances: Array, player_id: int) -> bool:
	return find_index(instances, player_id) >= 0


static func record_score(instances: Array, player_id: int, score: float) -> bool:
	var index = find_index(instances, player_id)
	if index < 0:
		return false
	instances[index].score = float(score)
	return true


static func mark_finished(instances: Array, player_id: int, score: float) -> bool:
	var index = find_index(instances, player_id)
	if index < 0:
		return false
	instances[index].score = float(score)
	instances[index].finished = true
	return true


static func finish_all(instances: Array) -> void:
	for entry in instances:
		entry.finished = true


static func all_finished(instances: Array) -> bool:
	if instances.is_empty():
		return false
	for entry in instances:
		if not entry.finished:
			return false
	return true


## Highest score wins. Ties break to the lowest player id so exactly one player
## receives the winner-only shop.
static func pick_winner(instances: Array) -> int:
	var winner_id = 0
	var best = 0.0
	var found = false
	for entry in instances:
		if not entry.get("finished", false):
			continue
		var score = float(entry.score)
		var player_id = int(entry.player_id)
		if (
			not found
			or score > best
			or (is_equal_approx(score, best) and (winner_id == 0 or player_id < winner_id))
		):
			found = true
			best = score
			winner_id = player_id
	return winner_id if found else 0


static func snapshot(instances: Array, active: bool, winner_id: int, shop_armed: bool) -> Dictionary:
	return {
		"active": active,
		"instances": instances.duplicate(true),
		"winner_id": winner_id,
		"shop_armed": shop_armed
	}

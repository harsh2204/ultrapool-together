extends RefCounted

const REWARD = 25.0


static func resolve(summaries: Array, competitive: bool) -> void:
	var complete = competitive and not summaries.is_empty()
	var earliest = 0
	for summary in summaries:
		summary.bounty_bonus = 0.0
		summary.score = summary.base_score
		complete = complete and summary.finished
		if summary.bounty_shot > 0 and (earliest == 0 or summary.bounty_shot < earliest):
			earliest = summary.bounty_shot
	if not complete or earliest == 0:
		return
	for summary in summaries:
		if summary.bounty_shot == earliest:
			summary.bounty_bonus = REWARD
			summary.score = summary.base_score + REWARD

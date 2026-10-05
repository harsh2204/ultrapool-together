extends RefCounted

const REWARD = 25.0


static func resolve(summaries: Array, competitive: bool) -> void:
	var complete = competitive and not summaries.is_empty()
	var earliest = 0
	for summary in summaries:
		var base = float(summary.get("base_score", summary.get("score", 0.0)))
		summary.base_score = base
		summary.bounty_bonus = 0.0
		summary.score = base
		complete = complete and bool(summary.get("finished", false))
		var shot = int(summary.get("bounty_shot", 0))
		if shot > 0 and (earliest == 0 or shot < earliest):
			earliest = shot
	if not complete or earliest == 0:
		return
	for summary in summaries:
		if int(summary.get("bounty_shot", 0)) == earliest:
			summary.bounty_bonus = REWARD
			summary.score = float(summary.base_score) + REWARD


## MOD-04: render only a finalized authoritative award. This helper never
## resolves standings or modifies score, so duplicate lobby/resync updates are inert.
static func award_text(summary: Dictionary) -> String:
	if not summary.get("finished") is bool or not summary.finished:
		return ""
	if not summary.get("bounty_shot") is int or summary.bounty_shot <= 0:
		return ""
	var bonus = summary.get("bounty_bonus")
	if not (bonus is int or bonus is float) or not is_finite(float(bonus)) or bonus != REWARD:
		return ""
	return "Bounty +25 points"

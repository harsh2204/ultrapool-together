extends RefCounted
## Run-owned cue handling, independent from cosmetic finishes. Refs PERF-013/030.
## The authoritative table maps an accepted shot once, then broadcasts that same
## vector. No physics properties, resources, or persistent native state are changed.

const DEFAULT_ID = "house"
const MIN_SHOT_LENGTH = 50.0
const MAX_SHOT_LENGTH = 200.0
const ROUND_BONUS_CAP = 4.0
const BONUS_LIMITS = "First qualifying pot per shot. Fractional points; +4/player/round across cues."
# Prices reflect repeatability as well as payout. Trick shots keep higher caps
# than easier triggers; every scoring model still shares ROUND_BONUS_CAP.
const MODELS = [
	{
		"id": "house",
		"label": "House",
		"price": 0,
		"bias": 0.0,
		"bonus_rate": 0.0,
		"bonus_cap": 0.0,
		"trigger": "",
		"asset": "house.png",
		"description": "The familiar native feel. A straight, predictable power response.",
	},
	{
		"id": "finesse",
		"label": "Finesse",
		"price": 2,
		"bias": -0.30,
		"bonus_rate": 0.0,
		"bonus_cap": 0.0,
		"trigger": "",
		"asset": "finesse.png",
		"description":
		(
			"Slightly gentler light shots; slightly firmer heavy shots. "
			+ "Midpoint and maximum power stay unchanged."
		),
	},
	{
		"id": "firm",
		"label": "Firm",
		"price": 2,
		"bias": 0.30,
		"bonus_rate": 0.0,
		"bonus_cap": 0.0,
		"trigger": "",
		"asset": "firm.png",
		"description":
		(
			"Slightly firmer light shots; slightly gentler heavy shots. "
			+ "Midpoint and maximum power stay unchanged."
		),
	},
	{
		"id": "bankshot",
		"label": "Bankshot",
		"price": 7,
		"bias": 0.0,
		"bonus_rate": 0.06,
		"bonus_cap": 2.0,
		"trigger": "bankshot",
		"asset": "bankshot.png",
		"description": "+6% if the potted ball hit a rail (+2 max). " + BONUS_LIMITS,
	},
	{
		"id": "double_rail",
		"label": "Double Rail",
		"price": 6,
		"bias": 0.0,
		"bonus_rate": 0.09,
		"bonus_cap": 2.5,
		"trigger": "double_rail",
		"asset": "double_rail.png",
		"description": "+9% if the potted ball hit rails twice (+2.5 max). " + BONUS_LIMITS,
	},
	{
		"id": "carom",
		"label": "Carom",
		"price": 5,
		"bias": 0.0,
		"bonus_rate": 0.10,
		"bonus_cap": 2.5,
		"trigger": "carom",
		"asset": "carom.png",
		"description": "+10% if the potted ball hit 2 distinct object balls (+2.5 max). " + BONUS_LIMITS,
	},
	{
		"id": "silk",
		"label": "Silk",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.04,
		"bonus_cap": 1.5,
		"trigger": "silk",
		"asset": "silk.png",
		"description": "+4% on light shots, pull 90 or less (+1.5 max). " + BONUS_LIMITS,
	},
	{
		"id": "thunder",
		"label": "Thunder",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.04,
		"bonus_cap": 1.5,
		"trigger": "thunder",
		"asset": "thunder.png",
		"description": "+4% on heavy shots, pull 170 or more (+1.5 max). " + BONUS_LIMITS,
	},
	{
		"id": "opener",
		"label": "Opener",
		"price": 3,
		"bias": 0.0,
		"bonus_rate": 0.06,
		"bonus_cap": 1.5,
		"trigger": "opener",
		"asset": "opener.png",
		"description": "+6% on the round's first shot (+1.5 points max). " + BONUS_LIMITS,
	},
	{
		"id": "closer",
		"label": "Closer",
		"price": 8,
		"bias": 0.0,
		"bonus_rate": 0.05,
		"bonus_cap": 2.0,
		"trigger": "closer",
		"asset": "closer.png",
		"description": "+5% if 3 or fewer ordinary balls start the shot (+2 max). " + BONUS_LIMITS,
	},
	{
		"id": "comeback",
		"label": "Comeback",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.06,
		"bonus_cap": 1.5,
		"trigger": "comeback",
		"asset": "comeback.png",
		"description": "+6% after your previous shot potted nothing (+1.5 max). " + BONUS_LIMITS,
	},
	{
		"id": "relay",
		"label": "Relay",
		"price": 7,
		"bias": 0.0,
		"bonus_rate": 0.05,
		"bonus_cap": 2.0,
		"trigger": "relay",
		"asset": "relay.png",
		"description": "+5% after a teammate's shot made a pot (+2 max). " + BONUS_LIMITS,
	},
	{
		"id": "corner",
		"label": "Corner",
		"price": 5,
		"bias": 0.0,
		"bonus_rate": 0.03,
		"bonus_cap": 1.5,
		"trigger": "corner",
		"asset": "corner.png",
		"description": "+3% in fixed corner pockets (+1.5 points max). " + BONUS_LIMITS,
	},
	{
		"id": "sidewinder",
		"label": "Sidewinder",
		"price": 5,
		"bias": 0.0,
		"bonus_rate": 0.05,
		"bonus_cap": 1.5,
		"trigger": "sidewinder",
		"asset": "sidewinder.png",
		"description": "+5% in fixed middle pockets (+1.5 points max). " + BONUS_LIMITS,
	},
	{
		"id": "clean",
		"label": "Clean",
		"price": 3,
		"bias": 0.0,
		"bonus_rate": 0.03,
		"bonus_cap": 1.0,
		"trigger": "clean",
		"asset": "clean.png",
		"description": "+3% with no object-ball rail hit (+1 point max). " + BONUS_LIMITS,
	},
]


static func entries() -> Array:
	return MODELS.duplicate(true)


static func ids() -> Array:
	var result: Array = []
	for model in MODELS:
		result.append(model.id)
	return result


static func is_known(model_id: String) -> bool:
	for model in MODELS:
		if model.id == model_id:
			return true
	return false


static func entry(model_id: String) -> Dictionary:
	for model in MODELS:
		if model.id == model_id:
			return model.duplicate(true)
	return MODELS[0].duplicate(true)


static func shot_vector(vector: Vector2, model_id: String) -> Vector2:
	# This is a power mapping, not permission to shoot. Actor, turn, ownership,
	# replay, and raw-input validation must succeed before the table calls it.
	if not vector.is_finite():
		return Vector2.ZERO
	var length: float = vector.length()
	if not is_finite(length):
		return Vector2.ZERO
	if length <= MIN_SHOT_LENGTH:
		return vector
	if length >= MAX_SHOT_LENGTH:
		return vector.limit_length(MAX_SHOT_LENGTH)
	var bias: float = 0.0
	for model in MODELS:
		if model.id == model_id:
			bias = model.bias
			break
	if bias == 0.0:
		return vector
	var span: float = MAX_SHOT_LENGTH - MIN_SHOT_LENGTH
	var t: float = (length - MIN_SHOT_LENGTH) / span
	# Bias +/-0.30 shifts power at most 4.331 native length units (2.17% of
	# full power). The curve is monotonic; min/mid/max and direction are fixed.
	var adjusted: float = t + bias * t * (1.0 - t) * (1.0 - 2.0 * t)
	return vector * ((MIN_SHOT_LENGTH + span * adjusted) / length)

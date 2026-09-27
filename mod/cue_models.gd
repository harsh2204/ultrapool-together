extends RefCounted
## Run-owned cue handling, independent from cosmetic finishes. Refs PERF-013/030.
## The authoritative table maps an accepted shot once, then broadcasts that same
## vector. No physics properties, resources, or persistent native state are changed.

const DEFAULT_ID = "house"
const MIN_SHOT_LENGTH = 50.0
const MAX_SHOT_LENGTH = 200.0
const ROUND_BONUS_CAP = 4.0
const BONUS_LIMITS = (
	"First qualifying pot per shot. Fractional points; +4/player/round across cues."
)
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
		"price": 4,
		"bias": -0.30,
		"bonus_rate": 0.0,
		"bonus_cap": 0.0,
		"trigger": "",
		"asset": "finesse.png",
		"description": (
			"Slightly gentler light shots; slightly firmer heavy shots. "
			+ "Midpoint and maximum power stay unchanged."
		),
	},
	{
		"id": "firm",
		"label": "Firm",
		"price": 4,
		"bias": 0.30,
		"bonus_rate": 0.0,
		"bonus_cap": 0.0,
		"trigger": "",
		"asset": "firm.png",
		"description": (
			"Slightly firmer light shots; slightly gentler heavy shots. "
			+ "Midpoint and maximum power stay unchanged."
		),
	},
	{
		"id": "bankshot",
		"label": "Bankshot",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.04,
		"bonus_cap": 2.0,
		"trigger": "bankshot",
		"asset": "bankshot.png",
		"description": "+4% after a rail hit (+2 points max). " + BONUS_LIMITS,
	},
	{
		"id": "double_rail",
		"label": "Double Rail",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.06,
		"bonus_cap": 2.0,
		"trigger": "double_rail",
		"asset": "double_rail.png",
		"description": "+6% after two rail hits (+2 points max). " + BONUS_LIMITS,
	},
	{
		"id": "carom",
		"label": "Carom",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.06,
		"bonus_cap": 2.0,
		"trigger": "carom",
		"asset": "carom.png",
		"description": "+6% after hitting two different object balls (+2 max). " + BONUS_LIMITS,
	},
	{
		"id": "silk",
		"label": "Silk",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.03,
		"bonus_cap": 1.5,
		"trigger": "silk",
		"asset": "silk.png",
		"description": "+3% on light shots, pull 90 or less (+1.5 max). " + BONUS_LIMITS,
	},
	{
		"id": "thunder",
		"label": "Thunder",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.03,
		"bonus_cap": 1.5,
		"trigger": "thunder",
		"asset": "thunder.png",
		"description": "+3% on heavy shots, pull 170 or more (+1.5 max). " + BONUS_LIMITS,
	},
	{
		"id": "opener",
		"label": "Opener",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.05,
		"bonus_cap": 2.0,
		"trigger": "opener",
		"asset": "opener.png",
		"description": "+5% on the round's first shot (+2 points max). " + BONUS_LIMITS,
	},
	{
		"id": "closer",
		"label": "Closer",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.04,
		"bonus_cap": 2.0,
		"trigger": "closer",
		"asset": "closer.png",
		"description": "+4% if 3 or fewer ordinary balls start the shot (+2 max). " + BONUS_LIMITS,
	},
	{
		"id": "comeback",
		"label": "Comeback",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.05,
		"bonus_cap": 2.0,
		"trigger": "comeback",
		"asset": "comeback.png",
		"description": "+5% after your previous shot potted nothing (+2 max). " + BONUS_LIMITS,
	},
	{
		"id": "relay",
		"label": "Relay",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.03,
		"bonus_cap": 1.5,
		"trigger": "relay",
		"asset": "relay.png",
		"description": "+3% after a teammate's shot made a pot (+1.5 max). " + BONUS_LIMITS,
	},
	{
		"id": "corner",
		"label": "Corner",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.02,
		"bonus_cap": 1.0,
		"trigger": "corner",
		"asset": "corner.png",
		"description": "+2% in fixed corner pockets (+1 point max). " + BONUS_LIMITS,
	},
	{
		"id": "sidewinder",
		"label": "Sidewinder",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.03,
		"bonus_cap": 1.5,
		"trigger": "sidewinder",
		"asset": "sidewinder.png",
		"description": "+3% in fixed middle pockets (+1.5 points max). " + BONUS_LIMITS,
	},
	{
		"id": "clean",
		"label": "Clean",
		"price": 4,
		"bias": 0.0,
		"bonus_rate": 0.02,
		"bonus_cap": 1.0,
		"trigger": "clean",
		"asset": "clean.png",
		"description": "+2% with no object-ball rail hit (+1 point max). " + BONUS_LIMITS,
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

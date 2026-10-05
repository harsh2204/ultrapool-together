extends RefCounted

const MAX_BALLS = 128
const RELAY = "TOGETHER_RELAY"
const CALL = "TOGETHER_CALL"
const PATIENCE = "TOGETHER_PATIENCE"
const BOUNTY = "TOGETHER_BOUNTY"
const BANKROLL = "TOGETHER_BANKROLL"
const LIFELINE = "TOGETHER_LIFELINE"
const ENCORE = "TOGETHER_ENCORE"
const DOMINO = "TOGETHER_DOMINO"
const KINDS = [RELAY, CALL, PATIENCE, BOUNTY, BANKROLL, LIFELINE, ENCORE, DOMINO]

var balls: Dictionary = {}
var last_shooter = 0
var shot_index = 0
var shooter = 0
var pending = false
var call_state: Dictionary = {}
var bounty_shot = 0
# PERF-028 / MOD-04..06: five fixed outcome slots, never an event backlog.
# Receipts live until the next round/session. Resync reads them; it cannot replay
# scoring, healing or respawning. The round generation changes even with no receipt.
var feedback_generation = 0
var feedback: Dictionary = {}
var _round_key = ""
var _competitive = false
var _solo_table = false
var _hit_object = false
var _walls: Dictionary = {}
var _pocketed: Dictionary = {}
var _utilities: Dictionary = {}
var _domino_armed = false


func reset_round(round_key: String) -> void:
	if round_key == _round_key:
		return
	_round_key = round_key
	feedback_generation += 1
	feedback = {}
	balls.clear()
	last_shooter = 0
	shooter = 0
	pending = false
	call_state.clear()
	_utilities.clear()
	_clear_shot()


func register_ball(id: int, kinds: Array) -> void:
	if id <= 0:
		return
	var registered: Array = []
	for kind in kinds:
		if kind in KINDS and kind not in registered:
			registered.append(kind)
	if not balls.has(id):
		balls[id] = {"kinds": [], "marker": 0, "marked_shot": 0, "charge": 0, "paid": {}}
	balls[id].kinds = registered


func begin_shot(accepted_index: int, actor: int, competitive: bool, member_count: int) -> bool:
	if pending or accepted_index <= shot_index or actor <= 0 or member_count < 1:
		return false
	shot_index = accepted_index
	shooter = actor
	_competitive = competitive
	_solo_table = member_count == 1
	pending = true
	_clear_shot()
	return true


func hit(ball_id: int) -> void:
	if not pending or ball_id <= 0:
		return
	_hit_object = true
	if not balls.has(ball_id):
		return
	var ball: Dictionary = balls[ball_id]
	if RELAY in ball.kinds and ball.marked_shot == 0 and not ball.paid.has(RELAY):
		ball.marker = shooter
		ball.marked_shot = shot_index


func wall(ball_id: int) -> void:
	if pending and ball_id > 0:
		_walls[ball_id] = true


func call_ball(actor: int, ball_id: int, pocket_index: int) -> bool:
	if (
		pending
		or actor <= 0
		or actor != last_shooter
		or pocket_index < 0
		or pocket_index > 5
		or not balls.has(ball_id)
		or CALL not in balls[ball_id].kinds
		or balls[ball_id].paid.has(CALL)
	):
		return false
	call_state = {"ball": ball_id, "pocket": pocket_index, "actor": actor}
	return true


func pocket(
	ball_id: int, kinds: Array, base_value: float, pocket_index: int, ordinary: bool
) -> Dictionary:
	var result = {"points": 0.0, "money": 0, "heal": 0, "encore": false, "bounty": false}
	if not pending or ball_id <= 0 or _pocketed.has(ball_id):
		return result
	_pocketed[ball_id] = true
	register_ball(ball_id, kinds)
	var ball: Dictionary = balls[ball_id]
	var value = maxf(0.0, base_value) if is_finite(base_value) else 0.0
	if _domino_armed and ordinary and ball.kinds.is_empty():
		result.points += ceilf(value)
		_record_feedback("domino", ball_id, "awarded", ceilf(value))
		_domino_armed = false
	for kind in ball.kinds:
		if ball.paid.has(kind):
			continue
		match kind:
			RELAY:
				if (
					ball.marked_shot > 0
					and ball.marked_shot < shot_index
					and (_competitive or _solo_table or ball.marker != shooter)
				):
					result.points += ceilf(value * 0.5)
					ball.paid[kind] = true
			CALL:
				if call_state.get("ball") == ball_id and call_state.get("pocket") == pocket_index:
					result.points += ceilf(value)
					ball.paid[kind] = true
			PATIENCE:
				result.points += ceilf(value * 0.25 * ball.charge)
				ball.paid[kind] = true
			BOUNTY:
				if bounty_shot == 0:
					bounty_shot = shot_index
					result.bounty = true
					if not _competitive and shot_index <= 3:
						result.points += 10.0
					_record_feedback("bounty_award", ball_id,
						"claimed" if _competitive else ("awarded" if shot_index <= 3 else "late"),
						10 if not _competitive and shot_index <= 3 else 0)
				ball.paid[kind] = true
			BANKROLL:
				if _walls.has(ball_id) and not _utilities.has(kind):
					result.money = 2
					_record_feedback("bankroll", ball_id, "awarded", 2)
					_utilities[kind] = true
			LIFELINE:
				if not _utilities.has(kind):
					result.heal = 1
					_utilities[kind] = true
			ENCORE:
				if not _utilities.has(kind):
					result.encore = true
					_record_feedback("encore", ball_id, "pending")
					_utilities[kind] = true
			DOMINO:
				if not _utilities.has(kind):
					_domino_armed = true
					_utilities[kind] = true
	return result


func _record_feedback(kind: String, ball_id: int, status: String, amount = 0) -> void:
	feedback[kind] = {"ball": ball_id, "shot": shot_index, "status": status, "amount": amount}


## Called after the authoritative native HP mutation; a full-health pot has zero
## applied healing. Do not infer health feedback from a requested +1 action.
func record_heal(ball_id: int, amount: int) -> void:
	if not _pocketed.has(ball_id) or not balls.has(ball_id) or LIFELINE not in balls[ball_id].kinds:
		return
	if not _utilities.has(LIFELINE) or feedback.has("lifeline") or amount not in [0, 1]:
		return
	_record_feedback("lifeline", ball_id, "healed" if amount > 0 else "full", clampi(amount, 0, 1))


## A pending Encore can resolve once. A repeated callback or resync cannot turn a
## terminal outcome back into a pending return or replace its originating shot.
func record_encore(status: String) -> void:
	if not feedback.has("encore") or feedback.encore.status != "pending":
		return
	if status in ["returned", "unavailable", "cancelled"]:
		feedback.encore = feedback.encore.duplicate()
		feedback.encore.status = status


func capture_feedback() -> Dictionary:
	return {"generation": feedback_generation, "outcomes": feedback.duplicate(true)}


static func valid_feedback(data) -> bool:
	if not data is Dictionary or data.size() != 2:
		return false
	if not data.get("generation") is int or data.generation < 0:
		return false
	if not data.get("outcomes") is Dictionary or data.outcomes.size() > 5:
		return false
	for kind in data.outcomes:
		var receipt = data.outcomes[kind]
		if not receipt is Dictionary or receipt.size() != 4:
			return false
		if not receipt.get("ball") is int or receipt.ball <= 0:
			return false
		if not receipt.get("shot") is int or receipt.shot <= 0:
			return false
		if (not receipt.get("amount") is int and not receipt.get("amount") is float) or not is_finite(float(receipt.amount)) or not receipt.get("status") is String:
			return false
		match kind:
			"bounty_award":
				if receipt.status not in ["awarded", "late", "claimed"]:
					return false
				if receipt.amount != (10 if receipt.status == "awarded" else 0):
					return false
			"bankroll":
				if receipt.status != "awarded" or receipt.amount != 2:
					return false
			"domino":
				if receipt.status != "awarded" or receipt.amount < 0:
					return false
			"lifeline":
				if receipt.status not in ["healed", "full"]:
					return false
				if receipt.amount != (1 if receipt.status == "healed" else 0):
					return false
			"encore":
				if receipt.status not in ["pending", "returned", "unavailable", "cancelled"] or receipt.amount != 0:
					return false
			_:
				return false
	return true


func finish_shot(survivors: Array) -> void:
	if not pending:
		return
	if _hit_object:
		for id in survivors:
			if not balls.has(id) or _pocketed.has(id):
				continue
			var ball: Dictionary = balls[id]
			if PATIENCE in ball.kinds and not ball.paid.has(PATIENCE):
				ball.charge = mini(3, ball.charge + 1)
	last_shooter = shooter
	pending = false
	call_state.clear()
	_clear_shot()


func _clear_shot() -> void:
	_hit_object = false
	_walls.clear()
	_pocketed.clear()
	_domino_armed = false


## Compact signature of guest-visible ball state. Host state publishes must include this
## so calls, Relay markers, and Patience charges reach teammates when nothing else changes.
static func display_signature(data: Dictionary) -> Array:
	var signature: Array = [
		data.get("last_shooter", 0),
		data.get("pending", false),
		data.get("bounty_shot", 0),
		data.get("call", {}),
		data.get("feedback", {})
	]
	for ball in data.get("balls", []):
		if not ball is Dictionary:
			continue
		signature.append(
			[
				ball.get("id", 0),
				ball.get("marker", 0),
				ball.get("charge", 0),
				ball.get("callable", false),
				ball.get("alive", false)
			]
		)
	return signature


## Encore may still fire after native round_ended starts; only a cashed-out or shop phase
## permanently cancels the pending return.
static func encore_cancelled(in_shop: bool, round_finalized: bool) -> bool:
	return in_shop or round_finalized


static func valid_state(data) -> bool:
	if not data is Dictionary:
		return false
	if data.is_empty():
		return true
	# Optional protocol-10 display extension: older peers omit or ignore it.
	if data.has("feedback") and not valid_feedback(data.feedback):
		return false
	for field in ["last_shooter", "bounty_shot"]:
		if not data.get(field) is int or data[field] < 0:
			return false
	if (
		not data.get("pending") is bool
		or not data.get("call") is Dictionary
		or not data.get("balls") is Array
		or data.balls.size() > MAX_BALLS
		or not data.get("pockets") is Array
		or data.pockets.size() > 6
	):
		return false
	var ids: Dictionary = {}
	for ball in data.balls:
		if not ball is Dictionary or not ball.get("id") is int or ball.id <= 0 or ids.has(ball.id):
			return false
		if (
			not ball.get("kinds") is Array
			or ball.kinds.is_empty()
			or ball.kinds.size() > 2
			or not ball.get("name") is String
			or ball.name.length() > 160
			or not ball.get("position") is Vector2
			or not ball.position.is_finite()
			or ball.position.length() > 100000
			or not ball.get("color") is Color
			or not ball.get("marker") is int
			or ball.marker < 0
			or not ball.get("charge") is int
			or ball.charge < 0
			or ball.charge > 3
			or not ball.get("alive") is bool
			or not ball.get("callable") is bool
		):
			return false
		for channel in [ball.color.r, ball.color.g, ball.color.b, ball.color.a]:
			if not is_finite(channel):
				return false
		var kinds: Array = []
		for kind in ball.kinds:
			if kind not in KINDS or kind in kinds:
				return false
			kinds.append(kind)
		ids[ball.id] = kinds
	var pockets: Dictionary = {}
	for pocket in data.pockets:
		if (
			not pocket is Dictionary
			or not pocket.get("index") is int
			or pocket.index < 0
			or pocket.index > 5
			or pockets.has(pocket.index)
			or not pocket.get("position") is Vector2
			or not pocket.position.is_finite()
			or pocket.position.length() > 100000
			or not pocket.get("open") is bool
		):
			return false
		pockets[pocket.index] = true
	if not data.call.is_empty():
		for key in ["ball", "pocket", "actor"]:
			if not data.call.get(key) is int:
				return false
		if (
			not ids.has(data.call.ball)
			or CALL not in ids[data.call.ball]
			or not pockets.has(data.call.pocket)
			or data.call.actor <= 0
			or data.call.actor != data.last_shooter
		):
			return false
	return true

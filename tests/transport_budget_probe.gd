extends SceneTree


class SteamStub:
	extends RefCounted
	var reliable: Array = []
	var transient: Array = []
	var requested_counts: Array = []

	func run_callbacks() -> void:
		pass

	# Match GodotSteam's API spelling.
	# gdlint: disable=function-name
	func receiveMessagesOnChannel(channel: int, maximum: int) -> Array:
		requested_counts.append(maximum)
		var queue: Array = reliable if channel == 47 else transient
		return [] if queue.is_empty() else [queue.pop_front()]


class BudgetTransport:
	extends "../mod/transport.gd"
	var delivered: Array = []
	var one_packet_per_frame := false

	func _receive_budget_available(started_usec: int) -> bool:
		return (
			super._receive_budget_available(started_usec)
			and (not one_packet_per_frame or _receive_packets == 0)
		)

	func _receive_wire(sender: int, packet: PackedByteArray, transient := false) -> void:
		delivered.append({"sender": sender, "sequence": packet[0], "transient": transient})


var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_packet_limit_and_reliable_retention()
	_fairness_across_frames()
	_byte_limit_keeps_next_packet_queued()
	_time_limit_allows_first_message()
	for failure in failures:
		print("TRANSPORT_BUDGET_PROBE FAIL ", failure)
	print("TRANSPORT_BUDGET_PROBE ", "PASS" if failures.is_empty() else "FAIL", " ", checks)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _packet(sequence: int, byte_count := 1) -> Dictionary:
	var payload := PackedByteArray([sequence])
	payload.resize(byte_count)
	return {"identity": 42, "payload": payload}


func _new_transport() -> BudgetTransport:
	var transport := BudgetTransport.new()
	transport._steam = SteamStub.new()
	transport._mode = "steam"
	return transport


func _dispose(transport: BudgetTransport) -> void:
	transport.close()
	transport._steam = null
	transport.free()


func _packet_limit_and_reliable_retention() -> void:
	var transport := _new_transport()
	var steam: SteamStub = transport._steam
	for sequence in range(64):
		steam.reliable.append(_packet(sequence))
		steam.transient.append(_packet(sequence))
	for _frame in range(128):
		transport._process(0.016)
		var stats := transport.receive_stats
		_check(stats.packets <= transport.RECEIVE_BUDGET_PACKETS, "packet limit per frame")
		_check(
			transport.delivered.size() + steam.reliable.size() + steam.transient.size() == 128,
			"budget exit never discards fetched messages"
		)
		if steam.reliable.is_empty() and steam.transient.is_empty():
			break
	_check(transport.delivered.size() == 128, "both channels eventually drain")
	var reliable: Array = transport.delivered.filter(func(entry): return not entry.transient)
	var transient: Array = transport.delivered.filter(func(entry): return entry.transient)
	_check(
		reliable.map(func(entry): return entry.sequence) == range(64),
		"reliable channel stays ordered with no duplicate deliveries"
	)
	_check(
		transient.map(func(entry): return entry.sequence) == range(64),
		"transient channel preserves native order"
	)
	_check(steam.requested_counts.all(func(count): return count == 1), "no bulk dequeue")
	_dispose(transport)


func _fairness_across_frames() -> void:
	var transport := _new_transport()
	transport.one_packet_per_frame = true
	var steam: SteamStub = transport._steam
	for sequence in range(12):
		steam.reliable.append(_packet(sequence))
		steam.transient.append(_packet(sequence))
	for _frame in range(8):
		transport._process(0.016)
	_check(
		(
			transport.delivered.map(func(entry): return entry.transient)
			== [false, false, false, true, false, false, false, true]
		),
		"reliable priority and transient turn survive budget boundaries"
	)
	steam.reliable.clear()
	transport._process(0.016)
	_check(transport.delivered.back().transient, "empty reliable channel never blocks transient")
	steam.reliable.append(_packet(42))
	steam.transient.clear()
	transport._steam_reliable_received = transport.STEAM_RELIABLE_BURST
	transport._process(0.016)
	_check(
		not transport.delivered.back().transient,
		"empty transient channel never blocks reliable control"
	)
	_dispose(transport)


func _byte_limit_keeps_next_packet_queued() -> void:
	var transport := _new_transport()
	var steam: SteamStub = transport._steam
	steam.reliable.append(_packet(7, transport.RECEIVE_BUDGET_BYTES))
	steam.reliable.append(_packet(8))
	transport._process(0.016)
	var stats := transport.receive_stats
	_check(
		stats.packets == 1 and stats.bytes == transport.RECEIVE_BUDGET_BYTES,
		"one maximum-size packet uses the byte allowance"
	)
	_check(stats.budget_reached and steam.reliable.size() == 1, "next reliable packet stays queued")
	transport._process(0.016)
	_check(transport.delivered.back().sequence == 8, "next frame delivers deferred reliable packet")
	_dispose(transport)


func _time_limit_allows_first_message() -> void:
	var transport := _new_transport()
	var expired_start := Time.get_ticks_usec() - transport.RECEIVE_BUDGET_USEC - 1
	_check(
		transport._receive_budget_available(expired_start), "first message always makes progress"
	)
	transport._receive_packets = 1
	_check(
		not transport._receive_budget_available(expired_start),
		"expired time budget prevents another dispatch"
	)
	_dispose(transport)

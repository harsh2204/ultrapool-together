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


class WireTransport:
	extends "../mod/transport.gd"
	var sent: Array = []

	# Only the socket write is replaced. Receive decoding, nonce/session checks,
	# version negotiation, ready gating and signals remain production behavior.
	func _send_wire(id: int, message: Dictionary, transient := false) -> void:
		if not _peers.has(id):
			return
		var envelope = message.duplicate(true)
		envelope["session"] = _peers[id].session
		sent.append({"id": id, "packet": var_to_bytes(envelope), "transient": transient})


var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_packet_limit_and_reliable_retention()
	_fairness_across_frames()
	_byte_limit_keeps_next_packet_queued()
	_time_limit_allows_first_message()
	_handshake_version_boundaries()
	_handshake_authority_and_retired_sessions()
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


func _new_wire_transport(host: bool) -> WireTransport:
	var transport = WireTransport.new()
	transport.is_host = host
	transport._token = "a".repeat(32)
	if not host:
		transport._host_id = 7
	transport._add_peer(42 if host else 7)
	return transport


func _last_wire(transport: WireTransport, kind: String) -> Dictionary:
	for index in range(transport.sent.size() - 1, -1, -1):
		var wire: Dictionary = transport.sent[index]
		if bytes_to_var(wire.packet).get("kind") == kind:
			return wire
	return {}


func _dispose_wire(transport: WireTransport) -> void:
	transport.close()
	transport.free()


func _handshake_version_boundaries() -> void:
	# Change exactly one compatibility field at a time so a wrong game version
	# cannot conceal an ineffective protocol check, or vice versa.
	for field in ["protocol", "game_version"]:
		var host = _new_wire_transport(true)
		var guest = _new_wire_transport(false)
		guest._send_hello()
		var hello: Dictionary = bytes_to_var(_last_wire(guest, "hello").packet)
		hello[field] = 10 if field == "protocol" else "0.15.7"
		host._receive_wire(42, var_to_bytes(hello))
		_check(
			not host._peers.has(42) and not host.connected_peer,
			"offline host rejects independently mismatched " + field
		)
		var rejection = _last_wire(host, "reject")
		_check(
			not rejection.is_empty()
			and bytes_to_var(rejection.packet).nonce == hello.nonce,
			"offline host rejection identifies the incompatible hello " + field
		)
		var welcome = {
			"kind": "welcome",
			"protocol": guest.PROTOCOL,
			"game_version": guest.GAME_VERSION,
			"token": guest._token,
			"nonce": guest._peers[7].nonce,
			"session": "c".repeat(32)
		}
		welcome[field] = 10 if field == "protocol" else "0.15.7"
		guest._receive_wire(7, var_to_bytes(welcome))
		_check(
			not guest._peers.has(7) and not guest.connected_peer,
			"offline guest rejects independently mismatched " + field
		)
		_check(
			not _last_wire(guest, "reject").is_empty()
			and _last_wire(guest, "ready").is_empty(),
			"offline incompatible welcome never produces an acknowledgement " + field
		)
		_dispose_wire(host)
		_dispose_wire(guest)


func _handshake_authority_and_retired_sessions() -> void:
	var host = _new_wire_transport(true)
	var guest = _new_wire_transport(false)
	var host_inbox: Array = []
	var guest_inbox: Array = []
	var host_joins: Array = []
	var guest_joins: Array = []
	var host_departures: Array = []
	host.received.connect(func(sender, data): host_inbox.append({"sender": sender, "data": data}))
	guest.received.connect(func(sender, data): guest_inbox.append({"sender": sender, "data": data}))
	host.peer_joined.connect(func(id): host_joins.append(id))
	guest.peer_joined.connect(func(id): guest_joins.append(id))
	host.peer_left.connect(func(id, _reason): host_departures.append(id))
	_check(
		host._mode.is_empty() and guest._mode.is_empty()
		and host._enet == null and guest._enet == null
		and host._steam == null and guest._steam == null,
		"offline handshake uses no network mode, socket or Steam session"
	)
	guest._send_hello()
	var first_hello = _last_wire(guest, "hello")
	var hello_message: Dictionary = bytes_to_var(first_hello.packet)
	_check(
		hello_message.protocol == host.PROTOCOL
		and hello_message.game_version == host.GAME_VERSION
		and first_hello.id == 7,
		"production hello carries current compatibility fields to the coordinator"
	)
	var premature = {"kind": "data", "session": "", "data": {"kind": "premature"}}
	host._receive_wire(42, var_to_bytes(premature))
	guest._receive_wire(7, var_to_bytes(premature), true)
	host._receive_wire(42, first_hello.packet)
	var first_welcome = _last_wire(host, "welcome")
	_check(not first_welcome.is_empty(), "current hello produces a production welcome")
	if first_welcome.is_empty():
		_dispose_wire(host)
		_dispose_wire(guest)
		return
	var welcome_message: Dictionary = bytes_to_var(first_welcome.packet)
	var retired_session: String = welcome_message.session
	_check(
		host._valid_token(retired_session)
		and welcome_message.nonce == hello_message.nonce
		and welcome_message.protocol == host.PROTOCOL
		and welcome_message.game_version == host.GAME_VERSION,
		"welcome binds the current protocol and game to the hello nonce and new session"
	)
	_check(
		not host.connected_peer and not guest.connected_peer
		and host_joins.is_empty() and guest_joins.is_empty(),
		"hello and welcome creation alone confer no ready authority"
	)
	premature.session = retired_session
	host._receive_wire(42, var_to_bytes(premature))
	host.send_to(42, {"kind": "premature_outgoing"})
	_check(
		host_inbox.is_empty() and guest_inbox.is_empty() and _last_wire(host, "data").is_empty(),
		"unacknowledged peers cannot receive or dispatch application data"
	)
	guest._receive_wire(99, first_welcome.packet)
	_check(not guest.connected_peer, "an unknown sender cannot welcome the guest")
	guest._receive_wire(7, first_welcome.packet)
	var first_ack = _last_wire(guest, "ready")
	_check(
		guest.connected_peer and guest_joins == [7]
		and not first_ack.is_empty() and not host.connected_peer,
		"valid welcome readies only the guest and generates its ready acknowledgement"
	)
	if first_ack.is_empty():
		_dispose_wire(host)
		_dispose_wire(guest)
		return
	host._receive_wire(42, var_to_bytes({"kind": "ready", "session": ""}))
	_check(not host.connected_peer, "acknowledgement with another session cannot authorize the peer")
	host._receive_wire(42, first_ack.packet)
	_check(
		host.connected_peers() == [42] and host_joins == [42]
		and guest._peers[7].session == host._peers[42].session,
		"matching acknowledgement authorizes the peer in the negotiated session"
	)
	guest.send_to(7, {"kind": "input", "claimed_actor": 999})
	host._receive_wire(42, _last_wire(guest, "data").packet)
	host.send_to(42, {"kind": "reply"})
	guest._receive_wire(7, _last_wire(host, "data").packet)
	_check(
		host_inbox == [{"sender": 42, "data": {"kind": "input", "claimed_actor": 999}}]
		and guest_inbox == [{"sender": 7, "data": {"kind": "reply"}}],
		"ready data uses authenticated wire sender instead of the payload actor claim"
	)
	# Start a genuine second negotiation for the same remote identity. The host
	# retains its nonce history; no test writes ready, session or retired history.
	guest._add_peer(7)
	guest._send_hello()
	host._receive_wire(42, _last_wire(guest, "hello").packet)
	var second_welcome = _last_wire(host, "welcome")
	var active_session: String = host._peers[42].session
	_check(
		active_session != retired_session and not host.connected_peer
		and host_departures == [42],
		"fresh hello retires the old session and requires a new acknowledgement"
	)
	host._receive_wire(42, first_hello.packet)
	host._receive_wire(42, first_ack.packet)
	guest._receive_wire(7, first_welcome.packet)
	_check(
		host._peers[42].session == active_session and not host.connected_peer
		and not guest.connected_peer,
		"retired hello, welcome and acknowledgement cannot take over pending negotiation"
	)
	guest._receive_wire(7, second_welcome.packet)
	host._receive_wire(42, _last_wire(guest, "ready").packet)
	_check(
		host.connected_peer and guest.connected_peer
		and host._peers[42].session == active_session
		and guest._peers[7].session == active_session
		and host_joins == [42, 42] and guest_joins == [7, 7],
		"the replacement session becomes ready only through its own welcome and acknowledgement"
	)
	var stale_data = var_to_bytes({
		"kind": "data", "session": retired_session, "data": {"kind": "retired"}
	})
	host._receive_wire(42, first_hello.packet)
	host._receive_wire(42, stale_data)
	guest._receive_wire(7, first_welcome.packet)
	guest._receive_wire(7, stale_data, true)
	_check(
		host._peers[42].session == active_session and guest._peers[7].session == active_session
		and host.connected_peer and guest.connected_peer
		and host_inbox.size() == 1 and guest_inbox.size() == 1
		and host_joins.size() == 2 and guest_joins.size() == 2,
		"retired hello and session data cannot replace or inject into the ready session"
	)
	_dispose_wire(host)
	_dispose_wire(guest)

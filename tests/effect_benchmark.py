#!/usr/bin/env python3
"""Static effect-replication benchmark for Ultrapool Together.

Scores three things without launching the game:

1. Coverage ledger: every guest/spectator status row in
   docs/EFFECT_REPLICATION_TRACKER.md, cross-checked against code evidence so a
   row cannot be marked implemented without a matching presentation path (and a
   path cannot exist while the tracker still says "missing").
2. Performance gates: PASS/FAIL predicates over the mod sources for the scoring
   amplification paths tracked as PERF-* IDs. A gate is static evidence that a
   specific redundant-work pattern is gone; it is never a frame-time measurement.
3. Wire model: an estimate of Godot ``var_to_bytes`` size for synthetic table
   snapshots whose field lists are parsed from the capture sources. It reports
   bytes per snapshot, bytes per second at the host cadence and the share spent
   on repeated dictionary keys.

Run ``python3 tests/effect_benchmark.py`` to print the report, ``--json PATH`` to
save it, ``--write-baseline`` to record the current result as the reference and
``--check`` to exit nonzero when any gate, coverage score or wire scenario
regresses against ``tests/effect_benchmark_baseline.json``.

Everything here is **static**. It cannot prove engine compatibility, rendering,
or live latency; use the authorized capture harness for those.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "mod"
DOCS = ROOT / "docs"
BASELINE = ROOT / "tests" / "effect_benchmark_baseline.json"
TRACKER = DOCS / "EFFECT_REPLICATION_TRACKER.md"
STATUS_WEIGHT = {"I": 1.0, "G": 0.75, "P": 0.5, "?": 0.25, "M": 0.0}
SNAPSHOT_HZ = 10.0  # main.SNAPSHOT_INTERVAL = 0.10


def read(relative: str) -> str:
    path = ROOT / relative
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def exists(relative: str) -> bool:
    return (ROOT / relative).is_file()


def function_body(source: str, name: str) -> str:
    """Return the body of a top-level GDScript function (until the next one)."""
    match = re.search(r"^(?:static )?func %s\(.*?$" % re.escape(name), source, re.M)
    if not match:
        return ""
    rest = source[match.end():]
    following = re.search(r"^(?:static )?func |^class ", rest, re.M)
    return rest[: following.start()] if following else rest


# --------------------------------------------------------------------------- coverage


@dataclass
class Row:
    id: str
    family: str
    guest: str
    spectator: str
    section: str

    @property
    def score(self) -> float:
        return (STATUS_WEIGHT[self.guest] + STATUS_WEIGHT[self.spectator]) / 2.0


ROW_PATTERN = re.compile(
    r"^\|\s*([A-Z]+-\d+)\s*\|(.*?)\|\s*\**\s*([IGPM?])\s*/\s*([IGPM?])\s*\**\s*\|", re.M
)


def parse_tracker() -> list[Row]:
    rows: list[Row] = []
    section = ""
    for line in read("docs/EFFECT_REPLICATION_TRACKER.md").splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
            continue
        match = ROW_PATTERN.match(line)
        if match:
            family = re.sub(r"[`*]", "", match.group(2)).strip()
            rows.append(Row(match.group(1), family[:70], match.group(3), match.group(4), section))
    return rows


@dataclass
class Corroboration:
    """Code evidence for a tracker row. ``guest``/``spectator`` are predicates."""

    row: str
    note: str
    guest: "callable | None" = None
    spectator: "callable | None" = None


def _overlay() -> str:
    return read("mod/ability_overlay.gd")


def _overlay_handles(token: str) -> bool:
    return token in _overlay()


def _spectator_uses_overlay() -> bool:
    return "ability_overlay.gd" in read("mod/table_spectator.gd")


def _guest_uses_overlay_for(set_id: str) -> bool:
    return _overlay_handles(set_id) and "ability_overlay.gd" in read("mod/multiplayer_ball_ui.gd")


def _guest_renders_expansion() -> bool:
    ui = read("mod/multiplayer_ball_ui.gd")
    return "ability_overlay.gd" in ui and "expansion" in ui


CORROBORATIONS = [
    Corroboration(
        "MOD-01",
        "relay owner ring/name drawn on watched tables",
        spectator=lambda: _spectator_uses_overlay() and _overlay_handles("TOGETHER_RELAY"),
    ),
    Corroboration(
        "MOD-02",
        "called-shot rings on watched tables",
        spectator=lambda: _spectator_uses_overlay() and _overlay_handles("call"),
    ),
    Corroboration(
        "MOD-03",
        "patience pips on watched tables",
        spectator=lambda: _spectator_uses_overlay() and _overlay_handles("TOGETHER_PATIENCE"),
    ),
    Corroboration(
        "MOD-04",
        "bounty crosshair plus award cause/timing feedback on watched tables",
        spectator=lambda: _spectator_uses_overlay()
        and _overlay_handles("TOGETHER_BOUNTY")
        and "bounty_award" in _overlay(),
    ),
]
# The complete path per set: the overlay consumes the set's display state and,
# where the tracker names a dedicated cue, draws it (ZODIAC Aspect/Grand Trine).
_SET_COMPLETE = {"ZODIAC": lambda: "aspect" in _overlay().lower()}
for _set_id, _row in [
    ("PHASES", "MOD-07"),
    ("MORPH", "MOD-08"),
    ("TIDE", "MOD-09"),
    ("RELIC", "MOD-10"),
    ("TAROT", "MOD-11"),
    ("ZODIAC", "MOD-12"),
]:
    CORROBORATIONS.append(
        Corroboration(
            _row,
            "%s ability state has a view consuming the replicated display state" % _set_id,
            guest=(lambda s=_set_id: _guest_renders_expansion() and _overlay_handles(s)
                   and _SET_COMPLETE.get(s, lambda: True)()),
            spectator=(lambda s=_set_id: _spectator_uses_overlay() and _overlay_handles(s)
                       and _SET_COMPLETE.get(s, lambda: True)()),
        )
    )
CORROBORATIONS += [
    Corroboration(
        "BOARD-10",
        "fleeting flag presentation",
        guest=lambda: "clear_fleeting" in read("mod/replica_game.gd"),
        spectator=lambda: "fleeting" in function_body(read("mod/table_spectator.gd"), "_apply_item"),
    ),
    Corroboration(
        "FX-08",
        "final_round RichTextLabel content survives the scriptless reader",
        guest=lambda: "RichTextLabel" in read("mod/spectator_scene.gd")
        and "RichTextLabel" in read("mod/table_visual_fx.gd"),
        spectator=lambda: "RichTextLabel" in read("mod/spectator_scene.gd")
        and "RichTextLabel" in read("mod/table_visual_fx_view.gd"),
    ),
    Corroboration(
        "FX-07",
        "dicepop face selection is transmitted",
        guest=lambda: "DICE" in read("mod/table_visual_fx.gd"),
        spectator=lambda: "DICE" in read("mod/table_visual_fx.gd"),
    ),
    Corroboration(
        "DRAW-01",
        "pentagram/ritual geometry captured and drawn",
        guest=lambda: "pentagram" in read("mod/table_sync.gd").lower(),
        spectator=lambda: "pentagram" in read("mod/table_sync.gd").lower()
        and "pentagram" in read("mod/table_spectator.gd").lower()
        and "_hide_named(_table, name)" not in read("mod/table_spectator.gd"),
    ),
    Corroboration(
        "DRAW-03",
        "floating score/money presentation events",
        guest=lambda: "score_events" in read("mod/table_sync.gd"),
        spectator=lambda: "score_events" in read("mod/table_spectator.gd"),
    ),
]


def check_corroborations(rows: dict[str, Row]) -> list[dict]:
    results = []
    for item in CORROBORATIONS:
        row = rows.get(item.row)
        if row is None:
            continue
        for side in ("guest", "spectator"):
            predicate = getattr(item, side)
            if predicate is None:
                continue
            evidence = bool(predicate())
            claim = getattr(row, side)
            # Predicates describe the complete path for the named gap. A partial
            # (P) claim is consistent with that path still missing.
            if evidence and claim in ("M", "P"):
                verdict = "STALE"  # code has the path, tracker still says missing/partial
            elif not evidence and claim in ("I", "G"):
                verdict = "UNSUPPORTED"  # tracker claims a path the code lacks
            else:
                verdict = "OK"
            results.append(
                {"row": item.row, "side": side, "claim": claim, "evidence": evidence,
                 "verdict": verdict, "note": item.note}
            )
    return results


# --------------------------------------------------------------------------- perf gates


@dataclass
class Gate:
    id: str
    perf: str
    title: str
    predicate: "callable"
    passed: bool = False
    evidence: str = ""

    def run(self) -> None:
        try:
            result = self.predicate()
        except Exception as error:  # a gate must never crash the benchmark
            result = (False, "gate error: %s" % error)
        if isinstance(result, tuple):
            self.passed, self.evidence = bool(result[0]), str(result[1])
        else:
            self.passed, self.evidence = bool(result), ""


def gate_single_validation():
    sync = read("mod/table_sync.gd")
    main = read("mod/main.gd")
    # PERF-014 contract: a public validating apply plus an internal apply reached
    # only after boundary validation. No "trusted" flag on the data.
    signature = re.search(r"^func apply_validated_snapshot\(data: Dictionary\)", sync, re.M) is not None
    no_flag = re.search(r"func apply_snapshot\(data: Dictionary\) -> bool", sync) is not None
    internal_calls = len(re.findall(r"apply_validated_snapshot\(message\.scene\)", main))
    body = function_body(main, "_received_table") + function_body(main, "_apply_guest_snapshot")
    validates_first = "_valid_snapshot(message.scene)" in body
    ok = signature and no_flag and internal_calls >= 2 and validates_first
    return ok, "internal apply=%s, no trusted flag=%s, boundary calls=%d, boundary validation=%s" % (
        signature, no_flag, internal_calls, validates_first)


def gate_latest_snapshot_slot():
    main = read("mod/main.gd")
    transport = read("mod/transport.gd")
    slot = "_pending_snapshot" in main
    flush = "func _flush_pending_snapshot" in main
    drained = "signal receive_drained" in transport and "receive_drained.emit()" in transport
    connected = "receive_drained.connect(_flush_pending_snapshot)" in main
    cleared = function_body(main, "_end_table").count("_pending_snapshot") >= 1
    ok = slot and flush and drained and connected and cleared
    return ok, "slot=%s flush=%s drain signal=%s connected=%s cleared on end=%s" % (
        slot, flush, drained, connected, cleared)


def gate_watchers_gated():
    body = function_body(read("mod/main.gd"), "_forward_watchers")
    if not body:
        return False, "no _forward_watchers"
    copies = body.count("duplicate(true)")
    validate_at = body.find("_valid_snapshot")
    watcher_check_at = min(
        [i for i in (body.find("_table_watched("), body.find("_watchers.values()")) if i >= 0]
        or [-1]
    )
    gated = watcher_check_at >= 0 and (validate_at < 0 or watcher_check_at < validate_at)
    return copies == 0 and gated, "deep copies=%d, watcher check before validation=%s" % (
        copies, gated)


def gate_guest_score_only_item():
    source = read("mod/replica_game.gd")
    update = function_body(source, "_update_item")
    apply_body = function_body(source, "apply_table")
    if not update:
        return False, "no _update_item path; every item change reruns _set_item"
    allocates = (
        "BallItem.new" in update or "material.duplicate" in update or "flash_spr.material =" in update
    )
    dispatched = "_item_identity_changed(" in apply_body
    return (not allocates) and dispatched, "allocation-free=%s dispatched=%s" % (
        not allocates, dispatched)


def gate_spectator_score_only_item():
    body = function_body(read("mod/table_spectator.gd"), "_apply_item")
    if not body:
        return False, "no _apply_item"
    material_at = body.find(". duplicate()")
    if material_at < 0:
        material_at = body.find(".duplicate()")
    guard_at = body.find("identity_changed")
    ok = guard_at >= 0 and material_at > guard_at
    return ok, "material rebuild guarded by identity change=%s" % ok


def gate_spectator_frame_gated_ui():
    body = function_body(read("mod/table_spectator.gd"), "tick")
    lines = body.splitlines()
    gate_indent = None
    gated = {"_update_pockets(": False, "_update_table_ui(": False}
    for line in lines:
        stripped = line.lstrip("\t")
        indent = len(line) - len(stripped)
        if "is_same(_effects_frame, after)" in line:
            gate_indent = indent
            continue
        if gate_indent is not None and stripped and indent <= gate_indent:
            gate_indent = None
        for key in gated:
            if key in line and gate_indent is not None and indent > gate_indent:
                gated[key] = True
    return all(gated.values()), "frame-gated: %s" % gated


def gate_spectator_no_find_child_per_apply():
    body = function_body(read("mod/table_spectator.gd"), "_update_table_ui")
    count = body.count("find_child(")
    return count == 0, "find_child calls per table UI update=%d" % count


def gate_effect_lifecycle_separate():
    main = read("mod/main.gd")
    return "_publish_effect_lifecycle" in main, (
        "effect births/removals still promote the whole table snapshot to reliable delivery")


def gate_fleeting_clear():
    body = function_body(read("mod/replica_game.gd"), "_update_item")
    body += function_body(read("mod/replica_game.gd"), "_set_item")
    return "clear_fleeting" in body or "fleeting_cleared" in body, (
        "guest only calls set_fleeting on true; no true→false cleanup")


def gate_transient_capture_single_encode():
    fx = read("mod/table_visual_fx.gd")
    sig = re.search(r"static func problem\(data, encoded_bytes", fx) is not None
    capture = function_body(fx, "capture")
    passes = "problem(result, bytes)" in capture
    return sig and passes, "host capture reuses its item byte sum for validation=%s" % (sig and passes)


def gate_table_limit_skips_encode():
    body = function_body(read("mod/table_sync.gd"), "_limit_effect_payload")
    skips = "_effect_substates_empty(" in body or "items.is_empty()" in body
    return skips, "whole-table encode skipped when effect substates are empty=%s" % skips


def gate_guest_hud_change_gated():
    body = function_body(read("mod/replica_game.gd"), "_update_hud")
    return "_hud_state.get(" in body, "guest HUD writes are change-gated"


def gate_durable_view_change_gated():
    body = function_body(read("mod/table_effects_view.gd"), "apply")
    return "entry.state != state" in body, "durable renderer updates only changed descriptors"


def gate_pocket_update_change_gated():
    body = function_body(read("mod/replica_game.gd"), "_update_pockets")
    return "_pocket_states == states" in body, "guest pocket updates skip unchanged state"


def gate_overlay_redraw_change_gated():
    ui = read("mod/multiplayer_ball_ui.gd")
    body = function_body(ui, "refresh")
    return "_signature" in body and "queue_redraw" in ui, (
        "overlay redraw only when display state changes")


GATES = [
    Gate("G01", "PERF-014", "Guest validates each accepted snapshot once", gate_single_validation),
    Gate("G02", "PERF-002/004", "Bounded latest-snapshot slot per receive drain", gate_latest_snapshot_slot),
    Gate("G03", "PERF-007", "Watcher forwarding validates/copies only with watchers", gate_watchers_gated),
    Gate("G04", "PERF-018/019", "Guest score/status-only item updates avoid BallItem/material rebuild", gate_guest_score_only_item),
    Gate("G05", "PERF-024", "Spectator score-only item updates keep the ball material", gate_spectator_score_only_item),
    Gate("G06", "PERF-022", "Spectator table UI/pockets update per snapshot frame, not per render tick", gate_spectator_frame_gated_ui),
    Gate("G07", "PERF-022", "Spectator table UI update has no per-apply find_child", gate_spectator_no_find_child_per_apply),
    Gate("G08", "PERF-008/011", "Effect lifecycle delivered separately from whole-table reliable promotion", gate_effect_lifecycle_separate),
    Gate("G09", "BOARD-10", "Guest clears fleeting presentation on true→false", gate_fleeting_clear),
    Gate("G10", "PERF-004/019", "Transient capture validates without re-encoding every item", gate_transient_capture_single_encode),
    Gate("G11", "PERF-008", "Combined-table byte limit skips the whole-table encode when no effects exist", gate_table_limit_skips_encode),
    Gate("G12", "PERF-015", "Guest HUD writes are change-gated", gate_guest_hud_change_gated),
    Gate("G13", "PERF-019", "Durable effect renderer updates only changed descriptors", gate_durable_view_change_gated),
    Gate("G14", "PERF-016", "Guest pocket updates skip unchanged state", gate_pocket_update_change_gated),
    Gate("G15", "PERF-028", "Ability overlay redraws only when display state changes", gate_overlay_redraw_change_gated),
]


# --------------------------------------------------------------------------- wire model


class V2(tuple):
    pass


class V3(tuple):
    pass


class Col(tuple):
    pass


class PV2(list):
    pass


def _pad4(n: int) -> int:
    return (n + 3) // 4 * 4


def _float_bytes(value: float) -> int:
    # Godot 4 encodes a FLOAT as 32-bit when the double round-trips exactly.
    return 4 if struct.unpack("f", struct.pack("f", value))[0] == value else 8


def var_bytes(value) -> int:
    """Approximate Godot 4 ``var_to_bytes`` size (4-byte header per Variant)."""
    if value is None:
        return 4
    if isinstance(value, bool):
        return 8
    if isinstance(value, int):
        return 8 if -2**31 <= value < 2**31 else 12
    if isinstance(value, float):
        return 4 + _float_bytes(value)
    if isinstance(value, str):
        return 8 + _pad4(len(value.encode("utf-8")))
    if isinstance(value, V2):
        return 12
    if isinstance(value, V3):
        return 16
    if isinstance(value, Col):
        return 20
    if isinstance(value, PV2):
        return 8 + 8 * len(value)
    if isinstance(value, dict):
        return 8 + sum(var_bytes(k) + var_bytes(v) for k, v in value.items())
    if isinstance(value, (list, tuple)):
        return 8 + sum(var_bytes(v) for v in value)
    raise TypeError(type(value))


def key_bytes(value) -> int:
    """Bytes spent on dictionary key strings (repeated per entry)."""
    if isinstance(value, dict):
        return sum(var_bytes(k) + key_bytes(v) for k, v in value.items())
    if isinstance(value, (list, tuple)) and not isinstance(value, (V2, V3, Col)):
        return sum(key_bytes(v) for v in value)
    return 0


def _keys_in_block(source: str, start_marker: str) -> list[str]:
    start = source.find(start_marker)
    if start < 0:
        return []
    depth = 0
    index = source.find("{", start)
    end = index
    while end < len(source):
        char = source[end]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                break
        end += 1
    block = source[index:end]
    return re.findall(r'"(\w+)":', block)


def _const_list(source: str, name: str) -> list[str]:
    match = re.search(r"const %s = \[(.*?)\]" % name, source, re.S)
    return re.findall(r'"(\w+)"', match.group(1)) if match else []


def _const_dict_keys(source: str, name: str) -> list[str]:
    match = re.search(r"const %s = \{(.*?)\n\}" % name, source, re.S)
    return re.findall(r'"(\w+)":', match.group(1)) if match else []


TYPE_BY_NAME = {
    "position": V2((100.5, -40.25)), "velocity": V2((12.5, 3.0)), "force": V2((0.0, 0.0)),
    "visual_scale": V2((1.0, 1.0)), "scale": V2((1.0, 1.0)), "table_position": V2((0.0, 0.0)),
    "direction": V2((1.0, 0.0)), "suction_scale": V2((1.0, 1.0)),
    "spin": V3((0.1, 0.2, 0.3)), "color": Col((1.0, 1.0, 1.0, 1.0)), "sprite_color": Col((1, 1, 1, 1)),
    "suction_color": Col((0, 0, 0, 0)), "modulate": Col((1, 1, 1, 1)), "self_modulate": Col((1, 1, 1, 1)),
    "rotation": 0.5, "angular_velocity": 0.25, "linear_damp": 1.5, "angular_damp": 1.0,
    "radius_scale": 1.0, "mass": 1.0, "multiplier": 1.0, "score": 10.0, "required_score": 300.0,
    "money": 12.0, "sprite_rotation": 0.5, "shadow_rotation": 0.5, "flower_rotation": 0.5,
    "launch_timer": 0.5, "width": 2.0,
    "id": 123456, "scene_id": 98765, "round": 3, "rounds_played": 2, "shots": 4, "shots_max": 6,
    "shots_used": 2, "hp": 3, "max_hp": 3, "base_index": 0, "kind": 1, "texture_index": 2,
    "flower_power": 1, "charges": 2, "held_ball_id": 0, "index": 0, "frame": 0, "level": 1,
    "weight_state": 0, "base_score": 5, "temp_extra_score": 0,
    "data": "FOOD_APPLE", "mixed": "",
}


def _value_for(name: str):
    if name in TYPE_BY_NAME:
        return TYPE_BY_NAME[name]
    return True  # flags


def build_ball(sync: str, item_numbers, item_flags, ball_keys):
    item = {"data": "FOOD_APPLE", "mixed": ""}
    for key in item_numbers:
        item[key] = _value_for(key)
    for key in item_flags:
        item[key] = False
    ball = {}
    for key in ball_keys:
        if key == "item":
            ball[key] = item
        elif key in ("player", "visible", "alive", "spawned", "falling", "gone", "passive"):
            ball[key] = key in ("visible", "alive", "spawned")
        else:
            ball[key] = _value_for(key)
    return ball


def build_pocket(pocket_keys, base_index):
    pocket = {}
    for key in pocket_keys:
        if key == "base_index":
            pocket[key] = base_index
        elif key in ("closed", "shielded", "has_held_balls"):
            pocket[key] = False
        else:
            pocket[key] = _value_for(key)
    return pocket


def build_results():
    # round_presentation.capture is approximated: a few numbers, flags and a phase key.
    return {"phase": "table", "won": False, "score": 10.0, "bonus_money": 0.0, "money_before": 12.0,
            "round_reward": 0.0, "balls_pocketed": 1, "money_earned": 0.0, "game_time": 83.5}


def build_inventory():
    item = {"data": "FOOD_APPLE", "mixed": "", "base_score": 5, "temp_extra_score": 0, "level": 1,
            "weight_state": 0, "flaming": False, "fleeting": False, "star_power": False,
            "shielded": False, "shield_broken": False, "locked": False}
    return {"snacks": 1, "cocktails": 0, "balls": [item] * 8, "passives": [None] * 3,
            "cubes": [None] * 2, "tickets": []}


def build_droplet(effects_source: str):
    common = _const_list(effects_source, "COMMON")
    fields = _const_list(effects_source, "DROPLET_FIELDS")
    drop = {}
    for key in common + fields:
        if key == "flower_colors":
            drop[key] = [Col((1, 0, 0, 1))] * 3
        elif key in ("visible", "sprite_flip_h", "shadow_visible"):
            drop[key] = True
        else:
            drop[key] = _value_for(key)
    return drop


def build_energy(effects_source: str):
    common = _const_list(effects_source, "COMMON")
    fields = _const_list(effects_source, "ENERGY_FIELDS")
    body = {}
    for key in common + fields:
        if key == "trails":
            body[key] = []
        elif key in ("visible", "alive", "spawned", "gone", "sphere_visible"):
            body[key] = True
        else:
            body[key] = _value_for(key)
    return body


def build_transient(parts: int, ident: int, kind: str = "wisp"):
    part_states = []
    for index in range(parts):
        state = {"index": index, "position": V2((1.0, 2.0)), "rotation": 0.5, "scale": V2((1, 1)),
                 "modulate": Col((1, 1, 1, 1)), "self_modulate": Col((1, 1, 1, 1)), "visible": True}
        if index % 2 == 0:
            state["frame"] = 0
        part_states.append(state)
    return {"id": ident, "kind": kind, "parts": part_states}


def build_snapshot(balls: int, holes: int, droplets: int, energy: int, transients: int,
                   transient_parts: int) -> dict:
    sync = read("mod/table_sync.gd")
    effects_source = read("mod/table_effects_sync.gd")
    item_numbers = _const_dict_keys(sync, "ITEM_NUMBERS")
    item_flags = _const_list(sync, "ITEM_FLAGS")
    ball_keys = _keys_in_block(function_body(sync, "capture"), "data.balls.append(")
    top_keys = _keys_in_block(function_body(sync, "capture"), "var data = {")
    pocket_keys = _keys_in_block(function_body(sync, "_capture_pockets"), "states.append(")
    if not (item_numbers and item_flags and ball_keys and top_keys and pocket_keys):
        raise RuntimeError("could not parse snapshot field lists from table_sync.gd")
    data = {}
    for key in top_keys:
        if key == "balls":
            data[key] = [build_ball(sync, item_numbers, item_flags, ball_keys) for _ in range(balls)]
        elif key == "pockets":
            data[key] = [build_pocket(pocket_keys, i) for i in range(6)]
            data[key] += [build_pocket(pocket_keys, -1) for _ in range(holes)]
        elif key == "inventory":
            data[key] = build_inventory()
        elif key == "results":
            data[key] = build_results()
        elif key in ("available", "ready", "in_menu", "in_shop", "round_ended", "game_over",
                     "daily", "rotated"):
            data[key] = key in ("available", "ready")
        else:
            data[key] = _value_for(key)
    data["effects"] = {
        "version": 1, "status": "complete", "reason": "",
        "droplets": [build_droplet(effects_source) for _ in range(droplets)],
        "energy": [build_energy(effects_source) for _ in range(energy)],
        "pockets": [],
    }
    data["visual_fx"] = {
        "version": 1, "status": "complete", "reason": "",
        "items": [build_transient(transient_parts, 1000 + i) for i in range(transients)],
    }
    return {"kind": "snapshot", "id": 1200, "scene": data}


WIRE_SCENARIOS = {
    # name: (balls, holes, droplets, energy, transients, transient_parts)
    "idle_16_balls": (16, 0, 0, 0, 0, 0),
    "scoring_burst_16_balls": (16, 2, 6, 1, 8, 8),
    "late_run_48_balls": (48, 4, 24, 4, 24, 8),
}


def wire_report() -> dict:
    report = {}
    for name, args in WIRE_SCENARIOS.items():
        snapshot = build_snapshot(*args)
        total = var_bytes(snapshot)
        keys = key_bytes(snapshot)
        scene = snapshot["scene"]
        report[name] = {
            "bytes": total,
            "bytes_per_second_at_cadence": int(total * SNAPSHOT_HZ),
            "key_share": round(keys / total, 3),
            "ball_bytes": var_bytes(scene["balls"][0]),
            "effects_bytes": var_bytes(scene["effects"]) + var_bytes(scene["visual_fx"]),
        }
    return report


# --------------------------------------------------------------------------- report


def build_report() -> dict:
    rows = parse_tracker()
    by_id = {row.id: row for row in rows}
    sections: dict[str, list[Row]] = {}
    for row in rows:
        sections.setdefault(row.section, []).append(row)
    coverage = {
        "rows": len(rows),
        "score": round(100.0 * sum(r.score for r in rows) / max(len(rows), 1), 1),
        "guest": round(100.0 * sum(STATUS_WEIGHT[r.guest] for r in rows) / max(len(rows), 1), 1),
        "spectator": round(100.0 * sum(STATUS_WEIGHT[r.spectator] for r in rows) / max(len(rows), 1), 1),
        "missing_rows": sorted(r.id for r in rows if r.guest == "M" or r.spectator == "M"),
        "sections": {
            name: {
                "rows": len(items),
                "score": round(100.0 * sum(r.score for r in items) / len(items), 1),
            }
            for name, items in sections.items()
        },
    }
    corroborations = check_corroborations(by_id)
    for gate in GATES:
        gate.run()
    return {
        "coverage": coverage,
        "corroborations": corroborations,
        "corroboration_failures": sorted(
            "%s/%s:%s" % (c["row"], c["side"], c["verdict"]) for c in corroborations if c["verdict"] != "OK"
        ),
        "gates": [
            {"id": g.id, "perf": g.perf, "title": g.title, "passed": g.passed, "evidence": g.evidence}
            for g in GATES
        ],
        "gates_passed": sum(1 for g in GATES if g.passed),
        "gates_total": len(GATES),
        "wire": wire_report(),
    }


def compare(report: dict, baseline: dict) -> list[str]:
    regressions = []
    if report["coverage"]["score"] < baseline["coverage"]["score"]:
        regressions.append("coverage score fell %.1f → %.1f" % (
            baseline["coverage"]["score"], report["coverage"]["score"]))
    base_gates = {g["id"]: g["passed"] for g in baseline.get("gates", [])}
    for gate in report["gates"]:
        if base_gates.get(gate["id"]) and not gate["passed"]:
            regressions.append("gate %s (%s) regressed to FAIL" % (gate["id"], gate["perf"]))
    for name, values in report["wire"].items():
        before = baseline.get("wire", {}).get(name, {}).get("bytes")
        if before and values["bytes"] > before * 1.01:
            regressions.append("wire %s grew %d → %d bytes" % (name, before, values["bytes"]))
    new_failures = set(report["corroboration_failures"]) - set(baseline.get("corroboration_failures", []))
    for failure in sorted(new_failures):
        regressions.append("tracker/code mismatch " + failure)
    return regressions


def print_report(report: dict, baseline: dict | None) -> None:
    cov = report["coverage"]
    print("EFFECT REPLICATION BENCHMARK (static; no runtime evidence)")
    print("=" * 72)
    print("Coverage ledger: %d rows, score %.1f%% (guest %.1f%%, spectator %.1f%%)" % (
        cov["rows"], cov["score"], cov["guest"], cov["spectator"]))
    for name, values in cov["sections"].items():
        print("  %-58s %5.1f%% (%d rows)" % (name[:58], values["score"], values["rows"]))
    print("  rows with a missing side: %s" % ", ".join(cov["missing_rows"]))
    print()
    print("Tracker/code corroboration:")
    for item in report["corroborations"]:
        flag = "ok " if item["verdict"] == "OK" else "!! "
        print("  %s%-8s %-9s claim=%s evidence=%-5s %s" % (
            flag, item["row"], item["side"], item["claim"], item["evidence"], item["verdict"]))
    print()
    print("Performance gates: %d/%d PASS" % (report["gates_passed"], report["gates_total"]))
    for gate in report["gates"]:
        print("  [%s] %s %-12s %s" % ("PASS" if gate["passed"] else "FAIL", gate["id"], gate["perf"], gate["title"]))
        if gate["evidence"]:
            print("         %s" % gate["evidence"])
    print()
    print("Wire model (estimated var_to_bytes; host cadence %.0f Hz):" % SNAPSHOT_HZ)
    for name, values in report["wire"].items():
        print("  %-24s %7d B/snapshot  %7.1f KiB/s  keys %4.0f%%  ball %4d B  effects %6d B" % (
            name, values["bytes"], values["bytes_per_second_at_cadence"] / 1024.0,
            values["key_share"] * 100, values["ball_bytes"], values["effects_bytes"]))
    print()
    punch = [g for g in report["gates"] if not g["passed"]]
    if punch:
        print("Punch list (open gates, in tracker priority order):")
        for gate in punch:
            print("  - %s %s: %s" % (gate["id"], gate["perf"], gate["title"]))
    if baseline:
        regressions = compare(report, baseline)
        print()
        if regressions:
            print("REGRESSIONS vs baseline:")
            for item in regressions:
                print("  - " + item)
        else:
            print("No regressions vs baseline (coverage %.1f%%, gates %d/%d)." % (
                baseline["coverage"]["score"], baseline["gates_passed"], baseline["gates_total"]))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", type=Path, help="write the report to this path")
    parser.add_argument("--write-baseline", action="store_true", help="record this run as the baseline")
    parser.add_argument("--check", action="store_true", help="exit 1 on regression vs the baseline")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    report = build_report()
    baseline = json.loads(BASELINE.read_text()) if BASELINE.is_file() else None
    if not args.quiet:
        print_report(report, baseline)
    if args.json:
        args.json.write_text(json.dumps(report, indent=2) + "\n")
    if args.write_baseline:
        BASELINE.write_text(json.dumps(report, indent=2) + "\n")
        print("Baseline written to %s" % BASELINE.relative_to(ROOT))
    if args.check and baseline:
        return 1 if compare(report, baseline) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())

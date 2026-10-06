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
   on repeated dictionary keys. The historical scenarios retain their original
   synthetic inventory; a separate 0.17.2 scenario models the current inventory
   schema and sparse GUMMY-BRAIN copy identity without rewriting that baseline.

Run ``python3 tests/effect_benchmark.py`` to print the report, ``--json PATH`` to
save it, ``--write-baseline`` to record the current result as the reference and
``--check`` to exit nonzero when any gate, coverage score or wire scenario
regresses against ``tests/effect_benchmark_baseline.json``.
Run ``--self-test`` to check the benchmark's parsing, mutation guards and wire
accounting without a game process. A model-version change requires an explicit
baseline review; it never bypasses the existing wire-growth threshold.

Everything here is **static**. It cannot prove engine compatibility, rendering,
or live latency; use the authorized capture harness for those.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from dataclasses import dataclass
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


def code(source: str) -> str:
    """Discard comments without discarding # inside a quoted GDScript string."""
    return re.sub(r'("(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')|#[^\n]*',
                  lambda match: match.group(1) or "", source)


def body(relative: str, name: str) -> str:
    return code(function_body(read(relative), name))


def has_calls(relative: str, name: str, *expressions: str) -> bool:
    """Scoped static call/field evidence, never proof that a function executes."""
    source = re.sub(r"\s+", "", body(relative, name))
    return bool(source) and all(re.sub(r"\s+", "", item) in source for item in expressions)


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
    complete: bool = True


def _overlay() -> str:
    return code(read("mod/ability_overlay.gd"))


def _overlay_handles(token: str) -> bool:
    return token in _overlay()


def _state_path(service: str, side: str) -> bool:
    """Require the actual producer, boundary validator and view handoffs.

    These assertions deliberately name the integration calls. A comment, preload
    or unused helper containing the family name must not satisfy a tracker row.
    This is still source evidence, not a runtime reachability analysis.
    """
    main = "mod/main.gd"
    common = (
        has_calls(main, "_publish_state", '"%s": %s.capture()' % (service, service))
        and has_calls(main, "_valid_state", '%s.valid_state(message.get("%s"))' % (service, service))
        and has_calls("mod/%s.gd" % service, "capture", "_last_capture = data")
    )
    if side == "guest":
        return common and (
            has_calls(main, "_received_table", "%s.apply_state(message.%s)" % (service, service))
            and has_calls("mod/%s.gd" % service, "apply_state", "_remote = data.duplicate(true)")
            and has_calls("mod/%s.gd" % service, "display_state", "_remote")
            and has_calls("mod/multiplayer_balls.gd", "_process", "_ui.refresh(")
            and has_calls("mod/multiplayer_ball_ui.gd", "draw_overlay", "AbilityOverlay.draw(", "_data", "_expansion")
        )
    return common and (
        has_calls(main, "_receive_watch", "_valid_state(payload, message.table)", "spectator.apply_state(message.table, payload)")
        and has_calls("mod/table_spectator.gd", "apply_state", "_state = data.duplicate(true)")
        and has_calls("mod/table_spectator.gd", "_ability_states", '_state.get("%s", {})' % service)
        and has_calls("mod/table_spectator.gd", "_draw_abilities", "_ability_states()", "AbilityOverlay.draw(", "states[0]", "states[1]")
    )


def _spectator_uses_overlay() -> bool:
    return _state_path("multiplayer_balls", "spectator")


def _guest_renders_expansion() -> bool:
    return _state_path("expansion_balls", "guest") and has_calls(
        "mod/multiplayer_balls.gd", "_process", "expansion.display_state()", "_ui.refresh(display_state() if _active else {}, expansion_state")


def _fx_path(side: str) -> bool:
    common = (
        has_calls("mod/table_sync.gd", "capture", "_visual_fx_capture.capture(game)")
        and has_calls("mod/table_visual_fx.gd", "capture", "_describe(node, entry.kind)", "problem(result, bytes)")
        and has_calls("mod/table_sync.gd", "_snapshot_problem", "VisualFx.problem(data.visual_fx)")
        and has_calls("mod/table_visual_fx_view.gd", "apply", "_apply_item(entry, item, origin)")
    )
    consumer, function = (("mod/replica_game.gd", "apply_table") if side == "guest"
                          else ("mod/table_spectator.gd", "tick"))
    return common and has_calls(consumer, function, '_visual_fx_view.apply(', 'get("visual_fx", {})')


def _feedback_path(kind: str, side: str) -> bool:
    rules = "mod/multiplayer_ball_rules.gd"
    producer = (has_calls("mod/multiplayer_balls.gd", "record_pocket", "rules.record_heal(")
                and has_calls(rules, "record_heal", '_record_feedback("lifeline",') if kind == "lifeline"
                else has_calls(rules, "pocket", '_record_feedback("%s",' % kind))
    return (
        producer and _state_path("multiplayer_balls", side)
        and has_calls("mod/multiplayer_balls.gd", "capture", '"feedback": rules.capture_feedback()')
        and has_calls(rules, "valid_state", "valid_feedback(data.feedback)")
        and ('"%s"' % kind) in body(rules, "valid_feedback")
        and ('"%s"' % kind) in body("mod/ability_overlay.gd", "feedback_lines")
        and has_calls("mod/ability_overlay.gd", "draw", '_draw_shared_panel(', 'balls.get("feedback", {})')
        and has_calls("mod/ability_overlay.gd", "_draw_shared_panel", "feedback_lines(")
    )


SET_FIELDS = {
    "PHASES": (("phase", "silent"), ()),
    "MORPH": (("form_changes", "prime"), ("form", "charge", "marked")),
    "TIDE": (("height",), ()),
    "RELIC": (("persist", "idol_temps"), ("dig",)),
    "TAROT": (("spread",), ("upright", "in_spread", "charge")),
    "ZODIAC": (("align",), ("charge",)),
}


def _expansion_path(set_id: str, side: str) -> bool:
    shared, per_ball = SET_FIELDS[set_id]
    coordinator = "mod/expansion_balls.gd"
    rules = "mod/sets/%s_rules.gd" % set_id.lower()
    shared_tokens = ['"%s"' % field for field in shared]
    ball_tokens = ['"%s"' % field for field in per_ball]
    return (
        _state_path("expansion_balls", side)
        and (side != "guest" or _guest_renders_expansion())
        and has_calls(coordinator, "capture", "rules[set_id].capture_shared()")
        and has_calls(coordinator, "valid_state", "_valid_shared_display(set_id, data.sets[set_id])")
        and has_calls(rules, "capture_shared", *shared_tokens)
        and has_calls(coordinator, "_valid_shared_display", '"%s"' % set_id, *shared_tokens)
        and has_calls("mod/ability_overlay.gd", "shared_lines", 'sets.has("%s")' % set_id, *shared_tokens)
        and (not per_ball or (
            has_calls(coordinator, "capture", "rules[set_id].capture_ball(id)")
            and has_calls(coordinator, "valid_state", "_valid_ball_display(set_id, ball.extra[set_id])")
            and has_calls(rules, "capture_ball", *ball_tokens)
            and has_calls(coordinator, "_valid_ball_display", '"%s"' % set_id, *ball_tokens)
            and has_calls("mod/ability_overlay.gd", "_draw_expansion_ball", 'extra.get("%s", {})' % set_id, *ball_tokens)
        ))
    )


def _native_draw_path(kind: str, side: str) -> bool:
    source = "mod/table_native_draw.gd"
    producer = (has_calls(source, "capture", 'describe(pentagram, "pentagram")') if kind == "pentagram"
                else has_calls(source, "capture", 'describe(node, "score")') if kind == "score"
                else has_calls(source, "capture", 'describe(source, kind)', '"%s"' % kind))
    consumer, function = (("mod/replica_game.gd", "apply_table") if side == "guest"
                          else ("mod/table_spectator.gd", "tick"))
    return (
        producer
        and has_calls("mod/table_sync.gd", "capture", "_native_draw_capture.capture(game)")
        and has_calls("mod/table_sync.gd", "_snapshot_problem", "NativeDraw.problem(data.native_draw)")
        and has_calls(source, "problem", "PATHS.has(item.kind)", "MAX_BYTES", "MAX_POINTS")
        and has_calls(consumer, function, '_native_draw_view.apply(', 'get("native_draw", {})')
        and has_calls("mod/table_native_draw_view.gd", "apply", "_apply_item(")
        and has_calls("mod/table_native_draw_view.gd", "_apply_item", "part.position", "state.position")
    )


def _ball_visual_path(side: str) -> bool:
    return (
        has_calls("mod/table_sync.gd", "capture", '"ball_visual": BallVisual.capture(body)')
        and has_calls("mod/table_sync.gd", "_ball_problem", "BallVisual.problem(body.ball_visual)")
        and has_calls("mod/ball_visual_state.gd", "capture", "_read(node, field)", "changes.append([index, value])")
        and has_calls("mod/ball_visual_state.gd", "problem", "MAX_FIELDS", "_same_value_type(value, fields[index][2],", "_value_ok(value)")
        and has_calls("mod/ball_visual_state.gd", "apply", "_nodes(body, true)", "node.set(field[1], value)")
        and (has_calls("mod/replica_game.gd", "apply_table", 'BallVisualState.apply(body, state.get("ball_visual", {}))')
             if side == "guest" else has_calls("mod/table_spectator.gd", "_render_balls", 'BallVisualState.apply(visual.node, ball.get("ball_visual", {}))'))
    )


def _dice_path(side: str) -> bool:
    return (
        _fx_path(side)
        and has_calls("mod/table_visual_fx.gd", "_cache_scene", 'Reader.exported(scene, "dice_imgs")', '"dice_faces"')
        and has_calls("mod/table_visual_fx.gd", "_describe", 'dice_faces.find(part.texture)', 'state["dice_face"] = face')
        and has_calls("mod/table_visual_fx.gd", "problem", 'part.has("dice_face")', 'item.kind != "dicepop"', "part.dice_face >= _catalog[item.kind].dice_faces.size()")
        and has_calls("mod/table_visual_fx_view.gd", "_apply_item", "dice_faces[state.dice_face]", "part.texture = texture")
    )


def _rich_text_path(side: str) -> bool:
    return (
        _fx_path(side)
        and has_calls("mod/spectator_scene.gd", "_visual_node", '"RichTextLabel":', "return RichTextLabel.new()")
        and has_calls("mod/table_visual_fx.gd", "_describe", "part is RichTextLabel", 'state["text"] = part.text')
        and has_calls("mod/table_visual_fx.gd", "problem", 'part.has("text")', "part.text.length() > 256", "part.text != _catalog[item.kind].parts[part.index].rich_text")
        and has_calls("mod/table_visual_fx_view.gd", "_apply_item", "part is RichTextLabel", "part.text = state.text")
    )


def _catalog_fixture_path(side: str) -> bool:
    fixture = "tests/native_visual_fx_fixture.gd"
    return (
        _fx_path(side)
        and has_calls(fixture, "_check_catalog_host", "Fx.catalog(mod)", "for kind in catalog:",
                      'mod.table_sync.capture().get("visual_fx", {})', "_collect_native_pose(node, node, native)")
        and has_calls(fixture, "_check_catalog_guest", "mod.table_sync.apply_snapshot(packet)",
                      "watcher.apply_snapshot(1, packet)", "_compare_native_pose(visual, pose.native, record,")
        and has_calls(fixture, "_compare_native_pose", "var matches = actual == expected[key]", "record.call(matches,")
    )


def _pocket_visual_path(side: str) -> bool:
    return (
        has_calls("mod/table_sync.gd", "capture", "data.pockets = _capture_pockets(game)")
        and has_calls("mod/table_sync.gd", "_capture_pockets", '"pocket_visual": TableEffects.capture_pocket_visuals(pocket)')
        and has_calls("mod/table_sync.gd", "_pocket_problem", "TableEffects.pocket_visual_valid(pocket.pocket_visual)")
        and has_calls("mod/table_effects_sync.gd", "pocket_visual_valid", "POCKET_VISUAL_PATHS.size()", "part.size() != 7")
        and has_calls("mod/table_effects_view.gd", "apply_pockets", '_apply_pocket_visuals(pocket, state.get("visuals", []))')
        and has_calls("mod/table_effects_view.gd", "_apply_pocket_visuals", '_set_changed(node, "position", part[0])', '_set_changed(node, "text", part[6])')
        and (has_calls("mod/replica_game.gd", "apply_table", 'effects_view.apply_pockets(data.get("effects", {}), pocket_replicas, data.pockets)')
             if side == "guest" else has_calls("mod/table_spectator.gd", "_update_pockets", '_effects_view.apply_pockets(data.get("effects", {}), effect_pockets, data.pockets)'))
    )


def _spectator_hud_values() -> bool:
    return (
        has_calls("mod/round_presentation.gd", "capture", '"game_time": game.game_time')
        and has_calls("mod/round_presentation.gd", "valid", '"game_time"')
        and has_calls("mod/table_sync.gd", "_snapshot_problem", 'RoundPresentation.valid(data.get("results"))')
        and has_calls("mod/table_spectator.gd", "apply_snapshot", "_update_status(data)")
        and has_calls("mod/table_spectator.gd", "_update_status", "data.results.game_time", "data.shots_max", "data.shots_used", "_status.text = text")
        and has_calls("mod/table_spectator.gd", "_update_table_ui", "data.money", "data.hp", "data.max_hp")
    )


def _cue_feedback_path(side: str) -> bool:
    committed = body("mod/cue_effects.gd", "commit_pocket")
    common = (
        0 <= committed.find("game.add_score(") < committed.find("_feedback = {")
        and has_calls("mod/cue_effects.gd", "capture_feedback", "return _feedback.duplicate(true)")
        and has_calls("mod/cue_effects.gd", "valid_feedback", "data.size() != 6", "CueModels.is_known(data.model)", "data.points <= model.bonus_cap")
        and has_calls("mod/main.gd", "_publish_state", '"cue_feedback": cue_effects.capture_feedback()')
        and has_calls("mod/main.gd", "_valid_state", "CueEffects.valid_feedback(message.cue_feedback)")
        and has_calls("mod/ability_overlay.gd", "draw", "_draw_shared_panel(", "cue_feedback)")
        and has_calls("mod/ability_overlay.gd", "_draw_shared_panel", "cue_feedback_lines(cue_feedback)")
        and has_calls("mod/ability_overlay.gd", "cue_feedback_lines", 'CueModels.entry(str(feedback.get("model", "")))', 'feedback.get("points", 0)')
    )
    if side == "guest":
        return common and (
            has_calls("mod/main.gd", "_received_table", "latest_state = message")
            and has_calls("mod/multiplayer_balls.gd", "_process", '_controller.latest_state.get("cue_feedback", {})', "_ui.refresh(", "expansion_state, cue_feedback)")
            and has_calls("mod/multiplayer_ball_ui.gd", "refresh", "_cue_feedback = cue_feedback")
            and has_calls("mod/multiplayer_ball_ui.gd", "draw_overlay", "AbilityOverlay.draw(", "_cue_feedback")
        )
    return common and (
        has_calls("mod/main.gd", "_receive_watch", "_valid_state(payload, message.table)", "spectator.apply_state(message.table, payload)")
        and has_calls("mod/table_spectator.gd", "apply_state", "_state = data.duplicate(true)")
        and has_calls("mod/table_spectator.gd", "_draw_abilities", "AbilityOverlay.draw(", '_state.get("cue_feedback", {})')
    )


def _bounty_path(side: str) -> bool:
    common = (
        _feedback_path("bounty_award", side)
        and has_calls("mod/bounty_race.gd", "resolve", "summary.bounty_bonus = REWARD", 'complete = complete and bool(summary.get("finished", false))')
        and has_calls("mod/main.gd", "_broadcast_lobby", "bounty_race.resolve(table_summaries, _score_match())", "lobby.table_summaries = table_summaries.duplicate(true)")
        and has_calls("mod/bounty_race.gd", "award_text", 'summary.get("finished") is bool', "summary.bounty_shot <= 0", "is_finite(float(bonus))", "bonus != REWARD")
    )
    if side == "guest":
        return common and has_calls("mod/main.gd", "_result_text", "bounty_race.award_text(summary)", 'summary.get("table") == table_id', 'return text + " · " + award')
    return common and (
        has_calls("mod/main.gd", "_roster_changed", "spectator.refresh_summary()")
        and has_calls("mod/table_spectator.gd", "refresh_summary", "_update_status(_frames.back().data)")
        and has_calls("mod/table_spectator.gd", "_update_status", "BountyRace.award_text(summary)", 'summary.get("table") == _table_id', 'text += " · " + award')
    )


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
        "Bounty pot receipts and settled competitive final award reach both views; watcher refresh follows lobby delivery",
        guest=lambda: _bounty_path("guest"),
        spectator=lambda: _bounty_path("spectator"),
    ),
    Corroboration(
        "MOD-05",
        "Bankroll, applied Lifeline and Domino receipts reach the shared view",
        guest=lambda: all(_feedback_path(kind, "guest") for kind in ("bankroll", "lifeline", "domino")),
        spectator=lambda: all(_feedback_path(kind, "spectator") for kind in ("bankroll", "lifeline", "domino")),
    ),
    Corroboration(
        "MOD-06",
        "Encore receipt reaches the shared view after the production restore attempt",
        guest=lambda: _feedback_path("encore", "guest") and has_calls("mod/multiplayer_balls.gd", "_try_encore", 'rules.record_encore("returned")'),
        spectator=lambda: _feedback_path("encore", "spectator") and has_calls("mod/multiplayer_balls.gd", "_try_encore", 'rules.record_encore("returned")'),
    ),
]
# The complete path per set: the overlay consumes the set's display state and,
# where the tracker names a dedicated cue, draws it (ZODIAC Aspect/Grand Trine).
_SET_COMPLETE = {"ZODIAC": lambda: has_calls("mod/ability_overlay.gd", "shared_lines", '" Aspect"', '" Grand Trine"')}
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
            guest=(lambda s=_set_id: _expansion_path(s, "guest")
                   and _SET_COMPLETE.get(s, lambda: True)()),
            spectator=(lambda s=_set_id: _expansion_path(s, "spectator")
                       and _SET_COMPLETE.get(s, lambda: True)()),
        )
    )
CORROBORATIONS += [
    Corroboration(
        "BOARD-10",
        "fleeting flag presentation",
        guest=lambda: gate_fleeting_clear()[0],
        spectator=lambda: _ball_visual_path("spectator") and '"visuals"' in code(read("mod/ball_visual_state.gd")),
    ),
    Corroboration(
        "FX-08",
        "final_round RichTextLabel content survives the scriptless reader",
        guest=lambda: _rich_text_path("guest"),
        spectator=lambda: _rich_text_path("spectator"),
    ),
    Corroboration(
        "FX-07",
        "dicepop face selection is transmitted",
        guest=lambda: _dice_path("guest"),
        spectator=lambda: _dice_path("spectator"),
    ),
    Corroboration("BOARD-11", "sampled native pocket doors, shield and label capture/validation/application",
                  guest=lambda: _pocket_visual_path("guest"), spectator=lambda: _pocket_visual_path("spectator")),
    Corroboration("HUD-02", "spectator consumes validated elapsed time and remaining/max/spent shots with native wallet/health fields",
                  spectator=_spectator_hud_values),
    Corroboration("HUD-03", "guest aim reminder only; table/Doors lookup has no matching native 0.15.7 table node",
                  guest=lambda: has_calls("mod/replica_game.gd", "apply_table", "_update_aim_reminder(data.ready and playing)")
                  and has_calls("mod/replica_game.gd", "_update_aim_reminder", "reminder.visible = show_aim"),
                  complete=False),
    Corroboration("MOD-13", "committed native cue award receipt, bounded validation and playing/watched shared label",
                  guest=lambda: _cue_feedback_path("guest"), spectator=lambda: _cue_feedback_path("spectator")),
]
for _kind, _row in [("pentagram", "DRAW-01"), ("tether", "DRAW-02"), ("score", "DRAW-03"),
                    ("trail", "DRAW-04"), ("prediction", "DRAW-05")]:
    CORROBORATIONS.append(Corroboration(
        _row, "%s native capture, bounded validation and both view handoffs" % _kind,
        guest=lambda k=_kind: _native_draw_path(k, "guest"),
        spectator=lambda k=_kind: _native_draw_path(k, "spectator"),
    ))
for _row in ("BOARD-02", "BOARD-05", "BOARD-06", "BOARD-07", "BOARD-08", "BOARD-21", "BOARD-22", "DRAW-06", "HUD-06"):
    CORROBORATIONS.append(Corroboration(
        _row, "native ball art capture, typed sparse validation and view application",
        guest=lambda: _ball_visual_path("guest"),
        spectator=lambda: _ball_visual_path("spectator"),
    ))
for _index in range(1, 35):
    if _index in (7, 8):
        continue  # dice/rich-text require their specialized contracts above
    CORROBORATIONS.append(Corroboration(
        "FX-%02d" % _index,
        "catalog producer/validator/view integration and authored independent native-pose fixture; runtime not implied",
        guest=lambda: _catalog_fixture_path("guest"),
        spectator=lambda: _catalog_fixture_path("spectator"),
    ))


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
            if evidence and (claim == "M" or (claim == "P" and item.complete)):
                verdict = "STALE"  # code has the path, tracker still says missing/partial
            elif (not evidence and claim in ("I", "G")) or (claim == "I" and not item.complete):
                verdict = "UNSUPPORTED"  # tracker claims a path the code lacks
            else:
                verdict = "OK"
            results.append(
                {"row": item.row, "side": side, "claim": claim, "evidence": evidence, "complete_path": item.complete,
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
    dispatched = all(has_calls("mod/replica_game.gd", name,
                               "BallLevelFx.set_fleeting(body, bool(item.fleeting))")
                     for name in ("_update_item", "_set_item"))
    inverse = has_calls("mod/ball_level_fx.gd", "set_fleeting", "if enabled:", "body.set_fleeting()",
                        "body.ball_item.fleeting = false", "body.visuals.modulate = Color.WHITE",
                        'body.edge.material.set_shader_parameter("color", Color.BLACK)')
    return dispatched and inverse, "both item paths pass true/false=%s, explicit native visual inverse=%s" % (dispatched, inverse)


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


class PCol(list):
    pass


class PF32(list):
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
    if isinstance(value, PCol):
        return 8 + 16 * len(value)
    if isinstance(value, PF32):
        return 8 + 4 * len(value)
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
    return re.findall(r'"([^"\n]+)"', match.group(1)) if match else []


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
    "data": "FOOD_APPLE", "mixed": "", "ball_visual_status": "complete", "pocket_visual_status": "complete",
}

FLAG_NAMES = {
    "flaming", "fleeting", "star_power", "shielded", "shield_broken", "locked",
    "sprite_flip_h", "shadow_visible", "visible", "alive", "spawned", "gone", "sphere_visible",
}


def _value_for(name: str):
    if name in TYPE_BY_NAME:
        return TYPE_BY_NAME[name]
    if name in FLAG_NAMES:
        return True
    raise ValueError("wire field %r needs an explicit representative value" % name)


def build_ball(sync: str, item_numbers, item_flags, ball_keys, visual_changes: int):
    item = {"data": "FOOD_APPLE", "mixed": ""}
    for key in item_numbers:
        item[key] = _value_for(key)
    for key in item_flags:
        item[key] = False
    ball = {}
    for key in ball_keys:
        if key == "item":
            ball[key] = item
        elif key == "ball_visual":
            # Sparse indexed values: include transforms, tint, shaders/particle
            # numbers and flags. This is an explicit workload, not a native
            # scene-default comparison and not the MAX_FIELDS worst case.
            values = [V2((1.05, 0.95)), Col((1.0, 0.75, 0.25, 0.8)), 0.375, True, 24, 1.5]
            ball[key] = {"v": 1, "p": 0,
                         "d": [[index, values[index % len(values)]] for index in range(visual_changes)]}
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
        elif key == "pocket_visual":
            pocket[key] = build_pocket_visuals(read("mod/table_effects_sync.gd"))
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
    # Historical v2 workload, retained for baseline comparison. These toy keys
    # and slot counts are not the production inventory schema. The separate
    # compatibility scenario below parses that schema; correcting this old
    # workload would be a model correction, not actual network growth.
    item = {"data": "FOOD_APPLE", "mixed": "", "base_score": 5, "temp_extra_score": 0, "level": 1,
            "weight_state": 0, "flaming": False, "fleeting": False, "star_power": False,
            "shielded": False, "shield_broken": False, "locked": False}
    return {"snacks": 1, "cocktails": 0, "balls": [item] * 8, "passives": [None] * 3,
            "cubes": [None] * 2, "tickets": []}


def _inventory_slot_minimums(source: str) -> dict[str, int]:
    match = re.search(r"const SLOT_MINIMUMS = (\{[^}]*\})", source)
    if not match:
        raise ValueError("inventory slot minimums require a representative model update")
    result = json.loads(match.group(1))
    if set(result) != {"build", "passives", "cubes"} or any(type(value) is not int or value < 0 for value in result.values()):
        raise ValueError("inventory slot groups require a representative model update")
    if set(_keys_in_block(source, "const SLOT_LIMITS =")) != set(result):
        raise ValueError("inventory slot limits require a representative model update")
    return result


def build_current_inventory(copy_id: str = "CRISPS") -> dict:
    """0.17.2 shape: eight balls, CRISPS, GUMMY-BRAIN, and empty padded slots.

    CRISPS is an installed passive with passive_has_number_in_round=true. Only
    GUMMY-BRAIN gets copy_id; ordinary table-ball items do not carry this field.
    This is a synthetic shape, not a captured or validated native inventory.
    """
    source = code(read("mod/player_inventory_sync.gd"))
    capture = code(function_body(source, "capture"))
    minimums = _inventory_slot_minimums(source)
    item_keys = _keys_in_block(capture, "var entry = {")
    numbers = _const_dict_keys(source, "NUMBERS")
    flags = _const_list(source, "FLAGS")
    optional = set(re.findall(r'entry\["(\w+)"\]\s*=', capture))
    if not item_keys or not numbers or not flags or optional != {"copy_id"}:
        raise ValueError("inventory item fields require a representative model update")
    if not has_calls("mod/player_inventory_sync.gd", "capture",
                     'group == "passives" and entry.data == "GUMMY-BRAIN"',
                     'entry["copy_id"] = item.copy_id'):
        raise ValueError("inventory copy identity requires its sparse capture contract")
    item = {key: _value_for(key) for key in item_keys + numbers}
    item.update({key: False for key in flags})
    values = {"snacks": 1, "cocktails": 0}
    top_keys = _keys_in_block(capture, "var result = {")
    if set(top_keys) != set(values):
        raise ValueError("inventory top fields require a representative model update")
    result = {key: values[key] for key in top_keys}
    result["build"] = [item.copy() for _ in range(8)]
    result["passives"] = [dict(item, data="CRISPS"), dict(item, data="GUMMY-BRAIN", copy_id=copy_id)]
    result["cubes"] = [None] * 2
    for group, minimum in minimums.items():
        result[group] += [None] * max(0, minimum - len(result[group]))
    return result


def compatibility_inventory_wire() -> dict:
    """Separate port workload; never substitute it for a historical scenario."""
    import copy

    populated = build_current_inventory()
    cleared = build_current_inventory("")
    absent = copy.deepcopy(populated)
    del absent["passives"][1]["copy_id"]
    snapshot = build_snapshot(*WIRE_SCENARIOS["idle_16_balls"])
    bytes_by_case = {}
    for name, inventory in [("absent", absent), ("cleared", cleared), ("copied", populated)]:
        snapshot["scene"]["inventory"] = inventory
        bytes_by_case[name] = var_bytes(snapshot)
    return {
        "native_version": "0.17.2",
        "copy_target": "CRISPS",
        "slot_counts": {group: len(populated[group]) for group in ("build", "passives", "cubes")},
        "inventory_bytes_without_optional_copy": var_bytes(absent),
        "inventory_bytes_cleared": var_bytes(cleared),
        "inventory_bytes_copied": var_bytes(populated),
        "copy_field_bytes_cleared": var_bytes(cleared) - var_bytes(absent),
        "copy_field_bytes_populated": var_bytes(populated) - var_bytes(absent),
        "idle_snapshot_bytes": bytes_by_case,
        "scope": "Separate synthetic current-schema inventory: eight build items, CRISPS and GUMMY-BRAIN, empty padding to source minimums. Absent copy_id is an accepted legacy field case; current capture emits the copied ID or explicit empty clear. Reuses the idle 16-ball table shape. Excludes transport overhead; no actual native packet, frequency or performance claim. Historical wire scenarios and comparison thresholds are unchanged.",
    }


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


def build_pocket_visuals(effects_source: str):
    paths = _const_list(effects_source, "POCKET_VISUAL_PATHS")
    if not paths:
        raise RuntimeError("could not parse pocket visual paths")
    return [[V2((0.0, 0.0)), 0.0, V2((1.0, 1.0)), Col((1, 1, 1, 1)),
             Col((1, 1, 1, 1)), True, "x12" if path == "Label" else ""] for path in paths]


def build_effect_pocket(effects_source: str, ident: int):
    keys = _keys_in_block(function_body(effects_source, "capture"), "data.pockets.append(")
    if not keys:
        raise RuntimeError("could not parse durable pocket capture fields")
    pocket = {}
    for key in keys:
        if key == "id":
            pocket[key] = ident
        elif key == "visuals":
            pocket[key] = build_pocket_visuals(effects_source)
        else:
            pocket[key] = _value_for(key)
    return pocket


def build_transient(parts: int, ident: int, kind: str = "wisp"):
    part_states = []
    for index in range(parts):
        state = {"index": index, "position": V2((1.0, 2.0)), "rotation": 0.5, "scale": V2((1, 1)),
                 "modulate": Col((1, 1, 1, 1)), "self_modulate": Col((1, 1, 1, 1)), "visible": True}
        if index % 2 == 0:
            state["frame"] = 0
        # Nontrivial sampled state. The old estimate counted only transforms
        # and therefore ignored the expensive optional fields entirely.
        if index == 1:
            state.update({"points": PV2([V2((float(i), float(i) / 2)) for i in range(16)]),
                          "width": 2.0, "color": Col((1, 0.75, 0.25, 1))})
        if index == 2:
            state["shader"] = {"alpha": 0.5, "color": Col((1, 0.75, 0.25, 1))}
        if index == 3:
            state["emitting"] = True
        if kind == "final_round" and index == 4:
            state["text"] = "UI_LAST_ROUND"
        if kind == "dicepop" and index == 4:
            state["dice_face"] = 5
        part_states.append(state)
    return {"id": ident, "kind": kind, "parts": part_states}


def build_native_draw(active: bool, scores: int, trails: int) -> dict:
    """Synthetic representative drawings including label and gradient costs.

    The host omits a reset, zero-candle pentagram. Active scenarios contain one
    ritual, tether, prediction, several motion trails and retained score labels.
    Counts are documented in the report; this never truncates to hide overflow.
    """
    layouts = {"pentagram": (4, {2}, set()), "tether": (1, {0}, set()),
               "trail": (1, {0}, set()), "prediction": (5, {1}, set()),
               "score": (7, set(), {3, 4, 6})}
    kinds = []
    if active:
        kinds = ["pentagram", "tether", "prediction"] + ["trail"] * trails + ["score"] * scores
    items = []
    for ident, kind in enumerate(kinds, 2000):
        count, lines, labels = layouts[kind]
        item = {"id": ident, "kind": kind, "parts": []}
        if kind == "pentagram":
            item.update({"candles": 3 if active else 0, "strength": 2, "progress": 0.5, "done": False})
        elif kind == "score":
            item["ttl"] = 0.75
        else:
            item["owner"] = 123456
        for index in range(count):
            part = {"index": index, "position": V2((100.5, -40.25)), "rotation": 0.5,
                    "scale": V2((1, 1)), "visible": active, "modulate": Col((1, 1, 1, 1)),
                    "self_modulate": Col((1, 1, 1, 1)), "z": 1}
            if index in lines:
                points = 32 if kind == "trail" else 16
                part.update({"points": PV2([V2((float(i), float(i) / 2)) for i in range(points if active else 0)]),
                             "width": 2.0, "color": Col((1, 0.75, 0.25, 1)),
                             "gradient_colors": PCol([Col((1, 1, 1, 0)), Col((1, 1, 1, 1))]),
                             "gradient_offsets": PF32([0.0, 1.0])})
            if index in labels:
                part["text"] = "+12,345" if index == 3 else "+2 money" if index == 4 else "BONUS"
            if kind == "score" and index in (3, 4, 5, 6):
                part["size"] = V2((96.0, 24.0))
            if (kind == "score" and index == 2) or (kind == "prediction" and index == 3):
                part["shader"] = {"alpha": 0.5, "color": Col((1, 0.75, 0.25, 1))}
                if kind == "prediction":
                    part["shader"]["charge_amount"] = 0.5
            item["parts"].append(part)
        items.append(item)
    return {"version": 1, "status": "complete", "reason": "", "items": items}


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
    visual_changes = 36 if transients else 12
    for key in top_keys:
        if key == "balls":
            data[key] = [build_ball(sync, item_numbers, item_flags, ball_keys, visual_changes) for _ in range(balls)]
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
        "pockets": [build_effect_pocket(effects_source, 3000 + i) for i in range(6 + holes)],
    }
    data["visual_fx"] = {
        "version": 1, "status": "complete", "reason": "",
        "items": [build_transient(transient_parts, 1000 + i,
                                  ("wisp", "final_round", "dicepop")[i % 3]) for i in range(transients)],
    }
    if has_calls("mod/table_sync.gd", "capture", "data.native_draw =", "_native_draw_capture.capture(game)"):
        data["native_draw"] = build_native_draw(bool(transients), min(transients, 8), min(balls // 4, 12))
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
        native_bytes = var_bytes(scene["native_draw"]) if "native_draw" in scene else 0
        ball_visual_bytes = sum(var_bytes(ball["ball_visual"]) for ball in scene["balls"] if "ball_visual" in ball)
        report[name] = {
            "bytes": total,
            "bytes_per_second_at_cadence": int(total * SNAPSHOT_HZ),
            "key_share": round(keys / total, 3),
            "ball_bytes": var_bytes(scene["balls"][0]),
            "effects_bytes": var_bytes(scene["effects"]) + var_bytes(scene["visual_fx"]) + native_bytes,
            "ball_visual_bytes": ball_visual_bytes,
            "native_draw_bytes": native_bytes,
            "native_draw_items": len(scene.get("native_draw", {}).get("items", [])),
            "pocket_effects_bytes": var_bytes(scene["effects"]["pockets"]),
            "pocket_visual_bytes": sum(var_bytes(pocket["pocket_visual"]) for pocket in scene["pockets"] if "pocket_visual" in pocket),
            "ball_visual_changes_each": len(scene["balls"][0].get("ball_visual", {}).get("d", [])),
            "exceeds_table_target": var_bytes(scene) > 192 * 1024,
            "exceeds_native_draw_limit": native_bytes > 32 * 1024,
        }
    return report


def reliable_feedback_wire() -> dict:
    """Presentation additions to reliable state, separate from table snapshots."""
    cue_values = {"generation": 1, "shot": 4, "actor": 76561198000000000,
                  "ball": 12345678900, "model": "double_rail", "points": 2.5}
    cue_keys = _keys_in_block(body("mod/cue_effects.gd", "commit_pocket"), "_feedback = {")
    if not cue_keys or set(cue_keys) != set(cue_values):
        raise ValueError("wire cue receipt fields require a representative model update")
    cue = {key: cue_values[key] for key in cue_keys}
    outcomes = {}
    for kind, status, amount in [("bounty_award", "awarded", 10), ("bankroll", "awarded", 2),
                                 ("lifeline", "healed", 1), ("domino", "awarded", 20),
                                 ("encore", "returned", 0)]:
        outcomes[kind] = {"ball": 12345678900, "shot": 4, "status": status, "amount": amount}
    together = {"generation": 1, "outcomes": outcomes}
    return {"cue_receipt_bytes": var_bytes(cue), "five_together_receipts_bytes": var_bytes(together),
            "scope": "Synthetic populated receipt values only; excludes enclosing state/keys, other abilities and transport envelope. No cadence estimate: publication is change-gated."}


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
        "wire_model_version": 2,
        "wire_model_scope": "Historical synthetic descriptor shapes, not captured or validated native packets; the v2 inventory retains toy keys/slot counts for baseline comparability. Current 0.17.2 inventory is reported separately. Includes sparse ball art, pocket art, native drawing, transient points/shaders/text. Excludes transport envelope, reliable state/ability stream and retransmission overhead. No compression or overflow trimming applied.",
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
        "reliable_feedback_wire": reliable_feedback_wire(),
        "compatibility_inventory_wire": compatibility_inventory_wire(),
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
    print("Wire model v%d (estimated var_to_bytes; comparison cadence %.0f Hz):" % (
        report["wire_model_version"], SNAPSHOT_HZ))
    print("  Synthetic workload before overflow limits; normal idle heartbeat is slower.")
    for name, values in report["wire"].items():
        print("  %-24s %7d B/snapshot  %7.1f KiB/s  keys %4.0f%%  ball %4d B  effects %6d B" % (
            name, values["bytes"], values["bytes_per_second_at_cadence"] / 1024.0,
            values["key_share"] * 100, values["ball_bytes"], values["effects_bytes"]))
        print("    sparse ball art %d B (%d fields/ball); pocket art %d B; native drawing %d B (%d items)%s" % (
            values["ball_visual_bytes"], values["ball_visual_changes_each"], values["pocket_visual_bytes"], values["native_draw_bytes"],
            values["native_draw_items"], " — exceeds table target; production must overflow a substate" if values["exceeds_table_target"] else ""))
        if values["exceeds_native_draw_limit"]:
            print("    exceeds native drawing substate limit; production must report overflow")
    receipts = report["reliable_feedback_wire"]
    print("  Separate reliable state: cue receipt %d B; five TOGETHER receipts %d B (values only)." % (
        receipts["cue_receipt_bytes"], receipts["five_together_receipts_bytes"]))
    inventory = report["compatibility_inventory_wire"]
    print("  Separate native 0.17.2 inventory scenario (current schema, two occupied passives):")
    print("    idle snapshot absent/cleared/copied: %d / %d / %d B; GUMMY-BRAIN copy_id adds %d B empty or %d B for %s." % (
        inventory["idle_snapshot_bytes"]["absent"], inventory["idle_snapshot_bytes"]["cleared"],
        inventory["idle_snapshot_bytes"]["copied"], inventory["copy_field_bytes_cleared"],
        inventory["copy_field_bytes_populated"], inventory["copy_target"]))
    print("    Historical v2 inventory keys/counts are synthetic, not production-valid; no baseline rewrite.")
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


def self_test() -> bool:
    """Test the evidence checker itself; no GDScript or game is executed."""
    import copy
    import unittest
    from unittest.mock import patch

    class BenchmarkTests(unittest.TestCase):
        def test_comments_cannot_supply_integration_evidence(self):
            sample = 'func sample():\n\t# consume(data)\n\tvar label = "#keep"\n'
            with patch.dict(globals(), read=lambda _path: sample):
                self.assertFalse(has_calls("unused", "sample", "consume(data)"))
                self.assertTrue(has_calls("unused", "sample", '"#keep"'))

        def test_disconnected_fx_pipeline_is_rejected(self):
            original_read = read
            changes = [
                ("mod/table_sync.gd", "_visual_fx_capture.capture(game)"),
                ("mod/table_sync.gd", "VisualFx.problem(data.visual_fx)"),
                ("mod/table_visual_fx_view.gd", "_apply_item(entry, item, origin)"),
            ]
            for side in ("guest", "spectator"):
                self.assertTrue(_fx_path(side))
                for path, expression in changes:
                    source = original_read(path)
                    self.assertIn(expression, source)
                    mutated = source.replace(expression, "null # " + expression)
                    with patch.dict(globals(), read=lambda relative, p=path, s=mutated: s if relative == p else original_read(relative)):
                        self.assertFalse(_fx_path(side), (side, path, expression))

        def test_dice_validator_and_consumer_are_required(self):
            original_read = read
            for path, expression in [
                ("mod/table_visual_fx.gd", "part.dice_face >= _catalog[item.kind].dice_faces.size()"),
                ("mod/table_visual_fx_view.gd", "dice_faces[state.dice_face]"),
            ]:
                self.assertTrue(_dice_path("guest"))
                mutated = original_read(path).replace(expression, "null # " + expression)
                with patch.dict(globals(), read=lambda relative, p=path, s=mutated: s if relative == p else original_read(relative)):
                    self.assertFalse(_dice_path("guest"))

        def test_native_draw_requires_each_producer_and_view(self):
            original_read = read
            for kind in ("pentagram", "tether", "trail", "prediction", "score"):
                for side in ("guest", "spectator"):
                    self.assertTrue(_native_draw_path(kind, side), (kind, side))
            path = "mod/table_native_draw_view.gd"
            mutated = original_read(path).replace("_apply_item(entry, item, origin)", "pass # _apply_item(entry, item, origin)")
            with patch.dict(globals(), read=lambda relative: mutated if relative == path else original_read(relative)):
                self.assertFalse(_native_draw_path("pentagram", "guest"))
                self.assertFalse(_native_draw_path("score", "spectator"))

        def test_wire_unknown_fields_fail_closed(self):
            with self.assertRaisesRegex(ValueError, "explicit representative"):
                _value_for("future_expensive_descriptor")

        def test_compatibility_inventory_preserves_sparse_copy_cost(self):
            legacy = build_inventory()
            current = build_current_inventory()
            self.assertEqual(set(current), {"snacks", "cocktails", "build", "passives", "cubes"})
            self.assertEqual(len(current["build"]), 16)
            self.assertEqual(len(current["passives"]), 4)
            self.assertTrue(all("copy_id" not in item for item in current["build"] if item))
            self.assertNotIn("copy_id", current["passives"][0])
            self.assertEqual(current["passives"][1]["copy_id"], "CRISPS")
            report = compatibility_inventory_wire()
            # Variant key + String value: 16 + 8 empty, 16 + 16 for CRISPS.
            self.assertEqual(report["copy_field_bytes_cleared"], 24)
            self.assertEqual(report["copy_field_bytes_populated"], 32)
            self.assertEqual(report["idle_snapshot_bytes"]["copied"] - report["idle_snapshot_bytes"]["absent"], 32)
            self.assertEqual(build_inventory(), legacy)
            self.assertEqual(build_snapshot(*WIRE_SCENARIOS["idle_16_balls"])["scene"]["inventory"], legacy)

        def test_compatibility_inventory_rejects_unmodeled_fields(self):
            original_read = read
            path = "mod/player_inventory_sync.gd"
            source = original_read(path)
            marker = 'entry["copy_id"] = item.copy_id'
            self.assertIn(marker, source)
            mutated = source.replace(marker, marker + '\n\t\t\tentry["future_expensive_descriptor"] = []')
            with patch.dict(globals(), read=lambda relative: mutated if relative == path else original_read(relative)):
                with self.assertRaisesRegex(ValueError, "item fields"):
                    build_current_inventory()

        def test_partial_path_does_not_support_complete_claim(self):
            evidence = Corroboration("HUD-03", "aim reminder only", guest=lambda: True, complete=False)
            with patch.dict(globals(), CORROBORATIONS=[evidence]):
                partial = Row("HUD-03", "doors and aim reminder", "P", "M", "HUD")
                self.assertEqual(check_corroborations({partial.id: partial})[0]["verdict"], "OK")
                complete = Row("HUD-03", "doors and aim reminder", "I", "M", "HUD")
                self.assertEqual(check_corroborations({complete.id: complete})[0]["verdict"], "UNSUPPORTED")

        def test_bounty_completion_requires_final_award_delivery(self):
            original_read = read
            self.assertTrue(_bounty_path("spectator"))
            path = "mod/main.gd"
            expression = "spectator.refresh_summary()"
            mutated = original_read(path).replace(expression, "pass # " + expression)
            with patch.dict(globals(), read=lambda relative: mutated if relative == path else original_read(relative)):
                self.assertFalse(_bounty_path("spectator"))
                self.assertTrue(_bounty_path("guest"))

        def test_wire_accounts_for_packed_payload_and_visuals(self):
            self.assertEqual(var_bytes(PV2([V2((0, 1))] * 3)), 32)
            self.assertEqual(var_bytes(PCol([Col((1, 1, 1, 1))] * 2)), 40)
            self.assertEqual(var_bytes(PF32([0.0, 1.0])), 16)
            idle = build_snapshot(*WIRE_SCENARIOS["idle_16_balls"])["scene"]
            active = build_snapshot(*WIRE_SCENARIOS["scoring_burst_16_balls"])["scene"]
            self.assertGreater(var_bytes(idle["balls"][0]["ball_visual"]), var_bytes(True))
            self.assertGreater(var_bytes(active["native_draw"]), var_bytes(idle["native_draw"]))
            self.assertGreater(var_bytes(active["balls"][0]), var_bytes(idle["balls"][0]))

        def test_model_version_does_not_hide_wire_regression(self):
            baseline = {"coverage": {"score": 90}, "gates": [],
                        "wire": {"sample": {"bytes": 1000}}, "corroboration_failures": []}
            report = copy.deepcopy(baseline)
            report["wire_model_version"] = 999
            report["wire"]["sample"]["bytes"] = 1020
            self.assertEqual(compare(report, baseline), ["wire sample grew 1000 → 1020 bytes"])

    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(BenchmarkTests))
    return result.wasSuccessful()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", type=Path, help="write the report to this path")
    parser.add_argument("--write-baseline", action="store_true", help="record this run as the baseline")
    parser.add_argument("--check", action="store_true", help="exit 1 on regression vs the baseline")
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--self-test", action="store_true", help="exercise static benchmark guards without launching a game")
    args = parser.parse_args(argv)
    if args.self_test:
        return 0 if self_test() else 1
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

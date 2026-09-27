# Regression lessons and verification

Read [AGENTS.md](../../../../AGENTS.md), [tests/README.md](../../../../tests/README.md), [GAME_LOOP.md](../../../../tests/GAME_LOOP.md) and the relevant entries in [PERFORMANCE.md](../../../../docs/PERFORMANCE.md). These are evidence requirements, not a guarantee that tests find every bug.

## What recent fixes teach

| Failure and source | General rule | Regression seam |
| --- | --- | --- |
| Initial click stopped after idle cue hiding ([PR #46](https://github.com/harsh2204/ultrapool-together/pull/46)). Native `_process` polls input and calls `can_shoot`; a temporary menu flag blocked startup. | Test the initial action; do not pre-set aiming state. Cosmetic suppression must not change gameplay eligibility. | `native_aim_fixture.gd::check` sends press/motion/release on host and guest; menu/off-turn rejection and one submission. Sink replaces physics/network submission, so verify those elsewhere. |
| Cue tint restored opaque parent fade and fixed positioning erased native charge pullback ([PR #47](https://github.com/harsh2204/ultrapool-together/pull/47)). | Inspect native animation ownership. Preserve alpha/parent transforms and test repeated reconciliation while hidden and while charging. | `cue_probe.gd` and `native_aim_fixture.gd`: fade, pullback, teammate aim, menu/stale cleanup. New cases were authored, unrun at v0.9.2. |
| BLACK-HOLE appended into an Array aliased by native Game/Table, producing an invalid fixed-pocket index ([PR #47](https://github.com/harsh2204/ultrapool-together/pull/47)). | Model actual aliasing and ownership. Validate the shot baseline before spending a shot; make topology reliable. | `snapshot_probe._check_pocket_capture`: same shared Array, zero-scale spawn, all ten holes, cleanup. `controller_probe._topology_keyframes/_rejected_shots_preserve_turn_state`: targeted resync isolation, reorder and recovery. |
| Guests still missed snacks/cubes after an earlier sync fix ([#33](https://github.com/harsh2204/ultrapool-together/issues/33), [PR #37](https://github.com/harsh2204/ultrapool-together/pull/37)). | Follow the field through capture, validation, native apply, unlock gates and actual visible controls. A transmitted value is not rendered parity. | `render_probe._capture_guest_shop/_capture_guest_negative_cubes`; authoritative counter flags and inventory refresh. Compare matched host appearance before changing shader code ([PR #44](https://github.com/harsh2204/ultrapool-together/pull/44)). |
| Navigation and shared-shop state diverged ([#16](https://github.com/harsh2204/ultrapool-together/issues/16), [PR #35](https://github.com/harsh2204/ultrapool-together/pull/35)). | Keep view navigation separate from transaction revision/readiness. Defer host-follow during drags or pending actions; honor sync-off and exclusive shopping. | `ui_nav_probe.gd`, `render_ui_fixtures.capture_shop_presence`, round-flow delayed/rejected actions. Vocabulary checks alone do not verify live follow timing. |
| Scene unique-name binding and long option text broke UI ([PR #24](https://github.com/harsh2204/ultrapool-together/pull/24), [PR #44](https://github.com/harsh2204/ultrapool-together/pull/44)). | Review script and scene together: exported types, `%Name` ownership, dimensions, input filters and CRT layers. | `render_ui_fixtures.capture_together_options/_assert_mod_options_no_horizontal_overflow`; shop layout probe. Parsing cannot prove a node path or rendered size. |
| Some failed probes also failed at the base revision ([PR #27](https://github.com/harsh2204/ultrapool-together/pull/27)). | Compare the same fixture/configuration at base and head. Repair stale IDs/stubs without weakening production validation or deleting useful assertions. | Controller service substitutes and snapshot valid-state construction; record exact base/head evidence and unexpected errors. |
| Ball state arrived while floor effects did not ([#15](https://github.com/harsh2204/ultrapool-together/issues/15), GAP-007). | Inventory durable objects and transient events separately; avoid executing native effect callbacks on guests. | [Table-effect matrix](../../../../docs/TABLE_EFFECTS.md); future snapshot/guest/spectator lifecycle fixtures. Basic FX pulses do not establish full effect parity. |

## Choose coverage by behavior

| Change | Existing seam | Required negative/lifecycle cases |
| --- | --- | --- |
| Input/cue | `native_aim_fixture.gd`, `adapter_probe.gd`, `controller_probe.gd`, `cue_probe.gd` | Idle first click, native charge/release, controller path separately, local/off-turn/menu, remote stale state; production authority and exactly one accepted shot. |
| Table state/effects | `snapshot_probe.gd`, `controller_probe.gd`, `render_probe.gd`, `round_flow_fixtures.gd` | Capture→validate→apply, malformed IDs/values/resources, first/late sync, duplicate/reordered/lost motion, reliable create/remove, scene/round reset, disconnect/rematch, spectator switch and no guest mutations. |
| Shop transactions | `shop_probe.gd`, `shop_layout_probe.gd`, `shop_input_fixture.gd`, `round_flow_fixtures.gd` | Source/target identity, stale/duplicate requests, affordability, conflict, pending state, rejection rollback, timeout/resync, removed item during drag, Ready invalidation, sync-off and winner-only. |
| Snack bar | Above plus `shop_probe.check_native_transactions`, `round_flow_fixtures.check_guest_snack_drag` and `render_probe._capture_guest_shop` | Native ticket purchase, one owned identity, no money spend, no-ticket/occupied-slot/stale-ID/replay rejection. Passive gameplay, counter availability and live simultaneous spending need separate coverage. |
| Mixer | `shop_probe.check_native_transactions`, layout/inventory roundtrip and `render_ui_fixtures.capture_shop_presence` | Both native ingredients→real animation/completion→output collection, score/ticket/item conservation, invalid/occupied inputs/output, replay/busy/rejected actions. Add already-mixed inputs, interrupted close/reopen and remote delayed/conflicting transactions as relevant. |
| New content | `multiplayer_balls_probe.gd`, `expansion_sets_probe.gd`, shop and snapshot seams | Disabled/master-off, host/guest catalog registration, allowlisted IDs, shop-only gating, native effect order, bounded caps, duplicate callbacks, scene reset and rematch. Inspect harness registration before claiming a probe runs. |
| Lobby/navigation/HUD | `lobby_probe.gd`, `ui_nav_probe.gd`, `render_ui_fixtures.gd`, `render_probe.gd` | Focus and node identity, real interaction, maximum roster, narrow layouts, changed locale if affected, settings popups, host/guest and CRT layering. |
| Routing/transport | `router_probe.gd`, `transport_budget_probe.gd`, `controller_probe.gd`; separately authorized session/transport tests | Authenticated actor/table boundaries, stale generations, channel progress, burst packet/byte/time limits including handlers, bounded cache cleanup. |
| Packaging/installers | `tests/installation.ps1`, `tests/installation_macos.py`, `tests/capture_macos.py` | Isolated profiles, repeat update/uninstall, original-file and save preservation, unsafe paths, cleanup and correct platform. |

All paths in this table are under `tests/`. **Probe existence is not execution.** Check `render_probe._ready → _run`, its model-probe list, loaded fixture calls and result aggregation. The expanded harness invokes snapshot plus eleven model probes: team_vote, lobby, cue, ui_nav, expansion_sets, multiplayer_balls, presence, router, controller, transport_budget and shop_layout. It also calls the native pocket and snack/mixer transaction fixtures. Each embedded model must report completion, a nonzero assertion count and no failures. Earlier v0.9.2 runs did not include all these probes. Clone-round/set-vote and standalone adapter/session/transport probes are not automatically covered; consult tests/README. Wire a new required assertion into the shared harness before claiming the gallery tested it.

## Validation sequence

1. Review native/protocol contracts and write a meaningful regression. State the pre-fix failure, production boundary, expected outcome and checks outside the fixture's reach.
2. Run `git diff --check`. Parse changed GDScript with `gdtoolkit`, plus scripts importing a changed contract where appropriate. Check referenced file paths, `preload/load`, exported properties and scene unique names. GDScript parsing does not check inherited native types or execute assertions.
3. For installer/package changes, run the relevant isolated platform suites from tests/README. Inspect built ZIP content and asset references; never ship supplied native game files. Do not claim macOS verification from Windows or vice versa. Documentation-only changes need link/metadata/content review, not a game launch.
4. For authorized native rendering, use [Capture-Screens](../../../../docs/screenshots.md) with the existing isolated profile, muted audio, single bounded process and watchdog. Review assertions, stdout/stderr, gallery, cleanup and preservation audit together. A good screenshot with failed assertions or changed normal saves is not a passing run.
5. Verify live interactions/topologies separately when authorized: local leader and remote-led table, multiple guests, simultaneous input, delay/loss, disconnect/rematch, Windows/macOS. A one-process record/replay substitutes neither transport nor physical user input on several machines.
6. Record actual evidence and remaining acceptance. Performance claims require matched fixture, renderer/frame cap, counts, topology and latency; frame-time p50/p95/p99/max, input-to-feedback/confirmation, packet bytes/rates, queue growth and relevant call counts. Average FPS and static estimates cannot close performance issues.

The expanded Windows run and remaining native/live/platform limits are recorded in tests/README and PERFORMANCE.md. Historical passing runs apply to their recorded commits/configurations, not every later merge. Update the tracking docs when a run actually passes.

## PR/release evidence record

Use this compact record in the change description:

- Trigger and user-visible before/after.
- Affected authority, protocol and native callback contracts.
- Regression fixture and why it detects the former bug.
- Commands/checks actually run, outcome and exact revision; label authored/unrun checks separately.
- Native/live/platform/performance checks still pending, relevant tracker IDs and next runnable scenario.
- Packaging/update/uninstall and preservation evidence when applicable.

Do not turn incomplete verification into “bug-free,” “all effects synced,” “fully tested” or a latency/FPS claim. For shared-schema changes, explicitly decide mixed-version behavior and review version/room-code compatibility gates; do not assume installation on one player updates everyone.

# Client table-effect coverage

Native floor effects, energy projectiles, WORMHOLE pocket state, and catalogued transient visuals have shared guest and spectator renderers. **Overall parity: partial; the implemented subset has Windows and macOS native fixture evidence.** This document records implementation details and historical acceptance for [issue #48](https://github.com/harsh2204/ultrapool-together/issues/48), **GAP-007** in [PERFORMANCE.md](PERFORMANCE.md). The measurements below cover bounded fixtures, not complete audiovisual parity or live-session performance.

Use the [effect replication and scoring tracker](EFFECT_REPLICATION_TRACKER.md) for the 2026-10-05 audit, per-family guest/spectator status, native catalog checklist, missing non-catalog drawing and scoring effects, and prioritized scoring-stall investigation. CANDLE ritual geometry, ball-local tether/trail/prediction geometry and floating score/money now use a separate `native_draw` contract. Ball-local sampled presentation uses `ball_visual`; neither contract runs native gameplay callbacks. Fixed-pocket artwork uses optional ordinary `pocket.pocket_visual`, keeping the legacy durable-effect pocket schema unchanged for protocol-10 peers. See the tracker for the exact stated fields and remaining trigger acceptance.

The supported native source is Ultrapool 0.15.7. Assets are read from the installed game; no native source or art is redistributed. Historical evidence below describes the exact revision tested, rather than verification of later additions.

The optional `effects` and `visual_fx` fields originally preserved protocol 8 acceptance in v0.9.4; older leaders could not provide the descriptors and older clients ignored them. The current Cue Workshop build uses **v0.10.0 / protocol 10 / UP10**, so every participant must use that compatible build. Historical v0.9.4 evidence below remains specific to the revision tested. The PR #53 fields are additive within protocol 10: updated peers accept their absence, while older builds omit or ignore them. Matching PR builds and native 0.15.7 are required for the new presentation; mixed builds do not establish visual parity.

## Coverage matrix

| Family | Guest and spectator implementation | Remaining verification or limit |
| --- | --- | --- |
| BLACK-HOLE / dynamic pockets | Stable identity, position, rotation, root scale, multiplier, extra score, closed/shielded state, held-ball indicator, creation and removal. Fixed pockets are distinguished by native parent ownership. | Six-base/ten-hole validation, native physical pocketing, guest hydration, retained identity, removal and resync passed in the current Windows run. Live delivery still needs verification. |
| Flowers | Native texture hierarchy, host-chosen petal/core colors, power label, spin, root growth/scale, visibility and removal. | Real native improvement and consumption, host/guest/spectator appearance, and retained lifecycle checks passed. |
| Oil | Native texture, host flip, rotation, tint, charge-related opacity, pose and removal. | Native collision charge consumption and comparison against the host texture, flip, tint and lifecycle passed. |
| Floor fire / flame drops | Native flame texture/material, host pose/tint, pickup disappearance and cleanup. | Ignition remains host-only. A burning ball is still a separate state family. |
| Stoves | Native patch appearance, host pulse tint/pose, persistence and removal. | Native ignition and persistence checks passed separately from flame pickup. |
| Thorns | Native appearance/pose and authoritative consumption/removal. | Native consumption and guest/spectator visual comparison passed. |
| Launchpads | Host-selected direction, sprite/shadow rotation, pose and lifecycle. Held-ball identity and launch timer are captured; the ordinary ball stream carries the held/released ball pose. | Native hold/release checks passed. The replica never holds, damps or launches a ball itself. |
| WORMHOLE | Pocket child suction scale and WhiteHoleEffect tint, plus traveling pocket-wisp presentation through the transient renderer. | Root pocket scale remains a separate field. Native suction and guest/spectator child-state checks passed; live transport timing needs separate verification. |
| ENERGY-BALL projectiles | Dedicated native visual hierarchy and host pose/visual scale/visibility, including native retirement after removal from the active energy array. A weak registry retains only still-existing native bodies until they are freed. | Native active limit is ten; the replication limit also includes retiring bodies. The verified 0.15.7 hierarchy uses an EnergyCircle Sprite2D and has no line or particle nodes. Optional prefab line support is bounded; it is not evidence of native projectile trails. |
| Burning ball, star/shield/lock, level and item transformations | Existing durable ball item fields and native visual setters remain represented. Catalogued transformation/upgrade visuals use the transient path. | Durable result correctness and each transient animation remain distinct acceptance checks. |
| Wisps, tornado, lightning/zap lines, constellation links, explosions and catalogued effects | Shared scriptless rendering of the installed EffectManager catalog plus ordinary and pocket wisps. Host part transforms, visibility, tint, sprite frames, allowlisted wisp textures, line geometry, labels and typed scalar/vector shader parameters are captured. Constellation child stars/links have an explicit visual path. | The catalog contains 34 definitions on the supported installation; this is not 34 independently verified gameplay triggers. The native fixture passed for boom, tornado, zap line, constellation and both wisp kinds. Particle seeds/elapsed simulation, uncatalogued effects and arbitrary dynamic children are not a general replication protocol. |
| Basic shot/spawn/pocket/impact visuals and sounds | Existing [replica_fx.gd](../mod/replica_fx.gd) supplies bounded guest pulses and inferred impact sounds; catalogued native visual nodes are additional presentation. | There is no general native audio/event replay. Full-screen native postprocessing and effects outside the catalog need their own contract and tests. |

## Sampled native presentation

[ball_visual_state.gd](../mod/ball_visual_state.gd) transfers sparse differences from two cached native ball templates over a fixed set of visual children. Actual host flame/star/score particles, fleeting shader state, flash, level spark, tint and transforms apply to retained guest and spectator nodes. Resource paths, native callbacks and cue input are excluded. Native particle count and typed-value bounds apply; particle random phase is still approximate. Local guest LUNA aiming remains native, with the corresponding sampled hint suppressed only while that player owns local input.

[table_native_draw.gd](../mod/table_native_draw.gd) and its [scriptless view](../mod/table_native_draw_view.gd) carry CANDLE line/circle pose, bounded REAPER/trail/LUNA geometry and native score/money text, tint, shader values and Control bounds. Score descriptors have bounded lifetime and duplicate-expiry protection. Round/scene reset clears pending work and expired identities. The installed 0.15.7 REAPER ball leaves its `deathline` reference null despite having the native `visuals/deathline` node. A host-only lifecycle repair binds that existing node once after native readiness; native code still owns its geometry. The macOS fixture confirms the reference, visible host tether and matching guest/spectator geometry.

The transient contract additionally covers six allowlisted dice faces, localized native RichTextLabel content, AnimatedSprite2D animation/frame, and changing constellation graphs with native antialias resources. The fixture samples 79 native scenes/variants: every catalog definition, all six dice faces, and 21 visual modes for each wisp kind. These are native scene-pose comparisons, not 79 independent gameplay-trigger or network tests. Five catalog rows retain unresolved UI/shop ownership. The legacy `upgrade_big` scene is sampled with native level 2 and its own tween advanced to 40/80 ms; its invalid bare default level is not treated as a gameplay trigger.

On a player's own table, teammate aiming uses the installed native prediction line, collision marker, charge gauge and outgoing cue/struck-ball directions over the retained replica bodies. The custom presence arrow is removed; cursors and player names remain. Only the current turn owner's presence with matching match, table, turn and committed round can drive this presentation. A held aim refreshes every 500 ms, with a 1.5-second expiry and sequence rejection after expiry. Missing legacy context preserves cursor compatibility but cannot produce a prediction. Spectator aiming remains a separate gap because the scriptless watched board does not own the native physics context.

## Ownership and lifecycle

[table_effects_sync.gd](../mod/table_effects_sync.gd) captures and validates the six native droplet kinds, dedicated energy bodies and pocket child state. It sends identities and values, never wire-supplied resource paths or gameplay instructions. Host randomness that selects a droplet's flip, direction, color or pose is transmitted rather than rerolled on another peer.

[table_visual_fx.gd](../mod/table_visual_fx.gd) observes allowlisted native scene additions. It keeps weak references and briefly retains the last descriptor after a transient leaves the tree. The shared catalog is cached at initialization and released after its final capture owner exits. Native effect layouts exceeding the part limit report overflow rather than silently omitting later parts. The installed catalog consists of the 32 EffectManager definitions and ordinary/pocket wisps; capture does not call their effects or termination callbacks.

[table_effects_view.gd](../mod/table_effects_view.gd) and [table_visual_fx_view.gd](../mod/table_visual_fx_view.gd) build visual templates through [spectator_scene.gd](../mod/spectator_scene.gd). Native scripts, collision objects/shapes, audio, timers and gameplay callbacks are not instantiated. Sprite, line, label, shader and particle drawing remain available. Node identities are retained and properties change only when their descriptors change. Each renderer keeps one latest bounded state for deferred creation, rather than accumulating historical snapshots. Exported texture arrays are copied before local ownership; teardown cannot clear the native PackedScene's texture catalog.

[replica_game.gd](../mod/replica_game.gd) and [table_spectator.gd](../mod/table_spectator.gd) use the same effect renderers. Scene/round changes clear old presentation; disconnect/rematch and watcher switch clear the associated state and nodes. WORMHOLE suction/tint resets with the renderer's epoch. Spectators apply each selected buffered effect descriptor once while continuing the existing ball interpolation.

[main.gd](../mod/main.gd) includes effect identity/kind and overflow/recovery changes in reliable snapshot topology. A targeted resync does not advance the broadcast topology cache. Existing snapshot IDs and scene/round/phase checks protect against older motion restoring removed effects. Settled tables keep the normal 100 ms snapshot cadence while effects are active or their removal is pending, so short-lived visuals do not depend on the one-second idle heartbeat. This adds full-state traffic while effects animate; its actual cost remains unmeasured.

Incomplete native racks hold both broadcast and targeted baselines until every body is initialized; the two-second warning never permits a partial rack. Failed captures leave the reliable phase transition pending for retry and do not publish a standalone shop transition ahead of it. Guests validate a bundled table and shop before either applies, and expose input only after table/results hydration commits a round matching the reliable authority state. Host shots and passes share setup/spawn barriers. This can increase waiting time when initialization is slow; it avoids spending an action against an old rack or opening a new shop over the prior board. No historical snapshot queue or fixed presentation delay is added.

## Bounds and recovery

| Boundary | Implemented limit / behavior |
| --- | --- |
| Durable descriptors | 128 droplets, 32 active/retiring energy bodies, 16 pockets; 96 KiB encoded effect state. Candidate scans are separately bounded at 256 droplets, 64 energy candidates and 32 pockets. |
| Energy history | Weak references never extend native lifetime. Only overflow recovery scans the native Balls container, capped at 256 direct children; ordinary capture uses the retained registry. |
| Optional projectile lines | Four lines per projectile, 32 points per line, and 256 visited prefab nodes when establishing line references. Points use host world coordinates. |
| Transient descriptors | 96 tracked effects, 96 parts per definition, 64 points per line/constellation, and 96 KiB encoded state. Capture checks a 192-entry / 4 ms budget between complete effects. |
| Transient expiry | Last captured pose retained for 250 ms after native exit; no historical gameplay or audio is replayed. An overflowed still-live effect keeps the substate in explicit overflow rather than falsely declaring full coverage. |
| Combined table payload | A 192 KiB target reserves space beneath the 256 KiB transport envelope limit. Transient presentation becomes overflow first, then native drawing, durable presentation, optional ball art, then optional pocket art if necessary; normal ball/turn/pocket scoring state remains available. Existing excessive base-ball state remains an independent limit. |
| Native drawing | 192 descriptors, including at most 64 retained scores; 128-ball scan, 64 points per line, 32 KiB encoded state, 4 ms soft capture allowance. Renderer checks eight creations / 2 ms between operations. |
| Ball presentation | Two immutable native layouts, at most 512 indexed differences per ball; native particle limits and strict scalar/vector/color types. Aggregate pressure sets explicit `ball_visual_status=overflow` and omits optional art while retaining every authoritative body/item. |
| Pocket presentation | Eight fixed native visual nodes per pocket with strict fields. Aggregate pressure sets explicit `pocket_visual_status=overflow` and omits optional art while retaining authoritative pocket identity and scoring. |
| Deferred visual creation | Durable renderer: eight creations / 4 ms per apply. Transient renderer: twelve creations / 4 ms per apply. Only the latest bounded descriptor is retained and drained on subsequent frames. |
| Overflow | An explicit status/reason pauses replacement of that effect substate and retains its last complete view within the current epoch. Main logs capacity and recovery transitions. New epochs clear old presentation even when the first substate overflows. A later complete state restores current coverage. |

Elapsed budgets are checked between complete operations. One scene duplication, descriptor encoding/validation, or a bulk lifecycle teardown may exceed the nominal time limit. These limits do not establish a hard four-millisecond frame guarantee. The synthetic burst below exceeded the soft apply budget. Individual operation cost, matched workload comparisons and repeated-lifecycle resource growth remain PERF-004/019 acceptance work.

Native active-ball caps do not bound retained potted bodies. The existing 128-body table snapshot cap remains an independent PERF-008 follow-up. The 128-droplet replication cap is also explicit coverage capacity, not a newly imposed native gameplay cap.

## Verification and remaining acceptance

Windows Capture-Screens run `20260927T094004Z-238aa6bf` passed on mod 0.9.4 / native 0.15.7: 1,312 harness checks, 85 snapshot assertions, 85 table-effect assertions and eleven other model probes, with 66 screenshots. The single bounded process exited with code 0 and no script errors; the process stopped and normal saves/installed files were unchanged. Its coverage includes:

- [table_effects_probe.gd](../tests/table_effects_probe.gd) covers descriptor validation, finite/type/count/byte limits, topology and overflow/recovery contracts, including energy retirement and capture initialization.
- [native_table_effects_fixture.gd](../tests/native_table_effects_fixture.gd) uses real native spawn/collision/lifecycle methods for all six floor types, energy retirement and WORMHOLE suction. It compares guest/spectator visuals against the host, checks script/physics absence, retained identity, malformed-update rejection, removal/resync, watcher cleanup and native texture-resource preservation.
- [native_visual_fx_fixture.gd](../tests/native_visual_fx_fixture.gd) captures native boom, tornado, zap line, constellation and both wisp scenes, then checks scriptless guest/spectator hydration, typed presentation state, identity reuse, same-ID kind replacement with correct prefab parts, removal/resync and cleanup.
- Controller and pocket fixtures cover reliable topology, targeted resync isolation, delayed/reordered state and existing BLACK-HOLE identity behavior. Single-process replay does not establish behavior over live transport.

Keep GAP-007 open until the relevant remaining acceptance is recorded:

1. Resolve the observed soft-budget overshoot and investigate resource ownership across repeated lifecycle transitions. The expanded fixtures exposed retained off-tree drawing templates and catalog oracle resources; explicit teardown was added. Final run diagnostics are recorded below. A single clean preservation audit does not establish stable resource counts across long sessions.
2. Exercise each remaining catalog family and gameplay trigger that is not included in the current native fixture. Add a separate contract for an uncatalogued or dynamically generated visual when encountered.
3. Verify late joining, simultaneous bursts, reordered/lost updates, disconnect/rematch and overflow/recovery with a remote table leader and multiple live guests. Record topology, versions and latency conditions.
4. Run the expanded shared fixtures on Windows and in mixed-platform sessions; macOS native replay evidence is recorded below.
5. Extend the bounded fixture measurements below to matched before/after workloads, input feedback and confirmation, live bytes/rates, queue growth and repeated native/resource counts before claiming an FPS or latency improvement.

Particle emitters use native art/materials and host visibility/emission controls where captured. Their individual random particles and elapsed simulation phase are not deterministic replicas. General native audio, camera/postprocessing effects, and arbitrary native runtime children remain outside the current visual descriptor contract.

## Evidence

| Date / revision | Check and result | Limit |
| --- | --- | --- |
| 2026-09-27 / v0.9.2 (`6bd2b14`) | Static mod/native audit: ball/pocket capture and application existed; all six droplets, WORMHOLE child state and energy projectiles were absent at that revision. Basic guest FX was selective. | Historical baseline; no complete native-effect parity or performance claim. Runtime hotfix verification is recorded separately in PERFORMANCE.md. |
| 2026-09-27 / `96aee53`, Windows capture `20260927T081352Z-547cd002` | Actual native BLACK-HOLE spawn/capture, aliased identity, collapsed birth/growth, guest visuals with gameplay disabled, retained node, removal and resync passed. Corresponding host/guest screenshots were reviewed; the whole harness passed with preserved saves/files. | Direct spawn and one-process replay, not a physical pot or live transport. This run did not implement or verify the later floor, WORMHOLE, projectile or general-effect additions. |
| 2026-09-27 / v0.9.4, Windows capture `20260927T094004Z-238aa6bf` | **1,312 checks passed; zero failures**, 85 snapshot assertions, 85 table-effect assertions, eleven other model probes and 66 screenshots. Native physical BLACK-HOLE pot, all six floor types, energy retirement, WORMHOLE, representative transient effects, guest/spectator parity, retained identity, texture ownership, rejection/resync and cleanup passed. Exit 0, no script errors, process stopped, normal saves and installed files unchanged. Same-ID kind replacement passed on guests and spectators while unaffected nodes retained their identities. Five earlier off-tree fixture lookups are fixed. | One-process native replay and the bounded measurements below do not establish live remote-led transport, macOS/crossplay or a before/after performance improvement. Soft apply-budget overshoot and shutdown resource diagnostics remain open. |

## Measured fixture costs

These measurements come from the same Windows run, using the compatibility renderer and the harness's 30 FPS cap. They are workload observations, not a matched before/after benchmark or a hard frame guarantee.

| Workload / measurement | Samples | Result |
| --- | --- | --- |
| Actual native six droplets, one energy body and six pockets: durable capture plus validation | 16 captures | p50 1.287 ms; p95/p99/max 1.431 ms. |
| Synthetic accepted 128-droplet state | 84,968 encoded bytes; drained over 15 frames | Frame intervals p50 33.302 ms; p95/p99/max 33.577 ms at the 30 FPS cap. |
| Durable renderer apply during that synthetic burst | 15 per-frame apply samples | p50 4.625 ms; p95/p99/max 5.062 ms. Both exceed the soft 4 ms target; work is checked between whole operations. |
| Full table snapshot application | Three applications | p50 6.991 ms; p95/p99/max 13.235 ms. This includes work outside the durable renderer's individual budget. |

The synthetic burst verifies bounded draining and replacement of pending state without resurrecting removed effects. It does not represent 128 naturally spawned droplets or a live network burst. No input-to-feedback/confirmation latency, live packet-rate distribution, GPU timing, or mixed-platform measurements were collected in this run.

## macOS PR #53 follow-up

Capture `20261005T134751Z-32cbb0fa` on native 0.15.7 / protocol 10 passed **19,146/19,146 harness checks** and produced **108 screenshots**. It used one muted isolated process, compatibility rendering, 1280×720, a 30 FPS cap and a 300-second watchdog, and exited normally after 143 seconds. No script errors were reported; installed files and normal saves were unchanged, and the private runtime was removed. The tested gameplay, fixture and runner files match the follow-up source. Native drawing, ball art, pocket overflow/recovery, catalog poses and ability/Bounty galleries were reviewed.

The fixture covers 79 native catalog samples at two poses, CANDLE stages, real REAPER geometry, score/money text and Control layout, retained ball/item/material state, independent pocket-art overflow, strict optional fields, reliable recovery, elapsed-time HUD, native cue receipts, and competitive Bounty finalization including lobby-only updates. Existing controller, input, shop/snack/mixer, round-flow and full-catalog/localized lobby checks also pass. This is one-process native replay, not live transport or every gameplay-trigger combination.

The pre-follow-up comparison used `138c9b3` with only the nested Overlay class renamed to avoid the native global-class collision. It failed three aggregate-budget assertions and five lobby clipping assertions. Both runs use the same named cost fixture and rendering settings; the expanded run carries additional presentation state and more fixture work. The short background samples below are observations, not a controlled foreground FPS or latency result.

| Measurement | Earlier PR fixture | Final fixture |
| --- | --- | --- |
| Six native droplets, one energy body, six pockets: capture + validation, 16 samples | p50 1.426 ms; p95/p99/max 2.133 ms | p50 2.863 ms; p95/p99/max 3.481 ms |
| Synthetic 128-droplet payload | 84,968 B | 84,968 B (ordinary pocket art is outside this durable substate) |
| Burst frame interval | n=17; p50 33.324 ms; p95/p99/max 33.479 ms | n=15; p50 33.327 ms; p95/p99/max 34.287 ms |
| Durable renderer tick | n=17; p50 4.625 ms; p95/p99/max 5.050 ms | n=15; p50 3.747 ms; p95/p99/max 4.067 ms |
| Full snapshot apply | n=3; p50 3.973 ms; p95/p99/max 17.330 ms | n=3; p50 5.202 ms; p95/p99/max 15.410 ms |

The final renderer still exceeds its soft 4 ms allowance, and full snapshot application includes larger indivisible work. There is no measured input-to-feedback/confirmation latency, live packet-rate or queue-growth distribution, GPU timing or mixed-platform evidence. Performance changes remain **implemented, unmeasured** against those acceptance criteria.

Expanded testing exposed retained off-tree drawing templates and catalog oracle resources; explicit disposal releases them. Final shutdown diagnostics returned to the earlier fixture counts: 63 CanvasItems, nine materials, one shader, six textures and 22 resources, with existing RenderingServer/ObjectDB shutdown errors. They remain unresolved; matching counts in these runs do not prove long-session resource stability.

### Native aiming and coherent phase follow-up

Capture `20261006T005011Z-8eed0e6f` passed **19,344/19,344 checks** with **112 screenshots** on the same native version, renderer, resolution and frame cap. The one muted isolated process exited with code 0; no script errors, changed saves or changed installed files were reported, and the private runtime was removed. Host and guest glancing-hit captures were reviewed. The tested gameplay, fixture and runner sources match this follow-up.

Direct-hit, glancing-hit and empty-rail cases compare actual local mouse input with teammate replay through the native predictor: all four lines, outgoing shader lengths, collision/bounce markers and charge gauge match. Repeated replay retains native nodes/materials and cannot submit a shot or alter score, health, economy or registered body physics. Menu, stale-presence, turn handoff and below-threshold cleanup also pass. The production presence probe passes 44 checks, controller probe 232 and snapshot probe 117, including malformed/stale context, sequence rejection after expiry, held-aim refresh, incomplete-rack timeout/retry, targeted recovery, shop phase ordering, delayed pass rejection and readiness during table/results hydration.

The first attempt on the identical frozen source, `20261006T004458Z-6bc445c0`, stopped progressing after 12,405 logged checks and reached the 300-second watchdog. It reported no script errors and preserved files/saves during cleanup. The log ended inside a buffered output block, so it does not establish the exact stall location or cause. The successful repeat does not resolve this intermittent runtime/harness stall; it remains acceptance work alongside live transport and platform checks.

The passing run's existing cost fixture recorded capture/validation p50 **4.293 ms**, p95/p99/max **4.954 ms** (16 samples); durable renderer tick p50 **3.542 ms**, p95/p99/max **4.851 ms** (16); full apply p50 **7.221 ms**, p95/p99/max **13.660 ms** (3); and capped frame intervals p50 **33.277 ms**, p95/p99/max **34.435 ms** (16). The synthetic payload remains 84,968 bytes. These short background observations still exceed soft budgets and do not establish an improvement or live aiming latency. Shutdown diagnostics retain 63 CanvasItems, nine materials, one shader, six textures and 17 resources; resource ownership remains open.

# Client table-effect coverage

Native floor effects, energy projectiles, WORMHOLE pocket state, and catalogued transient visuals now have shared guest and spectator renderers. **Status: implemented; Windows native fixtures passed.** This document records the implementation and remaining acceptance for [issue #48](https://github.com/harsh2204/ultrapool-together/issues/48), **GAP-007** in [PERFORMANCE.md](PERFORMANCE.md). The measurements below cover bounded fixtures, not complete audiovisual parity or live-session performance.

The supported native source is Ultrapool 0.15.7. Assets are read from the installed game; no native source or art is redistributed. Historical evidence below describes the exact revision tested, rather than verification of later additions.

The optional `effects` and `visual_fx` fields preserve protocol 8 acceptance of legacy peers. Older leaders cannot provide the new descriptors, and older clients ignore them. Every participant must update to v0.9.4 for the new guest/spectator effect parity.

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

## Ownership and lifecycle

[table_effects_sync.gd](../mod/table_effects_sync.gd) captures and validates the six native droplet kinds, dedicated energy bodies and pocket child state. It sends identities and values, never wire-supplied resource paths or gameplay instructions. Host randomness that selects a droplet's flip, direction, color or pose is transmitted rather than rerolled on another peer.

[table_visual_fx.gd](../mod/table_visual_fx.gd) observes allowlisted native scene additions. It keeps weak references and briefly retains the last descriptor after a transient leaves the tree. The shared catalog is cached at initialization and released after its final capture owner exits. Native effect layouts exceeding the part limit report overflow rather than silently omitting later parts. The installed catalog consists of the 32 EffectManager definitions and ordinary/pocket wisps; capture does not call their effects or termination callbacks.

[table_effects_view.gd](../mod/table_effects_view.gd) and [table_visual_fx_view.gd](../mod/table_visual_fx_view.gd) build visual templates through [spectator_scene.gd](../mod/spectator_scene.gd). Native scripts, collision objects/shapes, audio, timers and gameplay callbacks are not instantiated. Sprite, line, label, shader and particle drawing remain available. Node identities are retained and properties change only when their descriptors change. Each renderer keeps one latest bounded state for deferred creation, rather than accumulating historical snapshots. Exported texture arrays are copied before local ownership; teardown cannot clear the native PackedScene's texture catalog.

[replica_game.gd](../mod/replica_game.gd) and [table_spectator.gd](../mod/table_spectator.gd) use the same effect renderers. Scene/round changes clear old presentation; disconnect/rematch and watcher switch clear the associated state and nodes. WORMHOLE suction/tint resets with the renderer's epoch. Spectators apply each selected buffered effect descriptor once while continuing the existing ball interpolation.

[main.gd](../mod/main.gd) includes effect identity/kind and overflow/recovery changes in reliable snapshot topology. A targeted resync does not advance the broadcast topology cache. Existing snapshot IDs and scene/round/phase checks protect against older motion restoring removed effects. Settled tables keep the normal 100 ms snapshot cadence while effects are active or their removal is pending, so short-lived visuals do not depend on the one-second idle heartbeat. This adds full-state traffic while effects animate; its actual cost remains unmeasured.

## Bounds and recovery

| Boundary | Implemented limit / behavior |
| --- | --- |
| Durable descriptors | 128 droplets, 32 active/retiring energy bodies, 16 pockets; 96 KiB encoded effect state. Candidate scans are separately bounded at 256 droplets, 64 energy candidates and 32 pockets. |
| Energy history | Weak references never extend native lifetime. Only overflow recovery scans the native Balls container, capped at 256 direct children; ordinary capture uses the retained registry. |
| Optional projectile lines | Four lines per projectile, 32 points per line, and 256 visited prefab nodes when establishing line references. Points use host world coordinates. |
| Transient descriptors | 96 tracked effects, 96 parts per definition, 64 points per line/constellation, and 96 KiB encoded state. Capture checks a 192-entry / 4 ms budget between complete effects. |
| Transient expiry | Last captured pose retained for 250 ms after native exit; no historical gameplay or audio is replayed. An overflowed still-live effect keeps the substate in explicit overflow rather than falsely declaring full coverage. |
| Combined table payload | A 192 KiB target reserves space beneath the 256 KiB transport envelope limit. Transient presentation becomes overflow first, then durable presentation if necessary; normal ball/turn state remains available. Existing excessive base-ball state remains an independent limit. |
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

1. Resolve the observed soft-budget overshoot and investigate resource ownership across repeated lifecycle transitions. Shutdown diagnostics reported 63 CanvasItems, nine materials, one shader, six textures and 22 resources, compared with 21 resources in the preceding run; this is not evidence of stable resource counts.
2. Exercise each remaining catalog family and gameplay trigger that is not included in the current native fixture. Add a separate contract for an uncatalogued or dynamically generated visual when encountered.
3. Verify late joining, simultaneous bursts, reordered/lost updates, disconnect/rematch and overflow/recovery with a remote table leader and multiple live guests. Record topology, versions and latency conditions.
4. Run the expanded shared fixtures on macOS and in mixed-platform sessions.
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

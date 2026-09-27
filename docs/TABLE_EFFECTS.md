# Client table-effect coverage

**Complete table-effect parity is not implemented.** This is the detailed inventory and acceptance plan for [issue #48](https://github.com/harsh2204/ultrapool-together/issues/48), **GAP-007 (native table-effect parity on main)** in [PERFORMANCE.md](PERFORMANCE.md). The BLACK-HOLE identity fix in v0.9.2 prevents an invalid pocket index from stalling guest updates; it does not add floor effects or a general effect stream.

This inventory comes from static inspection of the mod and supported native Ultrapool 0.15.7 scripts. “Represented” means capture/application code exists; use the evidence log for actual runtime verification. Native source/assets are supplied by the installed game and are not redistributed here.

## Coverage matrix

| Family | Guest | Spectator | Missing work / verification |
| --- | --- | --- | --- |
| BLACK-HOLE / dynamic pockets | Represented: stable identity, position, rotation, root scale, multiplier, extra score, closed/shielded state, held-ball indicator; creation/removal. | Durable pocket properties and hole lifecycle represented. | Verify actual native first spawn, zero-scale growth, ten-hole limit, ordered/reordered delivery, resync and round cleanup. Existing strict six-base/ten-hole validation remains. |
| Flowers | Missing. Native `game.droplets`. | Missing. | Creation, growth/power, size/color, consumption/removal; host-chosen appearance and applicable native cap. |
| Oil | Missing. Native `game.droplets`. | Missing. | Position/appearance, charge/depletion/fade and removal. Resulting ball motion alone cannot display the oil. |
| Floor fire / flame drops | Missing. Native `game.droplets`. | Missing. | Active patch appearance, pickup and round-cleanup removal; keep ignition gameplay on the host. |
| Stoves | Missing. Native `game.droplets`. | Missing. | Patch appearance/lifetime and cleanup; distinguish from floor flame and from burning balls. |
| Thorns | Missing. Native `game.droplets`. | Missing. | Spawn, size/appearance, native consumption/lifetime and cleanup. |
| Launchpads | Missing. Native `game.droplets`. | Missing. | Direction, held/released presentation and lifetime; guests must not launch balls independently. |
| WORMHOLE | Ordinary pocket/resulting ball state only. | Same limitation. | Pocket `Area2D.scale` suction state, WhiteHoleEffect pulse/tint and traveling pocket wisp are absent. Root pocket scale is a different field. |
| ENERGY-BALL projectiles | Missing. Native `game.energy_balls` is separate from `game.balls`. | Missing. | Specialized visual/pose/lifetime descriptors, spawn/destruction, native ten-projectile cap; do not represent these as ordinary inventory balls. |
| Burning ball, star/shield/lock, level and item transformations | Durable ball item fields and setters represented. | Durable item appearance/indicators represented. | Verify visual parity independently. Burning-ball state is **not floor-fire coverage**; a resulting transformed item does not imply the transformation animation arrived. |
| Wisps, tornado, lightning/zap lines, constellation links, explosions and other native effect nodes | No general native event/state replication; durable score/ball/pocket outcomes may arrive. | No general effect stream. | Finish catalog inventory; define presentation events or active descriptors per effect. Native wisp termination can mutate gameplay and must not execute on guests. |
| Basic shot/spawn/pocket/impact visuals and sounds | Selective approximations in `replica_fx.gd`: edge pulses and speed-drop impact inference. | No equivalent general native FX/audio path. | Test deduplication, loss, resync and bursts. Current per-apply limits are four sounds/eight visual pulses and eight spark timers; this is not complete audio/effect parity. |

## Entry points and native evidence

- [table_sync.gd](../mod/table_sync.gd): `capture` enumerates native balls plus cue and pockets. `_capture_pockets` identifies fixed pockets by parent ownership, not position in a shared mutable Array. No droplets/projectiles/general-effect descriptors exist.
- [replica_game.gd](../mod/replica_game.gd): `apply_table`, `_update_pockets`, `_set_item` implement guest state; `_disable_gameplay` demonstrates the existing presentation boundary.
- [table_spectator.gd](../mod/table_spectator.gd): independent ball/pocket rendering; must be extended separately.
- [replica_fx.gd](../mod/replica_fx.gd): bounded transient approximations, not native effect execution.
- [main.gd](../mod/main.gd): `_publish_snapshot` handles ball/pocket topology reliability and targeted resync isolation; `_take_shot` validates the baseline before authoritative mutation.
- Native inspection points: `Game.spawn_flower/spawn_thorn/spawn_oil/spawn_stove/spawn_flame/spawn_launchpad` append to `droplets`; `clear_table` clears them. `spawn_energy_ball` uses a separate collection. `Pocket.increase_suck` changes child suction/visual state. Inspect native initialization, timers, callbacks and cleanup before reusing scenes.

Native active-ball limits do not bound the total retained potted bodies. The existing 128-body snapshot limit remains an independent PERF-008 follow-up; do not silently drop identities or loosen bounds to conceal it. Likewise, not all droplet spawn methods share a common native cap: design explicit replication limits and recovery behavior.

## Work packages and acceptance

All unchecked items remain open. Authoring a fixture is not a passing run.

1. **Inventory and schema**
   - [ ] Complete the native effect catalog audit, including passive/snack/ball triggers and round cleanup; add missing families to the matrix.
   - [ ] Define allowlisted kinds, stable IDs scoped to match/table/scene/round, finite geometry/type-specific values, and compatibility for peers without the fields. Never accept wire-supplied resource paths.
   - [ ] Specify count, encoded-byte, queue/cache and apply-time budgets, plus observable overflow/recovery behavior. Do not hide excess work in an unbounded backlog.
2. **Durable effects**
   - [ ] Implement capture/validate/apply for all six droplet types, WORMHOLE state and energy projectiles; add guest and spectator presentation.
   - [ ] Send reliable creation/removal/topology transitions and recoverable current state for resync/watcher hydration. Disposable motion cannot recreate a removed effect after a newer phase.
   - [ ] Retain nodes and update changed properties. Stage/cache assets at lifecycle boundaries. Clear state on round/scene change, disconnect, watcher switch and rematch.
3. **Transient effects and authority**
   - [ ] Define bounded event IDs, deduplication, expiry and late-sync behavior for each required transient effect/audio family.
   - [ ] Disable guest/spectator collisions, scoring, upgrades, ignition, launching, spawns and native wisp completion callbacks. Synchronize host-chosen randomness.
   - [ ] Hydrate active visuals without replaying historical gameplay or a burst of old audio.
4. **Behavioral fixtures**
   - [ ] Cover every floor type, flower growth, oil depletion, launchpad hold/release, flame pickup, stove persistence and cleanup.
   - [ ] Cover BLACK-HOLE, WORMHOLE and energy spawn/destruction, simultaneous effect bursts and removal between snapshots.
   - [ ] Cover malformed IDs/kinds/values, initial and late hydration, duplicate/reordered/lost motion around reliable lifecycle changes, targeted resync and no guest gameplay mutations.
   - [ ] Cover round/disconnect/rematch and spectator-switch cleanup, with bounded object/queue counts.
5. **Verification**
   - [ ] Run and review authorized Windows **and** macOS Capture-Screens fixtures for newly implemented families.
   - [ ] Run representative live sessions with a remote table leader and multiple guests; record the topology, versions, latency/loss conditions and remaining limitations.
   - [ ] Record matched frame/apply cost, input feedback, bytes/rates, queue growth and lifecycle/native-call counts before claiming a performance improvement.

First independent implementation step: define and test the descriptor/validation/lifecycle contract for one floor family (oil), then extend the shared path to the remaining families. Keep this issue open until the entire matrix's acceptance is met; do not close it merely because BLACK-HOLE synchronizes.

## Evidence

| Date / revision | Check and result | Limit |
| --- | --- | --- |
| 2026-09-27 / v0.9.2 (`6bd2b14`) | Static mod/native audit: ball/pocket capture and application exist; all six droplets, WORMHOLE child state and energy projectiles are absent. Basic guest FX is selective. | No complete native-effect parity or performance claim. Runtime hotfix verification is recorded separately in PERFORMANCE.md. |

| 2026-09-27 / `96aee53`, Windows capture `20260927T081352Z-547cd002` | Actual native BLACK-HOLE spawn/capture, aliased identity, collapsed birth/growth, guest visuals with gameplay disabled, retained node, removal and resync passed. Corresponding host/guest screenshots reviewed; whole harness passed with preserved saves/files. | Direct spawn and one-process replay, not a physical pot or live transport. No missing floor, WORMHOLE, projectile or general-effect family was implemented or verified by these checks. GAP-007 remains open. |

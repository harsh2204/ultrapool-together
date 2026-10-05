# Effect replication and scoring performance tracker

Audit date: **2026-10-05**. Repository baseline: **`60a2a72`**, mod **0.10.0 / protocol 10**, native **0.15.7**. This is a static audit of host capture, transport, guest rendering, spectator rendering, native presentation resources, and existing fixtures. It does not establish live-session performance or complete visual parity. No gameplay code changes or new runtime measurements accompany this tracker.

Native scope: read-only, in-memory inspection of the installed pack directory (**3,860 entries, 436 compiled scripts, 220 scenes**), a presentation-symbol scan of all 436 scripts, and targeted inspection of gameplay/ball/table/effect implementations and scenes. Pack SHA-256: `9a1e875944a526b24efef205978bdc6ebe849a4c96a3908074834e344c503844`. Native paths below identify symbols/resources for local inspection; native source/assets are not included. This inventories identified presentation families, not every possible combination of ball/passive triggers.

Related: [implementation and historical fixture evidence](TABLE_EFFECTS.md), [performance backlog](PERFORMANCE.md), **GAP-007 / issue #48**. The table leader owns gameplay; the room host can be a different peer and relay its messages. “Host” below means the authoritative table leader unless stated otherwise.

## Current assessment

Scoring/effect bursts have several concrete amplification paths: sampled effect births/removals make whole table snapshots reliable; active effects keep full snapshots running every 100 ms; guests validate accepted newer snapshots twice; and a score-only ball change can recreate its native item presentation. These are strong investigation candidates for scoring-time stalls with otherwise smooth play and shopping. They are not measured causes, and increasing the snapshot rate would add work to these paths.

The current effect implementation covers substantial native presentation, but its 34-entry scene catalog is not an inventory of everything the game can draw. Script-generated drawing, non-catalog scenes, ball-local animations, audiovisual events, and spectator-specific gaps require separate contracts. A synchronized score or status flag proves the result arrived, not that its animation appeared correctly.

## Status rules

| Mark | Implementation meaning |
| --- | --- |
| **I** | Explicit capture and a matching presentation path exist for the stated fields. Does not imply complete native animation or runtime verification. |
| **G** | Generic catalog capture/rendering exists. Actual gameplay trigger and complete native appearance remain unverified unless separately noted. |
| **P** | Partial: final state, some fields, or an approximation exists; a named part is missing. |
| **M** | No matching host-to-view presentation path found. |
| **?** | Needs a native trigger/field audit before implementation can be classified. |

Guest and spectator statuses are separate. **W** in evidence means the historical Windows 0.9.4 fixture recorded in [TABLE_EFFECTS.md](TABLE_EFFECTS.md), not a new run or a live session. **S** means source inspection only. Keep a row open until its stated visual behavior, lifecycle, and relevant platform/live delivery checks pass. Record the implementing revision and verification evidence independently when updating a row.

## Scoring-stall investigation order

All rows below remain **open; causal ranking unmeasured**. Existing mitigations are implemented, unmeasured.

| Order / existing IDs | Source-confirmed work | Next change or diagnostic | Acceptance |
| --- | --- | --- | --- |
| 1 — PERF-008/011 | `table_visual_fx.topology()` includes every effect ID/kind. `main._publish_snapshot()` promotes the **whole table** to reliable delivery on sampled effect creation/removal, kind change or overflow/recovery. Effects keep 100 ms snapshots after balls settle. | Measure bytes/rate/queue age during a scoring chain; design compact, bounded reliable lifecycle events separately from replaceable pose updates and full resync keyframes. | No lost effect births/removals or phase barriers; reliable scoring traffic and command age measured before/after. Do not simply make lifecycle updates unreliable. |
| 2 — PERF-002/004/014 | `main._received_table()` validates, then `table_sync.apply_snapshot()` validates again. Accepted newer snapshots apply synchronously; effect byte checks serialize descriptors again. | Keep one validated network boundary and a separate internal apply path; add a bounded latest-state slot for replaceable samples within the same scene/phase/action barriers. | Malformed inputs rejected before mutation; commands/results/transitions preserved; stale intermediate samples do not repeatedly reconcile within one frame. |
| 3 — PERF-019/004 | Durable and transient renderers each get their own soft 4 ms allowance per apply. Pending creation also drains in `replica_game._process()`. Cloning one tree/material and freeing old trees can overrun those allowances. | Measure clone, material, update, copy and teardown costs; share a presentation allowance across a frame and retain only the latest required state. Consider bounded pools only after ownership is established. | Worst single operation and total per-frame work reported; no resurrection from pending work; no growing resources across rounds/resyncs/watch switches. |
| 4 — PERF-018/019/022/024 | Any item dictionary change in `replica_game.apply_table()` calls `_set_item()`, including base/temporary score changes. It allocates `BallItem`, calls native `set_item`, duplicates a flash material and reruns status setters. Native `Ball.set_item → set_data` also duplicates the item and ball shader material and refreshes score/weight/prediction. Native `upgrade` changes temporary score, connecting real buff triggers to this path. Spectator `_apply_item()` also duplicates its ball material when only the score changes. | Separate identity/art changes from score, level and status updates after checking native setter dependencies. | Score-only cascades retain ball/material identity, produce correct labels and animations, and leave unchanged statuses untouched. Initial hydration and transformations still work. |
| 5 — PERF-005/006/007 | Room routing deep-copies payloads; watcher caching validates/copies snapshots even without watchers; transport serializes separately per recipient. | Establish immutable accepted-payload ownership and remove redundant work at trusted boundaries. | Correct immediate spectator hydration and recipient isolation; compare direct and remote-led tables at 2/4/8 peers. |
| 6 — PERF-013/040 | Generic scenes still draw particles/shaders; ball-native frame processing continues. Driver/GPU cost and first-use shader upload are hypotheses, not diagnosed faults. | Add bounded opt-in stage histograms and call/resource counts through the existing capture harness; measure CPU/render/GPU and live transport separately. | Matched fixture, item count, renderer/cap, topology and latency; frame p50/p95/p99/max, feedback/confirmation latency, packet bytes/rates and queue growth. |

Sources: [main](../mod/main.gd), [transport](../mod/transport.gd), [table sync](../mod/table_sync.gd), [guest application](../mod/replica_game.gd), [transient capture](../mod/table_visual_fx.gd), [transient view](../mod/table_visual_fx_view.gd), [durable view](../mod/table_effects_view.gd), [spectator](../mod/table_spectator.gd).

The effect system was introduced in `7ba1048`. Its four effect-specific capture/view files remain unchanged since that implementation in the audited baseline. The ordinary guest score HUD already updates only when its inputs change (`replica_game._update_hud`); unchanged score-text writes are not the leading suspect. Cue and optional-ball bonuses can trigger additional native score feedback, but their contribution has not been measured.

Historical context only: the prior Windows fixture recorded durable renderer apply p50 **4.625 ms**, max **5.062 ms**, and three full snapshot applications with max **13.235 ms** at a 30 FPS cap. The soft budget was already exceeded. Those samples do not measure the current reported session or demonstrate a regression/improvement.

## Durable board and ball state

Sources: [table_sync](../mod/table_sync.gd), [table_effects_sync](../mod/table_effects_sync.gd), [table_effects_view](../mod/table_effects_view.gd), [replica_game](../mod/replica_game.gd), [table_spectator](../mod/table_spectator.gd). These families must remain synchronized even if disposable animation is reduced under load.

| ID | Effect / host state to represent | Guest / spectator | Evidence; remaining work |
| --- | --- | --- | --- |
| BOARD-01 | Ball birth, respawn, disappearance, death, falling/pocketing and potted-rail lifecycle; stable IDs and visibility | I / I | S + existing snapshot fixtures. Test every real spawn/consume/resurrect trigger and reordered removal. The 128-body cap includes retained potted bodies; native active-ball limits do not prove capacity. |
| BOARD-02 | Motion, force, spin, mass, damping, radius, visual scale and tint | I / P | Explicit guest fields and spectator interpolation. Spectator weight/radius appearance needs comparison; custom trails are separate. |
| BOARD-03 | Native/mixed ball identity and transformation result | I / I | Resulting artwork is represented. Each transformation flash, mixed-material transition and simultaneous identity change needs trigger coverage. |
| BOARD-04 | Base score and temporary bonus / numeric ball value | I / I | Native `BallItem.get_score` is exactly `base_score + temp_extra_score`, matching spectator arithmetic. Native visible formatting/chrome and level effects are separate acceptance; test mixed and buffed balls against host. |
| BOARD-05 | Weight changes | I / P | Guest `update_weight`; mass/scale state exists. Spectator interpolates visual scale but does not explicitly apply `weight_state`; compare native appearance before declaring the whole visual missing. Test gain, loss and transformed-ball reset. |
| BOARD-06 | Flaming/burning ball | I / P | Guest native `set_flame`; spectator fire indicator. Full flame animation, ignition event and sound are separate. |
| BOARD-07 | Object-ball star power | P / P | Flag/indicator exists; guest `hide_default_table_fx` hides `StarEffect`. Compare native persistent star visuals and intentional pulses. Cue-ball star chrome is intentionally suppressed. |
| BOARD-08 | Shield grant, shielded state, shield break and removal | I / P | Guest native setters, spectator indicators. Impact/break animation and audio need a separate event check. |
| BOARD-09 | Locked/frozen state and release | I / I | Freeze indicator and authoritative result represented. Test acquisition/release mid-shot and resync. |
| BOARD-10 | Fleeting appearance and expiry | P / M | Guest only calls `set_fleeting` on true; explicit true→false visual cleanup is absent. Spectator does not render the flag. Test reuse/transform/reset as well as expiry. |
| BOARD-11 | Fixed pocket position, multiplier, extra score, closed/shielded state and held-ball indicator | I / P | Guest labels/setters; spectator state with simplified closed appearance. Native open/close/shield animation timing is not proven. |
| BOARD-12 | BLACK-HOLE / dynamic pocket birth, growth, pose, labels, removal and identity | I / I | W: actual physical native pot, aliased fixed/dynamic identity, retained nodes, removal/resync. Live delivery and expanded macOS checks remain. |
| BOARD-13 | WORMHOLE pocket suction scale and WhiteHoleEffect tint | I / I | W: native suction and child state. Traveling pocket wisps are a separate catalog row; verify their timing together. |
| BOARD-14 | Flowers: host colors, power text, growth, spin, pose and consumption | I / I | W: native improvement/consumption and retained lifecycle. Live bursts, late join and capacity remain. |
| BOARD-15 | Oil: chosen texture/flip, rotation, tint/charge opacity and consumption | I / I | W: native collision/charge and appearance. Live removal timing remains. |
| BOARD-16 | Flame pickups / floor fire: material, pose and pickup removal | I / I | W: native pickup lifecycle. Do not equate floor fire with BOARD-06 burning-ball state. |
| BOARD-17 | Stoves: persistent patch, pulse tint, ignition and removal | I / I | W: native persistence/ignition outcome. Ignition audiovisual event remains separate. |
| BOARD-18 | Thorns: pose and consumption/removal | I / I | W: native consumption. Live simultaneous collisions/removal remain. |
| BOARD-19 | Launchpads: direction, shadow/sprite rotation, held ball, timer and release | I / I | W: native hold/release. Ordinary ball stream carries motion; replicas must never launch a second time. Compare release timing live. |
| BOARD-20 | ENERGY-BALL active and retiring projectile bodies | I / I | W: pose, scale, sphere visibility and retirement tail. Native 0.15.7 uses EnergyCircle Sprite2D, not a particle/line trail. Optional line support is not evidence of native trail parity. |
| BOARD-21 | High-value ball score particles and outline | P / M | Native `update_score_label` enables particles at score ≥10 and outline at ≥20 with score-dependent amount/radius/color. Guest item setup calls it but then `hide_default_table_fx` hides their `static/score_effects` parent; only a temporary pocket pulse selectively re-shows it. Spectator hides this parent too and only updates the score label. Restore intentional persistent high-value feedback with native comparisons and bounded work. |
| BOARD-22 | Level and upgrade presentation | P / P | Level is transmitted, and guest native item setup runs, but table spark/flash is deliberately hidden; spectator does not apply level-specific presentation. Shop MERGED badges are a separate implemented UI and do not prove table animation parity. |

## Native drawing and scoring outside the catalog

These are the most important omissions to implement before declaring full native table parity. **All remain open.** A native scene child can exist in a copied table and still never receive the host's changed geometry or state.

| ID | Native source / effect | Guest / spectator | Missing contract and next acceptance |
| --- | --- | --- | --- |
| DRAW-01 | **CANDLE ritual pentagram / ritual strength** — `Game.pocket_candle`, `table.increase_pentagram`, `pentagram.gd` | M / M | Capture candle count, ritual strength and current host pentagram line/circle geometry, tint, visibility and completion/fade phase. No corresponding fields exist in table snapshots; spectator `_refresh_cosmetics` explicitly hides Pentagram. Compare each of 0–5 candle stages, completion, fade, late join and round reset. |
| DRAW-02 | **REAPER death tether** — `ball.gd` `last_collided_ball` / `deathline` | M / M | Send source/target identity and/or bounded authoritative endpoints, visibility and color; clear on target loss/pot/transform. Ordinary ball positions do not tell a guest which relationship to draw. Verify contact, changed target, death and resync. |
| DRAW-03 | **Floating score, bonus redisplay and money text** — `Game.score_display_scene`, `score_display.gd`, native `add_score` / `display_money` | M / M | This scene is outside EffectManager's catalog. Add bounded presentation events with ID, kind, host-selected value/style, origin and lifetime; keep actual score/money mutations host-only. Verify ordinary pot, chained upgrade/bonus, negative/large score, coins and duplicate/reordered events. Native HUD totals are already separate. |
| DRAW-04 | **Ball movement trails** — ball-local `Trail`, `trail.gd` | P / M | Guest retains native body processing, so some local motion-derived trail may appear; authoritative trail history is not transmitted. Spectator strips non-visuals children. Choose bounded host points or intentional local trail reconstruction and compare moving, teleported, potted and removed balls. |
| DRAW-05 | **LUNA object-ball prediction** — `Ball.update_prediction_sys`, runtime `prediction_sys` child | P / M | Guest native item setup can create local prediction; its geometry/result is not a host descriptor. Spectator lacks this runtime child/path. Compare host/guest prediction, identity transformation and cleanup; distinct from the player's cue aim. |
| DRAW-06 | **Native ball flash/score/hit animation timeline** — `Ball.flash_alpha`, local visual children | P / M | Guest pulses/setters reconstruct selected feedback; host alpha/animation events are absent and setup resets flash. Use bounded visual events/parameters; retain BOARD-06–10 durable statuses independently. |
| DRAW-07 | **Screen shockwave / bulge** — EffectManager `Overlay/BulgeEffects` | M / M | Catalog scene replay does not capture singleton overlay shader state. Add a typed, bounded screen-effect event/state and local accessibility policy; verify coordinate conversion at different table/view scales. |
| DRAW-08 | **Camera shake / push** — `camera.gd` | M / M | No host event path. Replicate only the agreed presentation cue, not camera ownership or authoritative input transforms. Test both playing and watched tables. |
| DRAW-09 | **Freeze-frame / hit-stop** — native `freeze_frame` | ? / ? | A five-frame tree-pause helper exists, but no active caller was found in the static scan. Establish a real trigger before adding replication. Do not replay the callback blindly on replicas because it can stall receive/input; any required equivalent should be visual-only and bounded. |

The reported “Spirit Strength drawing” may refer to **DRAW-01**, but that name match is unconfirmed. Native **SPIRIT** instead has a probability-based self-launch toward a nearby pocket after another ball is pocketed; its resulting motion uses BOARD-02. Native **CANDLE** accumulates `ritual_strength` and draws the pentagram. Do not conflate either with the optional TAROT Strength ball.

For DRAW-01, build a dedicated scriptless view shared by guest and spectator, driven only by validated host descriptors. **Do not enable the native pentagram script:** its completion callback invokes `Game.do_ritual`, which would rerun gameplay on the client. Start with a real CANDLE trigger fixture through production capture/application and compare line endpoints, tint, strength and completion at each stage. Stable state belongs in late-join hydration; one-shot ritual/audio cues need deduplication and expiry.

## Native transient catalog: every definition

The installed `EffectManager` loads these **32** definitions from `res://effects/scenes`; `table_visual_fx.catalog` adds ordinary/pocket wisps for **34**. Each row is independently trackable. Shared sources: [capture/catalog/validation](../mod/table_visual_fx.gd), [view](../mod/table_visual_fx_view.gd), [scriptless scene reader](../mod/spectator_scene.gd), [representative native fixture](../tests/native_visual_fx_fixture.gd).

**G is a working generic contract, not completed acceptance.** It captures existing sprite frames/transforms/tints, Line2D points, plain Label text, emission flags and typed scalar/vector/color shader parameters. It does not run native scripts, animation callbacks or audio. For every G row, exercise the real gameplay trigger and compare host/guest/spectator through birth, animation and removal; geometry layout checks alone do not establish appearance. Particle randomness and simulation age remain approximate across all particle-based rows.

| ID | Native key | Guest / spectator | Evidence; specific remaining check |
| --- | --- | --- | --- |
| FX-01 | `boom` | G / G | W: representative scene spawn/replay. Native `Game.boom/boom_pos/fireball` triggers, particle age and chain bursts remain. |
| FX-02 | `confetti` | G / G | S: achievement-toast use; establish local/shared ownership, then emission/timing and cleanup. |
| FX-03 | `confetti_secret` | G / G | S: secret achievement-toast variant; establish local/shared ownership. |
| FX-04 | `constellation` | G / G | W: explicit dynamic star/connection path. Native `score_closest_stars` trigger, growing/changing point sets and bounded connections remain. |
| FX-05 | `conveyor` | G / G | S: native `shoot_all_random` trigger and full transform/tint cycle. |
| FX-06 | `deny` | G / G | S: native ball-spawn rejection (`spawn_ball_from_data/from_item`); ordering and no duplicate replay. |
| FX-07 | `dicepop` | **P / P** | **Confirmed gap:** native `dice_pop.gd.set_value` replaces Ring1 texture with one of six dice faces. Current texture allowlist only has wisp art, so host-selected face is not sent. Add validated face index and compare all six. |
| FX-08 | `final_round` | **P / P** | **Confirmed gap:** native scene contains RichTextLabel with `UI_LAST_ROUND`. `spectator_scene._visual_node` falls back to Control; the text disappears. Add safe RichTextLabel/localized-content presentation and check text fit. |
| FX-09 | `hit_sparks` | G / G | S: `Game.gacha`, `Ball.hit`, `PlayerBall.shoot` triggers, emission/tint and burst load. |
| FX-10 | `last_shot` | G / G | S: `shot_pip.set_last_shot` trigger and timing. |
| FX-11 | `nudge` | G / G | S: NPC click feedback; normally local UI. Establish intended ownership before broadcasting it. |
| FX-12 | `place_sticker` | G / G | S: trigger and host-selected presentation. Shop-origin effects are explicitly excluded by `_node_added`; define intended visibility by phase. |
| FX-13 | `pocket_effect` | G / G | S: actual pot. Scene also contains hidden AnimatedSprite2D Impact unsupported by reader; no activation found in static scan. Keep this conditional variant unverified, not a confirmed visible defect. |
| FX-14 | `pocket_shockwave` | G / G | S: `EffectManager.shockwave`, including score-reached use; radius/opacity and simultaneous triggers. Separate from DRAW-07 full-screen bulge. |
| FX-15 | `pop` | G / G | S: tapas-purchase use; ordinary shop feedback remains local/shared-shop presentation, not an on-board parity claim. |
| FX-16 | `rarity_legendary` | G / G | S: trigger and particle/art appearance. |
| FX-17 | `rarity_rare` | G / G | S: trigger and particle/art appearance. |
| FX-18 | `rarity_spark_legendary` | G / G | S: trigger, timing and cleanup. |
| FX-19 | `rarity_spark_mixed` | G / G | S: mixed-ball variant and cleanup. |
| FX-20 | `rarity_spark_rare` | G / G | S: trigger, timing and cleanup. |
| FX-21 | `rarity_spark_uncommon` | G / G | S: trigger, timing and cleanup. |
| FX-22 | `rarity_uncommon` | G / G | S: trigger and particle/art appearance. |
| FX-23 | `score_reached` | G / G | S: `Table.show_score_reached`, ordinary/daily threshold, once-only delivery and correct timing. |
| FX-24 | `tiger` | G / G | S: event-manager round-end/effect triggers, transform/tint animation and complete lifecycle. |
| FX-25 | `tornado` | G / G | W: representative scene. Native event-manager trigger, motion/timing and burst load remain. |
| FX-26 | `transform` | G / G | S: event-manager transform/shop-buy triggers and synchronization with BOARD-03. |
| FX-27 | `upgrade` | G / G | S: `Ball.upgrade/set_passive`, split/transform and pocket multiplier/extra-score triggers; multiple recipients and score feedback. UI uses need separate phase ownership. |
| FX-28 | `upgrade_big` | G / G | S: large-upgrade variant and burst load. |
| FX-29 | `upgrade_lvl1` | G / G | S: level-one variant and ball-local feedback. |
| FX-30 | `upgrade_lvl2` | G / G | S: level-two variant and ball-local feedback. |
| FX-31 | `upgrade_lvl3` | G / G | S: level-three variant and ball-local feedback. |
| FX-32 | `zap_line` | G / G | W: line setup/replay. Event-manager other-ball-pocket trigger, real targets/endpoints and chained hits remain. |
| FX-33 | `wisp` | G / G | W: representative ordinary wisp. Exercise every native visual mode/target/buff combination and termination without client callbacks. |
| FX-34 | `pocket_wisp` | G / G | W: representative pocket wisp. Exercise real WORMHOLE route, target, termination and loss/reordering. |

Wisp texture allowlist: `apple` (`apple_slice`), `cloud`, `compass`, `egg`, `window`, `circle`, `gear`, `wheel`, `upgrade`, `time`, `mushroom`. Other native color/gradient modes require their own visual trigger checks; the beach/roulette color progression is sampled through tint/line color rather than transmitting a Gradient resource. General runtime texture swaps remain unsupported except for the explicit allowlist.

The historical fixture directly spawns only **six of these 34 kinds**: boom, tornado, zap_line, constellation, wisp and pocket_wisp. It also checks all catalog layouts fit the part bound; that is not 34 gameplay-trigger tests. The two known partial definitions and all unexercised triggers must remain open.

Catalog membership alone does not require network broadcasting. Achievement toasts, NPC nudges, sticker placement, tapas purchase and some rarity effects are UI/cosmetic presentation; retain local ownership unless they communicate an authoritative shared event. Host `in_shop` suppresses generic effect capture. Audit indirect resource-based rarity uses separately from literal spawn calls. Unreferenced packed SparkGroup/DoorEffect nodes and the freeze helper are audit candidates, not proven missing active scoring effects.

## HUD, local feedback and audiovisual effects

Sources: [replica_fx](../mod/replica_fx.gd), [ball_level_fx](../mod/ball_level_fx.gd), [round_presentation](../mod/round_presentation.gd), [presence](../mod/presence.gd), [native_player](../mod/native_player.gd), [spectator](../mod/table_spectator.gd). Final values and timed presentation require different acceptance checks.

| ID | Family | Guest / spectator | Remaining work |
| --- | --- | --- | --- |
| HUD-01 | Score/target totals and score diamond | I / P | Guest native value setter is change-gated; spectator draws value/fill. Native diamond animation timeline and per-score pulses are separate from totals. |
| HUD-02 | Money, HP/max HP, shots remaining/spent, round and time | I / P | Spectator shows wallet/health/remaining shots/round, without equivalent elapsed-time or spent/max-pip presentation. Test gain/loss animations, locale and unchanged-state call counts; spectator static UI still updates each render tick (PERF-022). |
| HUD-03 | Round-start doors and aim reminder | I / M | Guest re-enables native door animation. Spectator does not replay this edge. Test first hydration vs new round vs resync. |
| HUD-04 | Payout, reward count-up, victory/defeat and Continue | I / P | Guest native menus have per-round keys and phase barriers. Spectator has summaries/status, not full matching payout presentation. Keep live phase ordering acceptance open. |
| HUD-05 | Shot, spawn, pocket and collision pulses/sounds | P / M | Guest inferred/limited feedback is an approximation with sound/visual budgets, not an authoritative native event stream. No matching spectator event path. |
| HUD-06 | Ball-local flash, score pop, hit/stretch, level upgrade and star animation | P / M | Some guest pulses/setters and catalog effects exist; default table FX are deliberately hidden. Spectator hides local flash/score/spark nodes and has no matching animation replay; catalog scenes are tracked separately. Capture actual native per-ball animation state or define a compact event contract. |
| HUD-07 | Native effect audio, money/score sounds and positional sound selection | P / M | Selective guest sounds exist. General audio events, variations, timing and spectator policy have no protocol. Late join/resync should not replay old sounds. |
| HUD-08 | Camera shake, hit-stop/time scaling, full-screen native postprocessing | M / M | Local CRT/settings support is not host event replication. Audit each native trigger and define which cues are shared versus accessibility/local settings. |
| HUD-09 | Local cue aim/charge/prediction, teammate cursor/aim, cue art | I / M | Native guest input/cue and presence paths exist. Spectator removes CuePivot, hides chargeGauge and does not consume presence. Keep playing-client input locally responsive; do not replace it with generic board-FX snapshots. |

## Optional content: outcome versus visible cause

These features are present in the audited code. Their final score/money/HP/spawn/status outcomes mostly use BOARD/HUD rows above. That does not implement their ability-specific indicators. The exact eight TOGETHER triggers are in [MULTIPLAYER_BALLS.md](MULTIPLAYER_BALLS.md); all 54 expansion definitions are in [EXPANSION_SETS.md](EXPANSION_SETS.md); cue triggers are in [CUSTOM_CUES.md](CUSTOM_CUES.md). Use every listed ball/perk as a trigger checklist, including mixed balls.

| ID | Content / additional presentation | Guest / spectator | Implementation gap / next check |
| --- | --- | --- | --- |
| MOD-01 | Relay owner ring/player name | I / M | TOGETHER overlay draws on the playing table and is hidden while spectating. Add watched-table state/coordinates. |
| MOD-02 | Called Shot chosen ball/pocket rings and caller/pending state | I / M | Guest overlay exists. Test change, expiry and delayed state; add spectator equivalent. |
| MOD-03 | Patience charge pips | I / M | Guest 0–3 pips exist; spectator path absent. Verify award/clear and respawn. |
| MOD-04 | Bounty target and reward cue | P / M | Guest crosshair and authoritative reward bookkeeping exist; award-specific cause/timing and spectator marker absent. |
| MOD-05 | Bankroll, Lifeline, Domino bonus feedback | P / P | Wallet/HP/score result arrives. Dedicated cause/reward feedback is not sent; exercise native popup/score-event gaps. |
| MOD-06 | Encore restored-ball feedback | P / P | Outcome uses ordinary ball lifecycle. Verify actual delayed respawn and presentation, not a manually seeded snapshot. |
| MOD-07 | PHASES moon clock and Silent Charge | M / M | Reliable display state received/stored, with no renderer consuming it. Add clock/charge view. |
| MOD-08 | MORPH form, charge, mark, Prime readiness/change count | M / M | Underlying item/mass results arrive; ability state has no view. |
| MOD-09 | TIDE height | M / M | Launch/bonus results arrive; tide-height state has no view. |
| MOD-10 | RELIC digs, persistence and Idol counters | M / M | Outcome/lock state arrives; ability state has no view. |
| MOD-11 | TAROT Spread, upright/reversed state, Hanged charge | M / M | Outcome arrives; ability state has no view. This mod's Strength ball is separate from the native Spirit-related drawing report. |
| MOD-12 | ZODIAC alignment, Aspect/Grand Trine and Cancer charge | M / M | Outcome arrives; ability state has no view. |
| MOD-13 | Cue Workshop perk award/cause feedback | P / P | Model/finish and resulting scores arrive. Host invokes bounded native `add_score` awards; no dedicated award/cause event reaches views. Exercise each perk's qualifying pot. |

Source evidence: [multiplayer_ball_ui.refresh/draw_overlay](../mod/multiplayer_ball_ui.gd), [expansion_balls.apply_state](../mod/expansion_balls.gd), [cue_effects](../mod/cue_effects.gd). Expansion `_remote` is assigned and cleared but has no presentation consumer. It must not be marked visually implemented merely because it crosses the network.

## Transport, lifecycle and capacity checklist for every family

- [ ] **Authority:** capture the host-selected result/appearance. Guests and spectators never rerun native scoring, randomness, spawning, collision or save callbacks.
- [ ] **Identity and epoch:** stable effect ID/kind plus match/table/scene/round/phase; same-ID replacement safe; no stale resurrection.
- [ ] **Delivery:** compact reliable birth/end or durable revision where required; disposable intermediate pose; initial sync/late join hydrate only current effects. Preserve accepted-shot and phase barriers.
- [ ] **Validation:** native allowlisted kinds/resources, finite typed values, explicit count/point/text/byte limits; reject before any mutation. No wire paths or script callbacks.
- [ ] **Lifetime:** effect end/removal, overflow/recovery, scene change, disconnect, rematch and spectator switch clear the correct state. A targeted resync must not consume a broadcast owed to others.
- [ ] **Rendering:** compare host/guest/spectator at the same sampled stage, including labels, actual custom geometry, shader parameters, layering and host-chosen variants. A node existing is insufficient.
- [ ] **Budgets:** bound bytes, pending descriptors, scene/material creation, updates and teardown; keep newest work only. Report a single operation exceeding the budget as unresolved.
- [ ] **Trigger coverage:** invoke the real native ball/passive/scoring callback, then production capture/transport/application. Spawning a visual directly proves only that visual's replay path.
- [ ] **Delivery conditions:** initial sync, delayed/reordered/lost updates, rejected actions, simultaneous bursts, remote leader, multiple guests, active watcher, reconnect and rematch.
- [ ] **Performance/platform:** matched before/after measurements through the shared capture harness and live topology checks; Windows, macOS and mixed-platform evidence recorded separately.

Current bounds are documented in [TABLE_EFFECTS.md](TABLE_EFFECTS.md): 128 droplets, 32 active/retiring energy bodies, 16 pockets; 96 transient effects, 96 parts/definition, 64 points/line; 96 KiB per effect substate and a 192 KiB combined table target. Overflow retains the last complete view until recovery; it does not mean all current effects were displayed. A 250 ms transient tail improves delivery opportunity but does not reconstruct an animation that was never sampled.

## Completion record

| Date / revision | Work | Verification | Still open |
| --- | --- | --- | --- |
| 2026-10-05 / baseline `60a2a72` | Static coverage and scoring-path audit; separate implementation/visual evidence and guest/spectator gaps. | Source, native-resource inspection, existing fixture review and documentation checks only. | All new gap fixes, actual Spirit/scoring reproduction, matched performance measurements and live/platform acceptance. |

# Validation

Syntax checks do not verify engine types or gameplay. Follow [AGENTS.md](../AGENTS.md) before running any probe, including `--headless`.

For authorized visual tests, run `Capture-Screens.cmd` on Windows or `bash Capture-Screens.command` on macOS from the repository root. The [screenshot harness](../docs/screenshots.md) builds repeatable fixtures, checks native textures and shop actions, and saves an HTML gallery with logs and check results. It uses one muted game process and separate test saves; macOS uses a background-only app with an unfocusable, mouse-passthrough rendering surface.

For authorized same-PC host+guest play over LAN loopback (not Steam), see [LOCAL_SESSION.md](LOCAL_SESSION.md) and run `Test-LocalSession.cmd` from the repository root. It starts two isolated windowed processes and leaves them open for manual testing.

## Checks that do not launch the game

The effect-replication benchmark scores [the tracker](../docs/EFFECT_REPLICATION_TRACKER.md) statically: a weighted coverage ledger per guest/spectator row, PASS/FAIL source gates for the `PERF-*` scoring amplification paths, a cross-check that tracker claims match code evidence, and an estimated `var_to_bytes` wire model for synthetic snapshots:

```sh
python3 tests/effect_benchmark.py            # report and punch list
python3 tests/effect_benchmark.py --check    # exit 1 on regression vs tests/effect_benchmark_baseline.json
python3 tests/effect_benchmark.py --self-test # exercise evidence and regression detection
python3 tests/effect_benchmark.py --write-baseline
```

It reads sources and documentation only. Passing gates are static evidence that a redundant-work pattern is gone; they are not frame-time, rendering or engine-compatibility results.

Installer boundary tests use fake executable fixtures:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\installation.ps1
```

Every installer call in that suite supplies an isolated `UserDataRoot` under `.local/installer-tests`; real user profiles are not accessed. It checks one-time progression import, exact backups of existing mod saves, update preservation, untouched run files, missing/invalid source saves, dry runs, profile junction rejection, and uninstall behavior.

The macOS installer suite also uses fake app bundles and isolated profiles under `.local/installer-tests`:

```sh
python3 -m unittest discover -s tests -p installation_macos.py -v
```

It covers native app layout/version checks, Steam library discovery, configuration placement, executable permissions, one-time imports, save backups, update/uninstall preservation, unsafe paths, symbolic links, tampered manifests, and recovery after a signing failure. Installation fixtures substitute signing calls; a separate macOS-only check signs and verifies an inert copy of a system binary without executing it. These checks do not prove that macOS will launch the installed game or that Steam works across platforms.

Use `gdtoolkit` for GDScript syntax checks.

The macOS capture runner also has isolated lifecycle tests with a mocked child process:

```sh
python3 -m unittest discover -s tests -p capture_macos.py -v
```

These cover private app/profile isolation, exclusion of concurrent captures, watchdog/error cleanup, and original-file preservation without launching the game.

## Standalone model and controller probes

These scripts extend `SceneTree` and require a Godot 4.6 executable with `--script` support. Use an isolated test project with its own user-data directory and no game autoloads. The shipped game executable is a release template and does not support this workflow.

| Probe | Coverage | Success marker |
| --- | --- | --- |
| `team_vote_probe.gd` | Concurrent approvals, context generations, stale-vote rejection, membership changes, and deep-copied vote context. | `TEAM_VOTE_PROBE PASS` |
| `lobby_probe.gd` | Capacity/seats, run-choice allowlists, per-player votes, ties/abstention, frozen selections, stale readiness rejection, concurrent ready votes, host-only table settings, per-player cue cosmetics, start/reset, and disconnects. | `LOBBY_PROBE PASS` |
| `cue_probe.gd` | Cue catalog roster/normalize/apply idempotence, local prefs helpers, and lobby `set_cue` dirty-gating without clearing Ready. | `CUE_PROBE PASS` |
| `ui_nav_probe.gd` | Host-navigation vocabulary/signatures, malformed navigation rejection, CRT fallback placement, default-off personal view following, persisted preferences, deferred/latest navigation, and separation from shared shopping and transactions. | `UI_NAV_PROBE PASS` |
| `expansion_sets_probe.gd` | Expansion-set rules, registry allowlists, and master-toggle gating. | `PASS: ... expansion set rules checks` |
| `multiplayer_balls_probe.gd` | Multiplayer-ball rules, replay protection, per-round resets, display-state validation, and potted-rail classification. | `PASS: ... multiplayer ball rules checks` |
| `presence_probe.gd` | Seat-stable cursor colors and known/unknown shop presence-target resolution while the shop is open or closed. | `PRESENCE_PROBE PASS` |
| `cue_models_probe.gd` | Fifteen cue definitions, finite/direction-safe input mapping, native endpoints, monotonic equal-and-opposite handling curves, and bounded displacement. | `CUE_MODELS_PROBE PASS` |
| `cue_inventory_probe.gd` | Per-player ownership, shared-wallet sequential spending, duplicate/unowned rejection, snapshot validation/isolation, monotonic revisions across reordered confirmations, and new-run reset. | `CUE_INVENTORY_PROBE PASS` |
| `cue_effects_probe.gd` | Conditional cue perks, duplicate callbacks, shared round caps, cue swapping, first-shot/recovery/relay history, initial/mid-shot overflow, actual pocket geometry in both orientations, and malformed input. | `CUE_EFFECTS_PROBE PASS` |
| `transport_budget_probe.gd` | Fake Steam queues exercise bounded dispatch, reliable retention/order, channel fairness across frames, and byte/time limits without network connections. | `TRANSPORT_BUDGET_PROBE PASS` |
| `router_probe.gd` | Authenticated actor identity, requests to the correct table leader, table-isolated broadcasts and replies, reliable actions, disconnected members, and malformed routes. | `ROUTER_PROBE PASS` |
| `controller_probe.gd` | Main controller lifecycle using off-tree service substitutes: identity teardown, room/match generations, terminal leader disconnects and reconnects, a run closing during a shot, targeted shop synchronization preserving the broadcast cache, the guest's bounded latest-snapshot slot and single validation per accepted snapshot, and watcher forwarding that validates only for subscribed tables. | `CONTROLLER_PROBE PASS` |
| `shop_layout_probe.gd` | Guest remote-slot coverage for host-authoritative shop layouts, including stale pre-inventory replicas and extra local unlock slots. | `SHOP_LAYOUT_PROBE PASS` |

Each script exits 0 on success. The controller probe creates no native game scenes or network connections. It also covers Race versus Score PvP caps, authenticated race results, finish ordering, return-vote generations, startup failure handling, spectator routing, and reliable effect lifecycle transitions. The screenshot harness runs these fourteen model probes inside its existing game process, plus the embedded native `snapshot_probe.gd` and `table_effects_probe.gd`. Its model adapter requires a successful completion marker, at least one assertion, and no failed assertions; merely loading a probe cannot count as a pass. The navigation fallback case uses an explicit null context so the real process's CRT overlay does not change the test premise. `clone_round_probe.gd`, `set_vote_probe.gd`, and the standalone adapter/session/transport probes are not part of this model invocation list.

The `ui_nav_probe.gd` persistence cases require the harness's isolated `UltrapoolTogetherRenderTest` profile and restore the original configuration bytes. They intentionally refuse to write into a normal or arbitrary standalone profile; use the registered capture harness for the complete probe.

### Manual progression import coverage

`progress_import_probe.gd` requires the installed game's native `SaveData` resource and runs through the existing screenshot harness's model adapter, in addition to the fourteen model probes above. Its private service seam uses fresh fixture directories, a fake save owner, and fake progression-cache listeners. The public source-info check must reject the isolated test profile before reading saves; the production import action is never called. Neither real save profile is accessed. Its success marker is `PROGRESS_IMPORT_PROBE PASS`.

Authored cases cover copying and repeated imports, preserved source and run files, the current settings dictionary, local daily flags and entitlement, current-memory and original-file backups, fresh resource loading, and progression-cache adoption. They also cover missing/invalid/oversized sources, unsafe paths and links, staging/commit failures, a failed rename that already removed its target, rollback into an initially empty profile, and incomplete rollback.

`progress_settings_fixture.gd` uses the real native main menu and mod controls with a fake importer. It checks direct gear access without opening a room, retained settings layout and button text fit, no source reads merely from opening settings, confirmation/cancellation, missing-source and copy-error feedback, pending-action cancellation when the menu boundary changes, Close restoring native input, and the full lobby opening afterward. It also checks success feedback and menu reconstruction on dismissal. It adds the `mod-settings-steam-progress` capture for layout review.

Both files are registered in `Capture-Screens.py`, `Capture-Screens.ps1`, and the existing `render_probe.gd` flow. **Authored, not run:** no native-resource probe or rendering fixture has been executed for this feature. Use only the authorized existing capture harness; these registrations do not add a separate runtime launcher. Native save adoption, refreshed unlocks, rendered text fit, Windows/macOS behavior, and copy latency remain open under PERF-026 / PERF-038 / GAP-004. See [save copying and recovery](../docs/SAVE_IMPORT.md).

The harness also records and replays native host/client round transitions, including delayed shop acknowledgements, packet reordering, payout, victory, defeat, and teardown. It includes regression assertions for stationary replica sleep, spin reconciliation, shop map identity during wallet/health updates, and rarity indicators on unchanged offers. The [game-loop coverage matrix](GAME_LOOP.md) separates runtime assertions, model checks, and remaining multi-PC coverage. Added assertions are authored coverage until an authorized run passes them.

`render_ui_fixtures.gd` checks lobby card/button ballots through the controller, local selection, live voter identities, abstention, disconnects, frozen choices, and retained card identity and keyboard focus. Full-catalog and eight-player consensus fixtures check layout bounds and exact native shop poster references for all starting sets.

The difficulty regression uses the real `run_setup.available_choices()` path for both normal host unlocks and a full native catalog with only progression eligibility substituted. Every difficulty's label, card, tooltip, accessible name and selected result are checked against native translations or the distinct Together title. English and an installed non-English locale exercise line visibility and voter separation, with exact locale restoration. The fixture also checks registration does not desynchronize the native menu's difficulty array, panels and per-deck indicators, then opens/closes the native Play menu. These checks catch raw IDs and clipped suffixes that handwritten friendly-label snapshots would conceal.

`native_aim_fixture.gd` sends mouse press, motion, and release events through an isolated input viewport and steps the inherited cue-ball process on both native host and guest tables. It checks idle-to-aim startup, a visible charged cue, one release submission, idle cleanup, and off-turn/native-menu rejection. It preserves/restores native parent, transform, world and resize bindings. A controller sink records intent without applying physics; this fixture does not establish production controller authorization, physical controller input or network delivery. See the current native verification record below.

`native_pocket_fixture.gd` exercises native host blackhole creation and cleanup, including a real physical BLACK-HOLE pot through the native pocket sensor and callback, then guest materialization and removal from snapshots. Both entry points run in the existing screenshot process. The host case precedes the baseline table capture; the guest case restores that baseline before later shop fixtures.

`native_table_effects_fixture.gd` exercises native callbacks for all six droplet types, ENERGY-BALL retirement, and WORMHOLE suction, then checks guest and spectator appearance, retained identity, removal, resync and teardown. Repeated setup/dispose verifies that cached texture arrays cannot corrupt the native prefab. A synthetic burst built from native descriptors checks 128-droplet materialization and cancellation of pending births by a newer removal; it records capture, frame and apply timings. The installed native ENERGY-BALL contains an `EnergyCircle` sprite and no line or particle children; optional trail serialization has model coverage.

`native_visual_fx_fixture.gd` samples all 34 installed catalog definitions, all six dice faces and 21 modes for both wisp kinds (79 samples), comparing two native poses with guest and spectator views. It also triggers representative native explosions, tornado, lightning, constellation and ordinary/pocket wisps. Guest and spectator assertions cover line geometry, shader fields, particle activation, graph stars, stable identities, expiry, resync, legacy snapshots, malformed state and absence of gameplay callbacks. `table_effects_probe.gd` separately covers schema/capacity validation, energy retirement/recovery, combined packet sizing, capture lifecycle and settled-table effect scheduling. See the [effect matrix](../docs/TABLE_EFFECTS.md) for the exact contract and remaining verification.

`native_drawing_fixture.gd` compares native CANDLE stages/fade, REAPER tether, trail/LUNA geometry and floating score/money text, shader and Control layout with retained scriptless views. `ball_presentation_fixture.gd` samples native status, flame/star/score particles, fleeting/flash/level fields and checks retained item/material identity, removals, local aim and spectator elapsed time. `ability_feedback_fixture.gd` exercises committed TOGETHER outcomes and the actual native cue award receipt without replaying score or money changes. `bounty_feedback_fixture.gd` resolves pending, tied and completed competitive results through the real resolver and checks final award text on own and watched tables, including roster-only delivery. The expanded pocket fixture covers sampled doors/shields/labels, malformed fields and epoch-overflow recovery. These tests distinguish native scene poses from full gameplay-trigger, particle-phase and live transport coverage.

The harness also invokes `shop_probe.gd::check_native_transactions` against its already-open host shop. It exercises native snack purchase and cocktail mixing through the authoritative shop handler, including ticket and item conservation and returning the result to a build slot. A bounded failure stops the capture rather than carrying a half-finished mix into later tests. The standalone shop probe's game-start/exit path is not invoked. Existing `round_flow_fixtures.gd` separately covers real mouse dragging, snack offer retraction/cancellation, predicted ball purchases, delayed replies, rejected sales, and phase replay. These paths do not establish simultaneous remote snack purchases or multi-client mixing under network delay.

## Native game probes

The BLACK-HOLE regression in `snapshot_probe.gd` reproduces native table/game pocket-array aliasing, zero-scale first spawn, all ten holes, authoritative pocket state and round cleanup. `native_pocket_fixture.gd` additionally calls real native `spawn_hole`, captures birth/growth and applies it to the guest, checking visuals, disabled gameplay, retained identity, removal and resync. It verifies the engine's near-zero birth transform against the captured state. `controller_probe.gd` covers reliable topology changes, targeted resync isolation, late keyframes and invalid-shot rejection before physics. Cue fixtures check native fades/pullback, finish changes while hidden/aiming, and teammate-aim cleanup. Parsing alone does not execute these assertions.

Windows Capture-Screens `20260927T100006Z-e3d4caee` on mod v0.9.5 / native 0.15.7 passed **1,410 harness checks with zero failures**, both embedded 85-assertion probes and eleven model probes, producing **68 screenshots**. One muted isolated process, compatibility renderer, 1280×720, 30 FPS cap, 180-second watchdog. Exit 0, no script errors, process stopped, normal saves and installed files unchanged. Native host-unlock and complete production catalogs, English/Catalan names, every card/tooltip/accessible/result label, complete title lines, voter separation, eight-player layout, and native Play-menu open/close passed. The corresponding English/Catalan and native-menu screenshots were visually reviewed.

The expanded label fixture first reproduced the clipped-title failures; the final run retains the preceding table-effect, input, shop/snack/mixer and settings regressions. It establishes native Windows fixture behavior, not every installed locale, live networking or expanded macOS coverage.

Authorized Windows capture `20260927T094004Z-238aa6bf` passed **1,312 harness checks**, the embedded snapshot and table-effects probes (85 assertions each), and all eleven registered model probes, producing **66 screenshots**. The run used native 0.15.7 with v0.9.4 gameplay code, one muted process, compatibility rendering, 1280×720 and a 30 FPS cap. The runner recorded exit 0, no script errors, process stopped, and unchanged installed files and normal saves. This retains the click/cue, snack-bar, mixer and default-off shop-follow settings coverage and adds the effect fixtures above, including the physical BLACK-HOLE pot. Guest and spectator durable/transient effect frames were visually reviewed. The 128-droplet burst completed and newer removals cancelled unfinished creation without resurrection. See [PERFORMANCE.md](../docs/PERFORMANCE.md) for timings, sample counts and residual diagnostics.

This is single-process native correctness coverage. Live remote delivery and concurrent snack/mixer transactions, controller hardware, expanded macOS/crossplay, every catalog trigger and full input/network performance telemetry remain unverified. Particle phase is not deterministic, and general native audio/postprocessing are outside the visual descriptor contract. The renderer's 4 ms check is a soft budget between operations: sampled apply reached 5.062 ms and full snapshot apply reached 13.235 ms, so no hard frame limit or latency gain is claimed. The five historical off-tree fixture lookup errors are fixed; native shutdown resource diagnostics remain visible. A passing runner is not a zero-error-log claim.

These probes require your own installed Ultrapool 0.15.7. Make private test directories containing local copies of `game.exe`, `steam_api64.dll`, and `libgodotsteam.windows.template_release.x86_64.dll`. Keep overrides out of the normal game directory. Replace the checkout prefix in the following examples with an absolute path using forward slashes.

Each native probe checks its save namespace before proceeding. Configure the namespace and autoload in `override.cfg` beside the private executable:

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="UltrapoolTogetherAdapterTest"

[autoload]
AdapterProbe="*C:/path/to/ultrapool-multiplayer/tests/adapter_probe.gd"
```

Use the matching settings below. Only the shop and session probes also require the `UltrapoolTogether` main autoload; put it before the probe autoload.

| Probe | Save namespace | Probe autoload | Success marker |
| --- | --- | --- | --- |
| `adapter_probe.gd` | `UltrapoolTogetherAdapterTest` | `AdapterProbe` | `ADAPTER_PROBE_PASS` |
| `snapshot_probe.gd` | `UltrapoolTogetherSnapshotTest` | `SnapshotProbe` | `SNAPSHOT_PROBE PASS` |
| `shop_probe.gd` | `UltrapoolTogetherShopTest` | `ShopProbe` | `SHOP_PROBE_PASS` |
| `session_probe.gd` | `UltrapoolTogetherSessionTesthost` / `UltrapoolTogetherSessionTestguest` | `SessionProbe` | `SESSION_PROBE_PASS host` / `SESSION_PROBE_PASS guest` |
| `transport_probe.gd` | `UltrapoolTogetherTransportTest` | `TogetherTransportTest` | `TRANSPORT TEST COMPLETE PASS` |

Launch the test executable from its own directory and capture stdout and stderr. Success requires the listed marker, exit code 0, and no mod script errors. These tests load native game resources even with `--headless`.

The adapter probe starts a classic run and exercises the native aiming hook, unchanged mouse/controller bindings, off-turn drag and precise-confirmation rejection, cue state preservation, shot consumption and settling, round-end cash-out, a paused result popup, and restoration of the original player script.

The snapshot probe covers malformed values, duplicate identities, resource-path injection, base pockets, dynamic holes, round results, and complete native inventory reconstruction. It also runs inside the screenshot harness. It validates packet handling; it does not prove that guest visuals or ball movement are correct.

The shop probe needs this additional autoload before `ShopProbe`:

```ini
UltrapoolTogether="*C:/path/to/ultrapool-multiplayer/mod/main.gd"
```

It opens a native shop under a table-host controller substitute, buys and rearranges items, rejects replayed transactions and changed item identities, checks floating-point currency and resource validation, and rejects transactions while paused or after the table finishes. It exercises the shared action handler locally; it does not simulate simultaneous remote shoppers or validate every item combination.

See [TRANSPORT.md](TRANSPORT.md) for the eight-peer loopback transport probe and optional Steam room check.

## Two-process session flow

For manual same-PC play without Steam, prefer `Test-LocalSession.cmd` ([LOCAL_SESSION.md](LOCAL_SESSION.md)). The automated probe below still exits on its own after scripted checks.

Create two separate private runtime directories. The host's override is:

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="UltrapoolTogetherSessionTesthost"

[autoload]
UltrapoolTogether="*C:/path/to/ultrapool-multiplayer/mod/main.gd"
SessionProbe="*C:/path/to/ultrapool-multiplayer/tests/session_probe.gd"
```

Use `UltrapoolTogetherSessionTestguest` in the second directory. Start the first executable with `--rendering-method gl_compatibility -- --host` and the second with `--rendering-method gl_compatibility -- --guest`. The probe opens localhost UDP port 24817. Both processes must finish with their role-specific pass markers and exit code 0.

The session probe uses the actual lobby scene signals and controller in two phases:

1. **One shared co-op table.** Joining preserves the guest menu and places the guest on the unassigned bench. Starting early or readying without a seat is rejected. Both choose seats and ready up before the host starts. Native host input is blocked while the lobby is open; duplicate input cannot consume another shot. The guest checks native type textures and inspection, waits for confirmed shot input, and verifies that its ball moves across physics frames while network polling is briefly stopped. Two shots complete without a competitive cap. Returning to the lobby and closing it restores the guest's original menu.
2. **Two separate competitive tables.** The host changes to two tables with a one-shot budget, and both players seat and ready again. Each player runs its own native game with matching seed, deck, difficulty, and initial cue position. Distinct wallet changes remain local to their respective tables. Each table consumes one shot, locks aiming when finished, and receives a scoreboard containing both finished tables. Returning to the lobby and one guest leaving must preserve the host's room. Native input bindings must remain unchanged through both phases.

The probe drives UI signals rather than clicking rendered controls and takes no screenshots. It covers two local processes, not eight real players, Internet latency, Steam invitations, or a complete campaign.

Multi-PC testing should cover lobby layout, Steam invitations, uneven groups, equal shot budgets, independent tables and shops, ball movement under latency, cursors and inspection, concurrent shop actions, disconnects, and rematches.

## Rook animation capture

Windows run `20260927T104101Z-rook-animation` at gameplay/fixture commit `bb80925` passed 2,175/2,175 harness checks, produced 79 native screenshots and 96 real viewport animation frames, and preserved installed files and normal saves. The muted process exited normally within the 180-second watchdog with no script errors; existing engine shutdown resource warnings remain. The cue probes additionally reported 226 catalog/curve, 189 inventory and 204 effect checks. The case-art descendant bounds check catches an overflow that the earlier parent-only check missed. Animation output and timing provenance are described in [screenshots.md](../docs/screenshots.md). This is fixture rendering/callback evidence at 1280×720, not live multiplayer, actual narrow-window rendering or a performance measurement.


## Cue economy and collection capture

Windows capture `20260927T121822Z-clean-cue-placard` at gameplay/fixture commit `9541e71` passed **2,797/2,797 checks**, including **610 collection checks**, and produced **90 native screenshots** plus **96 actual viewport animation frames**. One muted isolated process used the compatibility renderer, 1280×720, a 30 FPS cap and a 180-second watchdog. It exited normally in about 105 seconds with no script errors; normal saves and installed files were unchanged. Engine shutdown resource warnings remain.

All eight ball inspections, native rarity prices and highlighted descriptions, the four-helper Bounty/Encore mix, level badges, label/ball/tooltip bounds, retained outline geometry, no-overlap checks, unchanged discovery records, native tabs/scrolling and close/reopen passed. Every individual tooltip and the mixed tooltip were visually reviewed. The final native rows are centered within the original set footprint. Cue probes passed 226 catalog/curve, 206 inventory and 209 effect checks, including mixed-price spending and the shared bonus budget. The final cue placard removes duplicate wallet text and idle prompts; the native inventory wallet remains. Pending confirmation stays on the action button, while rejection, blocked shopping and insufficient funds retain visible feedback. Host/guest transaction, preview and description/control-separation checks passed with the compact layout.

This is native fixture rendering and callback evidence, not live networking or a foreground performance/balance measurement. Actual narrow/portrait rendering, macOS, controller hardware, simultaneous shoppers, delayed/reordered network updates and long-run balance remain open.


## Host cue-shop setting verification

Windows capture `20260928T014725Z-cue-shop-setting` at gameplay/fixture commit `730d31f` passed **2,895/2,895 checks** and produced **93 native screenshots**. It used one muted isolated process, the compatibility renderer at 1280×720, a 30 FPS cap and a 180-second watchdog. The game exited normally with no script errors; normal saves and installed game files were unchanged. Engine shutdown resource warnings remain.

The actual lobby checkbox/controller path, guest and active-match locks, Ready invalidation, boolean validation, host/guest disabled shops, absent cue controls and art extension, denied cue actions, ignored cue inventory updates, normal ball/snack interactions and next-session re-enabling passed. Controller/effect fixtures cover frozen config, repeated starts, native shot strength and no perk hooks while disabled. Static parsing passed for all 112 GDScript files. Protocol-10 handshake scenarios are authored and parsed but remain unexecuted; live Steam, remote table leaders, reconnects, macOS, narrow-window rendering and performance/balance measurement remain open.

## PR #53 macOS follow-up

Capture `20261005T134751Z-32cbb0fa` passed **19,146/19,146 checks** with **108 screenshots**, exit 0 and no script errors. Installed files and normal saves were unchanged; the private runtime was removed. The final gameplay/fixture files match the tested source. Native drawing, ball/pocket art, 79 catalog samples at two poses, cue/ability/Bounty feedback, reliable recovery, and the existing input/shop/round-flow/lobby regressions passed. Key galleries were reviewed, including both competitive Bounty result labels and the full native/localized lobby.

All 123 GDScripts parse. Nine benchmark self-tests, 13 isolated macOS installer tests and nine mocked capture tests pass. The reviewed benchmark baseline records 90.5% coverage with unchanged rows/weights and explicit wire growth. Native shutdown diagnostics remain; full live delivery, expanded Windows/crossplay and complete performance telemetry are open. See [the scoped native evidence and measurements](../docs/TABLE_EFFECTS.md#macos-pr-53-follow-up).

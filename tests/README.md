# Validation

Syntax checks do not verify engine types or gameplay. Follow [AGENTS.md](../AGENTS.md) before running any probe, including `--headless`.

For authorized visual tests, run `Capture-Screens.cmd` on Windows or `bash Capture-Screens.command` on macOS from the repository root. The [screenshot harness](../docs/screenshots.md) builds repeatable fixtures, checks native textures and shop actions, and saves an HTML gallery with logs and check results. It uses one muted game process and separate test saves; macOS uses a background-only app with an unfocusable, mouse-passthrough rendering surface.

For authorized same-PC host+guest play over LAN loopback (not Steam), see [LOCAL_SESSION.md](LOCAL_SESSION.md) and run `Test-LocalSession.cmd` from the repository root. It starts two isolated windowed processes and leaves them open for manual testing.

## Checks that do not launch the game

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
| `transport_budget_probe.gd` | Fake Steam queues exercise bounded dispatch, reliable retention/order, channel fairness across frames, and byte/time limits without network connections. | `TRANSPORT_BUDGET_PROBE PASS` |
| `router_probe.gd` | Authenticated actor identity, requests to the correct table leader, table-isolated broadcasts and replies, reliable actions, disconnected members, and malformed routes. | `ROUTER_PROBE PASS` |
| `controller_probe.gd` | Main controller lifecycle using off-tree service substitutes: identity teardown, room/match generations, terminal leader disconnects and reconnects, a run closing during a shot, and targeted shop synchronization preserving the broadcast cache. | `CONTROLLER_PROBE PASS` |
| `shop_layout_probe.gd` | Guest remote-slot coverage for host-authoritative shop layouts, including stale pre-inventory replicas and extra local unlock slots. | `SHOP_LAYOUT_PROBE PASS` |

Each script exits 0 on success. The controller probe creates no native game scenes or network connections. It also covers Race versus Score PvP caps, authenticated race results, finish ordering, return-vote generations, startup failure handling, and spectator routing. The screenshot harness runs these eleven model probes inside its existing game process, plus the embedded native `snapshot_probe.gd`. Its model adapter requires a successful completion marker, at least one assertion, and no failed assertions; merely loading a probe cannot count as a pass. The navigation fallback case uses an explicit null context so the real process's CRT overlay does not change the test premise. `clone_round_probe.gd`, `set_vote_probe.gd`, and the standalone adapter/session/transport probes are not part of this model invocation list.

The `ui_nav_probe.gd` persistence cases require the harness's isolated `UltrapoolTogetherRenderTest` profile and restore the original configuration bytes. They intentionally refuse to write into a normal or arbitrary standalone profile; use the registered capture harness for the complete probe.

The harness also records and replays native host/client round transitions, including delayed shop acknowledgements, packet reordering, payout, victory, defeat, and teardown. It includes regression assertions for stationary replica sleep, spin reconciliation, shop map identity during wallet/health updates, and rarity indicators on unchanged offers. The [game-loop coverage matrix](GAME_LOOP.md) separates runtime assertions, model checks, and remaining multi-PC coverage. Added assertions are authored coverage until an authorized run passes them.

`render_ui_fixtures.gd` checks lobby card/button ballots through the controller, local selection, live voter identities, abstention, disconnects, frozen choices, and retained card identity and keyboard focus. Full-catalog and eight-player consensus fixtures check layout bounds and exact native shop poster references for all starting sets.

`native_aim_fixture.gd` sends mouse press, motion, and release events through an isolated input viewport and steps the inherited cue-ball process on both native host and guest tables. It checks idle-to-aim startup, a visible charged cue, one release submission, idle cleanup, and off-turn/native-menu rejection. It preserves/restores native parent, transform, world and resize bindings. A controller sink records intent without applying physics; this fixture does not establish production controller authorization, physical controller input or network delivery. See the current native verification record below.

`native_pocket_fixture.gd` exercises native host blackhole creation and cleanup, then guest materialization and removal from snapshots. Both entry points run in the existing screenshot process. The host case precedes the baseline table capture; the guest case restores that baseline before later shop fixtures.

The harness also invokes `shop_probe.gd::check_native_transactions` against its already-open host shop. It exercises native snack purchase and cocktail mixing through the authoritative shop handler, including ticket and item conservation and returning the result to a build slot. A bounded failure stops the capture rather than carrying a half-finished mix into later tests. The standalone shop probe's game-start/exit path is not invoked. Existing `round_flow_fixtures.gd` separately covers real mouse dragging, snack offer retraction/cancellation, predicted ball purchases, delayed replies, rejected sales, and phase replay. These paths do not establish simultaneous remote snack purchases or multi-client mixing under network delay.

## Native game probes

The BLACK-HOLE regression in `snapshot_probe.gd` reproduces native table/game pocket-array aliasing, zero-scale first spawn, all ten holes, authoritative pocket state and round cleanup. `native_pocket_fixture.gd` additionally calls real native `spawn_hole`, captures birth/growth and applies it to the guest, checking visuals, disabled gameplay, retained identity, removal and resync. It verifies the engine's near-zero birth transform against the captured state. `controller_probe.gd` covers reliable topology changes, targeted resync isolation, late keyframes and invalid-shot rejection before physics. Cue fixtures check native fades/pullback, finish changes while hidden/aiming, and teammate-aim cleanup. Parsing alone does not execute these assertions.

Authorized Windows capture `20260927T082742Z-0bdf5994` passed **693 harness checks**, the embedded snapshot probe (85 assertions), and all eleven registered model probes, producing **60 screenshots**. The run used native 0.15.7 with the v0.9.3 gameplay code, one muted process, compatibility rendering, 1280×720 and a 30 FPS cap. The runner recorded exit 0, no script errors, process stopped, and unchanged installed files and normal saves. This retains the blackhole, cue, snack-bar and mixer coverage from the preceding 672-check run and adds actual HUD gear/checkbox callbacks, default-off manual navigation, opt-in snack/mixer following, in-match preference access with host rules locked, and F8/Escape/outside dismissal. The settings on/off and lobby gear frames were visually reviewed. Native counter movement is allowed to settle through the existing navigation guard before follow assertions. See [PERFORMANCE.md](../docs/PERFORMANCE.md) for revision/evidence and residual diagnostics.

This is single-process native correctness coverage. Full physical BLACK-HOLE pot triggering, live remote concurrent snack/mixer transactions, controller hardware, current macOS/crossplay and performance measurements remain open. Floor oil/fire and other absent table effects remain [GAP-007](../docs/TABLE_EFFECTS.md). Historical off-tree fixture lookup errors and shutdown resource diagnostics remain visible in logs; a passing runner is not a zero-error-log claim.

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

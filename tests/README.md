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
| `lobby_probe.gd` | Capacity/seats, run-choice allowlists, per-player votes, ties/abstention, frozen selections, stale readiness rejection, concurrent ready votes, host-only table settings, start/reset, and disconnects. | `LOBBY_PROBE PASS` |
| `transport_budget_probe.gd` | Fake Steam queues exercise bounded dispatch, reliable retention/order, channel fairness across frames, and byte/time limits without network connections. | `TRANSPORT_BUDGET_PROBE PASS` |
| `router_probe.gd` | Authenticated actor identity, requests to the correct table leader, table-isolated broadcasts and replies, reliable actions, disconnected members, and malformed routes. | `ROUTER_PROBE PASS` |
| `controller_probe.gd` | Main controller lifecycle using off-tree service substitutes: identity teardown, room/match generations, terminal leader disconnects and reconnects, a run closing during a shot, and targeted shop synchronization preserving the broadcast cache. | `CONTROLLER_PROBE PASS` |
| `shop_layout_probe.gd` | Guest remote-slot coverage for host-authoritative shop layouts, including stale pre-inventory replicas and extra local unlock slots. | `SHOP_LAYOUT_PROBE PASS` |

Each script exits 0 on success. The controller probe creates no native game scenes or network connections. It also covers Race versus Score PvP caps, authenticated race results, finish ordering, return-vote generations, startup failure handling, and spectator routing. The screenshot harness runs all model probes in this table inside its existing game process.

The harness also records and replays native host/client round transitions, including delayed shop acknowledgements, packet reordering, payout, victory, defeat, and teardown. It includes regression assertions for stationary replica sleep, spin reconciliation, shop map identity during wallet/health updates, and rarity indicators on unchanged offers. The [game-loop coverage matrix](GAME_LOOP.md) separates runtime assertions, model checks, and remaining multi-PC coverage. Added assertions are authored coverage until an authorized run passes them.

## Native game probes

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

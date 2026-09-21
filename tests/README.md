# Validation

**Every Godot/runtime probe listed here is UNRUN for v0.4.** Source parsing is not engine type checking, gameplay validation, or a visual review. Local runtime tests remain suspended after the 2026-09-20 GPU hang: do not launch Ultrapool, Godot, or these probes, including `--headless`, without explicit user authorization for that test. See [AGENTS.md](../AGENTS.md). Earlier runtime results do not validate this revision.

## Checks that do not launch the game

Installer boundary tests use fake executable fixtures:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\installation.ps1
```

Every installer call in that suite supplies an isolated `UserDataRoot` under `.local/installer-tests`; real user profiles are not accessed. It checks one-time progression import, exact backups of existing mod saves, update preservation, untouched run files, missing/invalid source saves, dry runs, profile junction rejection, and uninstall behavior.

GDScript can also be parsed with the private `gdtoolkit` installation under `.local/static-tools`. This runs Python only and does not check native game resources, Godot API availability, or behavior at runtime.

## Standalone model and controller probes — UNRUN

These scripts extend `SceneTree`. They use a separate compatible Godot 4.6 executable's `--script` entry point; they are not game autoloads and do not have game-save namespace guards. Run them only after authorization, from a private test project with its own user-data directory and no game autoloads. The shipped game executable is a release template and does not provide this standalone script workflow.

| Probe | Coverage | Success marker |
| --- | --- | --- |
| `lobby_probe.gd` | Eight-player capacity, self-selected seats, readiness invalidation, host-only settings, unequal table groups, equal shots per table, start/reset, reserved disconnected seats, and leader selection. | `LOBBY_PROBE PASS` |
| `router_probe.gd` | Authenticated actor identity, requests to the correct table leader, table-isolated broadcasts and replies, reliable actions, disconnected members, and malformed routes. | `ROUTER_PROBE PASS` |
| `controller_probe.gd` | Main controller lifecycle using off-tree service substitutes: identity teardown, room/match generations, terminal leader disconnects and reconnects, a run closing during a shot, and targeted shop synchronization preserving the broadcast cache. | `CONTROLLER_PROBE PASS` |

Each script exits 0 only on success. The standalone controller probe creates no native game scenes or network connections. These scripts still execute Godot and remain covered by the runtime restriction.

## Native game probes — UNRUN

These probes require your own installed Ultrapool 0.15.7. Make private test directories containing local copies of `game.exe`, `steam_api64.dll`, and `libgodotsteam.windows.template_release.x86_64.dll`. Keep overrides out of the normal game directory. Replace the checkout prefix in the following examples with an absolute path using forward slashes.

Each native probe checks its save namespace before proceeding. Configure the namespace and autoload in `override.cfg` beside the private executable:

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="UltrapoolTogetherAdapterTest"

[autoload]
AdapterProbe="*C:/Code/ultrapool-multiplayer/tests/adapter_probe.gd"
```

Use the matching settings below. Only the shop and session probes also require the `UltrapoolTogether` main autoload; put it before the probe autoload.

| Probe | Save namespace | Probe autoload | Success marker |
| --- | --- | --- | --- |
| `adapter_probe.gd` | `UltrapoolTogetherAdapterTest` | `AdapterProbe` | `ADAPTER_PROBE_PASS` |
| `snapshot_probe.gd` | `UltrapoolTogetherSnapshotTest` | `SnapshotProbe` | `SNAPSHOT_PROBE PASS` |
| `shop_probe.gd` | `UltrapoolTogetherShopTest` | `ShopProbe` | `SHOP_PROBE_PASS` |
| `session_probe.gd` | `UltrapoolTogetherSessionTesthost` / `UltrapoolTogetherSessionTestguest` | `SessionProbe` | `SESSION_PROBE_PASS host` / `SESSION_PROBE_PASS guest` |
| `transport_probe.gd` | `UltrapoolTogetherTransportTest` | `TogetherTransportTest` | `TRANSPORT TEST COMPLETE PASS` |

After authorization for a particular probe, launch its private executable from its own test directory and capture stdout and stderr. Success requires the listed marker, exit code 0, and no mod script errors. Runtime tests use native game resources even when launched with `--headless`.

The adapter probe starts a classic run and exercises the native aiming hook, unchanged mouse/controller bindings, off-turn drag and precise-confirmation rejection, cue state preservation, shot consumption and settling, round-end cash-out, a paused result popup, and restoration of the original player script.

The snapshot probe covers malformed values, duplicate identities, resource-path injection, base pockets, and dynamic holes. It validates packet handling; it does not prove that guest visuals or ball movement are correct.

The shop probe needs this additional autoload before `ShopProbe`:

```ini
UltrapoolTogether="*C:/Code/ultrapool-multiplayer/mod/main.gd"
```

It opens a native shop under a table-host controller substitute, buys and rearranges items, rejects replayed transactions and changed item identities, checks floating-point currency and resource validation, and rejects transactions while paused or after the table finishes. It exercises the shared action handler locally; it does not simulate simultaneous remote shoppers or validate every item combination.

See [TRANSPORT.md](TRANSPORT.md) for the eight-peer loopback transport probe and optional Steam room check. The revised protocol 4 probe is also unrun. A Steam room creation check alone does not validate play across accounts.

## Two-process session flow — UNRUN

Create two separate private runtime directories. The host's override is:

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="UltrapoolTogetherSessionTesthost"

[autoload]
UltrapoolTogether="*C:/Code/ultrapool-multiplayer/mod/main.gd"
SessionProbe="*C:/Code/ultrapool-multiplayer/tests/session_probe.gd"
```

Use `UltrapoolTogetherSessionTestguest` in the second directory. After explicit authorization for this two-process test, start the first executable with `--rendering-method gl_compatibility -- --host` and the second with `--rendering-method gl_compatibility -- --guest`. This renderer argument is part of the proposed test configuration, not an established fix for the earlier GPU incident. The probe opens localhost UDP port 24817. Wait for both processes to finish and require both role-specific pass markers and exit code 0.

The v0.4 probe uses the actual lobby scene signals and controller in two phases:

1. **One shared co-op table.** Joining preserves the guest menu and places the guest on the unassigned bench. Starting early or readying without a seat is rejected. Both choose seats and ready up before the host starts. Native host input is blocked while the lobby is open; duplicate input cannot consume another shot. The guest checks native type textures and inspection, waits for confirmed shot input, and verifies that its ball moves across physics frames while network polling is briefly stopped. Two shots complete without a competitive cap. Returning to the lobby and closing it restores the guest's original menu.
2. **Two separate competitive tables.** The host changes to two tables with a one-shot budget, and both players seat and ready again. Each player runs its own native game with matching seed, deck, difficulty, and initial cue position. Distinct wallet changes remain local to their respective tables. Each table consumes one shot, locks aiming when finished, and receives a scoreboard containing both finished tables. Returning to the lobby and one guest leaving must preserve the host's room. Native input bindings must remain unchanged through both phases.

The probe drives UI signals rather than clicking rendered controls and takes no screenshots. It covers two local processes, not eight real players, Internet latency, Steam invitations, or a complete campaign.

A future authorized multi-PC playtest should check the full lobby at different window sizes, direct invitations with the overlay disabled, 1v1v1 and uneven table groups, equal table budgets, independent boards and shops, smooth local ball movement under latency, partner aiming/cursors, ball types and inspection, concurrent purchases and rearrangement, table-host departure, rematches, and restoration of local play after leaving.

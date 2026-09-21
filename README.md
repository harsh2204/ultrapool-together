# Ultrapool Together

A bolt-on Steam multiplayer mod for **Ultrapool 0.15.7**, Windows Steam build **25298901**.

Version **0.4** adds a full lobby scene for **2–8 players**. Choose seats at tables, ready up, and start together. One table is cooperative play; multiple tables compete with separate boards, balls, inventories, money, shops, and runs. The room host chooses between one table and one table per connected player. Uneven groups such as **2v1**, **1v1v1v2**, and **3v2v1** are supported by the lobby and routing model.

**Validation status:** v0.4 has been checked with a standalone GDScript parser, source review, scene structure checks, and installer tests using fake executables. It has not been launched or playtested. Runtime testing on the development PC remains suspended after a graphics-driver incident whose cause has not been attributed to the mod. The eight-player flow, native scene loading, Steam gameplay, reconnects, and UI layout still need runtime verification.

## Install

1. Every player needs their own Steam installation of Ultrapool.
2. Extract `UltrapoolTogether.zip` and run `Install.cmd`.
3. Open `UltrapoolTogether/Launch.cmd` inside the game's installation folder.

The installer copies the game's executable and two DLLs into the mod folder, requiring about 400 MB. The original game and its Steam launch are unchanged. The mod uses separate saves in `%APPDATA%/UltrapoolTogether`.

On the first installation or update with this feature, the installer imports your existing Steam progression from `%APPDATA%/Godot/app_userdata/Ultrapool/save.tres`. This brings over unlocks, achievements, tutorial progress, settings, and customization. Existing mod progression is backed up under `%APPDATA%/UltrapoolTogether/save-import-backups/` before replacement. The imported save also seeds the mod's native recovery backup. The completion record is `ultrapool-together-progress-import.json` in the mod profile; later installs preserve your mod progress.

This is a **one-time import**, not ongoing synchronization: progress earned afterward stays in the version you played. Original Steam saves and unfinished solo runs are never changed. The installer does not copy run files, daily history, Steam Cloud metadata, analytics files, or caches. If no Steam progression save exists yet, installation proceeds without importing or recording completion. Both versions must be closed during installation.

For a custom location, run `Install.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Ultrapool"`. Close the mod before rerunning the installer to update it. The copied runtime does not update automatically when Steam updates the game.

Everyone must install v0.4 and create a new **UP4** room. Older room codes and mod versions are incompatible.

## Create a match

1. Keep Steam running and open the mod on every PC. Stay at the main menu and close any game popups.
2. Press **F8** or choose **Lobby**, then **Create lobby**.
3. Choose **Invite friend** and a friend from the in-game Steam list, or copy the `UP4-...` room code for friends to paste into **Join lobby**. The Steam overlay is not required for invitations.
4. The room host selects the number of tables. With multiple tables, choose **Shots per table**: **six total shots per table by default**, configurable from 1 to 20.
5. Everyone clicks an open seat at their preferred table and selects **Ready up**. Changing seats or settings clears readiness. All players must be seated and ready, and every configured table must have at least one player.
6. The host selects **Start match**. Each table starts a fresh run using the room host's selected deck and difficulty and a shared generated seed.

Joining a room never starts a run. Joining another table never changes the room host. The first occupied seat at each table becomes that table's host for the match, indicated separately from **ROOM HOST** in the lobby.

Open the mod before accepting an invitation: Steam otherwise launches the original game. Rooms use Steam's friends-only lobby and invitation access. There is no IP address, port forwarding, or separate server in the player flow.

## Playing at a table

Each table plays independently. Members of the same table rotate through turns in seat order. Use the game's normal mouse or controller aiming, including precise-shot mode. Aiming and shooting are disabled while another teammate owns the turn. **Pass** hands a ready turn to the next connected teammate without consuming a shot.

All members can use their table's shared shop regardless of turn ownership: buy, sell, arrange, merge, reroll, and continue together. The table host validates transactions against the current inventory and balance, rejecting stale actions rather than spending twice. Live cursors and aim previews are visible only to members of the same table. Hover over balls to inspect their native type and effects.

With one table, co-op continues through the native run without the competitive shot cap. With multiple tables, each table receives the same total shot allowance regardless of headcount. For example, at six shots, a solo player can take six and a two-person table normally takes three each. A native run ending early also ends that table's match. Standings add the nonnegative points credited to completed shots; the highest table score wins once every table finishes. Equal scores draw. Opening the lobby shows table scores, shots used, and status while other tables continue playing.

The room host can choose **End match · Return to lobby** to stop all tables and configure the next match. Leaving restores the local menu. Seats and settings are locked during a match; new players wait for the next lobby. Existing Steam participants can reconnect to their reserved seats while their table host remains connected. A table host disconnecting ends that table; reconnecting it does not restart its run. Other tables continue. If the room host leaves, the room closes. Authority migration is not implemented.

## Synchronization and current limits

The room host coordinates the lobby and relays authenticated table messages. Each table host runs only its own native game and owns its scoring, effects, and shop. Teammates receive the accepted shot vector and starting table and simulate ball movement locally. Independent position/velocity corrections arrive at 10 Hz, followed by an exact settled-table update. A remote shot still waits for its table host's acceptance, so latency can delay the initial strike.

This is predictive local physics, not deterministic lockstep. Native special effects and corrections can change a predicted path. Tables start with the same deck, difficulty, seed, and initial cue position; native random abilities and subsequent shop decisions can diverge. Energy balls, droplets, wisps, other transient spell effects, and table-host audio are not yet mirrored. Table cosmetics use local selections. Standard runs are the development target; daily challenges are unsupported.

The eight-player cap is the current mod limit, not a two-player Steam restriction. Performance and reliability at that capacity remain unmeasured. Multiplayer-only ball concepts are documented in [`docs/MULTIPLAYER_BALLS.md`](docs/MULTIPLAYER_BALLS.md) in the source repository; they are proposals, not included ball abilities.

## Remove

Run `Uninstall.ps1` inside the installed mod folder. It removes installer-owned files and keeps saves and unrecognized files. Use the original Steam launch for single-player play.

## Development

`main.gd` connects room lifecycle, per-table turns, native runs, and standings. `lobby_scene.tscn` / `lobby_scene.gd` provide the full lobby; `lobby_state.gd` owns seats and readiness. `table_router.gd` enforces sender identity and table ownership. `run_setup.gd` starts matching native run configurations.

`game_adapter.gd` and `native_player.gd` connect normal input to turn ownership. `table_sync.gd`, `replica_game.gd`, and `replica_ball.gd` provide follower rendering and local physics. `shop_sync.gd` handles each table's cooperative shop; `presence.gd` draws its members' cursors and aiming. `transport.gd` uses Steam lobbies and P2P with separate reliable action and transient update channels, per-peer handshakes, session generations, and isolated peer departures. ENet is retained only for developer regression probes.

`Build-Package.ps1` packages the mod and installation scripts. Game assets, recovered scripts, and private diagnostics are excluded. Read `AGENTS.md` and `tests/README.md` before testing. Authored runtime probes and results from earlier versions do not validate this revision.

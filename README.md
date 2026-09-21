# Ultrapool Together

A bolt-on two-player mod for **Ultrapool 0.15.7**, Windows Steam build **25298901**.

Version 0.3 uses native shot controls, local ball movement on both PCs, an in-game Steam friends list and lobby roster, shared cursors and aiming, and a cooperative shop. Turns alternate automatically, with aiming and shooting disabled when it is your partner's turn. Both players can use the shop regardless of turn ownership.

**Validation status:** this revision has been checked with a standalone GDScript parser and static review. It has not been launched or playtested. Runtime testing on this PC is suspended after a graphics-driver incident; the cause of that incident has not been attributed to the mod. Cross-account Steam invitations and gameplay remain unverified.

## Install

1. Both players need their own Steam installation of Ultrapool.
2. Extract `UltrapoolTogether.zip` and run `Install.cmd`.
3. Open `UltrapoolTogether/Launch.cmd` inside the game's installation folder.

The installer copies the game's executable and two DLLs into the mod folder, requiring about 400 MB. The original game and its Steam launch are unchanged. The mod uses separate saves in `%APPDATA%/UltrapoolTogether`.

For a custom location, run `Install.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Ultrapool"`. Rerun the installer to update the mod. The copied runtime does not update automatically when Steam updates the game.

## Play with a friend

1. Keep Steam running and open the mod on both PCs. The joining player must be at the main menu.
2. Open **Multiplayer** or press **F8**. Choose **Co-op** or **PvP**, then **Host game**.
3. Select **Invite friend**, then choose a friend from the in-game list. Your friend accepts the invitation through Steam. The Steam overlay is not required.
4. The host starts or continues a normal run. On your turn, use Ultrapool's normal mouse or controller aiming, including its precise-shot mode.

Both players should open the mod before accepting an invitation: Steam otherwise launches the original game. You can also **Copy** the room code shown after hosting. Your Steam friend opens **Use a room code**, pastes the `UP3-...` code, and selects **Join**. The lobby panel shows both players' names, roles, and connection status. The room stays available while the host keeps it open; it is limited to Steam friends and invited players. No IP address, port forwarding, or separate server is part of this flow.

Co-op shares the run, money, inventory, and score. **Pass** hands a ready turn to your partner. The shared shop appears on both PCs between rounds; either player can buy, sell, and arrange items. The host validates each transaction against the latest inventory and balance, so an outdated purchase is rejected instead of spending twice. The partner's cursor is visible in the shop and on the table; their aiming direction is visible before a shot. Hover over a ball to inspect its native type and effects. PvP credits each player's shot score and finishes after five shots each. **Leave game** restores local play.

The host sends the accepted shot vector and starting table, then the guest simulates ball motion locally. Position/velocity corrections arrive independently at 10 Hz, with an exact settled-table update; movement no longer waits for a snapshot acknowledgement. The host remains authoritative for scoring, effects, and transactions. A guest shot still waits for host acceptance before starting, so network latency can delay the initial strike. This is predictive local physics, not deterministic lockstep: special effects and corrections can alter the predicted path.

The guest mirrors the table, cue, ball types, pockets, and score/round information. Energy balls, droplets, wisps, other transient spell effects, and host audio are not yet mirrored. Table cosmetics use the guest's local selections. Standard runs are the development target; daily challenges are not supported. Both players must install v0.3 and create a new room; v0.1 and v0.2 room codes are incompatible.

## Remove

Run `Uninstall.ps1` inside the installed mod folder. It removes installer-owned files and keeps saves and unrecognized files. Use the original Steam launch for single-player play.

## Development

`mod/main.gd` handles the multiplayer menu and turn ownership. `game_adapter.gd` and `native_player.gd` connect native input to that turn check. `table_sync.gd`, `replica_game.gd`, and `replica_ball.gd` provide guest rendering and local physics. `shop_sync.gd` handles shared shopping; `presence.gd` draws the partner cursor and aim. `transport.gd` provides Steam lobbies and P2P on separate reliable action and transient update channels; its ENet helper is retained for developer regression tests only.

`Build-Package.ps1` packages mod code and installation scripts. Game assets, recovered scripts, and local diagnostics are excluded. In the source checkout, read `AGENTS.md` and `tests/README.md` before testing. Prior versions' runtime results do not validate v0.3.

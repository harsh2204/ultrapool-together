# Ultrapool Together

Steam multiplayer for **2–8 players**. Share a table in co-op, race other tables to the end of a run, or compete on score. Each table has its own board, shop, and run.

**Source version: v0.7.0** · Requires **Ultrapool 0.15.7**, Windows Steam build **25298901**. [Released builds](https://github.com/harsh2204/ultrapool-together/releases) may be older than this branch.

## Install

1. Every player needs their own copy of Ultrapool installed through Steam.
2. Download and extract the matching `UltrapoolTogether` installation ZIP.
3. Close the game and run `Install.cmd`.
4. Start `UltrapoolTogether/Launch.cmd` inside the game's installation folder.

The installer creates a separate copy of the game, using about 400 MB. Your original Steam installation stays unchanged. Rerun the installer to update the mod.

On first install, your Steam progression, unlocks, settings, and customization are imported once. Existing mod progress is backed up in `%APPDATA%/UltrapoolTogether/save-import-backups/`. Later updates preserve mod progress; progress earned in the mod and the normal game stays separate. Original saves and unfinished solo runs are untouched.

## Play

1. Keep Steam running and open the mod on every PC before accepting invitations.
2. At the main menu, press **F8**, then **Create lobby**.
3. Invite friends from the in-game list or share the room code. The Steam overlay is optional.
4. Choose the number of tables and **Race** or **Score PvP**. Each player joins a table and selects **Ready up**.
5. The host selects **Start match** once everyone is ready and every table has a player.

Everyone must use v0.7 and a **UP7** room code. Changing seats or settings clears readiness.

## Match rules

- **One table:** co-op through a shared run, with shared money, inventory, and shop access.
- **Race:** the first table to successfully finish the full run wins. Tables share a seed, deck, and difficulty; there is no shot cap. Other tables can keep playing for their finishing place. The room host records finish order as results arrive, and elapsed time includes loading, shops, and pauses.
- **Score PvP:** independent runs with an equal shot budget per table—six by default, configurable from 1 to 20. The highest score from completed shots wins; a run ending early also ends that table's match. Uneven groups such as 2v1 and 1v1v1v2 work in either mode.
- Teammates take turns in seat order using the normal mouse or controller controls. **Pass** hands over the turn without spending a shot.
- Everyone at a table can shop and arrange items with the game's native ball and snack dragging. Each connected teammate must select **Ready** before leaving the shop. Purchases, rearrangements, and membership changes clear shop readiness. Teammate cursors and aiming are visible on that table.
- Each player sees the game's native round payout and selects **Continue** before shopping. Clients use the native shop, inventory, settings, and run results. Simple purchases, moves, sales, and Ready respond locally while the table host confirms them; rejected actions restore the shared state.
- Press **F8** for standings and **Watch** to spectate another table. Switch tables in the spectator view or return to your own table; your run remains loaded. A table in its shop shows its last board with a shopping status.
- Ending an unfinished match requires approval from every connected player. The host proposes returning to the lobby, and any player can cancel the proposal. Once all tables finish, the host can return directly. Seats stay assigned for the next ready-up. Native restart and menu buttons open this lobby flow.

## Multiplayer balls

Relay, Called Shot, Patience, Bounty, Bankroll, Lifeline, Encore, and Domino add team setups, pocket calls, bank-shot income, recovery, and combination shots. Matches start with Relay, Patience, and Bounty in the first three rack positions; shared shops rotate through all eight. See [ball effects and rules](docs/MULTIPLAYER_BALLS.md).

## Current limits

This is an experimental release; live Steam sessions, latency, and concurrent remote shopping still need playtesting.

- Standard runs only; daily challenges are unsupported.
- New players join between matches. A table host disconnecting ends that table; the room host leaving closes the lobby. Host migration is unsupported.
- Some transient effects and table-host audio are not mirrored. Local ball simulation uses corrections from the table host.
- A Steam game update may require a compatible mod update and reinstall.

## Uninstall

Run `Uninstall.ps1` from the installed mod folder. Saves and files not owned by the installer are preserved.

## Development

Run `Build-Package.ps1` to create the installation ZIP. See [tests/README.md](tests/README.md) for test setup and coverage. Game binaries and assets are supplied by each player's installed copy.

Run `Capture-Screens.cmd` to generate a gallery of the mod's screens without playing through a match. See the [screenshot harness](docs/screenshots.md) for fixtures and output files.

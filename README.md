# Ultrapool Together

Steam multiplayer for **2–8 players**. Share a table in co-op or compete across separate tables, each with its own board, shop, and run.

**Source version: v0.5.0** · Requires **Ultrapool 0.15.7**, Windows Steam build **25298901**. [Released builds](https://github.com/harsh2204/ultrapool-together/releases) may be older than this branch.

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
4. Choose the number of tables. Each player joins a table and selects **Ready up**.
5. The host selects **Start match** once everyone is ready and every table has a player.

Everyone must use v0.5 and a **UP5** room code. Changing seats or settings clears readiness.

## Match rules

- **One table:** co-op through a shared run, with shared money, inventory, and shop access.
- **Multiple tables:** independent runs with an equal shot budget per table—six by default, configurable from 1 to 20. Uneven groups such as 2v1 and 1v1v1v2 work the same way.
- Teammates take turns in seat order using the normal mouse or controller controls. **Pass** hands over the turn without spending a shot.
- Everyone at a table can shop and arrange items. Teammate cursors and aiming are visible on that table.
- Competing tables start with the same deck, difficulty, and seed. The highest score from completed shots wins; a run ending early also ends that table's match.
- Press **F8** for standings. The room host can end the match and return everyone to the lobby.

## Multiplayer balls

Relay, Called Shot, Patience, Bounty, Bankroll, Lifeline, Encore, and Domino add team setups, pocket calls, bank-shot income, recovery, and combination shots. Matches start with Relay, Patience, and Bounty in the first three rack positions; shared shops rotate through all eight. See [ball effects and rules](docs/MULTIPLAYER_BALLS.md).

## Current limits

This is an experimental release; gameplay and Steam multiplayer still need runtime verification.

- Standard runs only; daily challenges are unsupported.
- New players join between matches. A table host disconnecting ends that table; the room host leaving closes the lobby. Host migration is unsupported.
- Some transient effects and table-host audio are not mirrored. Local ball simulation uses corrections from the table host.
- A Steam game update may require a compatible mod update and reinstall.

## Uninstall

Run `Uninstall.ps1` from the installed mod folder. Saves and files not owned by the installer are preserved.

## Development

Run `Build-Package.ps1` to create the installation ZIP. See [tests/README.md](tests/README.md) for test setup and coverage. Game binaries and assets are supplied by each player's installed copy.

# Ultrapool Together

Steam multiplayer for **2–8 players**. Share a table in co-op, race other tables to the end of a run, or compete on score. Each table has its own board, shop, and run.

**Source version: v0.10.0** · Requires **Ultrapool 0.15.7**, Steam build **25298901**, on Windows or macOS. [Released builds](https://github.com/harsh2204/ultrapool-together/releases) may be older than this branch.

## Install

1. Every player needs their own copy of Ultrapool installed through Steam.
2. Download and extract the matching `UltrapoolTogether` installation ZIP.
3. Close the game. On Windows, run `Install.cmd`. On macOS, install [Python 3.9 or newer](https://www.python.org/downloads/macos/) if needed, then run `Install.command`.
4. Start `UltrapoolTogether/Launch.cmd` on Windows or `UltrapoolTogether/Launch.command` on macOS, inside the game's installation folder.

The installer creates a separate copy of the game, using about 400–500 MB. Your original Steam installation stays unchanged. Rerun the installer to update the mod.

On first install, your Steam progression, unlocks, settings, and customization are imported once. Existing mod progress is backed up in `%APPDATA%/UltrapoolTogether/save-import-backups/`. Later updates preserve mod progress; progress earned in the mod and the normal game stays separate. Original saves and unfinished solo runs are untouched.

On macOS, mod saves and progression backups are in `~/Library/Application Support/UltrapoolTogether/`. The installer copies the native app, adds the mod configuration inside the copy, and locally signs that copy using macOS's `codesign`. It retains the game's native Apple Silicon and Intel executables and Steam libraries. Launch through `Launch.command`, keep the installation in its original location, and rerun the installer after a Steam game update. Isolated installer tests and native macOS rendering/game-flow fixtures pass. Live Steam sessions and Windows/macOS multiplayer still need playtesting.

If Steam discovery fails, open Terminal in the extracted package and run:

```sh
bash Install.command --game-path "/path/to/Ultrapool.app"
```

Use `--destination "/path/to/UltrapoolTogether"` for a different mod folder, or `--dry-run` to check the installation without writing files. If an extracted `.command` file is not executable, run it with `bash` from Terminal.

To copy newer Steam progress after installation, close the normal game, then open the **Mod settings** gear at the mod's main menu → **Copy save from Steam** → **Back up and copy** → **Close**. No lobby is needed. This replaces mod progression and keeps a backup, your current settings, and unfinished runs. It reads the normal game's local save; it does not merge the two profiles. See [save copying and recovery](docs/SAVE_IMPORT.md).

## Play

1. Keep Steam running and open the mod on every computer before accepting invitations.
2. At the main menu, press **F8**, then **Create lobby**.
3. Invite friends from the in-game list or share the room code. The Steam overlay is optional.
4. The host chooses the number of tables. Vote for a **Starting set** using the shop's set cards and choose **Difficulty** from the buttons beside them. Player initials show live votes; hover for full names. A chalk check marks your vote, and a gold gem marks the current result. With multiple tables, everyone can also vote for **Race** or **Score PvP**.
5. Join a table and select **Ready up**. The host selects **Start match** once everyone is ready and every table has a player.

Everyone must use v0.10.0 and a **UP10** room code (protocol 10). Older versions cannot join these rooms. Changing seats, settings, or a vote clears readiness. Each connected player has one vote per choice; **No preference** abstains. The most votes wins, with ties resolved in the displayed option order. Without votes, the host's initial native selection applies. Choices use the host's unlocked standard sets and difficulties; every table receives the same frozen result and seed.

## Match rules

- **One table:** co-op through a shared run, with shared money, inventory, and shop access. Starting sets and shop offers use the native game balls.
- **Race:** the first table to successfully finish the full run wins. Tables share a seed, deck, and difficulty; there is no shot cap. Other tables can keep playing for their finishing place. The room host records finish order as results arrive, and elapsed time includes loading, shops, and pauses.
- **Score PvP:** independent runs with an equal shot budget per table—six by default, configurable from 1 to 20. The highest score from completed shots wins; a run ending early also ends that table's match. Uneven groups such as 2v1 and 1v1v1v2 work in either mode.
- Teammates take turns in seat order using the normal mouse or controller controls. **Pass** hands over the turn without spending a shot.
- Guests and spectators mirror native floor flowers, oil, fire, stoves, thorns and launchpads, plus wormhole visuals, energy projectiles and transient effects such as wisps, explosions and lightning. Use v0.10.0 on the host and clients. See the [effect coverage and verification record](docs/TABLE_EFFECTS.md).
- Everyone at a table can shop and arrange items with the game's native ball and snack dragging. Each connected teammate must select **Ready** before leaving the shop. Purchases, rearrangements, and membership changes clear shop readiness. Teammate cursors and aiming are visible on that table.
- Choose your own shop, snack-bar or mixer view by default. To follow the host's view automatically, open the **Mod settings** gear beside **Lobby · F8** and enable **Follow host shop view**. This personal choice persists; shared shopping remains available with it off.
- Each player sees the game's native round payout and selects **Continue** before shopping. Clients use the native shop, inventory, settings, and run results. Simple purchases, moves, sales, and Ready respond locally while the table host confirms them; rejected actions restore the shared state.
- Press **F8** for standings and **Watch** to spectate another table. Switch tables in the spectator view or return to your own table; your run remains loaded. A table in its shop shows its last board with a shopping status.
- Ending an unfinished match requires approval from every connected player. The host proposes returning to the lobby, and any player can cancel the proposal. Once all tables finish, the host can return directly. Seats stay assigned for the next ready-up. Native restart and menu buttons open this lobby flow.

## Multiplayer balls (opt-in)

The host can enable **Multiplayer balls** from the lobby's **Mod settings** gear (off by default). Relay, Called Shot, Patience, Bounty, Bankroll, Lifeline, Encore, and Domino never enter the starting rack; when enabled they appear only rarely in the shared shop. The native collection always includes a **Together** set with all eight balls, rarity and highlighted effect explanations, including when the option is off. See [ball effects and rules](docs/MULTIPLAYER_BALLS.md).

Six additional **expansion sets** (Phases, Morph, Tide, Relic, Tarot, Zodiac) use the same shop-only pattern. Open **Mod settings** in the lobby for Multiplayer balls, Clone-table rounds, **Shared shop access** (on by default), and an **Expansion sets** master toggle (default off) that reveals the six per-set toggles. Host rules lock at match start; personal view preferences remain available. See [expansion sets](docs/EXPANSION_SETS.md) and [shop access/view following](docs/SYNC_SHOP.md). **Status: implemented, unmeasured.**

## Custom cues

The host can disable **Cue shop** in the lobby’s **Mod settings** before starting a match (on by default). With it off, everyone uses House cues without perks, the cue counter is absent, and personal cosmetic finishes remain available. The choice locks for the run.

Visit the **Cue Workshop to the right of the snack bar** to browse fifteen distinct cues, preview ten free finishes, and buy or equip a personal cue. House is included; other cues cost 2–8€ from the shared run wallet, and last for that run. Reliable scoring perks cost more than handling preferences. Small handling changes or capped situational score perks add variety without extra shots or permanent upgrades. Finishes persist between runs, and teammates see the current shooter's cue. See the [full roster and balance rules](docs/CUSTOM_CUES.md). **Status: implemented, unmeasured.**

Rook runs the counter with upright cue racks, a short next/previous slide animation, and a felt-lined case displaying your equipped cue. Purple icon-only arrows follow the native shop pattern. The revised presentation has bounded Windows rendering and animation-capture coverage; live and cross-platform acceptance remains open.

The personal finish picker remains available in **Mod settings → Your starting cue finish**. Finishes are free cosmetic choices, are not host-locked, and persist in the mod's isolated user folder; owning a cue model never carries into a new run.

## Current limits

This source build is experimental; live Steam sessions, latency, and concurrent remote shopping still need playtesting.

- Standard runs only; daily challenges are unsupported.
- Start a new run when upgrading from a version with custom multiplayer balls. Those unfinished runs are unsupported; their save files are preserved.
- New players join between matches. A table host disconnecting ends that table; the room host leaving closes the lobby. Host migration is unsupported.
- Effect replication has explicit capacity limits and reports overflow while ordinary table updates continue. Native visual assets are mirrored; particle randomness and every native sound are not synchronized exactly. See the [client/spectator effect record](docs/TABLE_EFFECTS.md). Local ball simulation uses corrections from the table host.
- A Steam game update may require a compatible mod update and reinstall.

## Uninstall

Run `Uninstall.ps1` on Windows or `Uninstall.command` on macOS from the installed mod folder. Saves and files not owned by the installer are preserved.

## Development

Start with the [repository development skill](https://github.com/harsh2204/ultrapool-together/blob/main/.agents/skills/ultrapool-development/SKILL.md) for the native/mod code map, main game loop, shop/snack bar/mixer contracts, regression lessons, validation requirements, and a template for adding shop characters or content. It is also linked from [AGENTS.md](https://github.com/harsh2204/ultrapool-together/blob/main/AGENTS.md) for future contributors and agents.

Run `Build-Package.ps1` on Windows or `python3 Build-Package.py` on macOS to create the same installation ZIP for both platforms. See [tests/README.md](tests/README.md) for test setup and coverage. Game binaries and assets are supplied by each player's installed copy.

The [performance tracker](docs/PERFORMANCE.md) records identified networking, client rendering, and shop bottlenecks, implementation status, and the evidence still needed to verify improvements.

The [consumer distribution plan](docs/DISTRIBUTION.md) proposes graphical installation, Steam shortcuts, and on-demand updates, with a migration path and implementation tracker. These features are not yet available in released installers.

Run `Capture-Screens.cmd` on Windows or `bash Capture-Screens.command` on macOS to generate a gallery of the mod's screens without playing through a match. See the [screenshot harness](docs/screenshots.md) for fixtures and output files.

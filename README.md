# Ultrapool Together

Play Ultrapool with **2–8 players through Steam**. Share one table in co-op, race other teams to finish a run, or compete for the highest score.

**[Get started](https://harsh2204.github.io/ultrapool-together/get-started.html)** · **[Player guide](https://harsh2204.github.io/ultrapool-together/)** · **[Screenshots](https://harsh2204.github.io/ultrapool-together/gallery.html)**

Together is an unofficial mod and is still in development. Every player needs their own Steam copy of Ultrapool and the same compatible version of the mod.

Some features described here are not in the latest download yet. Check the supported Ultrapool version on the [download page](https://github.com/harsh2204/ultrapool-together/releases) before installing.

## Install

1. [Download](https://github.com/harsh2204/ultrapool-together/releases) and extract the matching `UltrapoolTogether` ZIP.
2. Close Ultrapool.
3. On **Windows**, run `Install.cmd`. On **macOS**, install [Python 3.9 or newer](https://www.python.org/downloads/macos/) if needed, then run `Install.command`.
4. Open `UltrapoolTogether/Launch.cmd` on Windows or `UltrapoolTogether/Launch.command` on macOS, inside the game's installation folder.

To find the installed folder, right-click Ultrapool in your Steam Library and choose **Manage → Browse local files**, then open **UltrapoolTogether**.

The mod uses a separate game copy, about 400–500 MB. Your normal game and saves stay untouched. Use the Together launcher to play the mod; use Steam as usual to play the original game.

To update, close the game and rerun the installer from the new download. Reinstall after a Steam game update once a compatible mod version is available.

## Start a game with friends

1. Keep Steam running and open Together on every computer.
2. At the main menu, press **F8 → Create lobby**.
3. Invite friends or share your room code.
4. Choose the number of tables. Vote for a starting set, difficulty, and match mode.
5. Join a table and select **Ready up**. The host selects **Start match** when everyone is ready.

Changing seats, settings, or votes clears readiness. New players can join between matches.

## Ways to play

| Mode | Goal |
| --- | --- |
| **Co-op** | Share one run, take turns, and build your table together. |
| **Race** | Be the first table to finish the full run. Other tables can keep playing for their finishing place. |
| **Score PvP** | Get the highest score within the same shot limit, six shots per table by default. |

Each table has its own board, shop, and run. Teams can have different numbers of players. Use the usual mouse or controller controls; **Pass** hands over your turn without spending a shot.

Between rounds, teammates share money and items. Everyone can shop and arrange the inventory, then everyone selects **Ready** to continue. You can browse a different counter from your teammates. To follow the table host's counter automatically, turn on **Follow host shop view** in Mod settings.

Press **F8 → Watch** to spectate another table. You can return to your own at any time.

## Optional upgrades

- **Custom cues:** visit the Cue Workshop to the right of the snack bar. Choose from fifteen cues and ten free finishes. Purchased cues last for the run; finishes carry over. [Cue guide](docs/content/custom-cues.md).
- **Multiplayer balls:** the host can enable eight special balls in Mod settings before starting. They appear in shops, not the starting rack. [Ball guide](docs/content/multiplayer-balls.md).
- **Expansion sets:** the host can enable six extra ball sets in Mod settings. These also add shop offers. [Expansion guide](docs/content/expansion-sets.md).

Multiplayer balls and expansion sets start off. The cue shop starts on. These options are fixed once the match begins.

## Your saves

The first installation copies your Steam unlocks, progression, settings, and customization into Together. After that, the two games keep separate progress.

To copy newer Steam progress later, close the normal game. In Together's main menu, open **Mod settings → Copy save from Steam → Back up and copy**. This replaces Together progression and keeps a backup. It does not merge the saves. [Saves and recovery](docs/content/save-import.md).

To uninstall on Windows, right-click `Uninstall.ps1` in the installed mod folder and choose **Run with PowerShell**. On macOS, open `Uninstall.command` there. Saves and files not owned by the installer are kept.

## Before you play

- Expect bugs. Online play, connection delays, and Windows/macOS sessions still need more testing.
- Standard runs are supported. Daily challenges and Creative multiplayer are not.
- If a table host disconnects, that table ends. If the room host leaves, the lobby closes.
- Start a new run after upgrading from a version with custom multiplayer balls. Older unfinished runs are kept but are not supported.
- To end an unfinished match, the host asks to return to the lobby and every connected player must agree.

[Compatibility and help](docs/content/compatibility.md) · [Report a problem](https://github.com/harsh2204/ultrapool-together/issues)

## Contributing

Current source: **v0.12.0**, protocol **12 / UP12**, targeting **Ultrapool 0.17.2** (Steam build **25727180**). Published packages may be older.

Start with the [development guide](.agents/skills/ultrapool-development/SKILL.md) and [agent rules](AGENTS.md). See [tests and coverage](tests/README.md), the [performance tracker](docs/PERFORMANCE.md), and [native compatibility](docs/NATIVE_COMPATIBILITY.md) for technical details and open work.

Build the installation ZIP with `Build-Package.ps1` on Windows or `python3 Build-Package.py` on macOS. Players supply the game files through their own Steam installation.

The [website guide](docs/README.md) covers local previews and GitHub Pages publishing. The [screenshot harness](docs/screenshots.md) covers gallery captures.

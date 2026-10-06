# Saves and progress

Together keeps its own saves. Your normal Steam game is left untouched.

The first installation copies your Steam progression, unlocks, settings, and customization. After that, progress earned in each game stays separate. Updating Together keeps your mod progress.

## Copy newer Steam progress

1. Let Steam finish syncing the normal game, then close it.
2. Open Together at the main menu, outside a lobby or run.
3. Choose **Mod settings → Copy save from Steam**.
4. Select **Back up and copy**.
5. After it finishes, select **Close** to refresh the menu.

This **replaces** your Together progress; it doesn’t combine progress from both games. A backup keeps your previous mod progress. Your current Together settings and unfinished runs are kept.

If no save is found, open the normal game first and let Steam finish syncing. Together reads the save on this computer.

## Find your backup

Backups are in the `save-import-backups` folder inside your Together save folder:

| System | Together save folder |
| --- | --- |
| Windows | `%APPDATA%\UltrapoolTogether\` |
| macOS | `~/Library/Application Support/UltrapoolTogether/` |

## Undo a copy

Close both games. Make a spare copy of your current Together save folder, and keep the backup folder intact.

Follow the [full recovery instructions](https://github.com/harsh2204/ultrapool-together/blob/main/docs/SAVE_IMPORT.md#recover-previous-mod-progress) to restore the backup’s progress and matching save records. These steps also cover an interrupted copy. Restore only into the Together save folder; leave the normal game’s saves alone.

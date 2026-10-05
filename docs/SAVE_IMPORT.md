# Copy Steam progress into the mod

At the mod's main menu, open the **Mod settings** gear beside **Lobby · F8**, select **Copy save from Steam**, then **Back up and copy**. After success, select **Close** to refresh the main menu. Creating or joining a lobby is unnecessary. Copying is available only at the main menu, outside a room or active run.

Let Steam finish syncing the normal game's save and close the normal game before copying. The mod reads the local Steam-synced profile on this computer. It does not download a save from Steam Cloud, select another account, or modify the normal game's save. A missing local save must first be created or synced through the normal game.

## What changes

This is a **replacement, not a merge**. Progression, unlocks, achievements, collection, statistics, and cosmetic customization from the normal game replace their mod equivalents. Mod-only progress acquired since the source save is retained in the backup, not combined with the imported progress. You can repeat the action later; each copy creates a new backup.

The mod keeps its current native settings, including display and audio settings, and its separate mod preferences. It also keeps local daily-session bookkeeping (`last_daily` and `daily_leaderboard_submitted`) and the local `full_game_unlocked` entitlement flag. Copying progress does not change entitlement.

Unfinished runs are untouched in both profiles. Neither `run_data.tres` nor `daily_data.tres` is imported, removed, or rewritten by this action. An existing saved solo run does not prevent copying from the main menu.

The installer still performs its separate, one-time import on first installation, which includes native settings. Later installer updates preserve mod progress. The manual action described here keeps the mod's current settings.

## Locations and backups

| Platform | Normal game's source | Mod profile |
| --- | --- | --- |
| Windows | `%APPDATA%\Godot\app_userdata\Ultrapool\save.tres` | `%APPDATA%\UltrapoolTogether\` |
| macOS | `~/Library/Application Support/Godot/app_userdata/Ultrapool/save.tres` | `~/Library/Application Support/UltrapoolTogether/` |

The source is checked before replacement. Missing, empty, oversized, unrecognized, or unsafe paths are rejected. Save files are limited to 8 MiB. The action runs synchronously after showing pending feedback, so copying may briefly pause menu updates; its duration has not been measured.

Each backup is stored under the mod profile at `save-import-backups/<timestamp>-<random-id>/`. A successful copy retains:

- `current-memory.tres`: the mod's progression immediately before copying, including changes newer than its last disk save.
- The previous `save.tres`, `save.bak.tres`, and `ultrapool-together-progress-import.json`, when each existed.
- `previous-files.json`: records which previous files existed and their hashes, plus the hash of `current-memory.tres`.

The new progression is written to both mod save files. The import marker records the source and backup location. The normal game's recovery file and both profiles' run files remain untouched.

## Recover previous mod progress

Close both the mod and the normal game before restoring files. First copy the current mod profile somewhere safe, and keep the import backup intact.

1. Open the backup for the copy you want to undo.
2. To recover the mod's most recent progress before that copy, copy `current-memory.tres` into the **mod profile** twice: once as `save.tres` and once as `save.bak.tres`.
3. Restore the backed-up `ultrapool-together-progress-import.json` if it existed. If `previous-files.json` records that it did not exist, remove the newly created marker from the mod profile.
4. Launch the mod and check the restored progress.

For an exact restoration of the previous disk state instead, restore the original `save.tres`, `save.bak.tres`, and marker from that backup. Follow `previous-files.json` for each file: restore it when `existed` is true, or remove the corresponding current file when false. That older disk state may omit progress captured by `current-memory.tres`.

Restore only into the mod profile. Leave `run_data.tres`, `daily_data.tres`, and mod preference files alone.

Observed replacement errors trigger rollback of the attempted files. If the action reports incomplete rollback, close the mod and restore the retained backup before playing. Multi-file replacement is **not guaranteed to be crash-atomic**, including on Windows, where an underlying rename can remove a destination before failing. Backups support manual recovery after an interruption; they do not guarantee automatic recovery from a crash or power loss.

## Verification status

**Implemented, unmeasured.** Static inspection and authored isolated fixtures cover the intended boundaries. Native-resource and menu fixtures are registered with the existing [screenshot harness](screenshots.md), but have not been run for this feature. Windows/macOS rendering, native save adoption, menu refresh, and timing remain to be verified. See [validation coverage](../tests/README.md) and PERF-026 / PERF-038 / GAP-004 in the [performance tracker](PERFORMANCE.md).

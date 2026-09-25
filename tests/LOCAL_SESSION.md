# Local two-window session

Same-computer host + guest over LAN loopback for manual co-op debugging. See [AGENTS.md](../AGENTS.md) before running anything that launches the game.

## What it proves

- Two real windowed `game.exe` processes on one PC
- ENet LAN on `127.0.0.1:24817` (not Steam lobbies / invites)
- Separate save profiles so the real install and Steam profile are untouched

It does **not** prove Steam invitations, multi-PC networking, or eight-player capacity.

## How to run

Close Ultrapool / Ultrapool Together first. From the repository root:

```powershell
.\Test-LocalSession.cmd
```

Or with an explicit install path:

```powershell
.\Test-LocalSession.cmd -GamePath "D:\SteamLibrary\steamapps\common\Ultrapool"
```

The launcher:

1. Refuses to start if a `game` process is already running or another local-session harness holds the mutex
2. Copies `game.exe`, `steam_api64.dll`, and `libgodotsteam.windows.template_release.x86_64.dll` into `.local/local-session/host` and `.local/local-session/guest` (outside the Steam install)
3. Writes per-role `override.cfg` with distinct `custom_user_dir_name` values and autoloads for the mod plus `tests/local_session_probe.gd`
4. Starts host with `--rendering-method gl_compatibility -- --host`, waits briefly, then starts guest with `-- --guest`

Both windows stay open for manual play. The probe opens the lobby after hosting/joining LAN; use seats, ready, and start as usual (F8 toggles the panel).

## How to close

Close both game windows (host and guest). That ends the processes. Isolated saves remain under `%AppData%\UltrapoolTogetherLocalSessionhost` and `%AppData%\UltrapoolTogetherLocalSessionguest`; delete those folders if you want a clean slate. Runtime copies under `.local/local-session/` are gitignored and safe to delete.

If a launch fails partway, the script stops any process it started. It does not kill windows you already closed yourself.

## Caveats

- The in-game F8 **Host** / **Join** buttons still target Steam. This harness connects via the probe's `host_lan` / `join_lan` calls. After leave, do not expect the Steam buttons to recreate the LAN room; re-run the harness instead.
- Uses the same UDP port (`24817`) as the automated `session_probe.gd`. Do not run both at once.
- Does not change display, driver, or GPU settings.
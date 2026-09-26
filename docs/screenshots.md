# Screenshot harness

The source checkout includes Windows and macOS runners for the same screenshot fixtures. Each runs one muted, isolated copy of the installed game, builds repeatable lobby, native starter, table, shop, race, vote, and spectator fixtures, and captures the game's rendered viewport into a local HTML gallery.

Close Ultrapool, then run from the source checkout. On Windows:

```powershell
.\Capture-Screens.cmd
```

On macOS, with Python 3.9 or later:

```sh
./Capture-Screens.command
```

Both runners find Ultrapool through Steam. To select an installation explicitly:

```powershell
.\Capture-Screens.cmd -GamePath "D:\SteamLibrary\steamapps\common\Ultrapool"
```

```sh
./Capture-Screens.command --game-path "/path/to/Ultrapool.app"
```

Open the `index.html` path printed when the run finishes. Each image has a description so interface changes can be reviewed without entering the game. Captures, logs, and `runner.json` are saved under `.local/screenshots/<run-id>/`, which is excluded from Git. `runner.json` records the renderer, process exit, probe result, and checks that the installed game files and normal saves stayed unchanged.

Optional arguments:

| Windows argument | macOS argument | Purpose |
| --- | --- | --- |
| `-OutputPath <directory>` | `--output-path <directory>` | Write to a new directory of your choice. Existing directories are rejected to preserve earlier captures. |
| `-TimeoutSeconds <seconds>` | `--timeout-seconds <seconds>` | Change the 180-second watchdog, within 30–300 seconds. |

The Windows runner reuses a local copy of the game's executable and Steam runtime DLLs in `.local/screenshot-runtime`, updating those copies when the installed files change. The macOS runner copies and signs the complete app into the operating system's per-user temporary directory, then removes that private runtime on completion or failure. Keeping the app outside synchronized Documents folders prevents file providers from reattaching metadata that invalidates signing. Captures remain in the selected output directory. The original app is never signed or modified. Each run uses a fresh `UltrapoolTogetherRenderTest-…` save profile, disables external integrations through the test bootstrap, and uses a 1280×720 compatibility-renderer viewport capped at 30 FPS. The runners refuse to start while another game process or screenshot harness is running and close their own process on failure, interruption, or timeout. They do not change display, driver, GPU, or system audio settings.

The macOS copy has background-only application metadata, noninteractive standard streams, and an unfocusable rendering surface with mouse passthrough. The runner requests minimization, but AppKit may report the surface as windowed; the request is not proof of a minimized or invisible surface. The test bootstrap forces viewport rendering without requesting a presentation swap. The audio driver is `Dummy`; the shared bootstrap and settings fixture also mute every game audio bus. `--headless` is deliberately not used because it selects a dummy renderer that cannot establish rendered screenshot correctness. `runner.json` records the requested window/audio/background settings separately from `native_environment`, the engine's reported window mode, focus flags, and frame cap. It also records the child PID and exit status, full original-app hashes, normal save-profile hashes before and after, and private-runtime cleanup. A missing native report is recorded as `null`, not inferred from the launch arguments. Background capture is a correctness fixture; its forced rendering cadence does not establish foreground gameplay performance.

The scenes use fixture players and multiplayer state. The same process also runs the vote, lobby, router, controller, transport-budget, shop-layout, and snapshot validation probes. Native starting sets and shop balls remain the game's own content. Spectator checks cover the native floor, table cosmetics, score and health HUD, pocket positions, interpolation, table switching, and isolation from the player's running game.

The round-flow fixture records the host's serialized controller messages across native payout, Continue, shopping, purchases, unanimous Ready, and the next round, then replays them through the client controller. It checks out-of-order phase updates, delayed purchase and Ready replies, rejected transactions, item reuse, native settings, and clean teardown. It also triggers native victory and defeat and compares client results and inventory with the host. These are native game transitions with fixture progression, not a played-through campaign. See the [game-loop coverage matrix](../tests/GAME_LOOP.md).

Shop interaction fixtures send mouse events to the native shop in an isolated viewport and capture host and client drags in progress. They exercise the real ball objects, slots, and drop handlers without moving the desktop pointer.

Screenshots exercise the real mod UI and native game rendering; they do not establish that Steam invitations, network latency, or a live multiplayer session work correctly. Review the images as well as the pass result: a successful script cannot judge every visual issue.

To extend coverage, add a scene setup and capture to `tests/render_probe.gd`. Keep fixtures repeatable, use the isolated profile, and leave process management to `Capture-Screens.ps1` or `Capture-Screens.py`. Only run the harness when runtime testing has been explicitly requested; ordinary development checks can continue using the static parser and isolated installer tests. The macOS runner's lifecycle tests use inert app files and a mocked child process: `python3 -m unittest discover -s tests -p capture_macos.py`. They validate isolation, exclusion, error handling, watchdog cleanup, and preservation checks without launching the game.

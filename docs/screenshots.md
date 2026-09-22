# Screenshot harness

The source checkout includes a screenshot harness for reviewing the mod without playing through a run. It opens one copy of the installed game, builds repeatable lobby, table, ball, shop, race, vote, and spectator fixtures, and captures the game's rendered viewport into a local HTML gallery.

Close Ultrapool, then run from the source checkout:

```powershell
.\Capture-Screens.cmd
```

The harness finds Ultrapool through Steam. To select an installation explicitly:

```powershell
.\Capture-Screens.cmd -GamePath "D:\SteamLibrary\steamapps\common\Ultrapool"
```

Open the `index.html` path printed when the run finishes. Each image has a description so interface changes can be reviewed without entering the game. Captures, logs, and `runner.json` are saved under `.local/screenshots/<run-id>/`, which is excluded from Git. `runner.json` records the renderer, process exit, probe result, and checks that the installed game files and normal saves stayed unchanged.

Optional arguments:

| Argument | Purpose |
| --- | --- |
| `-OutputPath <directory>` | Write to a new directory of your choice. Existing directories are rejected to preserve earlier captures. |
| `-TimeoutSeconds <seconds>` | Change the 180-second watchdog, within 30–300 seconds. |

The runner reuses a local copy of the game's executable and Steam runtime DLLs in `.local/screenshot-runtime`, updating those copies when the installed files change. Each run uses a fresh `UltrapoolTogetherRenderTest-…` save profile, disables external integrations through the test bootstrap, and runs windowed at 1280×720 with the compatibility renderer capped at 30 FPS. It refuses to start while another game process or screenshot harness is running and closes its own process on failure or timeout. It does not change display, driver, or GPU settings.

The scenes use fixture players and multiplayer state. The same process also runs the vote, lobby, router, controller, ball-rule, Bounty, and snapshot validation probes. Spectator checks cover the native floor, table cosmetics, score and health HUD, pocket positions, interpolation, table switching, and isolation from the player's running game.

The round-flow fixture records the host's serialized controller messages across native payout, Continue, shopping, purchases, unanimous Ready, and the next round, then replays them through the client controller. It checks out-of-order phase updates, delayed purchase and Ready replies, rejected transactions, item reuse, native settings, and clean teardown. It also triggers native victory and defeat and compares client results and inventory with the host. These are native game transitions with fixture progression, not a played-through campaign. See the [game-loop coverage matrix](../tests/GAME_LOOP.md).

Screenshots exercise the real mod UI and native game rendering; they do not establish that Steam invitations, network latency, or a live multiplayer session work correctly. Review the images as well as the pass result: a successful script cannot judge every visual issue.

To extend coverage, add a scene setup and capture to `tests/render_probe.gd`. Keep fixtures repeatable, use the isolated profile, and leave process management to `Capture-Screens.ps1`. Only run the harness when runtime testing has been explicitly requested; ordinary development checks can continue using the static parser and isolated installer tests.

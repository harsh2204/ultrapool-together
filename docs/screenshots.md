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

The scenes use fixture players and multiplayer state. The same process runs the snapshot and table-effects probes and fourteen model probes: team vote, lobby, cue finishes, UI navigation, expansion sets, multiplayer balls, presence, router, controller, transport budget, shop layout, cue models, cue inventory and cue effects. Each model must complete successfully, execute assertions and report no failures. Native starting sets and shop balls remain the game's own content. Spectator checks cover the native floor, table cosmetics, score and health HUD, pocket positions, interpolation, table switching, and isolation from the player's running game. See [table-effect coverage](TABLE_EFFECTS.md) for the shared guest/spectator descriptor contract and remaining acceptance.

Lobby fixtures exercise starting-set cards and difficulty buttons through the controller, including live voter identities, abstention, disconnects, frozen choices, and retained keyboard focus when remote votes arrive. Full-catalog and eight-player consensus captures check that all eight native set posters, five selectable difficulties, and voter badges fit at 1280×720. The full catalog is synthetic fixture coverage; real lobbies still use the host's unlocked choices. Each starting-set card is checked against the exact poster resource used in the native shop.

Difficulty-label checks obtain choices through the production run setup and compare every card, tooltip, accessible name and selected-result label with the native resource's translation or the explicit Together variant title. The full-catalog fixture substitutes only progression eligibility, preserving the production label path. English and an installed non-English locale are checked for complete visible text lines and a separate voter area; the original locale is restored without saving preferences. Registration and native Play-menu checks preserve the menu's parallel difficulty panels and indicators. Checking card rectangles alone would miss a clipped name.

Personal view fixtures exercise the HUD gear and settings checkbox callbacks, capture the slate with **Follow host shop view** off/on, and check in-match preferences alongside locked host rules. Following starts off; opting in follows the latest native snack/mixer section after counter movement settles. Turning it off clears deferred navigation while shared shopping remains active. F8, Escape and outside dismissal clear the settings input/navigation guard. The UI navigation model separately checks persisted preference defaults, malformed values, drag/pending deferral and unchanged transaction state inside the isolated profile.

The round-flow fixture records the host's serialized controller messages across native payout, Continue, shopping, purchases, unanimous Ready, and the next round, then replays them through the client controller. It checks out-of-order phase updates, delayed purchase and Ready replies, rejected transactions, item reuse, native settings, and clean teardown. It also triggers native victory and defeat and compares client results and inventory with the host. These are native game transitions with fixture progression, not a played-through campaign. See the [game-loop coverage matrix](../tests/GAME_LOOP.md).

Shop interaction fixtures send mouse events to the native shop in an isolated viewport and capture host and client drags in progress. They exercise the real ball objects, slots, and drop handlers without moving the desktop pointer.

The native aim fixture likewise moves the existing cue ball into an isolated input viewport, preserving and restoring its world, parent, transform and native resize bindings. It sends actual press/motion/release input through inherited player processing on host and guest, including cue fade/charge, off-turn and menu rejection. Its submission sink does not execute physics or real transport.

The pocket fixture calls native `spawn_hole`, captures its actual shared-array mutation, birth scale and growth, then replays the captured data on a guest. It also sends a real BLACK-HOLE ball through the native pocket sensor, suction and pot callback and checks the resulting dynamic hole. It checks native hole visuals, disabled guest gameplay, retained identity, authoritative removal and full resync. The supported engine represents native zero-scale assignment as a tiny nonzero transform; the fixture checks visually collapsed birth and exact host/guest state agreement.

Native table-effect fixtures create all six floor families, ENERGY-BALL and WORMHOLE state through native callbacks and replay their appearance and lifecycle into guests and spectators. A separate fixture captures representative explosions, tornado, lightning, constellation and ordinary/pocket wisps from the 34-definition native visual catalog. Assertions cover strict validation, scriptless rendering, host-selected textures, line/shader state, removal, resync and watcher switching. A synthetic 128-droplet burst checks bounded creation and cancellation by newer state and records frame/apply timings; these measurements do not establish live-network input latency. Both fixtures run inside the existing process and restore the baseline table before later tests.

The shop transaction fixture drives production `handle_request` against the already-open native host shop. It buys a snack, moves two ingredients into the cocktail bar, waits for the real bounded mix animation/completion, and collects the output. Ticket, item and score conservation, stale/replayed requests, insufficient tickets, invalid/occupied slots and busy rejection are checked. This is native local authority coverage; remote simultaneous snack/mixer transactions and interrupted close/reopen remain separate checks.

The cue-shop fixtures visit all five racks at the counter to the right of snacks and cover host/guest previews, purchases, equipment, pending/rejected confirmations, stale actions, retained focus/cards, and return navigation. The native cue fixture checks all fifteen textures on the real aiming sprite, including tip/shadow/fade preservation and House restoration. It stages bonus callbacks against a real native ball and pocket, then checks fractional scoring, caps, replay rejection, and the live-source GAMEBALL guard at the native score/HUD boundary. It does not fire a physical shot or pot that ball; temporary score, item, script, input, and achievement state are restored. The harness also embeds the cue catalog, inventory, and perk-rule probes. Authored scenarios count as verified only after their assertions pass in a capture run.

Screenshots exercise the real mod UI and native game rendering; they do not establish that Steam invitations, network latency, or a live multiplayer session work correctly. Review the images as well as the pass result: a successful script cannot judge every visual issue.

To extend coverage, add a scene setup and capture to `tests/render_probe.gd`. Keep fixtures repeatable, use the isolated profile, and leave process management to `Capture-Screens.ps1` or `Capture-Screens.py`. Only run the harness when runtime testing has been explicitly requested; ordinary development checks can continue using the static parser and isolated installer tests. The macOS runner's lifecycle tests use inert app files and a mocked child process: `python3 -m unittest discover -s tests -p capture_macos.py`. They validate isolation, exclusion, error handling, watchdog cleanup, and preservation checks without launching the game.

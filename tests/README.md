# Validation

**Local runtime tests are suspended after the 2026-09-20 GPU hang.** Do not execute the game or Godot commands below, including `--headless`, without explicit user authorization for that test. See [AGENTS.md](../AGENTS.md). The installer test below uses fake executable fixtures and does not start the game.

Run installer boundary tests with Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\installation.ps1
```

The Godot probes require your own installed Ultrapool 0.15.7. Make private test directories containing local copies of `game.exe`, `steam_api64.dll`, and `libgodotsteam.windows.template_release.x86_64.dll`. Keep test overrides away from your original game directory. Paths below are examples; replace the checkout prefix. Each probe verifies its save namespace before running.

For the adapter probe, use this `override.cfg` beside the private executable:

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="UltrapoolTogetherAdapterTest"

[autoload]
AdapterProbe="*C:/Code/ultrapool-multiplayer/tests/adapter_probe.gd"
```

After authorization, launch that executable from its own directory with `--headless`. The probe starts a real classic run and checks the native aiming hook, unchanged mouse/controller bindings, off-turn drag and precise-confirmation rejection, and preservation of cue-ball state. It then shoots the cue, checks shot consumption and settling, exercises round-end cash-out and a paused result popup, and verifies restoration of the original player script. It prints `ADAPTER_PROBE_PASS` and exits 0 on success.

See [TRANSPORT.md](TRANSPORT.md) for the network probe, including the optional Steam room check.

The packet-validation probe uses the same isolated-runtime setup with save namespace `UltrapoolTogetherSnapshotTest` and autoload `SnapshotProbe="*C:/Code/ultrapool-multiplayer/tests/snapshot_probe.gd"`. It covers malformed values, duplicate identities, resource-path injection, base pockets and dynamic holes; it remains unrun under the same runtime restriction.

For the complete session test, create two separate private runtime directories with these overrides:

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="UltrapoolTogetherSessionTesthost"

[autoload]
UltrapoolTogether="*C:/Code/ultrapool-multiplayer/mod/main.gd"
SessionProbe="*C:/Code/ultrapool-multiplayer/tests/session_probe.gd"
```

Use `UltrapoolTogetherSessionTestguest` for the second directory's save namespace. After authorization for this two-process test, start the first executable with `--rendering-method gl_compatibility -- --host` and the second with `--rendering-method gl_compatibility -- --guest`. The test opens localhost UDP port 24817. Capture stdout and stderr and wait for both processes to finish. Both must print `SESSION_PROBE_PASS` and exit 0.

The v0.2 session test starts a real game, passes turns in co-op, verifies the native controls are disabled off-turn and while the multiplayer panel is open, and rejects invalid/stale/duplicate shots. It seeds the PvP counters at four shots each and submits each player's last shot through the native player hook. The guest checks that its local table stays frozen, shot intents apply no local impulse, and successive host snapshots are acknowledged. Disconnect checks cover restoration of the host player script and the guest's original menu, camera, and input bindings. The probe does not capture screenshots. It does not cover a ten-shot full-run playthrough or a remote Internet connection.

The v0.2 native-control and replica changes have only been checked statically while runtime testing is suspended. Earlier v0.1 runtime results do not validate these changes.

Startup/exit warnings from the original executable (pre-tree node lookup and leaked rendering objects) also occur in the unmodded baseline; test success is determined by the explicit pass markers, exit codes, and absence of mod script errors. Release templates ignore `--script`; the probes use autoload overrides instead.

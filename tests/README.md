# Validation

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

Launch that executable from its own directory with `--headless`. The probe starts a real classic run, shoots the cue, checks shot consumption, waits for physics, exercises real round-end cash-out and a paused result popup, and verifies restoration of native input. It prints `ADAPTER_PROBE_PASS` and exits 0 on success.

See [TRANSPORT.md](TRANSPORT.md) for the network probe, including the optional Steam room check.

For the complete session test, create two separate private runtime directories with these overrides:

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="UltrapoolTogetherSessionTesthost"

[autoload]
UltrapoolTogether="*C:/Code/ultrapool-multiplayer/mod/main.gd"
SessionProbe="*C:/Code/ultrapool-multiplayer/tests/session_probe.gd"
```

Use `UltrapoolTogetherSessionTestguest` for the second directory's save namespace. Start the first executable with `--rendering-method gl_compatibility -- --host` and the second with `--rendering-method gl_compatibility -- --guest`. The test opens localhost UDP port 24817. Capture stdout and stderr and wait for both processes to finish. Both must print `SESSION_PROBE_PASS` and exit 0.

The session test starts a real game, passes turns in co-op, tests invalid/stale/duplicate shots, then seeds the PvP counters at four shots each and plays each player's last shot over the network. It verifies match results on both clients, video decoding, and disconnect recovery. Screenshots are saved under `.local/host-session.png` and `.local/guest-session.png`. This test is not a ten-shot full-run playthrough or a remote Internet test.

Startup/exit warnings from the original executable (pre-tree node lookup and leaked rendering objects) also occur in the unmodded baseline; test success is determined by the explicit pass markers, exit codes, and absence of mod script errors. Release templates ignore `--script`; the probes use autoload overrides instead.

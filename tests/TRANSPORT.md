# Transport runtime test

Use a private test copy of ULTRAPOOL 0.15.7's `game.exe`, `steam_api64.dll`, and `libgodotsteam.windows.template_release.x86_64.dll`. Do not put the test override in the normal game installation. Add this `override.cfg` beside the test executable, replacing the autoload path with this checkout's absolute path (use forward slashes):

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="UltrapoolTogetherTransportTest"

[autoload]
TogetherTransportTest="*C:/path/to/ultrapool-multiplayer/tests/transport_probe.gd"
```

Run the executable from that test directory with `--headless`. Capture standard output and standard error; the game's log file can remain buffered during native failures. The probe exits with code 0 and prints `TRANSPORT TEST COMPLETE PASS` on success. It opens UDP port 47657 on the local machine and connects two transport instances through loopback.

The probe covers random room tokens, two-way authentication, input and a 300 KB frame, disconnect/rejoin, wrong tokens, malformed messages, and invalid Steam room codes. It uses an isolated save directory and disables game analytics and cloud save handling during the test.

To also check Steam initialization and room-code creation, start Steam, put a `steam_appid.txt` containing `4195110` beside the test executable, and run with `--headless -- --steam`. This creates only a local room code and immediately closes the transport; it does not contact another player. A real Steam connection still requires a second account with the game and another machine.

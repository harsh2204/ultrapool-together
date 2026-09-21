# Transport runtime test

**Runtime testing is suspended on this PC.** Follow the restriction in [AGENTS.md](../AGENTS.md) before executing any command below, including `--headless`.

Use a private test copy of ULTRAPOOL 0.15.7's `game.exe`, `steam_api64.dll`, and `libgodotsteam.windows.template_release.x86_64.dll`. Do not put the test override in the normal game installation. Add this `override.cfg` beside the test executable, replacing the autoload path with this checkout's absolute path (use forward slashes):

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="UltrapoolTogetherTransportTest"

[autoload]
TogetherTransportTest="*C:/path/to/ultrapool-multiplayer/tests/transport_probe.gd"
```

Run the executable from that test directory with `--headless`. Capture standard output and standard error; the game's log file can remain buffered during native failures. The probe exits with code 0 and prints `TRANSPORT TEST COMPLETE PASS` on success. It opens UDP port 47657 on the local machine and connects two transport instances through loopback.

The probe covers random room tokens, two-way authentication, input and a 200 KB snapshot, the 256 KiB wire-packet limit, disconnect/rejoin, wrong tokens, malformed messages, invalid or obsolete Steam room codes, and keeping the current connection when another invite is accepted. It uses an isolated save directory and disables game analytics and cloud save handling during the test. ENet is an internal loopback test helper; players connect through Steam.

When a Steam runtime test is explicitly authorized, put a `steam_appid.txt` containing `4195110` beside the test executable and use `--headless -- --steam`. This creates a real friends-only, two-player Steam lobby, waits for its callback, checks its metadata, and leaves it. It contacts Steam and may briefly appear to friends. It does not invite another player or open the overlay. A real Steam connection requires a second account with the game and another machine.

The revised lobby flow has not been run on this PC. Future two-machine checks should cover accepting an invite, full-room rejection, guest departure and rejoin, host departure, cancelling a room request before its callback, and accepting another invite after leaving. Both players should open the installed `UltrapoolTogether/Launch.cmd` before accepting an invite: Steam normally launches the original game executable for an invite accepted while the game is closed.

GodotSteam exposes Steam's `GameLobbyJoinRequested_t` callback as `join_requested(lobby_id, steam_id)`. The transport also uses `lobby_created(result, lobby_id)`, `lobby_joined(lobby_id, permissions, locked, response)`, and `lobby_chat_update(lobby_id, changed_id, making_change_id, state)`. It preserves these bindings after `close()` so another invite works. A pending create/join must finish before another request can start; a cancelled request's successful callback leaves its lobby. Lobby metadata includes the mod ID, protocol, game version, host Steam ID, and random handshake token. Both invite and `UP2-<lobbyID>` code paths join and validate that lobby before exchanging gameplay messages.

API references: [GodotSteam source](https://github.com/GodotSteam/GodotSteam/blob/master/godotsteam.cpp), [Steam matchmaking](https://partner.steamgames.com/doc/api/ISteamMatchmaking), and [Steam invite overlay](https://partner.steamgames.com/doc/api/ISteamFriends#ActivateGameOverlayInviteDialog).

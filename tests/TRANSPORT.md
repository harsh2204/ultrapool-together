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

Run the executable from that test directory with `--headless`. Capture standard output and standard error; the game's log file can remain buffered during native failures. The probe exits with code 0 and prints `TRANSPORT TEST COMPLETE PASS` on success. It opens UDP port 47657 on the local machine and connects one coordinator plus seven guest transport instances through loopback. A ninth participant is refused.

The protocol 4 probe covers independent handshakes and membership for eight players, verified sender identities, addressed replies, broadcasts, transient relay excluding the sender, and coexistence of reliable and unreliable traffic. It checks that one departure or malformed packet does not disconnect other players, closed rooms reject new joins, reconnecting identities receive a fresh session, and delayed old hellos/data cannot replace it. It also covers random room tokens, a targeted 200 KB message, the 256 KiB wire-packet limit, wrong tokens, invalid or obsolete Steam room codes, and preserving the current connection when another invite is accepted. The revised probe has been authored and parsed but has not been run. It uses an isolated save directory and disables game analytics and cloud save handling during the test. ENet is an internal loopback test helper; players connect through Steam.

When a Steam runtime test is explicitly authorized, put a `steam_appid.txt` containing `4195110` beside the test executable and use `--headless -- --steam`. This creates a real friends-only, eight-player Steam lobby, waits for its callback, checks its metadata, and leaves it. It contacts Steam and may briefly appear to friends. It does not invite another player or open the overlay. A real Steam connection requires a second account with the game and another machine.

The revised lobby flow has not been playtested across Steam accounts. Future multi-PC checks should cover selecting an online friend and accepting the direct invitation with the overlay disabled, joining through a room code, full-room rejection, one guest departing while others keep playing, reserved guest rejoin, coordinator departure, cancelling a room request before its callback, and accepting another invite after leaving. All players should open the installed `UltrapoolTogether/Launch.cmd` before accepting an invite: Steam normally launches the original game executable for an invite accepted while the game is closed.

GodotSteam exposes Steam's `GameLobbyJoinRequested_t` callback as `join_requested(lobby_id, steam_id)`. The transport also uses `lobby_created(result, lobby_id)`, `lobby_joined(lobby_id, permissions, locked, response)`, and `lobby_chat_update(lobby_id, changed_id, making_change_id, state)`. It preserves these bindings after `close()` so another invite works. A pending create/join must finish before another request can start; a cancelled request's successful callback leaves its lobby. Lobby metadata includes the mod ID, protocol, game version, coordinator Steam ID, and random room token. Each connection uses a fresh client nonce and coordinator-issued session ID through hello/welcome/ready; later membership, data, and heartbeat frames must match that session. A peer joining or leaving does not restart the coordinator session. Both invite and `UP4-<lobbyID>` code paths join and validate that lobby before exchanging gameplay messages. Channel 47 carries reliable actions and settled state; channel 48 carries disposable cursor and table updates. ENet uses channels 0 and 1 respectively.

API references: [GodotSteam source](https://github.com/GodotSteam/GodotSteam/blob/master/godotsteam.cpp), [Steam matchmaking](https://partner.steamgames.com/doc/api/ISteamMatchmaking), and [direct lobby invitations](https://partner.steamgames.com/doc/api/ISteamMatchmaking#InviteUserToLobby).

The separate `controller_probe.gd` regression probe invokes the actual controller, lobby model, and table router with off-tree service substitutes. It covers teardown after transport identity is cleared, match generations when changing rooms, terminal table-leader reconnects, a run disappearing during a pending shot, and targeted shop synchronization preserving the broadcast cache. It creates no native game scenes or network connections, but executing it still requires authorization under the runtime restriction. It is a standalone SceneTree script and prints `CONTROLLER_PROBE PASS` with exit code 0 on success; source parsing alone does not validate its runtime behavior.

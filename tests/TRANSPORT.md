# Transport runtime test

See [test setup](README.md) and the [runtime testing policy](../AGENTS.md) before running these probes.

Use a private test copy of ULTRAPOOL 0.15.7's `game.exe`, `steam_api64.dll`, and `libgodotsteam.windows.template_release.x86_64.dll`. Do not put the test override in the normal game installation. Add this `override.cfg` beside the test executable, replacing the autoload path with this checkout's absolute path (use forward slashes):

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="UltrapoolTogetherTransportTest"

[autoload]
TogetherTransportTest="*C:/path/to/ultrapool-multiplayer/tests/transport_probe.gd"
```

Run the executable from that test directory with `--headless`. Capture standard output and standard error; the game's log file can remain buffered during native failures. The probe exits with code 0 and prints `TRANSPORT TEST COMPLETE PASS` on success. It opens UDP port 47657 on the local machine and connects one coordinator plus seven guest transport instances through loopback. A ninth participant is refused.

The protocol 8 probe covers independent handshakes and membership for eight players, verified sender identities, addressed replies, broadcasts, transient relay excluding the sender, and coexistence of reliable and unreliable traffic. It checks that one departure or malformed packet does not disconnect other players, closed rooms reject new joins, reconnecting identities receive a fresh session, and delayed old hellos/data cannot replace it. It also covers random room tokens, a targeted 200 KB message, the 256 KiB wire-packet limit, wrong tokens, invalid or obsolete Steam room codes, and preserving the current connection when another invite is accepted. The revised probe has been authored and parsed but has not been run. It uses an isolated save directory and disables game analytics and cloud save handling during the test. ENet is an internal loopback test helper; players connect through Steam.

When a Steam runtime test is explicitly authorized, put a `steam_appid.txt` containing `4195110` beside the test executable and use `--headless -- --steam`. This creates a real friends-only, eight-player Steam lobby, waits for its callback, checks its metadata, and leaves it. It contacts Steam and may briefly appear to friends. It does not invite another player or open the overlay. A real Steam connection requires a second account with the game and another machine.

The revised lobby flow has not been playtested across Steam accounts. Future multi-PC checks should cover selecting an online friend and accepting the direct invitation with the overlay disabled, joining through a room code, full-room rejection, one guest departing while others keep playing, reserved guest rejoin, coordinator departure, cancelling a room request before its callback, and accepting another invite after leaving. All players should open the installed `UltrapoolTogether/Launch.cmd` before accepting an invite: Steam normally launches the original game executable for an invite accepted while the game is closed.

GodotSteam exposes Steam's `GameLobbyJoinRequested_t` callback as `join_requested(lobby_id, steam_id)`. The transport also uses `lobby_created(result, lobby_id)`, `lobby_joined(lobby_id, permissions, locked, response)`, and `lobby_chat_update(lobby_id, changed_id, making_change_id, state)`. It preserves these bindings after `close()` so another invite works. A pending create/join must finish before another request can start; a cancelled request's successful callback leaves its lobby. Lobby metadata includes the mod ID, protocol, game version, coordinator Steam ID, and random room token. Each connection uses a fresh client nonce and coordinator-issued session ID through hello/welcome/ready; later membership, data, and heartbeat frames must match that session. A peer joining or leaving does not restart the coordinator session. Both invite and `UP8-<lobbyID>` code paths join and validate that lobby before exchanging gameplay messages. Channel 47 carries reliable actions and settled state; channel 48 carries disposable cursor and table updates. ENet uses channels 0 and 1 respectively.

API references: [GodotSteam source](https://github.com/GodotSteam/GodotSteam/blob/master/godotsteam.cpp), [Steam matchmaking](https://partner.steamgames.com/doc/api/ISteamMatchmaking), and [direct lobby invitations](https://partner.steamgames.com/doc/api/ISteamMatchmaking#InviteUserToLobby).

The standalone `controller_probe.gd` tests controller teardown, match generations, table-leader reconnects, runs closing during a shot, and targeted shop synchronization. It uses service substitutes without native scenes or network connections and prints `CONTROLLER_PROBE PASS` with exit code 0 on success.

## Receive budgets

Transport receive dispatch stops between messages after 2,000 microseconds, 32 packets, or 256 KiB in one frame. These are code constants in `mod/transport.gd`; the time measurement includes deserialization and synchronous `received` signal handlers. The first message always runs to keep large reliable snapshots moving. A complete message may cross the time or byte boundary, so these are soft limits, not a guarantee that every frame meets its rendering deadline. The `receive_stats` property returns the latest frame's packet and byte counts, elapsed dispatch time, maximum single-handler time, and whether a budget was reached. It does not measure native polling/callbacks, rendering, or all game work, and `budget_reached` alone does not establish a backlog.

Steam fetches one message at a time, keeping unread reliable messages in Steam's queue when the budget runs out. A persistent three-reliable-to-one-transient schedule favors actions and handshakes while giving transient updates a turn across frame boundaries. Empty channels immediately yield to the other channel. ENet retains its shared receive FIFO because its API does not select an incoming channel. Neither path adds an application queue or drops accepted reliable messages. Native queue growth under sustained overload, same-channel head-of-line blocking, large individual handlers, and native `poll`/`run_callbacks` costs still require measurement; lowering receive work can increase update latency under overload.

`transport_budget_probe.gd` is an additional standalone `SceneTree` probe for a separately authorized Godot test session with an isolated project, matching the standalone setup in [README.md](README.md). It substitutes Steam and packet handlers, opens no network connection, and creates no game scenes. It checks bounded frame packet counts, retained reliable messages across budget exits, per-channel order, persistent channel fairness, empty-channel fallback, byte limits, and the time-budget progress rule. Success is `TRANSPORT_BUDGET_PROBE PASS` with exit code 0. It has been parsed but not executed; it does not validate real Steam queues or frame times.

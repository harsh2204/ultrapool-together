# Ultrapool Together

A standalone, experimental two-player mod for **Ultrapool 0.15.7**, tested against Windows Steam build **25298901**. Co-op comes first; a shared-table PvP score mode is included.

The host runs the real game, including its physics, ball effects, shop, and progression. The guest receives a live image of that table and submits shots. This is a lightweight shared-screen multiplayer implementation, with an aim/power interface added to the game. It does not run a second synchronized simulation.

## Install and launch

1. Both players install their own copy of Ultrapool through Steam.
2. Extract `UltrapoolTogether.zip` and double-click `Install.cmd`.
3. The installer finds the Steam installation and creates an `UltrapoolTogether` subfolder. Open **`UltrapoolTogether/Launch.cmd`** to play the mod.

For a nonstandard Steam location:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Ultrapool"
```

Installation needs approximately **400 MB** because it makes a local copy of the installed game executable and its two DLLs. The download contains only original mod code and installation scripts; each player supplies their own game files. No separate engine, mod loader, account, or hosted server is required.

The original game executable and Steam launch remain unchanged. The mod uses its own save profile at `%APPDATA%\UltrapoolTogether`; it starts fresh and does not copy or overwrite your single-player progress. Rerun the installer to update the mod. The copied runtime does not update automatically when Steam updates the original game; this release accepts game version 0.15.7 only.

## Online co-op

1. Keep Steam running on both PCs and start the mod on both.
2. The host chooses **Co-op** and **Host Steam room** in the connection panel.
3. Click **Copy room code** and share it privately with your partner.
4. The guest pastes the code and clicks **Join Steam room**.
5. The host starts or continues a **normal run** through the game's menus.
6. On your turn, move the mod's **Aim** and **Power** sliders and click **Take shot**. The mint arrow shows the direction. Aim 0° points right, −90° points up; power ranges from 26% to 100%.

Turns alternate after the shot and its effects settle. **Pass turn** hands a co-op turn to your partner. The host manages the menus, shared build, shopping, and round progression using the original game UI. The guest's own game is suspended while connected. Press **F8** to show or hide the connection panel.

The two players share one run and one score. They do not each control a separate cue ball. The guest has video and shot control; audio plays on the host only. The stream targets 10 frames per second, up to 1280×800, with only one image in flight to limit delay. The original simulation still runs at the game's normal rate.

**Steam support status:** initialization and room creation have passed on the installed Steam build. An actual session between two separate Steam accounts and PCs has not yet been verified. Two complete game processes have passed the LAN session test, including real shots and streamed video. Treat this as a first playable alpha.

## LAN / VPN fallback

In the connection panel, choose a shared password of at least eight characters. The host selects **Host LAN / VPN**. The guest enters the host's LAN or VPN IP, enters the same password, and selects **Join LAN / VPN**.

This uses **UDP port 24816**. Allow the modded game through Windows Firewall if prompted. A remote friend needs a reachable host through a shared VPN or a forwarded UDP port. The installer does not change firewall or router settings. Use this direct-IP mode on a trusted LAN/VPN; its password handshake is not an encrypted transport.

## PvP score battle

The host selects **PvP** before opening the room. Both players use the same table/build and alternate shots. Points gained by each shot are credited to that player, including the final score before the game converts it to money at round end. **Five shots per player** completes the match; the higher total wins and equal totals draw.

This is a score battle using Ultrapool's existing rules, not an eight-ball rules conversion. Shops and round changes stay host-controlled. If a run ends before ten shots, the host can start another normal run to finish the match, or use **Start score match** on a ready table to reset the score battle. Scores are session-local; disconnecting and reconnecting starts a new match scoreboard. The shared game run remains on the host.

## Disconnect and remove

Click **Disconnect** to restore local controls. The host can continue the current run alone. The guest returns to their own local game. A host that remains in a waiting room can accept a reconnect; creating a new room produces a new Steam code.

To uninstall, run the installed `Uninstall.ps1`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\SteamLibrary\steamapps\common\Ultrapool\UltrapoolTogether\Uninstall.ps1"
```

It removes only files recorded by the installer and retains saves and any unrecognized files. Launch the original game from Steam for ordinary single-player play.

## Development and verification

- `mod/main.gd`: connection UI, turn ownership, score battle, host frame capture, guest display, bounded shot requests.
- `mod/game_adapter.gd`: runtime access to the existing game, validated cue shots, settlement and round-score snapshots, temporary native shot binding changes.
- `mod/transport.gd`: Steam NetworkingMessages or ENet, version/password handshake, one guest, timeouts, reconnects, object-free message decoding.
- `Install.ps1`, `Uninstall.ps1`: isolated installation with a manifest of owned files.
- `Build-Package.ps1`: produces `dist/UltrapoolTogether.zip` from an explicit mod-only allowlist.
- `tests/`: real-game adapter, network, two-process session, and installer probes. See `tests/README.md`.

The runtime uses a small external autoload through Godot's `override.cfg`. No binary patching, recovered game scripts, or game assets are included in the source or release. Private investigation files and local runtime copies live under the ignored `.local/` directory.

Verified locally: real cue movement and shot consumption; invalid and duplicate shot rejection; turn handoff; co-op passing; PvP completion; round-end score cash-out; paused result screens; two-process video decode/acknowledgment; disconnect control restoration; network authentication and reconnect; installer update/uninstall boundaries. Remote Steam play, long runs with every ball combination, audio streaming, guest shop interaction, and daily challenges are outside the validated scope of this release.

Transport references: [Godot ENetMultiplayerPeer](https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html), [Steam NetworkingMessages](https://partner.steamgames.com/doc/api/ISteamNetworkingMessages), [GodotSteam implementation](https://codeberg.org/godotsteam/godotsteam/src/branch/godot4/godotsteam.cpp).

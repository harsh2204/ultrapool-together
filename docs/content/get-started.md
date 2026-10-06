# Get started

You’ll need your own copy of Ultrapool on Steam and friends with the same Together version. The mod supports Windows and macOS and needs about **400–500 MB** of free space.

[Download Together v0.12.0](https://github.com/harsh2204/ultrapool-together/releases/tag/v0.12.0)

**Together v0.12.0 requires Ultrapool 0.17.2.** Everyone in your group should install the same release. If Steam updates Ultrapool, check for a compatible Together update before reinstalling.

## Windows

1. Download and extract the **UltrapoolTogether** ZIP.
2. Close Ultrapool, then run **Install.cmd** from the extracted folder.
3. In Steam, right-click **Ultrapool → Manage → Browse local files**. Open the **UltrapoolTogether** folder, then **Launch.cmd**.

## macOS

1. Install [Python 3.9 or newer](https://www.python.org/downloads/macos/) if you don’t already have it.
2. Download and extract the **UltrapoolTogether** ZIP.
3. Close Ultrapool, then run **Install.command**.
4. In Steam, right-click **Ultrapool → Manage → Browse local files**. Open the **UltrapoolTogether** folder, then **Launch.command**.

Keep the installed mod in the same location.

<details>
<summary>A macOS command file won’t open</summary>
<p>Open Terminal and type <code>bash </code>, including the space. Drag the command file into the Terminal window, then press Return.</p>
</details>

<details>
<summary>The installer can’t find my game</summary>
<p>Open Terminal or Command Prompt in the extracted package folder. Use the command for your system, replacing the example path with your game’s location.</p>
<p>Windows:</p>
<pre><code>Install.cmd -GamePath "C:\SteamLibrary\steamapps\common\Ultrapool"</code></pre>
<p>macOS:</p>
<pre><code>bash Install.command --game-path "/path/to/Ultrapool.app"</code></pre>
</details>

## Invite your friends

Keep Steam running and open Together on every computer. Press **F8 → Create lobby**, then invite friends or share your room code. [How to play together](play.md).

## Saves and updates

Together makes a separate copy of the game and imports your Steam progress on first install. Your normal game stays untouched. Progress earned afterward stays separate. [Copying saves](save-import.md).

To update, close the game and rerun the new installer. Start a fresh run after an update.

To uninstall, open the installed mod folder. On Windows, right-click **Uninstall.ps1 → Run with PowerShell**. On macOS, open **Uninstall.command**. Your saves are kept.

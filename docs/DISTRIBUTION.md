# Consumer installation, Steam access, and updates

**Status: proposed; not implemented.** The current installation instructions remain in [README.md](../README.md). This plan adds a graphical launcher and versioned updates while retaining the existing installer ownership rules and separate saves.

## Recommended experience

Download **Ultrapool Together** once as a Windows application or macOS application. Open it, confirm the detected Steam installation, and select **Install**. Existing installations instead offer **Update existing installation** at their recorded location. A folder picker handles custom locations without terminal commands.

After installation, the launcher presents **Play**, the installed version, **Check for updates**, **Repair**, and **Add to Steam**. An available update displays its version, compatibility, and release notes with an **Update** button. Check automatically when the launcher opens, with bounded asynchronous requests; keep Play available while checking and when offline. Applying an update requires the game to be closed. Automatic installation can be a later opt-in feature.

The Steam library entry uses a stable installed launcher path and remains valid across updates. The launcher starts the private game copy with the correct working directory and Steam AppID. Neither launching nor updating requires Git, a separately installed Python interpreter, or a terminal window.

## Delivery choices

| Approach | Consumer experience | Engineering cost / tradeoff | Recommendation |
| --- | --- | --- | --- |
| Download a graphical installer for each release | Download, open, select Update; installed folder is discovered automatically. | Smallest first release; repeated manual downloads remain. | Useful first milestone and permanent recovery path. |
| Graphical launcher with on-demand updater | Install once; later click Update. Play remains available offline. | Requires a release feed, staging, rollback, and launcher packaging on both platforms. | Recommended target. |
| Automatically install before every launch | Usually current without an extra click. | Can delay a session or split friends across incompatible releases; needs stronger recovery and channel controls. | Offer only as an explicit preference after on-demand updating is proven. |
| Download the current development branch | Immediate access to every pushed change. | Unreviewed intermediate states and no stable package identity or compatibility promise. | Keep source workflows for development. Consumer updates follow published releases. |

## Steam shortcut

Valve supports adding a non-Steam game to the library, but that shortcut does not provide Steam updates for the mod. Use **Add to Steam** to guide the user through Steam's own add dialog and show/copy the installed launch target. A URI can be a best-effort convenience; retain **Games → Add a Non-Steam Game** as the supported fallback. Do not report a shortcut as installed merely because the dialog opened. [Valve support](https://help.steampowered.com/en/faqs/view/4B8B-9697-2338-40EC)

| Platform / action | Required behavior | Acceptance |
| --- | --- | --- |
| Windows | Provide a clearly named installed launcher executable. Its child is the existing private `game.exe`, with the mod installation root as working directory. | Steam and desktop launches select the same mod installation and preserve its saves. No command window. |
| macOS | Provide a clearly named `Ultrapool Together.app`. Its child is the copied `Ultrapool.app/Contents/MacOS/Ultrapool`, with that `Contents/MacOS` directory as working directory. | Finder and Steam launches select the mod, with no Terminal or Python prerequisite. Test Apple Silicon and Intel builds. |
| Steam identity | Keep the existing `steam_appid.txt` containing `4195110` beside the child executable and set its working directory explicitly. | The native Steam API initializes for Ultrapool and multiplayer works when started through the shortcut. This needs an authorized live Steam check. |
| Repeated updates | Keep the launcher's installed target stable; ordinary mod updates do not rewrite Steam configuration. | An existing shortcut continues to launch after update and rollback. |
| Multiple installations | Show the installation being managed and let the user pick another valid marker through a folder dialog. | Updating one installation never redirects another shortcut or touches another profile. |

Valve documents that `steam_appid.txt` overrides the AppID supplied by Steam and is searched relative to the current working directory. Launching the native executable with the wrong directory can therefore break Steam initialization. [Steamworks initialization](https://partner.steamgames.com/doc/sdk/api)

Fully automatic shortcut registration is a separate enhancement. It requires editing Steam's binary `shortcuts.vdf`, selecting the intended account, preserving existing IDs and customizations, backing up the file, and refusing to write while Steam is running. Steam has no verified cross-platform fast-add URI in this design. Heroic's path-based URI implementation is specifically Linux-only. Prefer the Steam dialog for the first release rather than maintaining an unofficial configuration writer. [Heroic implementation](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/blob/main/src/backend/shortcuts/nonesteamgame/steamUrlHandler.ts)

## Release and update contract

Use GitHub Releases as the distribution service. Build consumer artifacts from an explicit version tag, run platform checks, and publish a stable release deliberately. A source push does not publish an update. GitHub exposes release assets and their SHA-256 digests through its release API. [GitHub release API](https://docs.github.com/en/rest/releases/releases)

| Item | Contract |
| --- | --- |
| Version source | One machine-readable package manifest provides mod version, network protocol, supported native game version/build, package schema, and minimum launcher version. Generate release metadata and validate runtime constants against it. |
| Release selection | Use stable published releases from the fixed project repository. Prereleases require an explicit channel choice. Compare semantic versions; never silently downgrade a newer source installation. |
| Bootstrap downloads | Platform-specific launcher/installer bundles include their runtime and initial mod payload. Ship no Ultrapool game binaries or assets; each player supplies the installed Steam game. |
| Routine updates | Download a small mod package. Reuse the private native runtime when compatible and unchanged; rebuild/sign that copy only when required. Current installers recopy the full runtime on every install, so this is new work. |
| Integrity and bounds | Verify expected asset name, version, platform, size, and SHA-256 before extraction. Limit request time, package size, extracted bytes, and entry count. Reject traversal, links, duplicate/case-colliding names, and unexpected paths. A checksum detects corruption; it is not an independent publisher signature. |
| Update transaction | Acquire an installation lock; verify the game is closed; stage and validate before replacing owned files. Preserve the previous working version until commit succeeds. Record recoverable transaction state so interruption cannot leave mixed versions launchable. Existing installers support retry after interruption; automatic rollback is new work. |
| Launch gate | Require an installation marker with `state=installed`. The existing Mac launcher checks this; the Windows launcher currently checks only marker existence and needs parity. |
| Concurrent operations | Share a lock across install/update/repair/uninstall. Add a running-game check to Windows uninstall before exposing it in the manager; it currently lacks that preflight. |
| Saves | Normal updates never import progression again, delete saves, or overwrite unowned files. Keep existing profile paths and import markers. Show backup/restore separately from update. |
| Native game updates | Validate the installed Steam game's supported version/build. If incompatible, keep the mod files intact and show a compatibility explanation; do not launch or patch an unsupported version automatically. |
| Launcher updates | Treat the manager binary separately from mod payloads. Replace it after exit using a staged helper or OS installer; do not overwrite a running Windows executable. Retain the same Steam shortcut target. |
| Network failure | Keep the installed version playable. Show retryable failure and local release state. No startup requirement for GitHub access or login. |
| Gameplay performance | Run update checks, downloads, extraction, hashing, and file replacement in the launcher, outside the game input/render/network receive paths. No update work during a match. |

The release feed currently has an older public release than the source branch. On 2026-09-26, the published release is [v0.4.0](https://github.com/harsh2204/ultrapool-together/releases/tag/v0.4.0), while the source declares v0.8.0/protocol 8. Enabling a naive “download latest” button now could downgrade a source installation. Ship the version contract and a compatible consumer release before activating the update channel.

## Existing installation migration

Existing installations have no updater, so they need one initial download of the new graphical installer. No remote update mechanism can reach them retroactively.

1. Discover Steam libraries and the existing `ultrapool-together-install.json`, including custom destinations selected through a folder picker.
2. Validate the marker, ownership list, and actual installation before offering migration. Read legacy version information as data; do not execute installed scripts to discover it. Unknown/newer source versions must not be silently replaced with an older published release.
3. Preserve the installation path, saves, one-time progression-import marker, and unowned files. Add the installed version and launcher metadata after a successful migration.
4. Install the persistent graphical launcher and offer Steam/desktop access. Further updates come through that launcher.
5. Exercise published v0.4.0 Windows markers, current macOS/Windows markers, interrupted installs, and custom paths in isolated fixtures. Existing unfinished custom-ball runs remain unsupported; migrating the installer does not migrate removed gameplay content.

## Packaging tradeoffs

For the first consumer manager, reuse the tested Python macOS installer and package its interpreter with a small graphical UI. A windowed PyInstaller bundle can produce a macOS `.app` and Windows executable without exposing a console. A common release-download/validation layer can serve both platforms; the Windows backend can initially invoke the existing PowerShell installer in a hidden child process and surface its progress/errors in the GUI. Keep long operations off the GUI event loop. [PyInstaller windowed packaging](https://pyinstaller.org/en/stable/usage.html)

This trades a larger launcher download for preserving tested install behavior and reducing duplicate implementation. Native Swift/AppKit and Windows native UI remain alternatives if bundle size or platform polish justifies separate installer ports. A native port must first match the existing save, ownership, interruption, and signing fixtures.

| Packaging concern | Required work |
| --- | --- |
| macOS architectures | Use a verified universal2 runtime and dependencies, or offer separate Apple Silicon and Intel artifacts. Test each supported architecture. |
| macOS bundle integrity | Use a bundle-aware packager such as `ditto` or a DMG. The existing source ZIP builder sets non-`.command` files to mode 0644 and is unsuitable for packaged native executable bundles. Keep source packaging separate. |
| macOS distribution trust | Sign and notarize the distributed launcher/installer with the publisher's Apple credentials. This is separate from ad-hoc signing the user's private copied game. Never disable Gatekeeper or remove quarantine as installation guidance. [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) |
| Windows distribution | Build the Windows package on Windows, preserve no-console behavior, and add publisher signing when available. Test non-admin installs and protected-library permission failures. Do not silently elevate. |
| CI publication | Produce versioned assets and checksums after platform tests. Keep signing credentials in CI secrets. Publishing a release is an explicit workflow action; ordinary pushes remain source changes. |

## Implementation tracker

All items below are **proposed**. They can be implemented independently where dependencies permit; completion requires the stated checks.

| ID | Work package | Dependencies | Acceptance | Status |
| --- | --- | --- | --- | --- |
| DIST-001 | Package version/compatibility manifest and release selection | None | Older/prerelease/incompatible releases are skipped correctly; runtime protocol/version and package agree; offline/rate-limit behavior covered. | Proposed |
| DIST-002 | Transactional update engine | DIST-001 | Corrupt/truncated/oversized packages, extraction attacks, disk errors, concurrency, interruption, and rollback use isolated fixtures; saves/unowned files unchanged. | Proposed |
| DIST-003 | Terminal-free macOS application | DIST-002 | Install/update/repair/play work without user Python/Git; both supported architectures; signing and clean-machine distribution checks pass. | Proposed |
| DIST-004 | Terminal-free Windows application | DIST-002 | Install/update/repair/play work without Git or visible shell; incomplete installs cannot launch; Windows GUI and permissions tests pass. | Proposed |
| DIST-005 | Stable launch targets and Steam add flow | DIST-003/004 | Clearly named mod entry; correct child directory/AppID; update preserves shortcut; authorized live Steam session on each platform. | Proposed |
| DIST-006 | Legacy installation migration | DIST-001/002 | v0.4.0/current/custom-path fixtures preserve all saves and unowned files; unknown/newer installs are not downgraded. | Proposed |
| DIST-007 | Platform builds and release publication | DIST-003/004/006 | Reproducible versioned assets, checksums, platform fixtures, signing configuration, and explicit stable-release publishing. | Proposed |
| DIST-008 | Optional automatic updates | DIST-002/007 | User opt-in, closed-game gating, session-compatible version choice, offline Play, and verified rollback. | Deferred |

The existing [performance tracker](PERFORMANCE.md) remains the source of truth for gameplay bottlenecks. Distribution work must preserve its installer/save boundaries and keep update activity outside gameplay.

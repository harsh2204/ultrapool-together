# Native game compatibility

The current source targets **Ultrapool 0.17.2**, Steam build **25727180**, with Together **0.11.0 / protocol 11**. Every participant needs this version and a new **UP11** room code. The installers reject unsupported native versions before replacing the mod runtime; Steam itself remains untouched.

## Changes from 0.15.7

- Candy is the seventh native floor effect. The table leader owns pickup, its native event and replacement spawn; guests and spectators render the captured native texture, shadow and identity changes. Descriptor and queue limits remain unchanged. Protocol 11 prevents clients with the six-kind validator from joining.
- Gummy Brain carries its native copied-snack identity through inventory snapshots. Only that snack can carry a bounded known passive ID, and an absent or empty value clears stale guest state when the host returns to the shop.
- Normal multiplayer startup clears the new Creative flag and forced selections. Guest entry saves and clears the local Creative context, then restores it on exit. Replica shops hide and disable Creative inventory-grant controls. Native solo Creative mode remains available; Creative multiplayer is unsupported.
- Native aiming, hit prediction and physics interfaces are unchanged. Existing client native aim rendering is retained. Native 0.17.2 fixes the deathline node reference; the mod fallback only applies when the reference is missing.
- The native save-recovery file `save_overwritten.tres` is preserved by updates and explicit progress imports, including rollback. Existing unfinished mod runs remain unsupported across upgrades; start a new run. Native 0.17.2 renames Halo-Halo's resource and reuses its old UID for Halloween Munch, so an older saved daily/run graph can resolve the old snack incorrectly. Together does not rewrite those native files or support continuing old daily runs. The manual importer retains the local daily state while copying progression; a legacy-reference fixture checks that boundary.

## Verification

Static native-pack comparison, strict protocol-boundary fixtures, isolated installer preservation tests and the shared native rendering fixtures cover this port. The macOS capture `20261006T053409Z-b08bd486` passed **19,443/19,443 checks** and produced **112 screenshots** on the new native build. It used one muted isolated process, the compatibility renderer at 1280×720, a 30 FPS cap and a 300-second watchdog, and exited normally in about 147 seconds. There were no script errors; normal saves and game files were unchanged, and the private runtime was removed. Native candy, Gummy Brain copy/count/clear, Creative containment/restore, menu alignment, native aim, and legacy progress-import boundaries passed. Representative table/aim/shop screenshots were reviewed.

A real macOS update from the previous native runtime also completed: installed mod files match the passing candidate, the native pack matches Steam, the copied app signature verifies, and vanilla files plus both progression profiles were unchanged.

All 124 GDScripts parse. Fourteen macOS installer tests (including real signing of an inert fixture), nine mocked capture tests and eleven benchmark self-tests pass. Windows manifest rejection/update fixtures are authored and statically reviewed; PowerShell and Windows native execution remain unverified here. This is separate from live Steam and Windows/macOS multiplayer acceptance. Existing engine shutdown diagnostics remain: 63 CanvasItems, nine materials, one shader, six textures and 18 resources. No performance improvement or long-session stability claim is made.

The new sparse Gummy Brain field adds a modeled 24 bytes for an explicit clear or 32 bytes for a `CRISPS` copy. It appears only on that passive; packet limits are unchanged. These are synthetic serialized-size estimates, not measured traffic or latency.

The 87-row **90.5%** effect ledger remains the sampled **0.15.7 baseline**. Candy is a new unscored family until the expanded native inventory is audited; the baseline is not a percentage claim for all new 0.17.2 content. See [table effect coverage](TABLE_EFFECTS.md).

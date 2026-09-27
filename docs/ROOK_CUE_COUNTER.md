# Rook cue counter integration

Implementation record for [#20](https://github.com/harsh2204/ultrapool-together/issues/20) and [PR #45](https://github.com/harsh2204/ultrapool-together/pull/45), following the repository's shop-content change template. **Implemented with bounded Windows native rendering/animation evidence; performance, live multiplayer and cross-platform acceptance remain open.**

## Behavior and scope

- **Identity:** Rook, a mod-owned cue-shop NPC; fifteen existing cue model IDs remain in `cue_models.gd`.
- **Base:** main `c07f6be`, native Ultrapool 0.15.7, mod v0.10.0 / protocol 9. Subsequent integration revisions are recorded in the PR.
- **Interaction:** browse three portrait cues per rack, switch racks with a short slide/fade, preview ten finishes, and use the selected cue's small wooden purchase/equip control. The right-hand felt case shows confirmed equipment independently of browsing.
- **Roles:** host and guest construct the same local presentation. The table leader owns transactions and cue effects. Spectator mode cannot submit cue transactions; Rook is not a new replicated gameplay entity.
- **Availability:** fourth native shop stop to the right of snacks; the shortcut from balls remains when snacks are locked. Shared-shop and winner-only gates are unchanged. Personal view following controls navigation only.
- **Tracking:** PERF-026/027/034/036, GAP-004. This update does not change cue prices, effects or caps.

## Ownership and integration

The native `ShopGirl` and `ShopBoy` instances and snack merchant remain intact. Inspected references include `ui/shop.gd`, `ui/shop.tscn`, `effects/ui/girl/npc.gd`, `npc_body.gd`, `dialog_box.gd`, and `custom_ui/custom_button.gd`. Rook composes a new `cue_seller.gd` component beside those counters and follows their blink, idle, speech and nudge pattern. The counter tiles remain straight through snacks; the curved end belongs to cues.

`shop_sync._ensure_cue_view` attaches the view once per native shop. `cue_shop.setup` caches two shop textures through `cue_shop_art.gd` and retains all cards, tags, swatches and the equipped case. Forward navigation uses native raised-button scenes; rack/back arrows use the native arrow textures. Decorative controls ignore pointer input. Only Rook's bounded body button handles his nudge; it does not cover the rack, transaction button or inventory.

At setup and viewport-size changes, the composition fits within the native camera's landscape/portrait bounds. Rook remains anchored to the counter edge, and the native inventory transform stays intact. Portrait layouts compact the case above the inventory. Returning to widescreen restores the full-size composition. The native geometry assertions pass; the current visual capture is 1280×720, not a rendered sweep of narrower windows.

Purchase input follows `cue_shop._submit → shop_sync._submit → handle_request/_apply_cue_action → apply_result`. Existing actor, scene, table, revision, ownership, wallet and eligibility checks remain authoritative. Pending requests retain immediate local browsing, and matching confirmation or rejection reconciles the UI. The case updates from the authoritative player row through `render`; model/finish preview does not call its update path.

Reliable cue inventory revisions flow through controller state, shop snapshots, validation, dirty signatures and `refresh_cue_inventory`. Stale nested cue data cannot replace a newer inventory. Repeated unchanged render signatures do not restart dialogue or animations. Hydration shows current equipment; only a subsequent changed confirmation produces Rook's success response.

Leaving the cue stop cancels its single tween, releases focus, hides the case and stops the seller's process/speech. View teardown frees the retained scene and restores native counter geometry and camera ownership. Immutable texture resources remain in a bounded two-entry cache for reuse. No native files or saves are changed by the presentation.

## State and bounds

| Object | Owner and ordering | Bound / cost | Reset |
| --- | --- | --- | --- |
| Rook visual | Local view; no network field | Four registered cels in one PNG, one body node, one speech tween, text capped at 180 characters | Stops off-counter; view teardown |
| Rack | Local preview | Fifteen retained cards, five pages, at most one 0.28-second tween; repeated input kills/replaces previous motion | Leave, identity change, teardown |
| Case | Confirmed player equipment | One preview and caption; catalog-valid model/finish; changes only with confirmed signature | Identity/session hydration |
| Shop artwork | Immutable local cache | Two PNGs, about 2.82 MiB compressed; roughly 8.8 MiB base RGBA texture pixels after case cropping, excluding engine overhead | Process lifetime |
| Cue ownership/effects | Table leader; reliable inventory revision | Existing eight players × fifteen models; +4 points/player/round, 128-ball tracking bound | Run/rematch, shot and round boundaries |

There are no new packets or wire-supplied paths. Artwork decoding and native control construction occur at view setup, not during rack transitions or snapshots. Construction/decode cost is unmeasured; no per-frame timing guarantee is implied. Tween replacement prevents a historical animation backlog.

## Regression and acceptance

| Scenario | Existing seam / expected outcome | Evidence for revised presentation |
| --- | --- | --- |
| Host/guest hydration and confirmed art | `cue_shop_fixtures`: case texture, tint and label match the authoritative model/finish | Windows fixture passed |
| Preview, pending, rejection, unrelated replies | Case stays confirmed while selection and pending UI can change | Windows fixture passed |
| Accepted/newer and stale nested revisions | Accepted equipment updates; stale data cannot rewind case | Windows fixture passed |
| Rapid next/previous input | One live tween, canceled predecessor, retained nodes, gated moving cards, responsive arrows | Windows fixture passed |
| Leave mid-transition and reopen | No rack/seller/speech work off-counter; retained node identities | Windows fixture passed |
| Fifteen cues and long descriptions | Every rack reachable; portrait texture identity and description/action bounds | Windows fixture and 1280×720 review passed; narrower text fit remains open |
| 16:9, 16:10, 4:3 and portrait resizing | Actual native camera/inventory bounds, no case overlap, fixed counter baseline, retained focus/art/nodes, return to full size | Windows geometry fixture passed; actual narrow-window rendering remains open |
| Native aim/cue/score behavior | Existing `native_aim_fixture`, `cue_native_fixtures`, model/inventory/effect probes | Windows fixtures rerun and passed at `bb80925` |
| Shared access, winner-only, Ready, simultaneous purchases, disconnect/rematch | Existing authority gates preserved; full live/platform acceptance remains open | Static integration review only |
| Snack/mixer transactions | No transaction changes; upstream native fixtures retained | Windows fixtures passed |

After integration onto `c07f6be`, all 109 GDScript files parsed, the five presentation/fixture files passed formatting checks, and all five Python and six PowerShell scripts parsed without execution. Image metadata/alpha/registration and whitespace were also inspected. These static checks are distinct from native runtime evidence. Those initial static checks preceded the authorized native run recorded below. No new installer behavior was needed: both package and installer paths already recurse through `mod` and record nested assets. Remaining independent verification covers actual narrow-window rendering, live multiplayer/platform behavior, and performance/balance acceptance. Keep #20 and applicable performance gaps open.

## Current native evidence

Capture `20260927T104101Z-rook-animation`, gameplay/fixture commit `bb80925`: 2,175/2,175 checks, 79 native screenshots and 96 real viewport animation frames. One muted isolated Windows process used a 30 FPS cap and 180-second watchdog; it exited normally with no script errors, unchanged normal saves and unchanged installed game files. Existing engine shutdown resource warnings remain. All four Rook cels and rack motion appeared in the recorded frames; preview changes preserved the confirmed Finesse/Gold case throughout.

Visual inspection of the preceding capture found that the case `TextureRect` kept the source image's minimum size despite its fitted parent bounds. Setting `EXPAND_IGNORE_SIZE` before texture assignment fixes that; the repeated fixture now measures the actual artwork control, not just its parent. The GIF uses captured frames and their recorded timing with palette/timing quantization, without synthetic interpolation. It demonstrates fixture callbacks and rendering, not human input, live networking or foreground performance.

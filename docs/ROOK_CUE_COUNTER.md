# Rook cue counter integration

Implementation record for [#20](https://github.com/harsh2204/ultrapool-together/issues/20) and [PR #45](https://github.com/harsh2204/ultrapool-together/pull/45), following the repository's shop-content change template. **Implemented, unmeasured; the revised presentation has static evidence only.**

## Behavior and scope

- **Identity:** Rook, a mod-owned cue-shop NPC; fifteen existing cue model IDs remain in `cue_models.gd`.
- **Base:** main `6f3105a`, native Ultrapool 0.15.7, mod v0.10.0 / protocol 9. Subsequent integration revisions are recorded in the PR.
- **Interaction:** browse three portrait cues per rack, switch racks with a short slide/fade, preview ten finishes, and use the selected cue's small wooden purchase/equip control. The right-hand felt case shows confirmed equipment independently of browsing.
- **Roles:** host and guest construct the same local presentation. The table leader owns transactions and cue effects. Spectator mode cannot submit cue transactions; Rook is not a new replicated gameplay entity.
- **Availability:** fourth native shop stop to the right of snacks; the shortcut from balls remains when snacks are locked. Shared-shop and winner-only gates are unchanged. Personal view following controls navigation only.
- **Tracking:** PERF-026/027/034/036, GAP-004. This update does not change cue prices, effects or caps.

## Ownership and integration

The native `ShopGirl` and `ShopBoy` instances and snack merchant remain intact. Inspected references include `ui/shop.gd`, `ui/shop.tscn`, `effects/ui/girl/npc.gd`, `npc_body.gd`, `dialog_box.gd`, and `custom_ui/custom_button.gd`. Rook composes a new `cue_seller.gd` component beside those counters and follows their blink, idle, speech and nudge pattern. The counter tiles remain straight through snacks; the curved end belongs to cues.

`shop_sync._ensure_cue_view` attaches the view once per native shop. `cue_shop.setup` caches two shop textures through `cue_shop_art.gd` and retains all cards, tags, swatches and the equipped case. Forward navigation uses native raised-button scenes; rack/back arrows use the native arrow textures. Decorative controls ignore pointer input. Only Rook's bounded body button handles his nudge; it does not cover the rack, transaction button or inventory.

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
| Host/guest hydration and confirmed art | `cue_shop_fixtures`: case texture, tint and label match the authoritative model/finish | Authored, unrun |
| Preview, pending, rejection, unrelated replies | Case stays confirmed while selection and pending UI can change | Authored, unrun |
| Accepted/newer and stale nested revisions | Accepted equipment updates; stale data cannot rewind case | Authored, unrun |
| Rapid next/previous input | One live tween, canceled predecessor, retained nodes, gated moving cards, responsive arrows | Authored, unrun |
| Leave mid-transition and reopen | No rack/seller/speech work off-counter; retained node identities | Authored, unrun |
| Fifteen cues and long descriptions | Every rack reachable; portrait texture identity and description/action bounds | Authored, unrun; native text fit remains open |
| Native aim/cue/score behavior | Existing `native_aim_fixture`, `cue_native_fixtures`, model/inventory/effect probes | Earlier evidence predates this rebase; not rerun |
| Shared access, winner-only, Ready, simultaneous purchases, disconnect/rematch | Existing authority gates preserved; full live/platform acceptance remains open | Static integration review only |
| Snack/mixer transactions | No transaction changes; upstream native fixtures retained | Not rerun |

Static GDScript parsing, image metadata/alpha/registration inspection and whitespace checks are distinct from native runtime evidence. No game, capture harness or test suite was launched for this presentation update. No new installer behavior was needed: both package and installer paths already recurse through `mod` and record nested assets. The next independent verification is the existing bounded Capture-Screens fixture after runtime authorization, followed by live multiplayer/platform and performance acceptance. Keep #20 and applicable performance gaps open.

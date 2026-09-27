# Shop character or content change plan

Copy this template into a feature design or PR working notes and fill each field with concrete decisions. It is a planning artifact, not an existing character API. Delete inapplicable fields with a short reason; do not leave an unchecked item looking complete.

## Behavior and scope

- Feature name and stable ID:
- Base commit, supported native/mod versions:
- User action and visible result:
- Kind: shopkeeper artwork/dialogue; purchasable ball; snack/passive; transactional service; new owned character model:
- Host, guest and spectator behavior:
- Availability: balls/snacks/mix section, unlock/option, master-off, sync-off and winner-only:
- Related PERF/GAP IDs and issue:

## Ownership and integration

- Authoritative owner and state lifetime (shop/round/run/player):
- Native scene/script/typed exports inspected:
- Existing entrypoints to extend; mark proposed files/APIs explicitly:
- Catalog/allowlist, art/resource registration and cache boundary:
- Actual pointer/controller input path and local hover/pending feedback:
- Authority request, validation, native mutation and result path:
- Capture → validate → apply → dirty signature → resync path:
- View/session attachment, signal restoration and cleanup:
- Compatibility decision for peers without the new fields/content:

## State and bounds

| Field/object/event | ID and valid values | Owner | Reliability/ordering | Cap/overflow rule | Reset |
| --- | --- | --- | --- | --- | --- |
| Fill for each new state or event | | | | | |

Specify finite numeric bounds and allowed resource IDs, never network-supplied resource paths. Include byte/apply-time cost and callbacks caused by native setters/creation. Define whether late hydration restores current state or plays a transient event. Repeated snapshots must not restart dialogue, spend tickets, replay audio or repeat gameplay.

## Example A: a decorative shopkeeper

Proposed example: add a mod-owned visual component, perhaps under a new `mod/characters/` folder. This folder and registry are not existing APIs.

1. Preserve native typed `ShopGirl`/`ShopBoy` objects, exported bindings and methods; compose art around them unless a verified compatible replacement is intended.
2. Attach once to both host and guest shop views through `shop_sync._ensure_view`, keyed by view identity. Cache assets at setup. Keep decorative pointer input passive.
3. Update confirmed dialogue/appearance on changed state through an appropriate view-update seam such as `_display_state`. Define event IDs if reactions must play exactly once; snapshot repetition is not a purchase event.
4. Release nodes/signals on view/session teardown. Verify reopen, scene replacement, disconnect/rematch, layer/geometry and unchanged-state node identity.
5. If the character sells a service, add that transaction through `_submit → handle_request → apply_result` with host validation. Art and dialogue do not grant authority. A snack-ticket-for-ball exchange needs its own service action; the existing snack group buys passives. Validate stock, ticket and destination before consuming either, invalidate Ready and reconcile the result.

Decisions for this feature:

## Example B: a shop-only ball

1. For an existing expansion set, extend that set's catalog/offer IDs and rules; see `sets/phases_catalog.gd`, `sets/catalog_util.gd` and `expansion_balls.gd`.
2. Register on every peer; let the table leader select stock and run effects. Keep disabled content out of offers and all shop-only content out of starting/voting decks.
3. Extend shared display state/validation only where needed. If the effect creates floor objects, update the table-effect replication plan as well as the ball rule.
4. Check purchase, sale, rearrangement, mixing eligibility, inventory/table roundtrip, cap/reset and duplicate effect callbacks.
5. A snack uses `id_to_passive` and snack tickets; the ball registrar does not implement that path.

Decisions for this feature:

## Regression and acceptance matrix

| Scenario | Production boundary/fixture | Expected result | Authored / executed / evidence |
| --- | --- | --- | --- |
| Initial host and guest hydration; late resync | | | |
| Real click/hover/drag; no input interception | | | |
| Successful transaction and conservation of money/tickets/items | | | |
| Invalid source/target, no funds/ticket/space, ineligible actor | | | |
| Stale/duplicate/conflicting requests; delayed result; timeout | | | |
| Rejection restores UI; unrelated updates preserve active drag/focus | | | |
| Both mixer inputs, completion and output collection, if affected | | | |
| Ready/Continue, counter navigation, sync-off and exclusive shopping | | | |
| Native callbacks/effects once on host; none on guest | | | |
| Round/scene cleanup, disconnect, reopen, rematch, spectator switch | | | |
| Bounds/overflow, changed-data cost, both platforms | | | |

Record authorized runtime scope before running native probes; otherwise leave those rows authored/unrun and complete static work. Keep a tracker open for remaining coverage.

## Delivery

- Files/behavior changed:
- Checks run and exact revision:
- Remaining native/live/platform/performance evidence:
- Package/update preservation evidence if applicable:
- Compatibility/release notes and independent next step:

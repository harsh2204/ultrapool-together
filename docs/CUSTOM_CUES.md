# Cue Workshop

Issue [#20](https://github.com/harsh2204/ultrapool-together/issues/20) expands personal cue cosmetics into a complete cue shop. The cue mechanics and Rook presentation have bounded Windows native functional evidence, including actual viewport animation frames. **Live multiplayer, macOS, performance and balance acceptance remain open.** Source v0.10.0 uses protocol 9 / UP9 rooms, so every player needs the same compatible build.

## Location and interaction

The workshop is the fourth counter, **to the right of snacks**, in the existing scrolling shop. Rook, a demon cue maker, stands behind its curved right-hand counter end. Snacks retain their existing merchant and background behind the straight front counter. Both share the native content slider, environment, inventory, Ready controls, and CRT treatment. Native purple icon-only arrows connect the counters; tooltips identify their destinations. A shortcut keeps cues reachable when snacks are locked.

Fifteen distinct cue designs occupy five racks of three upright portrait cards. Next/previous rack changes use a 0.28-second slide/fade/settle. Rapid clicks replace the current transition; they do not queue animations. The rack and purchase action pause during that brief transition, while rack arrows remain responsive. Cards, focus, and cached artwork survive state updates.

The selected cue's paper placard contains a compact purchase/equip control and the effect details. Browse, preview, and customize a finish locally while a purchase awaits table-host confirmation. Rejections reconcile ownership and money and show their reason. The felt-lined case beside the inventory displays only the player's confirmed cue and finish; browsing and pending/rejected purchases never replace it. Rook blinks, talks, idles, and responds to a click using the native merchants' presentation pattern. Seller motion and rack transitions stop when leaving the counter.

The placard shows the cue name, effect, limits and action. The native inventory supplies the wallet display. Run ownership and free switching are explained in the action tooltip; idle shopping has no extra status prompt. Pending confirmation appears on the action, while rejection, blocked shopping and insufficient funds retain visible feedback.

The composition fits narrower windows at resize boundaries while keeping Rook aligned with the counter and preserving the native inventory. Portrait windows use a smaller case above the inventory. Native geometry assertions pass at these sizes; actual narrow/portrait window rendering and readability remain pending.

## Ownership and economy

House is included. Paid cues cost **2–8€ from the shared run wallet** and belong to the purchasing player for that run. Handling preferences cost 2€; reliable, repeatable score perks cost more. Difficult tricks receive larger conditional rewards instead of simply carrying the highest price. Buying also equips the cue. Switching owned cues and finishes while shopping is free. There are no refunds, stacked cues, randomized offers, or permanent gameplay unlocks.

New runs/rematches start with House. Confirmed finish choices persist in the mod's isolated `user://together_cue.cfg`; ownership never comes from local preferences. Multiplayer run continuation across application restarts remains unsupported.

Ten free cosmetic finishes: Native, Emerald, Coral, Gold, Violet, Ice, Rose, Chalk, Midnight, Amber. Open the Mod settings gear in the lobby to choose **Your starting cue finish** before a match; the workshop handles in-run changes. The separate **Follow host shop view** preference remains available during play and does not control cue ownership or purchase authority.

## Complete roster

| Cue | Price | Visual design | Effect |
| --- | ---: | --- | --- |
| House | Free | Maple, black wrap, ivory ferrule | Native power and scoring. |
| Finesse | 2€ | Pale ash, teal wrap, brass diamonds | Gentler light shots; firmer heavy shots. |
| Firm | 2€ | Chestnut, burgundy grip, brass bands | Firmer light shots; gentler heavy shots. |
| Clean | 3€ | Bleached ash, white linen, black pinstripes | Pot a ball without a rail contact that shot: +3%, capped at +1. |
| Opener | 3€ | Honey wood, orange grip, rising sun | Pot on the round's first accepted shot: +6%, capped at +1.5. One table-wide opportunity per round. |
| Silk | 4€ | Ivory ash, rose silk, silver inlay | Pot on a light shot (input length ≤90): +4%, capped at +1.5. |
| Thunder | 4€ | Charcoal, violet grip, gold lightning | Pot on a heavy shot (input length ≥170): +4%, capped at +1.5. |
| Comeback | 4€ | Auburn wood, red grip, feather inlay | Pot after your previous shot this round made no eligible pots: +6%, capped at +1.5. Does not trigger on your first shot. |
| Corner | 5€ | Oak, burgundy grip, ivory geometry | Pot into a fixed corner pocket: +3%, capped at +1.5. |
| Sidewinder | 5€ | Olivewood, jade grip, brass wave | Pot into a fixed middle pocket: +5%, capped at +1.5. |
| Carom | 5€ | Maple, navy grip, interlocking diamonds | Pot a ball after it contacts two distinct other object balls: +10%, capped at +2.5. |
| Double Rail | 6€ | Ebony, copper grip, paired chevrons | Pot a ball after it makes two rail contacts: +9%, capped at +2.5. |
| Bankshot | 7€ | Walnut, emerald wrap, single chevrons | Pot a ball after it hits a rail: +6% of its unmultiplied value, capped at +2. |
| Relay | 7€ | Maple, teal/coral grip, brass links | Pot after a different teammate's immediately preceding shot made an eligible pot: +5%, capped at +2. |
| Closer | 8€ | Walnut, green grip, three ivory dots | Pot with at most three ordinary live object balls at shot start: +5%, capped at +2. |

## Balance bounds

Score perks trigger only on the **first qualifying pot per shot**. Bonuses use positive **unmultiplied** ball value, retain fractions without rounding upward, and share a **+4-point cap per player per round across every cue**. Changing cues cannot reset that budget. Shielded respawns, virtual pockets, non-scoring pots, and duplicate callbacks cannot farm bonuses. The equipped cue is frozen at shot acceptance.

Contact conditions track the potted ball itself, not the cue ball. Closer counts live ordinary objects: the cue ball and balls with multiplayer or expansion-set effects in either mixed half are excluded. The Relay cue is a separate perk from the Relay multiplayer ball.

Bonus score is applied after the native pot completes and does not trigger native SCORE/SCORE-SELF chains. Crossing the native required-score threshold can still trigger REACH-SCORE and its normal effects. No cue directly grants extra shots, money, health, random outcomes, or persistent ball-stat changes.

Finesse/Firm reshape power with `t=(length-50)/150`, then `t + bias*t*(1-t)*(1-2*t)`, bias −0.30/+0.30. They preserve direction, monotonicity, minimum/maximum input 50/200, midpoint 125, and maximum power. The largest adjustment is about 4.33 vector units, or 2.17% of full power. Other cues use native power.

Prices account for opportunity frequency: Closer already qualifies in the three-ball Classic starter, while Opener has only one table-wide attempt. Double Rail retains a larger cap than Bankshot so the harder requirement still has a payoff on high-value balls. Native level-one balls cost 3/4/6/9€ by rarity and a round win pays 4€; an 8€ cue is a meaningful shared-wallet choice. Score can indirectly improve native overflow payout, even though cues never grant money directly.

These are initial tuning values. Balance review should compare identical seeds, decks, difficulties, and player counts, measuring proc frequency, total bonus contribution, and shared-money opportunity cost.

## Authority, assets, and performance

Existing reliable shop requests/results retain actor, table, match, scene, revision, eligibility, winner-only, shop-state, and balance checks. Ownership and the native wallet change synchronously. Duplicate buys cannot spend twice. Cue changes invalidate shop readiness.

Reliable table state carries catalog-validated cue ownership and equipment for at most eight players. A run-scoped inventory revision prevents delayed table or shop state from undoing confirmed equipment and finishes. Only the table host applies perks. Accepted shot curves are applied once, with the identical vector sent to replicas. Gameplay ownership never comes from guest presence or cosmetic preferences.

Fifteen generated cue sprites are shipped under `mod/assets/cues/`; native files and saves remain untouched. Art is cached at lifecycle boundaries, not loaded on packet/frame paths. Effect tracking is bounded to 128 balls and eight player budgets, cleared at shot/round/session boundaries. Initial or mid-shot overflow disables that shot's remaining perks without restoring spent bonus budget; incomplete pot history cannot activate Comeback or Relay. Fixed corner and side pocket roles follow table geometry in either orientation. Relevant tracker items: PERF-010/026/034–038 and GAP-004.

## Acceptance tracking

- [x] Static parsing, source package checks, and isolated Windows installer tests. macOS execution remains pending.
- [x] Model fixtures: curves, all fifteen effects, ownership, sequential shared-wallet spending, malformed snapshots, duplicates, rejection, shared caps, swapping, and rematch reset.
- [x] Native host/guest capture: navigation right of snacks, all racks, long descriptions, finishes, buy/equip, insufficient funds, pending/rejected transactions, and return.
- [x] Native cue attachment/aim parity after current main-branch fixes; all fifteen textures, tip/shadow/fade preservation, House restoration, and equipped Bankshot capture.
- [x] Native score/HUD callback boundary: fractional credit, per-shot cap, duplicate commit, post-pot ordering, and refusal to award against a still-living GAMEBALL source. Full physical special-ball pot scenarios remain part of live playtesting.
- [x] Final Windows capture preserved normal saves and installed game files.
- [x] Windows 1280×720 verification of Rook cels/dialogue, portrait cue text, rapid rack navigation/focus, snack/cue counter composition, and confirmed equipment. Actual viewport animation frames and strengthened case-art bounds checks passed.
- [ ] Render and inspect actual narrow/portrait windows; current resize coverage checks transformed native bounds without resizing the window.
- [ ] Live concurrent shoppers, delayed/reordered updates, sync-shop-off and winner-only behavior, disconnect/rematch.
- [ ] Windows/macOS rendering plus measured responsiveness and balance.

Windows capture `20260927T070455Z-1962c3ec` passed all 731 harness assertions and produced 67 screenshots. Embedded cue probes passed 226 catalog/curve, 189 inventory, and 204 effect checks. The game exited normally with no script errors; shutdown resource warnings match the earlier baseline. Installed game files were unchanged. The normal save profile changed during the capture, so the runner's overall preservation audit failed; that run does not establish save preservation. Earlier captures preserved normal saves and installed files, but had test failures that were subsequently fixed. The isolated Windows installer suite and source ZIP integrity/asset checks also passed.

The branch has since been rebased onto main `c07f6be`, preserving native initial-click/charge behavior, opt-in shop-view following, client/spectator table-effect replication, and the localized difficulty/native-menu fixes. All 109 GDScript files parsed after integration. The older captures do not verify the rebased Rook layout; the newer native run below does.

The preceding Windows run `20260927T104101Z-rook-animation` at gameplay/fixture commit `bb80925` passed **2,175/2,175 harness checks**, produced **79 native screenshots** and **96 actual animation frames**, and preserved installed files and normal saves. It used one muted process, a 30 FPS cap and a 180-second watchdog, exiting normally in about 100 seconds with no script errors. Existing engine shutdown resource warnings remain. The sequence shows next/previous racks, seller idle/blink/talk/nudge, and finish previews while confirmed Finesse/Gold stays in the case. It uses fixture UI callbacks, not a recorded human or live network session.

The first Rook capture exposed an oversized case despite passing parent-bound assertions. The production fix sets `TextureRect.EXPAND_IGNORE_SIZE` before assigning its texture, and the repeated run checks the actual artwork descendant against the case, viewport and native inventory. PNG encoding now follows the bounded recording so compression does not stall the shown animation. GIF palette conversion uses recorded frame timing; no generated or interpolated frames are used. This establishes rendering/callback correctness for this fixture, not foreground frame-time or input-latency performance.
Runtime verification uses the existing bounded Capture-Screens harness after authorization. Keep #20 open until the remaining acceptance work is complete.


## Current economy and collection verification

Windows capture `20260927T121822Z-clean-cue-placard` at gameplay/fixture commit `9541e71` passed **2,797/2,797 checks**, including **610 collection checks**, and produced **90 native screenshots** plus **96 actual viewport animation frames**. One muted isolated process used the compatibility renderer, 1280×720, a 30 FPS cap and a 180-second watchdog. It exited normally in about 105 seconds with no script errors; normal saves and installed files were unchanged. Engine shutdown resource warnings remain.

All eight ball inspections, native rarity prices and highlighted descriptions, the four-helper Bounty/Encore mix, level badges, label/ball/tooltip bounds, retained outline geometry, no-overlap checks, unchanged discovery records, native tabs/scrolling and close/reopen passed. Every individual tooltip and the mixed tooltip were visually reviewed. The final native rows are centered within the original set footprint. Cue probes passed 226 catalog/curve, 206 inventory and 209 effect checks, including mixed-price spending and the shared bonus budget. The final cue placard removes duplicate wallet text and idle prompts; the native inventory wallet remains. Pending confirmation stays on the action button, while rejection, blocked shopping and insufficient funds retain visible feedback. Host/guest transaction, preview and description/control-separation checks passed with the compact layout.

This is native fixture rendering and callback evidence, not live networking or a foreground performance/balance measurement. Actual narrow/portrait rendering, macOS, controller hardware, simultaneous shoppers, delayed/reordered network updates and long-run balance remain open.

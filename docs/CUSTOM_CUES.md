# Cue Workshop

Issue [#20](https://github.com/harsh2204/ultrapool-together/issues/20) expands personal cue cosmetics into a complete cue shop. **Implemented with Windows native functional verification; performance and balance unmeasured.** Source v0.10.0 uses protocol 9 / UP9 rooms, so every player needs the same compatible build.

## Location and interaction

The workshop is the fourth counter, **to the right of snacks**, in the existing scrolling shop. It uses the native content slider, environment, inventory, Ready controls, and CRT treatment. A Cues arrow leads from snacks; Back returns there. A shortcut keeps cues reachable when snacks are locked.

Fifteen distinct cue designs occupy five racks of three. Browse, preview, customize a finish, buy, and equip. Preview and paging respond locally while purchases await table-host confirmation. Rejections reconcile ownership and money and show their reason. Cards, focus, and art are retained across state updates.

## Ownership and economy

House is included. Every other cue costs **4€ from the shared run wallet** and belongs to the purchasing player for that run. Buying also equips it. Switching owned cues and finishes while shopping is free. There are no refunds, stacked cues, randomized offers, or permanent gameplay unlocks.

New runs/rematches start with House. Confirmed finish choices persist in the mod's isolated `user://together_cue.cfg`; ownership never comes from local preferences. Multiplayer run continuation across application restarts remains unsupported.

Ten free cosmetic finishes: Native, Emerald, Coral, Gold, Violet, Ice, Rose, Chalk, Midnight, Amber. Together options selects the starting finish; the workshop handles in-run changes.

## Complete roster

| Cue | Visual design | Effect |
| --- | --- | --- |
| House | Maple, black wrap, ivory ferrule | Native power and scoring. Free. |
| Finesse | Pale ash, teal wrap, brass diamonds | Gentler light shots; firmer heavy shots. |
| Firm | Chestnut, burgundy grip, brass bands | Firmer light shots; gentler heavy shots. |
| Bankshot | Walnut, emerald wrap, single chevrons | Pot a ball after a rail hit: +4% of its base value, capped at +2 points. |
| Double Rail | Ebony, copper grip, paired chevrons | Pot a ball after two rail contacts: +6%, capped at +2. |
| Carom | Maple, navy grip, interlocking diamonds | Pot a ball after it contacts two distinct other object balls: +6%, capped at +2. |
| Silk | Ivory ash, rose silk, silver inlay | Pot on a light shot (input length ≤90): +3%, capped at +1.5. |
| Thunder | Charcoal, violet grip, gold lightning | Pot on a heavy shot (input length ≥170): +3%, capped at +1.5. |
| Opener | Honey wood, orange grip, rising sun | Pot on the round's first accepted shot: +5%, capped at +2. |
| Closer | Walnut, green grip, three ivory dots | Pot when at most three ordinary live object balls remain at shot start: +4%, capped at +2. |
| Comeback | Auburn wood, red grip, feather inlay | Pot after your previous shot this round made no eligible pots: +5%, capped at +2. Does not trigger on your first shot. |
| Relay | Maple, teal/coral grip, brass links | Pot after a different teammate's immediately preceding shot made an eligible pot: +3%, capped at +1.5. |
| Corner | Oak, burgundy grip, ivory geometry | Pot into a fixed corner pocket: +2%, capped at +1. |
| Sidewinder | Olivewood, jade grip, brass wave | Pot into a fixed middle pocket: +3%, capped at +1.5. |
| Clean | Bleached ash, white linen, black pinstripes | Pot a ball that did not contact a rail that shot: +2%, capped at +1. |

## Balance bounds

Score perks trigger only on the **first qualifying pot per shot**. Bonuses use positive **unmultiplied** ball value, retain fractions without rounding upward, and share a **+4-point cap per player per round across every cue**. Changing cues cannot reset that budget. Shielded respawns, virtual pockets, non-scoring pots, and duplicate callbacks cannot farm bonuses. The equipped cue is frozen at shot acceptance.

Bonus score is applied after the native pot completes and does not trigger native SCORE/SCORE-SELF chains. Crossing the native required-score threshold can still trigger REACH-SCORE and its normal effects. No cue directly grants extra shots, money, health, random outcomes, or persistent ball-stat changes.

Finesse/Firm reshape power with `t=(length-50)/150`, then `t + bias*t*(1-t)*(1-2*t)`, bias −0.30/+0.30. They preserve direction, monotonicity, minimum/maximum input 50/200, midpoint 125, and maximum power. The largest adjustment is about 4.33 vector units, or 2.17% of full power. Other cues use native power.

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
- [ ] Repeat the final preservation audit with no concurrent use of the normal save profile.
- [ ] Live concurrent shoppers, delayed/reordered updates, sync-shop-off and winner-only behavior, disconnect/rematch.
- [ ] Windows/macOS rendering plus measured responsiveness and balance.

Windows capture `20260927T070455Z-1962c3ec` passed all 731 harness assertions and produced 67 screenshots. Embedded cue probes passed 226 catalog/curve, 189 inventory, and 204 effect checks. The game exited normally with no script errors; shutdown resource warnings match the earlier baseline. Installed game files were unchanged. The normal save profile changed during the capture, so the runner's overall preservation audit failed; that run does not establish save preservation. Earlier captures preserved normal saves and installed files, but had test failures that were subsequently fixed. The isolated Windows installer suite and source ZIP integrity/asset checks also passed.

Runtime verification uses the existing bounded Capture-Screens harness after authorization. Keep #20 open until the remaining acceptance work is complete.

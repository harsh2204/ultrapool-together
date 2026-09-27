# Expansion sets (shop-only)

Opt-in extras live in the **Mod settings** slate, opened with the gear button in the lobby or beside **Lobby · F8** during play. The panel is closed by default and keeps the Tables/Mode/Shots heading intact. Host match rules lock once a match starts; personal view preferences remain available. Inside the panel: Multiplayer balls, Clone-table rounds (Together All Nighter only), and an **Expansion sets** master toggle (**off by default**). The master gates visibility of the six per-set toggles (Phases, Morph, Tide, Relic, Tarot, Zodiac) and defensively forces every set inactive for registration, shop offers, and rules when off—even if a stale per-set flag is on. When the master is on, the six toggles behave as before.

Enabled sets never enter the starting rack, lobby starting-set select, or between-round set vote pool (native base sets only: Classic, Nature, Tech, Spooky, Friends, Food, Space, Gacha). When enabled, their balls appear rarely in the shared shop (about one in six stocks/rerolls per set, same gate as TOGETHER). Buying, selling, arranging, and mixing use the existing shared shop.

**Status: implemented, unmeasured** — needs an authorized live playtest. No runtime FPS/latency claims.

Shared table state (phase clock, tide height, digs, morph forms, tarot spread, zodiac alignment) is **host-authoritative**, sync’d in `expansion_balls` state with dirty-gated publishes via `display_signature` (see PERF-010). Caps clear on disconnect, scene change, rematch, and round reset. Passing does not charge abilities. Percentage bonuses use pre-multiplier ball value, `ceilf`, and never multiply other ability bonuses.

## PHASES (`from_set = "PHASES"`)

Moon phase 0–3 (New → Waxing → Full → Waning) advances on each ordinary pocket. Phase balls read the clock.

| Ball | Rarity | Base | Effect |
| --- | --- | --- | --- |
| Crescent | Common | 2 | +50% if pocketed during Waxing/Waning |
| Full Moon | Common | 1 | During Full, on hit: +1 temp to a random ordinary ball |
| Gibbous | Common | 2 | +25% during Waxing/Full |
| New Moon | Uncommon | 2 | Pocket during New stores Silent Charge (max 2); spend for +100% on a later Phase pocket |
| Eclipse | Uncommon | 2 | Once/table/round: close top-multiplier pocket for the shot; +2 coins |
| Umbra | Uncommon | 2 | During New/Waning, first cushion bounce: +1 temp once/ball/round |
| Penumbra | Uncommon | 2 | While Full or New: next ordinary pocket +50% once/table/round |
| Apogee | Rare | 2 | First time each shot a Phase ball survives an object-ball hit, phase advances an extra step |

## MORPH (`from_set = "MORPH"`)

Per-ball form cycles Idle ↔ Active on **cue-ball** hits. Pocket pays the active form.

| Ball | Rarity | Base | Effect |
| --- | --- | --- | --- |
| Vessel | Common | 1 | Active (Sprinter): next cushion stores +25%; returns to Idle |
| Heavy Form | Common | 2 | Active: +1 weight; pocket arms +1 flat to the next pocket this shot |
| Shield Form | Common | 2 | Active (Guard): first cushion bounce grants +1 temp |
| Phaseform | Uncommon | 2 | First cushion marks it; pocket after mark +100% once/ball/round |
| Splitter | Uncommon | 1 | Active pocket respawns a fleeting 0-score Echo once/table/round |
| Catalyst | Uncommon | 2 | Active pocket: +1 temp to every Morph ball once/table/round |
| Prime Morph | Rare | 2 | After three form changes in a round, next pocket +150% once |
| Flux Core | Rare | 2 | Form changes count double toward Prime Morph |

## TIDE (`from_set = "TIDE"`)

Tide Height 0–3 rises on cushion hits (from Tide balls), falls on pockets.

| Ball | Rarity | Base | Effect |
| --- | --- | --- | --- |
| Driftwood | Common | 2 | +50% at Tide ≤1 |
| Breaker | Common | 1 | Wall raises Tide; at cap gain +1 temp instead |
| Undertow | Common | 2 | +25% at Tide ≥2 |
| Buoy | Uncommon | 2 | Once/round: set Tide 2 and +25% to next ordinary pocket |
| Riptide | Uncommon | 2 | Pocket at Tide 3 launches nearest ordinary ball |
| Harbor | Uncommon | 2 | Once/round: Tide −1 and +1 coin |
| Maelstrom | Rare | 2 | First wall hit each shot is a free Tide +1 |
| Tsunami | Rare | 2 | Pocket at Tide 3 for +100% once/ball/round |

## RELIC (`from_set = "RELIC"`)

Per-ball dig charges (max 4). Shard accrues by surviving object-ball shots; Dust on cushions. Spent on pocket unless Crown persists digs between shots.

| Ball | Rarity | Base | Effect |
| --- | --- | --- | --- |
| Shard | Common | 1 | Survive object-ball shot → +1 dig; pocket pays +25% × dig |
| Idol | Common | 2 | When any Relic gains a dig, +1 temp (cap +3/round) |
| Dust | Common | 2 | Cushion bounce → +1 dig once/shot |
| Sealed Chest | Uncommon | 2 | Once/round: pocket with dig ≥2 anywhere → +2 coins, clear 1 dig |
| Curse Tablet | Uncommon | 2 | Pocket locks a random non-Relic ball until end of shot |
| Reliquary | Uncommon | 2 | Pocket pays +50% if any Relic has dig ≥3 |
| Crown Relic | Rare | 2 | Digs persist between shots this round |
| Keystone | Rare | 2 | Pocket with dig ≥1: every Relic +1 dig (capped) |

## TAROT (`from_set = "TAROT"`)

At round start, up to three Arcana from the build form the Spread. Cushion hits flip upright/reversed. Pocketing pays the current orientation and spends that card from the Spread until next round. No shop redraw UI. **The Moon is not shipped** (reserved for Phases).

| Ball | Rarity | Base | Effect |
| --- | --- | --- | --- |
| The Fool | Common | 1 | Upright +100% once/ball/round; reversed 0 score but +2 coins once/table/round |
| Wheel of Fortune | Common | 2 | Upright rerolls +25/+50/+100%; reversed forces +25% |
| The Magician | Common | 2 | Upright +50%; reversed +1 coin |
| Temperance | Common | 2 | Upright +25% and arms +25% for next ordinary; reversed +25% only |
| The Tower | Uncommon | 2 | Once/table/round: upright clears all temp and +3; reversed strips one temp and +1 to two others |
| Death | Uncommon | 2 | Upright consumes nearest lower-base ordinary for +50%×level; reversed turns it into a fleeting Shade |
| The Sun | Uncommon | 2 | Upright +100% once; reversed clears own temp |
| The Hanged Man | Uncommon | 2 | Upright: survive → charge, pocket +50%; reversed 0 score |
| The Star | Rare | 2 | While upright in Spread: first ordinary pocket each shot +25% |
| Strength | Rare | 2 | While upright in Spread: first Arcana cushion bounce each shot +1 temp |

## ZODIAC (`from_set = "ZODIAC"`)

Each sign has an element (Fire / Earth / Air / Water). Alignment = count of that element's signs alive on the table. 2 = Aspect, 3+ = Grand Trine. All twelve signs ship. No planet/star body stats.

| Ball | Element | Rarity | Base | Effect |
| --- | --- | --- | --- | --- |
| Aries | Fire | Common | 2 | +25%; Aspect/Trine arms +25%/+50% on next pocket |
| Taurus | Earth | Common | 2 | Cue hit +1 temp (cap 3 / Aspect 5); Trine +1 weight |
| Gemini | Air | Common | 1 | Aspect: share +25% pre-mult value as temp to another Air sign |
| Libra | Air | Common | 2 | Aspect: first cushion bounce +1 temp |
| Capricorn | Earth | Common | 2 | Aspect: +2 coins once/table/round |
| Cancer | Water | Uncommon | 2 | Aspect: survive → charge max 2; pocket +50%×charges |
| Virgo | Earth | Uncommon | 2 | Aspect: lock a random non-Zodiac ball until end of shot |
| Scorpio | Water | Uncommon | 2 | Aspect: consume nearest lower-base ordinary for +25%×level |
| Sagittarius | Fire | Uncommon | 2 | Aspect: launch nearest ordinary |
| Aquarius | Air | Uncommon | 2 | Aspect: spawn fleeting Echo once/table/round |
| Pisces | Water | Uncommon | 2 | Aspect: restore 1 health once/table/round |
| Leo | Fire | Rare | 2 | Fire Grand Trine: first Fire pocket each shot +100% once |

## Sync and performance notes

- Wire field: `expansion_balls` on reliable table state (alongside `multiplayer_balls`).
- Dirty gate: `expansion_balls.display_signature` is part of `main._publish_state`’s `state_sig` (PERF-010).
- Ball loops capped at 128; shop offer scan capped; queues cleared on round/session end.
- Overlay for expansion state is minimal (state is carried for guests; TOGETHER UI overlays remain separate).

## Files

Per-set catalogs/rules under `mod/sets/`, coordinator `mod/expansion_balls.gd`, shared helpers `mod/sets/catalog_util.gd` and `mod/sets/registry.gd`. Placeholder atlas sources in `mod/assets/balls/` (`phases_*`, `morph_*`, `tide_*`, `relic_*`, `tarot_*`, `zodiac_*`).

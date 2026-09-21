# Multiplayer ball proposals

These are design proposals, not implemented features. Each table has its own board, run, shop, and score. Players seated together take turns on that board; competing tables share the same shot budget regardless of how many people sit at each one.

Start with native ball art, colored player marks, pocket outlines, and score labels. None of these proposals changes physics or needs synchronized particles.

| Ball | Rule and appeal | Limits and competitive fairness |
| --- | --- | --- |
| **Relay** | A player's first hit marks the ball. A different teammate pockets it on a later shot for a fixed +50% bonus. Players can deliberately leave a useful position for a partner. | One mark and payout per ball per round. In competition, a solo table meets the same two-shot condition by hitting and pocketing on different shots; a team must hand the shot to another member. Extra players and repeated touches do not increase the bonus. |
| **Called Shot** | After completing a shot, its shooter nominates this ball and a pocket for the table's next shooter. Making that call earns a fixed bonus. The caller's color and the pocket outline make the plan visible. | One active call per table, earned by a completed shot and consumed by the next accepted shot. A solo table calls its own next shot. Passing does not create, renew, or fulfill calls. |
| **Patience** | Leaving this ball on the board through qualifying shots charges up to three visible pips, worth +25% each when pocketed. The group weighs a safe payout against another setup turn. | Co-op can require a different contributing player for each pip. Competitive mode counts qualifying shots instead, so a larger group has no higher ceiling or faster charge rate than a solo table. A qualifying shot consumes budget and hits an object ball; passing and wall-only shots add no pips. |
| **Bounty** | Every competing table receives the same marked target. Pocket it using fewer accepted shots than the other tables to win a fixed bounty. Each table can decide which player is best placed to finish the attempt. | Compare shot indices, not wall-clock time, so ping and load time do not decide the winner. Resolve once all tables finish or exhaust their budgets; ties receive equal bonuses. Target identity must be a shared challenge ID, never a machine-local ball instance ID. |
| **Return Favor** | In co-op, Player A marks the ball and Player B pockets it. A gains one +25% token for their next actual shot, making the assist useful to both people. | Co-op only initially. One token per player, no stacking, expiry at round end, and ordinary ball points only: bonuses cannot multiply other bonuses. Passing does not consume or generate tokens. |

All triggers belong to an accepted shot ID and its shooter ID. Delayed scoring stays credited to that shooter even if the displayed turn changes or the player disconnects. A table leader emits each mark or payout once; guests only display it. Reset marks at a defined round boundary, and include their state in resynchronization snapshots.

For competitive tests, compare solo and larger tables with the same accepted-shot sequence. They should have the same attainable point ceiling and the same budget cost. Marks should name the contributing player without exposing authority, routing, or other implementation details in the game UI.

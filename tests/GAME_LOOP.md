# Host and client game-loop coverage

Run `Capture-Screens.cmd` for the combined regression suite and screenshot gallery. It uses one isolated native game process. `round_flow_fixtures.gd` records messages through the production table controller and router, serializes them, then replays them through the guest controller after returning to the native menu.

| Stage | Automated coverage |
| --- | --- |
| Lobby and match start | Lobby/controller models check seats, readiness, unequal table sizes, configuration, start failures, and match generations. Render fixtures cover lobby and vote screens. |
| Table presentation | Native host and client textures, ball inspection, floor, configured cosmetics, score, money, health, and shot pips. Spectator fixtures check the same presentation and isolation from the local table. |
| Turns and scoring | Controller models check valid actors, rejected and replayed shots, turn ownership, Race completion, and Score PvP budgets. |
| Round completion | The host's native round-end sequence produces payout and updates money. The client receives the same native payout labels and balance. A newer transient packet arriving before the reliable phase cannot skip the payout. |
| Entering the shop | Native Continue advances the host. Client payout remains until locally dismissed. Early shop data, the phase snapshot, and the retained replica must converge on the visible native shop and its camera. |
| Shared purchases | Routed guest purchases spend money once. With a delayed reply, the client moves the native item and updates money immediately. Unrelated updates preserve that prediction; confirmation reuses the item node. |
| Shop dragging | Mouse input picks up the actual native shop ball on host and client. Native movement and drop animations remain active; only the completed transaction is routed through the host. Cancelled or interrupted drags cannot submit stale purchases. |
| Rejected actions | A stale sale leaves host money unchanged and restores client money and the item. Host revision checks reject repeated or conflicting transactions. |
| Leaving the shop | Partial readiness keeps shopping open. Concurrent approvals use the same vote generation. Native Ready responds locally, and unanimous approval starts the next native round. |
| Next round | Client shop closes, the table is playable, the replica remains intact, and late payout/shop packets cannot reopen the previous phase. |
| Victory and defeat | Native final-round victory and a fresh-run defeat are recorded and replayed. Client labels, statistics, inventory, and shot lock are compared with the host. A cold client also receives first-round defeat before ever opening a shop. |
| Settings and teardown | Native guest settings show in-run actions and block aiming. Closing settings restores aiming. Ending the guest session with settings open restores the menu and unpaused UI. |
| Disconnect and rematch rules | Models check membership changes, abandoned table leaders, room teardown, vote invalidation, startup failure, and return-to-lobby rules. |

The terminal fixtures set the round/health needed to reach victory and defeat; they do not simulate every round of a campaign. Replay exercises controller messages in one process, without the Steam transport or a second GPU-rendered game instance. Multi-PC Steam invitations, real network loss and latency, simultaneous input from several remote users, and a complete campaign remain separate playtest coverage. `session_probe.gd` and `transport_probe.gd` provide additional separately authorized local transport tests.

# Sync shop with host

Host-only lobby toggle in the collapsed **Together options** panel (default **ON**). When enabled, the table keeps today's shared shop: guests open host `remote_slots` replicas, presence draws shared shop cursors, and host `ui_nav` can follow teammates into shop/snack_bar screens (PERF-009/010/029/035).

## Off mode

When **Sync shop with host** is off:

- The table host shops with the local native shop through `shop_sync` as usual.
- Shop state is **not** broadcast as an open shared session. Guests receive a closed stub and never build remote slot replicas or shared shop cursors.
- Guest `ui_nav` follow of `shop` / `snack_bar` is suppressed (lobby / table / set_vote follow stay).
- Remote `shop_request` from non-hosts is rejected. On a multi-seat table, only the table host shops; teammates wait through the shop phase via ordinary table state. Multi-table lobbies already give each table host their own shop.

## Precedence

`set_exclusive_shopper` / winner-only shop (clone-table vs mode) **wins** over sync-off. Vs mode needs one authoritative shop, so exclusive shopping forces shared sync for that shop session even when the lobby toggle is off. When the exclusive gate clears, sync-off behavior resumes at the next shop close / open boundary.

## Mid-match semantics

Like other ModOptions, the toggle is host-only and **locked once the match starts**. The match start copies `sync_shop` into `run_config`. `shop_sync` latches the flag at session begin and only refreshes it while no shop view is open, so a flag change can never tear down a shop a player is actively using.

## Gate points

| Concern | Location |
| --- | --- |
| Lobby setting + snapshot | `lobby_state.sync_shop` / `set_sync_shop` |
| ModOptions row | `lobby_scene._ensure_sync_shop_toggle` |
| Wire closed stub | `shop_sync.wire_shop_state` ← `main._publish_state` / shop_result |
| Guest apply / remote slots | `shop_sync.apply_state`, `_ensure_view` |
| Shared cursors | `shop_sync.presence_rect` / `presence_target` |
| ui_nav shop follow | `main._try_follow_host_ui_nav` (`shop` / `snack_bar` arms) |

**Implemented, unmeasured** — static review + `gdparse`; no authorized live shop session yet.

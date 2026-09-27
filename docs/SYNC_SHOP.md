# Shared shop access and view following

Open the **Mod settings** gear in the lobby or beside **Lobby · F8** during play. Its slate panel separates personal view preferences from host-controlled match rules.

## Follow host shop view — personal, default OFF

Each client chooses whether its shop automatically follows the host between balls, the snack bar and the mixer, including inspected-item focus. With the default off, choose your own counter while shared inventory, money, purchases and teammate cursors continue to synchronize.

This local preference can change during a match and persists in the mod's isolated `together_hud.cfg`. Existing profiles with no saved choice also default off. The host does not force it on. Turning it off clears queued navigation immediately; turning it on follows the newest authoritative shop view after any active drag or pending transaction finishes. A closed settings slate cannot intercept input, and an open slate defers controller-driven navigation.

Both the shop-state and controller `ui_nav` paths honor this preference. Required round/shop transitions, payout, votes and authoritative transactions keep their existing rules. This setting does not create independent inventories or wallets.

## Shared shop access — host rule, default ON

The separately labeled **Shared shop access** toggle keeps the existing `sync_shop` match rule. It is host-only and fixed once a match starts. When enabled, guests receive the host's `remote_slots`, shared inventory and shop cursors. Automatic counter/focus following still requires each client's personal opt-in (PERF-009/010/026/029/035).

## Off mode

When **Shared shop access** is off:

- The table host shops with the local native shop through `shop_sync` as usual.
- Shop state is **not** broadcast as an open shared session. Guests receive a closed stub and never build remote slot replicas or shared shop cursors.
- Guest `ui_nav` follow of `shop` / `snack_bar` is suppressed (lobby / table / set_vote follow stay).
- Remote `shop_request` from non-hosts is rejected. On a multi-seat table, only the table host shops; teammates wait through the shop phase via ordinary table state. Multi-table lobbies already give each table host their own shop.

## Precedence

`set_exclusive_shopper` / winner-only shop (clone-table vs mode) **wins** over shared-access-off. Vs mode needs one authoritative shop, so exclusive shopping forces shared access for that shop session even when the lobby toggle is off. When the exclusive gate clears, access-off behavior resumes at the next shop close / open boundary. This override never enables a client's personal view-follow preference.

## Mid-match semantics

Like other ModOptions, the toggle is host-only and **locked once the match starts**. The match start copies `sync_shop` into `run_config`. `shop_sync` latches the flag at session begin and only refreshes it while no shop view is open, so a flag change can never tear down a shop a player is actively using.

## Gate points

| Concern | Location |
| --- | --- |
| Personal persisted view preference | `hud_prefs.follow_shop_view_enabled` / `set_follow_shop_view_enabled` |
| Personal settings UI | `settings_icon_button.gd`, `lobby_scene.open_mod_options`, `main._open_mod_settings/_set_follow_shop_view` |
| Shop section/focus follow | `shop_sync._queue_host_nav/_try_apply_queued_nav` |
| Lobby setting + snapshot | `lobby_state.sync_shop` / `set_sync_shop` |
| ModOptions row | `lobby_scene._ensure_sync_shop_toggle` |
| Wire closed stub | `shop_sync.wire_shop_state` ← `main._publish_state` / shop_result |
| Guest apply / remote slots | `shop_sync.apply_state`, `_ensure_view` |
| Shared cursors | `shop_sync.presence_rect` / `presence_target` |
| ui_nav shop follow | `main._try_follow_host_ui_nav` (`shop` / `snack_bar` arms) |

Runtime evidence and remaining live/platform/performance checks are recorded in [PERFORMANCE.md](PERFORMANCE.md). A local native capture does not establish simultaneous remote shopping or a latency gain.

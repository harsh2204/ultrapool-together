# Code map and change routes

Paths below are relative to the repository root. Locate functions with `rg -n` rather than relying on line numbers. This map describes v0.10.0; confirm the checked-out implementation before extending it.

## Roles and native boundary

- **Room host:** transport/lobby membership, frozen match configuration, authenticated routing, standings and watchers.
- **Table leader / table host:** native run, physics outcomes, shop inventory and wallet, effects, turn acceptance and round results for one table. May be a remote peer relative to the room host.
- **Guest:** native-looking replica, local input/hover/drag and permitted reversible shop predictions; sends requests and reconciles to the table leader.
- **Spectator:** separate presentation of another table. New guest state does not automatically render here.

`mod/main.gd::_ready` creates the services. The installed pack supplies `res://` scripts/scenes and singletons such as Global, BallDatabase, UIManager and AudioManager. Inspect both the wrapper and inherited implementation, including signals, exported types, child paths, shared Arrays/Resources and native saves. A parsed wrapper does not prove that a method or scene child exists in the supported native build.

## Main game loop

| Stage | Entry points | Preserve |
| --- | --- | --- |
| Lobby and frozen run | `lobby_state.gd`, `lobby_scene.gd/.tscn`, `run_setup.gd::capture_config/validate_config/start`, `main.gd::_start_match/_begin_table` | Host-only settings, per-player votes, native allowlists, readiness invalidation, identical frozen configuration. |
| Native catalog labels | `run_setup.available_choices`, `difficulty_catalog._resource_label/register`, `lobby_vote_option._layout_label`, `render_ui_fixtures.gd` | Native name fields contain translation keys. Resolve them before fallback, preserve distinct mod variant names, measure actual text lines and reserve the voter row. Register multiplayer resources in the database without appending to already-built native menu arrays that have parallel panels/indicators. |
| Local input | `native_player.gd::_process`, `game_adapter.gd::can_shoot/shoot`, `main.gd::can_control/submit_shot` | Actual native initial click/controller poll, menu/popup and turn gates; rendering changes must not falsify gameplay state. |
| Accepted shot | `main.gd::_take_shot` → `table_sync.capture/valid_capture` → `game_adapter.shoot` → reliable `shot_start` | Validate actor, turn and baseline before physics or ability callbacks; one accepted shot. |
| Active shot and settlement | `game_adapter.gd::_process/_raw_settled`, `main.gd::_process/_finish_shot`, `multiplayer_balls.gd`, `expansion_balls.gd` | Native settlement, effect ordering, score/shot budgets, one turn advance and reliable settled state. |
| Table delivery | `main.gd::_publish_snapshot/_received_table`, `table_sync.gd::capture/apply_snapshot/_snapshot_problem` | Match/scene/phase ordering, strict bounds, spawn barrier, reliable topology changes; targeted resync does not advance broadcast caches. |
| Native table effects | `table_effects_sync.gd`, `table_effects_view.gd`, `table_visual_fx.gd`, `table_visual_fx_view.gd`; `table_sync.effects_active`, `main._snapshot_refresh_due` | All six droplets, energy and WORMHOLE; cached allowlisted native visual catalog. Scriptless guests/spectators never run gameplay callbacks. Preserve bounded creation, latest-state cancellation, explicit overflow/recovery, reliable birth/removal and 100 ms updates while effects animate on a settled table. |
| Guest rendering | `replica_game.gd::prepare_scene/apply_table/_update_pockets/_set_item`, `replica_ball.gd`, `replica_fx.gd` | Retained nodes, no native gameplay callbacks on guests, changed-data setters, bounded transient effects. See [effect coverage](../../../../docs/TABLE_EFFECTS.md). |
| Payout and shop | `round_presentation.gd`, `shop_sync.gd`, `tests/round_flow_fixtures.gd` | Native payout/Continue, each client's acknowledgement, phase barriers; early shop data cannot skip payout. |
| Finish and teardown | `main.gd::_end_table/_reset_match/_disconnected`, `run_controls.gd`, service `end_session`, `table_sync.end_guest` | Restore native scripts, signals, globals and menus; clear pending work, identities, effects, votes and caches. |
| Spectating | `main.gd::_forward_watchers/_receive_watch`, `table_spectator.gd`, `spectator_scene.gd` | Table isolation, hydration, watcher-switch cleanup; independently implement any new effect presentation. |

Transport path: `transport.gd::_process/_receive_wire` → synchronous `main._received` → `table_router.gd::route` → table leader/guest. Receive budgets include handler cost; they cannot interrupt a single expensive native call. Commands/results/transitions are reliable; motion/presence may be disposable. Preserve authenticated actor identity and match/table routing. Read PERF-001–014 before changing this path.

`presence.gd` sends local cursor/aim presentation. `cue_catalog.gd` and `cue_prefs.gd` provide personal finishes. `cue_models.gd`, `cue_inventory.gd`, `cue_effect_rules.gd` and `cue_effects.gd` own the fifteen-cue catalog, authoritative run equipment and bounded host perks. `cue_visuals.gd` caches cue art and changes the native sprite without taking ownership of native pivot fade or charge pose.

`multiplayer_ball_catalog.gd` registers the always-visible `TOGETHER` collection set independently of its opt-in drop gate. `multiplayer_collection.gd` appends one native set section to the balls gallery list at readiness and preserves initialized inspector fields when installing `multiplayer_info_display.gd`. The latter extends native keyword helpers using only the existing four panels. Native Play-menu arrays, discovery records and starting decks remain separate from collection visibility. `tests/multiplayer_collection_fixture.gd` covers this through the shared capture harness.

## Shop, snack bar and mixer

The **host** uses the installed native `res://ui/shop.gd`. `mod/native_shop.gd` is the **guest** wrapper; its save/play/reroll callbacks are intentionally inert. Editing that file alone does not add host gameplay.

| Concern | Read these functions |
| --- | --- |
| View lifecycle | `shop_sync.begin_session/end_session/_ensure_view/_clear_guest_view/_display_state`; `native_shop.ensure_remote_layout/apply_state`. |
| Wire state and catalog checks | `shop_sync.capture/_pack_slot/_valid_state`; `player_inventory_sync.gd` for the inventory carried outside the shop. |
| Actual drag | `native_shop_ball.gd`, `native_shop_passive.gd`; `shop_sync._begin_native_drag/_drop_native_item/_bind_native_item`. Native motion stays local; a completed drop submits intent. |
| Request and reconciliation | `shop_sync._submit/_predict_state` → `main._shop_request/_table_send/_route_table/_received_table` → `shop_sync.handle_request/_apply_item_action` → `apply_result`. |
| Buttons and restoration | `shop_sync._bind_action/_restore_items`: retain and restore original scripts and signal connections. Never bind a guest button straight to native spending or save callbacks. |
| Replica items | `native_shop._sync_items`: retain host item IDs/nodes; preserve inspection, drags and pending state. Slot reassignment remains a PERF-032 optimization gap. |
| Counter visibility | `main._annotate_shop_counters` and `native_shop.apply_state`: use authoritative `show_tapas/show_cocktail`, not the guest's local unlocks. |
| Navigation | `shop_sync.current_section/show_section/_try_apply_queued_nav/nav_interaction_blocked`, `ui_nav.gd`, `main._try_follow_host_ui_nav`: defer during interaction. View-only changes do not change the transaction revision. |

Slot vocabulary is a protocol contract:

| Group | Source and valid use |
| --- | --- |
| `offer` | Native ball offers; shared-money purchase into build. |
| `build` | Shared inventory/reserve slots; source for sale, rearrangement and mixer inputs. |
| `snack` | Tapas passive offers; spend a snack ticket to move into an empty `passive` slot. |
| `passive` | Owned passive inventory; uses `BallDatabase.id_to_passive`, not the ball catalog. |
| `mix` | Left/right inputs 0/1, center output 2. Only unmixed build balls enter empty inputs with a ticket and empty center. Host `can_mix` gates action `mix`; native cocktail callback creates the result. Output returns to an empty build slot. Never accept a direct drop into output 2. |

Ready cannot finish with occupied cocktail slots. Transaction validation includes actor eligibility, phase/busy/finished/exclusive-shopper gates, revision, source and destination identity, type and affordability. One pending guest mutation is reconciled by matching request ID, authoritative result, timeout and resync. Prediction never awards currency or gameplay effects.

Shop sections are `balls`, `mix`, `snacks`, and `cues`; snacks use UI-navigation place `snack_bar`, while cues use `shop` plus `section=cues`. Personal `HudPrefs.follow_shop_view_enabled()` defaults false and gates **both** shop-state navigation and controller `ui_nav`; clear queued follow immediately on opt-out. `settings_icon_button.gd` opens the slate via `main._open_mod_settings` / `lobby_scene.open_mod_options`, including during matches. The separately labeled **Shared shop access** is the existing host `sync_shop` rule. With access off, guests cannot shop the leader's run; it does **not** create independent guest wallets. Winner-only/exclusive shopping overrides access-off for that session, never the personal follow preference. Read [SYNC_SHOP.md](../../../../docs/SYNC_SHOP.md).

`shop_sync._ensure_cue_view` attaches Rook's `cue_shop.gd` counter at the right edge. The host's `cue_shop_enabled` lobby rule defaults on and freezes in `run_config`; `main.cue_shop_enabled()` gates cue handling/effects/model selection, while `shop_sync` latches it at session start to gate construction, navigation and transactions. Cosmetic starting finishes remain available when it is off. `cue_seller.gd` owns local blink/talk/nudge presentation; `cue_shop_art.gd` caches its two PNGs once. Fifteen portrait cards and the confirmed equipment case are retained. One replaceable rack tween and seller speech/idle work stop when leaving the counter. The case reads confirmed equipment, never local preview. See the completed [Rook integration record](../../../../docs/ROOK_CUE_COUNTER.md) for ownership, bounds and authored/unrun coverage.

## Adding content

Use the [change template](../assets/shop-content-change.md), then choose the actual seam:

- **Ball in an existing optional set:** `sets/phases_catalog.gd` demonstrates IDs, offers and registration; `sets/catalog_util.gd` registers ball resources and caches 2:1 source art from `mod/assets/balls`. It intentionally does not add starting decks or set-vote entries. Rules live in the matching `*_rules.gd`; `expansion_balls.gd` coordinates host-only shot/hit/wall/pocket callbacks and `prepare_shop`. Extend `capture/valid_state/apply_state/display_signature` together for new shared display data.
- **Whole optional set:** also update `sets/registry.gd`, `expansion_balls.setup/_rules_file` and lobby master/per-set gating. Disabled content must remain unavailable even with stale flags. Check [EXPANSION_SETS.md](../../../../docs/EXPANSION_SETS.md).
- **Multiplayer ball:** inspect `multiplayer_ball_catalog.gd`, `multiplayer_ball_rules.gd`, `multiplayer_balls.gd`, `multiplayer_ball.gd` and [MULTIPLAYER_BALLS.md](../../../../docs/MULTIPLAYER_BALLS.md). Preserve host callback ordering, deduplication and round caps.
- **Snack/passive:** needs passive-resource registration and the snack/passive transaction path. The ball registrar is not a passive API. Trace inventory capture/validation/apply and native passive hooks before designing it. Exchanging a snack ticket for a **ball** is a new service action, not a normal `snack → passive` purchase; do not spoof slot types or call `buy_passive` for it.
- **Shop character/NPC:** no general repo character registry exists. Native shop binds a typed `ShopGirl`; cocktail bar binds a typed `ShopBoy`. Inspect installed exports/methods before replacing art or bindings. A proposed mod-owned visual attached once through `_ensure_view` can preserve these objects; release it on view teardown. This is a new pattern to implement, not an existing `mod/characters` API. Decorative controls must pass through pointer input. Any service that spends money/tickets needs the authoritative request path, separately from dialogue/art.

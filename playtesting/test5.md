### 5th Playtesting — Bugs & Feature Requests

## Root Causes

- **RC-5A — Client `day_time_over` flag never reset between days**
  The host clears `DayManager.day_time_over` when a new phase begins, but clients only ever *set* it (via `_sync_day_timer` / `_sync_day_over`). `end_day_trigger` and `player_house_door` also only re-armed their `_ready_to_end` on `Phase.MORNING`, so a sign lit at 6 PM stayed lit into the evening phase.
  - **Evidence:** Client clock shows 6:00 but the end-day sign/door reports "It's not 6 pm yet" the next day; sign stays lit during evening.
  - **Status:** Addressed in code — `_sync_day_phase` resets `day_time_over` on clients whenever the phase isn't DAY; sign and door now re-arm on every non-DAY phase instead of only MORNING.

- **RC-5B — Customers registered as trash spawn candidates**
  `CustomerSpawner` added every spawned customer to the `trash_spawn_candidates` group in both spawn paths (`_spawn_at_slot`, `spawn_converted`). `TrashSpawner` picks drop targets from that group, so converted customers were littering.
  - **Evidence:** Customers standing in queue drop trash.
  - **Status:** Addressed in code — customers are no longer added to the group; only free-roaming pedestrians can be picked.

- **RC-5C — Route 1 crosses stand 2's queue line**
  Route 1's world-space waypoints run along z ≈ -21, straight through stand 2's queue area (stand 2 sits at ~(-8, 0, -24), queue along z ≈ -21.1). Stand 2 only exists in versus mode, so the route is fine in solo/coop.
  - **Evidence:** Pedestrians walk through the rival stand's queue in 2-stand mode.
  - **Status:** Addressed in code — `PedestrianPath.is_usable()` gates on a new `single_stand_only` export; Route 1 is flagged in `world.tscn`, and both `PedestrianSpawner` and `PeopleManager` filter unusable routes.

- **RC-5D — Pedestrian feedback label never sized; RPC order hid it on clients**
  `_resize_order_panel` positioned `_ui_label` but never set its `size` — with CENTER alignment the text centered on a zero-size rect and landed offset to the right of the panel (customer.gd already set `size` correctly). Separately, `try_serve()` sent `sync_show_order_text` *then* `sync_serving` — the serving RPC's `_hide_order_bubble()` hid the label, then the deferred `_resize_order_panel` re-showed the panel unconditionally → clients saw an empty panel.
  - **Evidence:** Host sees feedback text offset right of the bubble; clients see an empty panel with no text.
  - **Status:** Addressed in code — `_ui_label.size = label_size` added; `try_serve` now sends `sync_serving` before `sync_show_order_text`.

- **RC-5E — Cup recipe degrades as the pitcher drains**
  `pour_portion()` snapshots the pitcher's *total remaining* contents before each pour and drains proportionally. `RecipeEvaluator.evaluate_detailed` compares absolute `fruit_count`/`sugar`/`ice` against ideals, so each later cup is evaluated as a weaker recipe than the one the player made.
  - **Evidence:** On a client, filling successive cups shows lemon/sugar values dropping and later cups score worse.
  - **Status:** Addressed in code — the pitcher now freezes `serving_recipe` at the first pour and every cup carries it until the pitcher is emptied (`_clear_and_return`). `serving_recipe` is included in `_sync_state_to_peers` so whichever peer pours next uses the frozen recipe.

- **RC-5F — `_find_node` name cache ignored the parent**
  `WorldSync._find_node` cached and returned nodes by bare name. In versus mode both stands can hold same-named spawned nodes (e.g. two "Pitcher" nodes under different parents), so a client's `sync_properties` push could land on the wrong stand's object.
  - **Evidence:** Cross-stand property sync landing on the wrong node when net_id lookup misses.
  - **Status:** Addressed in code — `_find_node` no longer uses the bare-name cache for path lookups; after the exact parent lookup it prefers a name match whose parent path matches, and only falls back to a name-only search for reparented nodes.

- **RC-5G — World snapshot applied in a single frame on join**
  `_apply_world_snapshot` instantiated every container and supply box synchronously — hundreds of nodes in one frame → the "0.1 fps" freeze. The host also skipped sending the snapshot entirely when it was empty, so the client had no completion signal.
  - **Evidence:** Joiner's game freezes when transitioning into a running lobby/game.
  - **Status:** Addressed in code — snapshot apply is chunked across frames (12 spawns/frame), `world_snapshot_applied` is emitted on completion, and `sync_world_state_to_peer` always sends (even when empty). The late-join "Day X" screen now holds until the snapshot finishes, with a 15 s safety timeout.

## Feature Updates

- **FU-5A — Delivery work hours (shop closes at 6 PM)**
  Ordering is now gated on `DayManager.day_time_over`, which is already synced to clients. The phone menu shows a "Closed for today" overlay covering the order list, all three buy paths (`_order`, `_buy_container`, `_buy_upgrade`) reject with a hint, and the host-side `_request_purchase` RPC drops any purchase request that arrives after closing.
  - **Status:** Addressed in code.

- **FU-5B — Late join loads behind the Day X screen**
  The joiner stays in the lobby until ready (already the case). On ready, the host pushes world state and the client holds the black "Day X" overlay until `world_snapshot_applied` fires — the chunked spawn keeps the transition animating instead of hitching.
  - **Status:** Addressed in code (see RC-5G).

## Known Limitations / Not Done

- Pitcher pouring still runs on the clicking peer and pushes state to the host (inverted vs. the target request → host → broadcast pattern). The frozen recipe makes the outcome consistent, but a fully host-authoritative pour is a larger refactor for later.
- `WorldSync._find_node_by_name_only` still caches by bare name — left as-is since it's only used for NPC transform syncs where names are unique.

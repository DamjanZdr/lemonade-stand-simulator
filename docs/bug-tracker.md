# Bug Tracker — Lemonade Stand Simulator

> Tracking file for the current batch of reported multiplayer/onboarding issues.
> Update this file as each issue is investigated, fixed, and verified.

## Active Issues

### 15. Implement per-stand popularity conversion and HUD display
- **Reported:** design request
- **Symptom:** Popularity was not fully wired into gameplay — NPC conversion used global GameState.popularity (the legacy primary stand), and there was no visible popularity meter.
- **Root cause:** The code already tracked per-stand `StandUnit.popularity`, but `Pedestrian._get_convert_chance()` read `GameState.popularity` regardless of which stand an NPC was approaching. `PedestrianSpawner` only used popularity for stand *selection* after a generic conversion decision, so a versus stand's popularity didn't affect its own foot traffic. Additionally, popularity was not shown in the HUD, and per-stand popularity was not saved/restored.
- **Fix:**
  - `Pedestrian._arrive()` now simply reports that it hit a convertable waypoint; the actual conversion decision lives in `PedestrianSpawner._on_wants_to_join()`.
  - The spawner runs an independent popularity roll for every registered stand. Stands that succeed become candidates.
  - If one candidate wins, it gets the customer. If several win, a weighted popularity contest picks among them (40 vs 40 → 50/50, 40 vs 20 → 66/33, etc.).
  - If no stand wins, the pedestrian resumes its route.
  - Routes remain neutral — any route can feed any stand.
  - HUD shows `Pop: X%` under the money label, colored from red to green by value.
  - `SaveManager` persists and restores `stand_popularity` so versus reputation survives quit/rehost.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/customer/pedestrian.gd`, `scripts/customer/pedestrian_spawner.gd`, `scripts/ui/hud.gd`, `scripts/systems/save_manager.gd`

### 14. Secondary stand gets $150 after host quits and rehosts
- **Reported:** playtest batch (post a54d8c4)
- **Symptom:** In versus, if the host quits the game entirely, reopens it, and invites the same friend to Stand 2, Stand 2 starts with $150 again even if the friend had already spent it during the previous session. Going to the menu and restarting the same save (without quitting the application) did not reproduce it.
- **Root cause:** Saves only stored `GameState.money` (the legacy primary-stand balance). `StandUnit.money` for non-primary stands was never persisted, so on a fresh application start the secondary stand's `_ready()` reset it to `Balancing.STARTING_MONEY` ($150). In-session menu restarts didn't trigger the same full scene-reload + default-reset path, which is why the bug appeared only after a full quit.
- **Fix:** `SaveManager._build_save_dict()` now collects per-stand money (`stand_money`, keyed by node name), and `apply_save_to_game_state()` restores each `StandUnit.money` from the saved map with a sensible legacy fallback for older saves.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/systems/save_manager.gd`

### 10. Floating filled cup stuck near joiner's head (host's view)
- **Reported:** playtest batch (post d91584d)
- **Symptom:** Host watches joiner. Joiner fills a cup from the pitcher → a floating filled cup appears near the joiner's head (only on the host's view; joiner doesn't see it). Dropping the cup doesn't remove it. It disappears the moment the joiner sells a cup, then reappears on the next fill.
- **Root cause:** Held items are first-person-only — remote players never render what someone is holding. But `Pitcher._fill_cup_for_player` runs on the host and called `inventory.set_held(CUP_FILLED, ..., cup_mesh)` on the joiner's *remote player node*, attaching a visible cup mesh to its hand slot. The joiner's `clear_held()` never propagated to the host, so the mesh stayed until a host-side path (customer sale) cleared the remote node itself.
- **Fix:** `PlayerInventory.set_held()` now refuses to attach a hand mesh on any node this peer doesn't have authority over (remote nodes purge the slot and free the mesh instead) — the whole class of "floating item on another player" is closed. Held *state* (item type + data) is still mirrored to the host via `WorldSync.request_held_item_sync()` so host-side logic like serve checks stays accurate, with payloads sanitized (`_rpc_safe_dict`) so non-RPC-serializable entries can't error the send.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/player/player_inventory.gd`, `scripts/multiplayer/world_sync.gd`

### 11. Water-only pitcher/cup shows "Unknown" instead of "Just water"
- **Reported:** playtest batch (post d91584d)
- **Symptom:** A pitcher or cup containing only water displays "Unknown" instead of "Just water".
- **Root cause:** Three display paths treated a water-only recipe (no fruit/sugar/ice keys > 0) as unknown: `Cup._recipe_string()` and `PlayerInteraction._recipe_hint_string()` returned "unknown"/"unknown recipe" for empty parts lists, and `RecipeEvaluator.get_verdict_string()` returned "FAIL: unknown fruit type" on the debug panel for `fruit_type == ""` with only water.
- **Fix:** All three now return "Just water" when the recipe has water but no other displayed ingredients. `Pitcher.get_contents_string()` also capitalized to "Just water" for consistency.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/objects/cup.gd`, `scripts/player/player_interaction.gd`, `scripts/systems/recipe_evaluator.gd`, `scripts/objects/pitcher.gd`

### 12. Water cups appear yellow when placed on the stand
- **Reported:** playtest batch (post d91584d)
- **Symptom:** A water-only cup shows the correct water color while held, but appears yellow once placed on the stand.
- **Root cause:** `Cup._ready()` called `_refresh_fill_visibility()` but never `apply_fill_color()`. Spawned cups get `fill_color` set via spawn state before `_ready`, so the property was correct but the Fill mesh kept the GLB's default yellow material. Held cups go through `Cup.make_hand_mesh()` which applies the color — hence the held/placed mismatch.
- **Fix:** `_ready()` now calls `apply_fill_color()` after `_refresh_fill_visibility()`.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/objects/cup.gd`

### 13. Joiner can't fill cups from pre-existing pitchers until re-picked
- **Reported:** playtest batch (post d91584d)
- **Symptom:** When a player joins mid-game, pitchers that already contained lemonade exist in the world, but the joiner can't fill a cup from them until they pick the pitcher up and place it down again.
- **Root cause:** Cup fill used node-path RPCs on the `Pitcher` itself (`_rpc_request_fill_cup`, `_rpc_fill_cup_result`). A snapshot-restored pitcher on the joiner is parented to the scene root, while the host's copy can be parented elsewhere (snapped under a press/dispenser) — so the RPC resolves to a different path on the remote peer and silently drops. Worse, `_fill_request_pending` stayed `true` forever after a dropped request, so every subsequent interact early-returned. Re-picking respawned the pitcher under matching parents and reset the flag — which is why that "fixed" it.
- **Fix:** Fill request and result now route through `WorldSync` (autoload, identical path on every peer) keyed by `net_id`: `request_pitcher_fill_cup` → `_rpc_request_pitcher_fill_cup` on host → `pitcher._fill_cup_for_player()`, then `deliver_pitcher_fill_result` → `_rpc_pitcher_fill_result` → `pitcher.apply_fill_cup_result()` (clears pending flag + sets the local player's held cup). A 3-second stale-timeout also clears a wedged pending flag as a safety net.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/objects/pitcher.gd`, `scripts/multiplayer/world_sync.gd`

### 1. Missing task: "Take pitcher out of press and place it on the table"
- **Reported:** current batch
- **Symptom:** After squeezing lemons dry, there is no task prompting the player to move the pitcher to the table.
- **Root cause:** `demo_move_pitcher_to_workstation` was marked `retroactive: true`, so if the player already placed the pitcher on a table earlier during the "place equipment" task, it auto-completed the moment `demo_squeeze_lemons` finished.
- **Fix:** Removed `retroactive: true` from `demo_move_pitcher_to_workstation`.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/autoloads/onboarding_manager.gd`

### 2. Pitcher behaves like two pitchers / can pour far more than 10 cups
- **Reported:** current batch
- **Symptom:** Pitcher stays visually full for many cups; total pours exceed a single pitcher's capacity.
- **Root cause (updated):** Two separate problems reinforce each other:
  1. `_ensure_default_objects_registered()` was assigning net IDs on **clients** too, so the same object had a different `net_id` on host and client. A client despawn request could fail on the host, leaving the original object behind, while the host later spawned a replacement.
  2. The host didn't mark pending despawns or use a global name fallback, so in-flight snapshots could resurrect a freshly-picked-up object as a duplicate.
- **Fix:**
  - Only the host assigns net IDs now; clients rely on host-provided IDs from snapshots/spawns.
  - Host and client both mark recently-despawned net IDs as pending and skip them in snapshots and client spawn RPCs.
  - `_rpc_request_despawn` falls back to a global name search if the net_id/parent lookup fails.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/multiplayer/world_sync.gd`

### 3. PvP — host recipe board edits leak to the rival stand
- **Reported:** current batch
- **Symptom:** In versus mode, changing the recipe on Stand 1's board also updates the labels on Stand 2's board for the joiner.
- **Root cause (updated):** The primary stand writes to `GameState` and emits `EventBus.recipe_changed`. Every blackboard was listening to that global signal, so Stand 2's board updated its labels from the primary stand's recipe even though its own `StandUnit.recipes` stayed correct.
- **Fix:** Blackboards now connect to their own parent `StandUnit.recipe_changed` signal. They only fall back to `EventBus.recipe_changed` when not parented to a stand (test/dev scenes).
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/objects/blackboard.gd`

### 4. Joiner sees customers slide instead of walking when queue advances
- **Reported:** current batch
- **Symptom:** Host sees the walk animation when a customer steps forward; joiner just sees a positional slide.
- **Root cause:** `Customer.step_forward()` transitioned to `WALKING` locally on the host but did not broadcast the state/animation change.
- **Fix:** Added `sync_state(CustomerState.WALKING, "Walk")` when `step_forward()` leaves `WAITING`.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/customer/customer.gd`

### 5. Floating non-functional cup on the joiner
- **Reported:** current batch
- **Symptom:** Host sees a cup floating near the joiner's shoulder. The joiner is not actually holding a cup.
- **Root cause (updated):** Same duplicate-despawn failure as issue #2. A duplicated/stale cup can get stuck as a child of the player's hand slot. Also, `_create_container_hand_mesh()` disabled the FruitBin script before the correct fruit amounts were rendered, so the stale mesh could show the wrong visual.
- **Fix:**
  - Applied the duplicate-despawn/net_id fixes from issue #2.
  - Added authority-only `_process` cleanup in `PlayerInventory` that removes any leftover hand-slot children when the inventory is empty.
  - For FruitBin hand meshes, `update_display()` is now called **before** the script is stripped so the held crate shows the actual contents.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/multiplayer/world_sync.gd`, `scripts/player/player_inventory.gd`, `scripts/player/player_placement.gd`

### 6. Pitcher can be pulled off the water dispenser mid-fill
- **Reported:** current batch
- **Symptom:** Player can take the pitcher off the dispenser while it is actively filling.
- **Root cause (updated):** Two holes:
  1. `WaterDispenser` only checked `_is_filling`; the `locked_by_dispenser` flag was not set early enough and was not synced to peers.
  2. The pitcher itself has a `Pickupable` component that handles direct clicks on the pitcher mesh. That callback did not check `locked_by_dispenser`, so clicking the pitcher (rather than the dispenser) could steal it mid-fill.
- **Fix:**
  - Set and sync `locked_by_dispenser = true` immediately on fill request; sync `locked_by_dispenser = false` in the finish-fill state broadcast.
  - `WaterDispenser.interact()` and `interact_secondary()` refuse to take the pitcher while filling or locked.
  - `Pitcher._ready()` now wraps the `Pickupable.can_pickup_callback` so the pitcher cannot be picked up directly while `locked_by_dispenser` is true.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/objects/water_dispenser.gd`, `scripts/objects/pitcher.gd`

### 7. Fruit crate held in hand shows all fruits instead of actual contents
- **Reported:** current batch
- **Symptom:** A picked-up fruit bin renders every fruit type at once while held; after placing it, the display is correct.
- **Root cause:** `FruitBin.update_display()` needs `fruit_grids`, which are only populated in `_ready()`. `_create_container_hand_mesh()` was calling `update_display()` on a node that had never entered the tree, so `fruit_grids` was empty and the default scene visibility stayed.
- **Fix:** Add the FruitBin hand mesh to a temporary tree node so `_ready()` runs and builds `fruit_grids`, then call `update_display()` before detaching it for the hand slot. Also remove the leftover `Pickupable` component from the hand mesh.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/player/player_placement.gd`

### 8. Held pitcher looks empty even when full
- **Reported:** current batch
- **Symptom:** A pitcher that shows liquid when placed on a surface appears empty while held in first-person.
- **Root cause:** `_create_container_hand_mesh()` instantiated the pitcher scene and immediately stripped its script, so `Pitcher._ready()` never ran. `_ready()` is what hides the legacy GLB lemonade cylinders, sets the CSG fill eraser position, and applies the liquid color.
- **Fix:** Briefly add the pitcher hand mesh to a hidden temp node so `_ready()` executes. Keep the script active (the held pitcher must still respond to water refills and emptying), but remove the `Pickupable` component and disable physics/groups so it doesn't behave like a placed object.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/player/player_placement.gd`

## Fixed / Closed Issues

### 9. Pitcher yields ~19+ cups and doesn't visibly drain (versus, both stands)
- **Reported:** current batch
- **Symptom:** Pitcher appears full for ~9 cups; starts visibly lowering around the 9th–10th cup; a "full" pitcher yields ~19 cups instead of 10.
- **Root cause (updated):** Three compounding problems:
  1. `pour_portion()` computed `portion_ratio = PORTION_SIZE / current_volume` from the *remaining* volume each pour — exponential drain.
  2. `WaterDispenser._process` advances `_fill_progress` on **every** peer (set by the broadcast `_play_fill_visual`). When the timer completes, each client calls `_finish_fill()` → `request_container_action("finish_fill")` → host's `apply_finish_fill()` runs a **second time**, adding the water twice. Every multiplayer fill therefore pushed the pitcher to ~18-19 liquid — `vol/10` stays clamped at full for ~9 pours ("10/10") and yields ~19 cups. Explains both stands: any fill with another peer connected double-adds.
  3. `start_fill()` also trusted the client's stale `space` arg (now recomputed on host), and `end_press_eraser_animation` was only called on the host, leaving `_suppress_eraser_updates` stuck on clients.
- **Fix:**
  - `get_recipe_snapshot()` stores `_initial_volume`; each cup removes a fixed fraction of the *initial* amounts → exactly 10 cups from a full pitcher.
  - `apply_finish_fill()` is now idempotent (no-ops if `_is_filling` is already false), and `start_fill()` ignores requests while filling.
  - `start_fill()` recomputes fill amount from host-authoritative pitcher liquid.
  - `apply_finish_fill()` broadcasts `end_press_eraser_animation` so every peer unsuppresses eraser updates.
  - Added GameLog lines on pour/fill/clear so pitcher volume history can be inspected via the F10 debug console or `game_log.txt`.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/objects/pitcher.gd`, `scripts/objects/water_dispenser.gd`

*(None verified in a live playtest yet.)*

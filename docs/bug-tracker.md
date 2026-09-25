# Bug Tracker — Lemonade Stand Simulator

> Tracking file for the current batch of reported multiplayer/onboarding issues.
> Update this file as each issue is investigated, fixed, and verified.

## Active Issues

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
- **Root cause (updated):** Two separate problems:
  1. `pour_portion()` computed `portion_ratio = PORTION_SIZE / current_volume` from the *remaining* volume each pour — exponential drain, so the level barely moved early on and the pitcher never emptied in its real capacity.
  2. `WaterDispenser` trusted the requesting peer's `space` argument, computed on a possibly-stale local liquid view. A stale-low view sent `start_fill(≈8-10)` on an already-fuller pitcher, overfilling it to ~18-19 liquid. `t = vol/10` then clamps at full for the first ~9 pours (stays "10/10") and the pitcher serves ~19 cups.
  3. Bonus: `_play_fill_visual` ran `start_press_eraser_animation` on all peers but `end_press_eraser_animation` (which clears `_suppress_eraser_updates`) was only called on the host — client fill visuals could stay frozen.
- **Fix:**
  - `get_recipe_snapshot()` stores `_initial_volume`; each cup removes a fixed fraction of the *initial* amounts → exactly 10 cups from a full pitcher.
  - `start_fill()` recomputes the fill amount from the host-authoritative pitcher liquid, ignoring the client's stale `space` arg.
  - `apply_finish_fill()` broadcasts `end_press_eraser_animation` so every peer unsuppresses eraser updates.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/objects/pitcher.gd`, `scripts/objects/water_dispenser.gd`

*(None verified in a live playtest yet.)*

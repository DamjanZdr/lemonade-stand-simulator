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
- **Root cause:** `_is_filling` was the only guard. There is a small window between requesting a fill and the sync arriving where another peer (or the same peer via a different input path) could grab the pitcher. The pitcher lock (`locked_by_dispenser`) was not set early enough.
- **Fix:**
  - Set `_snapped_pitcher.locked_by_dispenser = true` immediately when a fill is requested, before the host RPC.
  - Both `interact()` and `interact_secondary()` now refuse to take the pitcher while `_is_filling` OR `locked_by_dispenser` is true.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/objects/water_dispenser.gd`

### 7. Fruit crate held in hand shows all fruits instead of actual contents
- **Reported:** current batch
- **Symptom:** A picked-up fruit bin renders every fruit type at once while held; after placing it, the display is correct.
- **Root cause:** `_create_container_hand_mesh()` stripped the FruitBin script before calling `update_display()`, so the default scene visibility (all fruit meshes visible) remained.
- **Fix:** Call `(inst as FruitBin).update_display()` immediately after restoring `fruit_amounts` and before `_disable_scripts()`.
- **Status:** fixed in code — needs playtest verification
- **Files:** `scripts/player/player_placement.gd`

## Fixed / Closed Issues

*(None verified in a live playtest yet.)*

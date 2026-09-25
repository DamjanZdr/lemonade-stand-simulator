# Bug Tracker — Lemonade Stand Simulator

> Tracking file for the current batch of reported multiplayer/onboarding issues.
> Update this file as each issue is investigated, fixed, and verified.

## Active Issues

### 1. Missing task: "Take pitcher out of press and place it on the table"
- **Reported:** 2025-??-??
- **Symptom:** After squeezing lemons dry, there is no task prompting the player to move the pitcher to the table.
- **Root-cause hypothesis:** `demo_move_pitcher_to_workstation` is marked `retroactive: true`, so if the player already placed the pitcher on a table earlier during the "place equipment" task, it auto-completes the moment `demo_squeeze_lemons` finishes and the player never sees it.
- **Fix:** Remove `retroactive: true` from `demo_move_pitcher_to_workstation` so it is always required when active.
- **Verification:** Start a new save, do the tutorial through squeezing lemons, confirm the move-pitcher task appears.
- **Status:** fixed in `scripts/autoloads/onboarding_manager.gd`

### 2. Pitcher behaves like two pitchers (host fills 18 cups from one pitcher)
- **Reported:** 2025-??-??
- **Symptom:** Pitcher stays full for many cups, then suddenly starts draining; total cups poured exceeds a single pitcher's capacity.
- **Root-cause hypothesis:** Default-scene / pre-placed pitchers/cups are not getting a stable `net_id` before despawn. The host/client fails to find the original object, leaves it behind, and a duplicate full pitcher remains hidden/overlapping with the moved one.
- **Fix:** Make `WorldSync` register default objects before despawn, track pending despawns, and ignore snapshot/spawn for net_ids that are pending despawn.
- **Verification:** Place a pitcher, fill it, move it, and confirm you can only pour the expected number of cups.
- **Status:** fixed in `scripts/multiplayer/world_sync.gd`

### 3. PvP — host setting recipe on their board changes rival stand recipes
- **Reported:** 2025-??-??
- **Symptom:** In versus mode, editing the recipe board for one stand writes the recipe to the other stand.
- **Root-cause hypothesis:** `Blackboard._find_nearest_stand()` uses nearest-stand fallback even when the blackboard already has a parent `StandUnit`, so the wrong stand may be targeted if scene layout is close.
- **Fix:** Make `_find_nearest_stand()` prefer the already-known parent `_stand` and only fall back to distance search.
- **Verification:** In a versus lobby, edit each stand's board separately; recipes stay isolated.
- **Status:** fixed in `scripts/objects/blackboard.gd`

### 4. Customers slide instead of walking when advancing in queue (joiner view)
- **Reported:** 2025-??-??
- **Symptom:** For the host, queue customers animate correctly when stepping forward. For joiners, they slide to the new slot.
- **Root-cause hypothesis:** `Customer.step_forward()` transitions `WAITING -> WALKING` locally on the host but does not call `sync_state()`, so clients keep playing the idle animation while only receiving position interpolation.
- **Fix:** Call `sync_state(CustomerState.WALKING, "Walk")` in `step_forward()` when the state becomes WALKING.
- **Verification:** Host serves the front customer; joiner sees the next customer play the walk animation to the front.
- **Status:** fixed in `scripts/customer/customer.gd`

### 5. Floating non-functional cup on joiner
- **Reported:** 2025-??-??
- **Symptom:** Host sees a cup floating near the joiner's shoulder. The joiner has no cup in inventory.
- **Root-cause hypothesis:** Same root as issue #2: a duplicated cup from a failed despawn becomes parented to/associated with the player and stays as a stale visual mesh. The hand-slot cleanup path may also miss meshes created outside the normal pickup flow.
- **Fix:** Apply the duplicate-despawn fix from #2, plus a defensive hand-slot cleanup in `PlayerInventory` when `held_item == HeldItem.NONE` but children remain.
- **Verification:** Pick up, serve, and place filled cups as a joiner; confirm no phantom cup remains.
- **Status:** fixed in `scripts/multiplayer/world_sync.gd` and `scripts/player/player_inventory.gd`

## Fixed / Closed Issues

*(None in this batch yet.)*

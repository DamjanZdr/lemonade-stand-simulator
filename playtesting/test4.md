### 4th Playtesting — Bugs & Feature Requests

## Root Causes

- **RC-4A — NpcNamer's `_managed` guard blocked PeopleManager's direct spawn calls**
  The NpcNamer debug tool set `PedestrianSpawner._managed = true` to pause spawning. But `PeopleManager._find_spawner()` also sets `_managed = true` on startup (by design — it tells the spawner to let PeopleManager handle scheduling). The `_managed` guard added to `spawn_on_path()` blocked the very call PeopleManager makes to spawn NPCs, so no pedestrians could spawn during the day. The spawner's own `_on_day_phase_changed` also returned early when `_managed` was true, so the timer was never started/stopped — leading to erratic spawn timing (e.g. after 6pm).
  - **Evidence:** NPCs don't spawn during the day; they spawn after 6pm or not at all.
  - **Status:** Addressed in code — introduced a separate `_paused` flag for the NpcNamer tool. `_managed` only disables the spawner's own timer; `_paused` blocks all spawn paths.

- **RC-4B — `snap_pitcher` is never called on clients**
  `WorldSync.request_spawn()` returns `null` on clients, so `press.snap_pitcher(placed)` in `player_interaction.gd` is skipped on non-host peers. The press's `_snapped_pitcher` stays `null`, the `Pickupable.can_pick_up` guard passes, and the press is picked up while the pitcher remains. The onboarding `pitcher_placed` event is also never reported on clients.
  - **Evidence:** Press picked up with pitcher left behind; onboarding "place pitcher under press" doesn't register.
  - **Status:** Addressed in code — added `_pending_snap_pitcher_net_id` synced via `WorldSync.sync_property`. Clients resolve the net_id in `_process` and set `_snapped_pitcher` once the pitcher is replicated.

- **RC-4C — Unowned surfaces treated as valid placement targets**
  `_is_placement_allowed_on()` returned `true` when `surface_owner == ""`, allowing placement on sidewalks and other neutral surfaces that are in the `placement_surface` group but don't belong to any stand.
  - **Evidence:** Cup blueprints show green on the sidewalk outside the player's placable area.
  - **Status:** Addressed in code — unowned surfaces now return `false` in multiplayer.

- **RC-4D — Trashcan had no branch for `HeldItem.SUPPLY_BOX`**
  Unopened equipment boxes are held as `HeldItem.SUPPLY_BOX`, but `Trashcan.interact()` only handled `is_trash` and `HeldItem.CONTAINER`. The interaction silently fell through, making it impossible to sell an unopened box directly.
  - **Evidence:** Trashing a placed bowl works, but trashing the unopened box containing it doesn't.
  - **Status:** Addressed in code — added a `SUPPLY_BOX` branch that refunds 70% of equipment cost (or `empty_box_refund` for ingredient boxes).

- **RC-4E — Delivery truck had no auto-restart for orders placed while busy**
  `start_delivery()` was a no-op when the truck was not idle. Boxes ordered during a delivery were queued in `_pending_boxes` but never delivered if the truck was driving away. `_drive_away()` cleared `_pending_boxes`, and nothing checked for leftover boxes when the truck returned to idle.
  - **Evidence:** Orders placed while the truck is en route don't get delivered until a subsequent order triggers a new delivery.
  - **Status:** Addressed in code — `queue_box` now schedules mid-transfer boxes; `_try_auto_restart()` starts a new delivery when the truck returns to idle with pending boxes.

---

## Reported Issues

- **NPC Spawning even after 6pm** — RC-4A — **Addressed in code; retest that NPCs spawn normally during the day and that N mode still pauses them.**
- **New order when truck en route** — RC-4E — **Addressed in code; retest ordering while truck is delivering and after it departs.**
- **Press pickup** — RC-4B — **Addressed in code; multiplayer retest required — verify pitcher stays snapped on clients and onboarding registers.**
- **Selling equipment** — RC-4D — **Addressed in code; retest trashing unopened equipment boxes.**
- **Wrong Blueprint showings** — RC-4C — **Addressed in code; retest that cup/equipment ghosts turn red on sidewalks.**
- **Keep computer tab same** — **Addressed in code; retest that last-used tab persists across computer open/close.**
- **Player camera when fall** — **Addressed in code; retest that camera drops and rises with the Fall animation.**
- **Remove pitcher 3d label** — **Addressed in code; visual retest.**
- **Slow down running** — **Addressed in code; sprint_multiplier 2.5→1.75, run anim speed 3.0→2.1.**

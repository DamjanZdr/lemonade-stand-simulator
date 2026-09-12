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

- **RC-4C — Ghost selection and click validation used different surface rules**
  Supply-box previews independently chose a box, cup stack, or equipment model before applying ownership and destination rules. Invalid targets often hid the ghost instead of showing a red box, while cup-box clicks used a different predicate and could unpack a cup stack even when the preview was a red box. The earlier ownership patch only affected multiplayer because its offline branch still accepted neutral surfaces.
  - **Evidence:** Stand floor showed a red box but clicking unpacked cups; streets showed a green cup although clicking was rejected.
  - **Status:** Addressed in code — unopened boxes remain box previews on floors, use green only on the player's floor or matching destination, use red on all invalid ground, and click handling now mirrors those rules.

- **RC-4D — Trashcan support existed but interaction routing bypassed it**
  `Trashcan.interact()` had a `HeldItem.SUPPLY_BOX` branch, but the player's specialized supply-box placement branch returned before fallback interactables were invoked. The disposal code was therefore unreachable while holding an unopened equipment box.
  - **Evidence:** Trashing a placed bowl works, but the unopened box containing it still cannot be trashed after adding disposal support.
  - **Status:** Addressed in code — trashcan targeting now takes priority for both containers and unopened supply boxes before placement dispatch.

- **RC-4F — Day transition stopped scheduling but did not own NPC cleanup**
  Pedestrians were only despawned after completing their routes, while queued customers were told to leave normally. Starting the next day before those paths completed preserved the previous day's NPC nodes.
  - **Evidence:** Pedestrians still walking when End Day is pressed remain visible the next morning.
  - **Status:** Addressed in code — non-day phases now host-despawn tracked customers and every pedestrian, then clear queue, reservation, and tracking state.

- **RC-4G — Destination interactions and placement previews ran independently**
  The placement system rendered a box preview even when clicking would consume the held item through a trashcan or matching bin. Trash boxes also inherited supply-box ownership limits despite being ordinary litter that can be dropped on neutral ground.
  - **Evidence:** Red boxes appeared over trashcans, green boxes appeared over matching bowls, and empty boxes could not be placed farther along the sidewalk.
  - **Status:** Addressed in code — valid consuming destinations suppress ghosts, held trash animates into the trashcan, and empty trash boxes may use any placement surface.

- **RC-4H — Price edits committed only on navigation**
  The price board kept typed digits in a temporary buffer and only called `request_set_price()` on Enter or vertical navigation. Escape discarded the buffer and refreshed the old authoritative price.
  - **Evidence:** Typing a new price and pressing Escape restored the previous value.
  - **Status:** Addressed in code — each valid text change commits immediately; Enter only advances and Escape closes without reverting.

- **RC-4E — Delivery truck had no auto-restart for orders placed while busy**
  `start_delivery()` was a no-op when the truck was not idle. Boxes ordered during a delivery were queued in `_pending_boxes` but never delivered if the truck was driving away. `_drive_away()` cleared `_pending_boxes`, and nothing checked for leftover boxes when the truck returned to idle.
  - **Evidence:** Orders placed while the truck is en route don't get delivered until a subsequent order triggers a new delivery.
  - **Status:** Addressed in code — `queue_box` now schedules mid-transfer boxes; `_try_auto_restart()` starts a new delivery when the truck returns to idle with pending boxes.

---

## Reported Issues

- **NPC Spawning even after 6pm** — RC-4A — **Addressed in code; retest that NPCs spawn normally during the day and that N mode still pauses them.**
- **New order when truck en route** — RC-4E — **Addressed in code; retest ordering while truck is delivering and after it departs.**
- **Press pickup** — RC-4B — **Addressed in code; multiplayer retest required — verify pitcher stays snapped on clients and onboarding registers.**
- **Selling equipment** — RC-4D — **Follow-up addressed; retest trashing unopened equipment boxes through the normal LMB interaction path.**
- **Wrong Blueprint showings** — RC-4C — **Follow-up addressed; retest boxed cups/equipment/ingredients on owned floor, street, workstation, and matching bins.**
- **End day NPCs** — RC-4F — **Addressed in code; retest ending the day with walking, queued, and leaving NPCs still active.**
- **Destination blueprints / trash placement** — RC-4G — **Addressed in code; retest trashcans, matching ingredient containers, and distant sidewalk placement.**
- **Immediate price updates** — RC-4H — **Addressed in code; retest typing, backspace, Enter, and Escape.**
- **Lemon mastery instruction** — **Updated to explicitly require making more lemonade with varied lemon amounts until five customers in a row are happy.**
- **Keep computer tab same** — **Addressed in code; retest that last-used tab persists across computer open/close.**
- **Player camera when fall** — **Addressed in code; retest that camera drops and rises with the Fall animation.**
- **Remove pitcher 3d label** — **Addressed in code; visual retest.**
- **Slow down running** — **Addressed in code; sprint_multiplier 2.5→1.75, run anim speed 3.0→2.1.**

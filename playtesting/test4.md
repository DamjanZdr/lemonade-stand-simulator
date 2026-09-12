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
  - **Status:** Addressed in code — valid consuming destinations suppress ghosts, held trash animates into the trashcan. Trash-box placement now follows the same ownership rules as equipment boxes (stand floor / workstation / delivery grid only), and trash-box clicks on the delivery grid snap to the correct cell instead of dropping at the mouse position.

- **RC-4H — Price edits committed only on navigation**
  The price board kept typed digits in a temporary buffer and only called `request_set_price()` on Enter or vertical navigation. Escape discarded the buffer and refreshed the old authoritative price.
  - **Evidence:** Typing a new price and pressing Escape restored the previous value.
  - **Status:** Addressed in code — each valid text change commits immediately. The blinking `_` cursor was replaced with a `>` arrow to the left of the edited line. Typing past the valid format (e.g. a third decimal digit) automatically restarts the buffer with the new character, so prices can be typed continuously without manual clearing. Escape commits and closes; Enter commits and advances.

- **RC-4E — Delivery truck had no auto-restart for orders placed while busy**
  `start_delivery()` was a no-op when the truck was not idle. Boxes ordered during a delivery were queued in `_pending_boxes` but never delivered if the truck was driving away. `_drive_away()` cleared `_pending_boxes`, and nothing checked for leftover boxes when the truck returned to idle.
  - **Evidence:** Orders placed while the truck is en route don't get delivered until a subsequent order triggers a new delivery.
  - **Status:** Addressed in code — `queue_box` now schedules mid-transfer boxes; `_try_auto_restart()` starts a new delivery when the truck returns to idle with pending boxes.

- **RC-4I — Money controller reactivated by `call_local` change RPC on clients**
  The customer's `_begin_change` RPC used `call_local`, so the host emitted `sale_initiated` and activated the local `MoneyController` even though the host is not the one paying. The money visual stayed visible after the customer left because the host's controller was activated by the same RPC that activated the paying client's controller.
  - **Evidence:** Money remains visible in front of the player after the correct change was paid and the customer left.
  - **Status:** Addressed in code — `_begin_change` no longer uses `call_local`; only the paying client's `MoneyController` is activated. The slide-down tween also uses a named method callback instead of a lambda for reliable `visible = false` cleanup.

- **RC-4J — Onboarding `customer_asked` not reachable while holding a container**
  `primary_interact()` dispatched container placement before checking for `CustomerInteractable`, so clicking a customer while holding a fruit bin tried to place the bin and returned without ever calling `customer.request_show_order()`. The order task could only register with empty hands.
  - **Evidence:** Holding a lemon (fruit bin) and clicking the customer shows the order but the "ask customer for order" task does not register.
  - **Status:** Addressed in code — `CustomerInteractable` is now checked early in `primary_interact()` for any held item except `CUP_FILLED` (which serves), so asking for an order works regardless of what the player is holding.

- **RC-4K — Filled cups spawned without `_net_scale` and despawned with `queue_free()`**
  `_place_filled_cup()` applied `cup.scale = Vector3.ONE * 0.03` only after `WorldSync.request_spawn()` returned on the host. The spawn state did not include `_net_scale`, so clients received the default scene scale and saw a giant cup. Separately, `Cup.pick_up_callback` and `Cup.interact()` called `queue_free()` locally instead of `WorldSync.request_despawn()`, so on a client the local copy was freed but the host and other clients still saw the cup — producing duplication.
  - **Evidence:** Filled cups duplicate or have inconsistent scale between host and client; a filled cup placed by the host appears giant to the client; if the client picks it up and places it, it becomes giant for both.
  - **Status:** Addressed in code — filled-cup spawn state now includes `_net_scale`. Cup pickup now routes through `WorldSync.request_despawn()` and removes the local copy immediately, matching the `pickup_container()` pattern used by other networked containers.

- **RC-4L — Cup ghost validation used a broader surface predicate than placement**
  `_update_single_cup_ghost()` used `is_placement_surface()` (which includes sidewalks) plus `_is_placement_allowed_on()` (which returns `true` in solo mode). The click handler used the same broad predicate, so cups could be placed on sidewalks outside the stand area in solo play.
  - **Evidence:** Cup previews show green on invalid surfaces such as sidewalks outside the player's stand placement area.
  - **Status:** Addressed in code — cup ghost validation and click handlers now use `is_stand_or_workstation_surface()`, which requires the collider to be part of a `StandUnit` or `Workstation` and owned by the player's stand. Sidewalks and other neutral surfaces show red and reject placement.

- **RC-4M — Trash-box click handler fell through to `_drop_trash()` on invalid surfaces**
  The trash-box ghost was previously restricted to stand-area surfaces (RC-4G), but the click handler still called `_drop_trash()` as a fallback when no supply box or delivery grid was hit. Clicking a red/invalid area (e.g. the street) dropped the box in front of the player instead of refusing the placement.
  - **Evidence:** Trash-box preview is correctly red on the street, but clicking the red area still drops the box in front of the player.
  - **Status:** Addressed in code — the click handler now checks `_ghost_valid` before calling `_drop_trash()`. Invalid placements emit a hint and do nothing instead of dropping the box.

- **RC-4N — Client pitcher snap never reached the host; water fill didn't sync pitcher state**
  `player_interaction.gd` called `_try_place_container()` which returns `null` on clients (because `WorldSync.request_spawn()` returns `null` on clients). The subsequent `press.snap_pitcher(placed)` was skipped, so the host never received a snap request, the press's `_snapped_pitcher` stayed `null` on all peers, and onboarding `pitcher_placed` never fired for clients. The same gap existed for the water dispenser. Separately, the water dispenser's `_apply_finish_fill()` updated `_snapped_pitcher.water` directly on the host but never synced the pitcher's state to clients, so clients never saw the fill result.
  - **Evidence:** A client/joiner cannot put a pitcher into the press and the tutorial does not register it (hard lock). A client cannot fill a pitcher on the water dispenser; pitcher state does not register correctly for the client.
  - **Status:** Addressed in code — added `request_snap_pitcher()` RPC on both `Press` and `WaterDispenser`. Clients send the recipe + stand owner to the host, which spawns the pitcher at the snap point, applies the recipe state, snaps it, and syncs to all clients. The water dispenser's `_apply_finish_fill()` now syncs the pitcher's properties and display calls to all clients via `WorldSync.sync_properties` / `sync_call`.

- **RC-4O — Missing onboarding step between filling a cup and asking a customer**
  The onboarding task list jumped from "fill a cup" directly to "ask a customer", skipping the step where the player places the filled cup on the stand for customers to take. Players would fill a cup and then ask a customer without ever placing the cup down.
  - **Evidence:** After filling a cup, onboarding should require placing the cup on the stand before asking a customer for their order.
  - **Status:** Addressed in code — added `demo_place_filled_cup` task between `demo_fill_cup` and `demo_ask_customer`. The task is satisfied by the `cup_placed_stand` event, reported when a filled cup is placed on a stand surface.

---

## Reported Issues

- **NPC Spawning even after 6pm** — RC-4A — **Addressed in code; retest that NPCs spawn normally during the day and that N mode still pauses them.**
- **New order when truck en route** — RC-4E — **Addressed in code; retest ordering while truck is delivering and after it departs.**
- **Press pickup** — RC-4B — **Addressed in code; multiplayer retest required — verify pitcher stays snapped on clients and onboarding registers.**
- **Selling equipment** — RC-4D — **Follow-up addressed; retest trashing unopened equipment boxes through the normal LMB interaction path.**
- **Wrong Blueprint showings** — RC-4C — **Follow-up addressed; retest boxed cups/equipment/ingredients on owned floor, street, workstation, and matching bins.**
- **End day NPCs** — RC-4F — **Addressed in code; retest ending the day with walking, queued, and leaving NPCs still active.**
- **Destination blueprints / trash placement** — RC-4G — **Follow-up addressed; retest trashcans, matching ingredient containers, trash-box on delivery grid (should snap to cell), and trash-box on sidewalk (should be red).**
- **Immediate price updates** — RC-4H — **Follow-up addressed; retest typing with arrow indicator, override typing (type past 2 decimals to restart), Escape commits, Enter advances.**
- **Lemon mastery instruction** — **Updated to explicitly require making more lemonade with varied lemon amounts until five customers in a row are happy.**
- **Keep computer tab same** — **Addressed in code; retest that last-used tab persists across computer open/close.**
- **Player camera when fall** — **Addressed in code; retest that camera drops and rises with the Fall animation.**
- **Remove pitcher 3d label** — **Addressed in code; visual retest.**
- **Slow down running** — **Addressed in code; sprint_multiplier 2.5→1.75, run anim speed 3.0→2.1.**
- **Money change remains visible** — RC-4I — **Addressed in code; retest that money disappears after the customer leaves.**
- **Place cup on stand onboarding task** — RC-4O — **Addressed in code; retest that the new task appears between fill and ask, and that placing a filled cup on the stand completes it.**
- **Ask customer while holding lemon** — RC-4J — **Addressed in code; retest clicking a customer while holding a fruit bin or other non-filled-cup item.**
- **Filled cup scale mismatch / duplication** — RC-4K — **Addressed in code; retest filled-cup placement and pickup on both host and client.**
- **Wrong cup blueprint** — RC-4L — **Addressed in code; retest cup previews on sidewalks (should be red) and stand surfaces (should be green).**
- **Trash-box placement on red area** — RC-4M — **Addressed in code; retest clicking a red trash-box preview on the street.**
- **Press pickup with pitcher inside** — RC-4N — **Addressed in code; retest that a press with a snapped pitcher cannot be picked up, and that clients can snap pitchers to the press.**
- **Client pitcher water fill** — RC-4N — **Addressed in code; retest that a client can fill a pitcher on the water dispenser and that the water state syncs to all peers.**

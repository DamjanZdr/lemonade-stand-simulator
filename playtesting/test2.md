### 2nd Playtesting — Bugs & Issues

## Root Causes

These root causes explain why multiple “unrelated” bugs below keep appearing together. Fix the root cause and the whole cluster usually goes away; fix only the symptom and the same failure resurfaces elsewhere.

- **RC-A — Host-authoritative placement boundary is incomplete**
  Clients are still deciding where objects go before the host validates. The placement raycast/ghost runs locally, surfaces are accepted locally, and stand ownership is not checked until too late. This produces ghost flicker, placement on invalid surfaces (floor), objects sinking when the authoritative transform arrives after local physics settles, and cross-stand equipment placement.
  *Evidence:* Equipment crate placement, Stand mixup equipment, Cups sinking, Trash sinking.
  *Status:* In progress — cross-stand ownership validation, tabletop probe fix, cup/trash bottom-offset fixes implemented; headless compile passed.

- **RC-B — State machine / animation state is not replicated**
  The host changes an NPC or player state (fall, get up, stunned) and plays an animation locally, but the state variable or animation trigger is never sent to clients. Clients keep rendering the old state, so characters slide in the old pose.
  *Evidence:* NPC getting up, Players not playing fall animation.
  *Status:* In progress — NPC stun recovery now syncs via `_sync_recover_start` and `sync_state`; player `_update_anim()` no longer overrides the stun/recovery animation. Headless compile passed.

- **RC-C — Day phase / UI state sync timing**
  Clients receive world visibility before the day phase / morning screen state, so they render the game world for a frame before the UI tells them to hide it.
  *Evidence:* Flash of Gameworld.
  *Status:* Addressed — the transition fade rect in `main.gd` now starts fully opaque black, hiding the world before the Day X overlay appears.

- **RC-D — UI / camera / input polish**
  Visual and input bugs that are local to one client and not caused by network authority leaks: slider track rendering, parallax direction, lobby blur size, camera/eye issues, button layout, movement vector normalization.
  *Evidence:* Slider Buttons, Blur in lobby, Main Menu Parallax, Eye in join, Ready button placement, Movement.
  *Status:* Addressed — movement, main-menu parallax, lobby blur, ready button placement, eye glyph rendering, and skin-color slider end caps are all fixed.

- **RC-E — Content / configuration / data**
  Missing or misconfigured assets/scene data: only one truck route exists, trashcan disposal spawns the wrong visual prefab.
  *Evidence:* Truck route, Trash Boxes.

- **RC-F — Network replication overhead on joiners**
  The host is fine (60–90 FPS), but joiners drop to 2–5 FPS in the middle of the day when client count is highest. This points to too much incoming data per frame, inefficient per-object sync, or clients simulating/rendering state they should not own. Often a symptom of unbatched transform/property RPCs, excessive per-entity updates, or client-side collision/physics on host-owned objects.
  *Evidence:* Joiner FPS drop with many clients.
  *Status:* In progress — throttled per-frame day-timer RPCs and per-trash transform sync; headless compile passed.

### Tackle Order Suggestion
1. **RC-A** first — it is the biggest authority leak and covers the most gameplay-breaking sync issues.
2. **RC-B** second — once placement works, animation/state sync becomes the next obvious missing multiplayer channel.
3. **RC-C** third — small ordering fix after RC-A/B are solid.
4. **RC-F** fourth — after sync authority is clean, audit and reduce replication volume; many RC-A/RC-B fixes should already reduce RPC spam.
5. **RC-D** and **RC-E** can be picked off in parallel or after the sync foundation is stable.

---

- **Slider Buttons: Sliders on their min/max positions don't look like the slider is actually fully empty or fully full.**
  - **Root cause:** RC-D
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** The slider visual doesn't reach the ends of the track at min/max values, making it look like it's not actually at 0% or 100%.
  - **Status:** Addressed — `lobby_ui.gd` now adds `StyleBoxFlat` theme overrides to the skin color slider with `content_margin_left/right` on the track and a 10 px rounded grabber, so the thumb reaches the track ends at 0 and 1.

- **Blur in lobby: The lobby background blur/darkening goes too far to the right, covering a bit of the player.**
  - **Root cause:** RC-D
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** The blur/darken overlay in the lobby extends too far right and obscures part of the player character preview.
  - **Status:** Addressed — `lobby_ui.gd` now constrains the blur and dim `ColorRect`s to a 500 px-wide left strip instead of full-screen, so the 3D player preview on the right is no longer covered.

- **Main Menu Parallax: Left/right goes opposite of mouse which is good, but up/down goes same as mouse. Make up/down also go opposite.**
  - **Root cause:** RC-D
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** The main menu parallax effect inverts horizontal movement correctly but vertical movement follows the mouse direction instead of opposing it.
  - **Status:** Addressed — `main.gd` `_menu_cam_parallax()` now applies a positive Y offset for the same mouse input sign as X, so vertical parallax also opposes mouse movement.

- **Eye in join: Fix the eye.**
  - **Root cause:** RC-D
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** The eye (likely the character customization eye or camera eye) has a visual issue in the join screen.
  - **Status:** Addressed — the lobby room-code `EyeButton` now uses a `SystemFont` override so its show/hide glyphs render even when the menu font doesn't include them.

- **Ready button placement: Ready button placement correction (mainly for joiners without the start game button).**
  - **Root cause:** RC-D
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** The Ready button is mispositioned in the lobby, especially for joiners who don't have the Start Game button.
  - **Status:** Addressed — `lobby_ui.gd` now hides the right spacer (`_start_spacer`) alongside the Start Game button for non-hosts, so the Ready button is properly right-aligned when the Start button is absent.

- **Flash of Gameworld: When joiner day starts, it flashes for a half second before the day X thing shows.**
  - **Root cause:** RC-C
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** Joiners see a brief flash of the game world before the "Day X" intro screen appears at the start of a day.
  - **Status:** Addressed — `_on_game_starting()` in `main.gd` now creates the transition fade rect with `color.a = 1.0` so the screen is black from the very first frame instead of fading up from transparent.

- **Trash in the ground: Trash when thrown or spawns, snaps to even further down in the ground after a second.**
  - **Root cause:** RC-A
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** Trash items (thrown or spawned) initially appear at the correct position but then snap further down into the ground after about a second.
  - **Status:** Addressed — `thrown_trash.gd` now uses the lowest collision-shape bottom as the visual/ground offset instead of the visual node's position.y, so the final TrashItem rests on the ground instead of clipping through it.

- **NPC getting up: On joiners the NPCs start moving in the falling end state, just sliding on floor. Host plays them getting up and walking away but it doesn't sync to joiners.**
  - **Root cause:** RC-B
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** The NPC "getting up" animation after being knocked down plays on the host but doesn't sync to joiners. Joiners see NPCs sliding on the floor in the fallen state instead of getting up.
  - **Status:** Addressed — `customer.gd` and `pedestrian.gd` now broadcast `_sync_recover_start` and `sync_state` when the NPC gets back up, so clients play Fall in reverse and resume the pre-stun animation instead of staying in the fallen pose.

- **Players not playing fall animation: They get stunned when thrown trash at but no fall animation.**
  - **Root cause:** RC-B
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** When a player is hit by thrown trash, they enter the stunned state but the fall animation doesn't play.
  - **Status:** Addressed — `player_controller.gd` `_update_anim()` now returns early while the player is stunned or recovering, so the per-frame `_process` override no longer interrupts the Fall animation that `_physics_process` starts.

- **Movement: Looking down, and holding left and right while holding forward or back, makes the forward and back be much slower than just looking straight.**
  - **Root cause:** RC-D
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** Diagonal movement (forward/back + left/right) while looking down is significantly slower than straight movement. Likely a camera-direction movement vector normalization issue.
  - **Status:** Addressed — `PlayerController` now builds the movement direction from horizontal projections of the head's right and forward basis vectors, so looking up/down doesn't shrink the forward/back component of diagonal input.

- **Equipment crate placement: When aiming at the edge of the top of the workstation, green ghost of placing an equipment goes up/down between the workstation top and the floor, and it allows placing it on the floor if clicked when the ghost is on the floor.**
  - **Root cause:** RC-A
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** The placement ghost flickers between the workstation surface and the floor when aiming at the edge, and allows invalid placement on the floor.
  - **Status:** Addressed — `_probe_tabletop_below()` in `player_placement.gd` is now constrained to the same hit object/descendants, preventing the probe from snapping to the floor. Cross-stand placement also rejects the invalid surface.

- **Trash Boxes: Throwing box in the trash makes a trash item like apple drop visually in the trashcan.**
  - **Root cause:** RC-E
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** When throwing a supply box into the trashcan, a random trash item (like an apple) visually drops instead of the box being disposed of correctly.
  - **Status:** Addressed — `Trashcan.apply_trash_disposal()` now skips the disposable visual spawn for `trash_type == "empty_box"`, so an apple no longer pops out of a discarded box.

- **Cups issue: Cups get sunk into the surface when placed down. When picking up a cup from a stack, the whole stack gets taken and the player gets pushed back by the collision.**
  - **Root cause:** RC-A
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** Two issues: (1) Cups sink into the surface when placed (similar to the supply box sinking issue). (2) Picking up a cup from a stack grabs the entire stack instead of one cup, and the player gets pushed back by collision.
  - **Status:** Addressed — `_place_single_cup()` and `_place_filled_cup()` in `player_placement.gd` now use the ghost's actual `bottom_offset` meta instead of a hardcoded 0.5 estimate. `cup_stack.gd` now overrides `Pickupable.can_pickup_callback` so the whole stack can only be picked up when it is empty, otherwise one cup is taken via `interact()`.

- **Truck route: Update the truck route and delivery position, or duplicate and make another one for stand 2 that matches the position of it.**
  - **Root cause:** RC-E
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** The delivery truck only serves stand 1's position. Need to either update the route or create a second truck/delivery point for stand 2.
  - **Status:** Addressed — `delivery_truck.gd` now derives its route node name from the truck's own name (`TruckRoute` for `DeliveryTruck`, `TruckRoute2` for `DeliveryTruck2`), and `world.tscn` now contains a `TruckRoute2` child under `StandUnit2` mirroring the stand 1 route for the second stand.

- **Stand mixup equipment: Players under stand 1 can place equipment in the area for placement of stand 2, which blocks stand 2. Players from a stand should only place equipment in their own designated area.**
  - **Root cause:** RC-A
  - **Category:** Concept / Bug
  - **Size:** Small
  - **Description:** Players can place equipment (workstation, crates, etc.) in the rival stand's placement area. This blocks the rival stand since they can't interact with enemy equipment. Need to restrict placement to the player's own stand area only.
  - **Status:** Addressed — `player_placement.gd` now validates stand ownership against both `Interactable.stand_owner` and the parent `StandUnit` of `PlacableFloor` surfaces for all placement ghosts (equipment, cups, supply boxes, containers). The placement ghost is hidden on rival-stand surfaces and the place action is blocked.

- **Joiner performance: Joiners drop to 2–5 FPS in the middle of the day when the number of clients is highest, while the host stays at 60–90 FPS.**
  - **Root cause:** RC-F
  - **Category:** Performance
  - **Size:** Medium
  - **Description:** Client FPS collapses during peak client count, especially mid-day. Likely excessive per-object network updates, unbatched RPCs, or clients simulating host-owned physics/collision. Host FPS is acceptable for now and can be optimized later.
  - **Status:** Addressed (third pass) — `DayManager` day-timer RPCs are throttled, `ThrownTrash` transform sync is interval + threshold gated, customer `sync_patience` only sends on ≥5% ratio change or 0.5s, `SupplyBox._process()` is throttled to 10 Hz, and `PlayerVisuals._process()` now caches its active skeleton and throttles eye-look quaternion updates to 10 Hz, reducing per-remote-player CPU cost.

### 3rd Playtesting — Follow-up Bugs & Regressions

## Root Causes

- **RC-3A — Delivery transforms and box-face visibility diverge by peer**
  Initial delivery synchronizes each box's arc position but not its final rotation. Box labels also cache whichever camera is active during delivery, so a menu/transition camera can keep controlling face visibility after gameplay begins. Moving and replacing a box gives it a fresh camera and transform, which is why the problem disappears afterward.
  - **Evidence:** Box labels differ between host/joiner and only fail on the initial palette delivery.
  - **Status:** Addressed in code — camera changes are detected and the final delivered rotation is synchronized.

- **RC-3B — Placement rules confuse generic surfaces, ground, and owned stand surfaces**
  Sidewalks are tagged as placement surfaces, unowned surfaces are accepted, and the layer-4 fallback ray can resolve a different floor farther along the camera ray. Actual click handlers also bypass some ghost ownership checks.
  - **Evidence:** Equipment/crates on neutral streets, crates on rival stands, and stand 2 workstation placement at stand 1 edges.
  - **Status:** Addressed in code — ground resolution now probes below the actual hit point, ownership walks the full hierarchy, and crates/equipment require the player's stand or workstation.

- **RC-3C — Final placement replaces valid physics transforms with bad estimates**
  Direct cup-box placement still uses a hardcoded offset, while thrown-trash finalization discards the settled physics position and reprojects high objects onto the ground using unscaled source-shape dimensions.
  - **Evidence:** Direct-from-box cup stacks sink; finalized cup trash floats or snaps vertically.
  - **Status:** Addressed in code — direct cup placement uses measured bounds and trash finalization preserves its settled physics position.

- **RC-3D — NPC movement bodies collide with world geometry unnecessarily**
  Customer and pedestrian CharacterBody nodes scan world layers 1 and 2 even though interaction already uses a separate Area3D and thrown trash detects the NPC body on layer 16.
  - **Evidence:** NPCs are blocked by tables crossing their route.
  - **Status:** Addressed in code — NPC movement masks are disabled while click and airborne-trash detection remain available.

- **RC-3E — Player stun visuals are advanced only by the owning physics controller**
  Remote copies never decrement the stun timer, and the controller's cached animation name is stale after reverse recovery. Client-thrown trash also fails to identify its source on the host because the client spawn request returns no local body.
  - **Evidence:** Host remains in the wrong animation, joiner becomes static, and players can stun themselves.
  - **Status:** Addressed in code — every peer advances stun visuals, animation state is forced to refresh after recovery, and throws replicate the source peer ID.

- **RC-3F — Slider endpoint behavior is controlled by the grabber mode**
  Styling the track margins does not make the grabber center reach the actual bounds. Godot's `center_grabber` theme constant controls that behavior.
  - **Evidence:** Min/max values still look partially filled/empty.
  - **Status:** Addressed in code — customized sliders now use centered grabbers at the true endpoints.

---

## Reported Issues

- **Box labels** — RC-3A — **Addressed in code; multiplayer retest required.**
- **Floating trash** — RC-3C — **Addressed in code; cup and other trash variants need visual retest.**
- **NPCs blocked** — RC-3D — **Addressed in code; route traversal needs gameplay retest.**
- **Equipment placement** — RC-3B — **Addressed in code; neutral/rival edges need multiplayer retest.**
- **Slider buttons** — RC-3F — **Addressed in code; endpoint appearance needs visual retest.**
- **Trash in the ground** — RC-3C — **Addressed in code; delayed finalization needs visual retest.**
- **Players not playing fall animation** — RC-3E — **Addressed in code; host/joiner recovery and self-hit immunity need multiplayer retest.**
- **Cups issue** — RC-3C — **Addressed in code; direct-from-box placement needs visual retest.**
- **Stand mixup equipment** — RC-3B — **Addressed in code; stand 2 edge cases need multiplayer retest.**

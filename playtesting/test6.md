# Test 6 — Batch Testing Feedback

Reported symptoms are grouped under the shared root causes that explain them.
Fixes target the cause, not each symptom independently.

## Root causes

### RC-6A — Task counter rewinds to 0/3 after completion

**Symptom:** "Place at least 3 filled cups" — once 3/3 is reached and the task
is crossed out, the counter briefly shows `0 / 3` before the task leaves.

**Cause:** When a task completes, `OnboardingManager` clears `part_counts` in the
incoming progress dict. The HUD's crossed-out render (`_render_onboarding`)
then reads `part_counts[part]` → 0 and displays `0 / 3` during the transition
animation.

**Fix:** In `_render_onboarding`, when `whole_task_complete` is set, render
`required / required` instead of the (already-cleared) live count.

---

### RC-6B — Patience-timeout customers "talk" with no speech

**Symptom:** Customers play the talking animation when leaving after patience
expires, but no text ever appears.

**Cause:** `_feedback_for_outcome("timeout")` returns `""`, and the
non-paying branch of `_resolve()` never calls `_set_order_text` — the Talk
anim plays over an empty bubble.

**Fix:** Give `"timeout"` a real feedback line ("This takes too long — I have
places to be!") and show it in the non-paying branch before leaving.

---

### RC-6C — Recipe board shows 3 fruit / 2 sugar from the start

**Symptom:** The host's recipe board displays `3` and `2` for lemon before the
player ever touches it.

**Cause:** `init_default_recipes()` pre-populates every fruit's recipe with the
*ideal* values (`ideal_fruit_count` / `ideal_sugar` from `IngredientData`), so
the board has real numbers to display. This also pollutes discovery: the stored
recipe starts at the "perfect" value the player is supposed to find.

**Fix:** Default recipes are empty (`{}`). `get_recipe()` falls back to `{}`
for missing keys, so the board keeps showing "?" until the player writes
values — and `recipe == discovered` equality now only succeeds when the
player actually sets them (which also makes the golden-mark check reliable).

---

### RC-6D — Lemon price confusion (1.50 flash + complaints at $1.00)

**Symptoms:**
- Host price board shows `1.50` until clicked, then snaps to `0.80`.
- Customers complain the $1.00 price is too expensive while the task tells the
  player to raise it *to* $1.00.

**Causes:**
1. `PriceBoard._ready()` refreshes labels before `StandUnit._ready()` runs
   (children ready before parents), so `get_price()` hits the `1.50` fallback.
2. `lemon.tres` `default_price = 0.8` is the "fair price" anchor —
   `RecipeEvaluator.get_base_price()` compares customer tolerance against
   `0.8`, so $1.00 is a 25% deviation → 25% chance of "too expensive".

**Fixes:**
1. Defer the initial label refresh one frame so stand prices exist first.
2. Make `default_price` the *ideal* anchor (`1.0` for lemon) and add a separate
   `start_price` field (`0.8` for lemon) used only by `init_default_prices()`.
   $1.00 is now deviation-zero → never "too expensive", and the
   "increase to $1.00" task still has somewhere to go.
3. `demo_set_price` gets an auto-satisfy check so a player who already set
   $1.00 gets credit when the task arrives.

---

### RC-6E — Blackboard typing replaces instead of appending

**Symptom:** Typing a two-digit value (e.g. `30` for ice ratio) is impossible —
each keystroke overwrites the last and immediately commits.

**Cause:** `Blackboard._append_char()` does `_edit_buffer = c` then calls
`_confirm_and_next()` on every character. `PriceBoard._append_char()` already
does it correctly (`_edit_buffer + c`).

**Fix:** Align with `PriceBoard` — append to the buffer (capped at 3 chars),
refresh the label, commit only on Enter/navigation. Backspace now deletes one
character instead of clearing the field.

---

### RC-6F — Perfect-recipe streak ignores paying customers + no golden mark

**Symptoms:**
- Serving the perfect recipe to customers doesn't advance the 5-customer
  streak — a mid-streak "not sweet enough" complaint appeared even though the
  recipe was already perfect.
- Setting the discovered recipe on the board never turns it golden.

**Causes:**
1. `customer_feedback` evaluations are only reported to `OnboardingManager`
   in the *incorrect-change* and *overpaid* paths. Exact-payment and
   exact-change customers leave via `_start_leaving()` without ever flushing
   `_served_evaluations`, so most paying customers are invisible to mastery
   tracking. (This also explains the "not sweet enough" complaint: that
   customer's evaluation was recorded but its transaction outcome was the
   exact-pay path — streak math was working on a subset of customers.)
2. `Blackboard` never listens to `stand_progress_changed`, so its golden
   check (`_refresh_label`) only runs when the board itself is touched.

**Fixes:**
1. Every paying outcome (`_resolve` exact-pay branch, `_leave_after_change`
   exact/overpaid) now goes through `_show_feedback_then_leave()`, which
   reports evaluations — all paid transactions count toward the streak.
2. `Blackboard` connects to `OnboardingManager.stand_progress_changed` for
   its own stand and refreshes all labels, so golden marks appear as soon as
   discovery lands.

---

### RC-6G — Cups pourable from an unfinished pitcher

**Symptom:** A pitcher with a few lemons and no water can fill cups; there's no
requirement to top the pitcher to 10 with fruit/water first.

**Cause:** The `PREPPING`/`COMPLETE` interact branch pours whenever
`fruit_count > 0` — no minimum volume check.

**Fix:** First pour requires `get_liquid_volume() >= PITCHER_MAX_LIQUID`.
Consequently the three water-fill paths (`water_tap`, `water_dispenser`,
held-pitcher tap fill in `player_interaction`) now allow topping up a pitcher
that already has *some* water instead of refusing on `water > 0` — otherwise a
partially-filled pitcher could never reach 10 and would be stuck.

---

### RC-6H — "Not enough money" shows green

**Symptom:** Shop/upgrade failure messages use the same green as success.

**Cause:** `_animate_status()` / `_animate_status_text()` hardcode the green
`font_color` override.

**Fix:** Both take a color parameter; failure call sites pass red.

---

### RC-6I — Sugar/ice into an empty pitcher wedges the press

**Symptom:** Sugar/ice into an empty pitcher → pitcher snaps to press → fruit
loaded → "incompatible" and the pitcher can't be retrieved.

**Causes:**
1. `Pitcher._can_add_ingredient()` returns `true` for sugar/ice unconditionally,
   even on a completely empty pitcher.
2. `Press.can_snap_pitcher()` accepts a pitcher with `water == 0` regardless of
   sugar/ice, so an invalid-content pitcher can be docked.
3. With fruit loaded and an incompatible pitcher, LMB only tries to press —
   the take-pitcher branch requires `fruit_count <= 0`, so the player is stuck
   unless they know RMB ejects.

**Fixes:**
1. Sugar/ice require `get_liquid_volume() > 0` (fruit or water must exist).
2. `can_snap_pitcher()` rejects pitchers containing sugar/ice.
3. Pressing LMB with an incompatible snapped pitcher now ejects it (with a
   hint) instead of leaving it trapped.

---

### RC-6J — Loose scoops refund more than they cost

**Symptom:** One lemon scooped from a bin recycles for $0.45; 10 lemons +
$0.25 box = $4.75 back on a $4.00 box.

**Cause:** A bin scoop is held as `SUPPLY_BOX` with `source = "bin_scoop"`,
so it flows through `_get_supply_box_refund()` which always adds the $0.25
empty-box scrap on top of `0.5 × unit_cost`.

**Fix:** Bin scoops skip the scrap — refund is `0.5 × unit_cost × amount`
(`$0.20`/lemon). Real boxes keep `scrap + 50% × contents`.

---

### RC-6K — Perfect-recipe popup shows % / unclear values

**Symptom:** The discovery popup contains `%`-style formatting artifacts
instead of plainly stating the recipe amounts.

**Cause:** The announce detail strings are built with `%g` format verbs fed
straight from dictionaries that have passed through RPC/save serialization —
any non-numeric value prints the raw format string.

**Fix:** Values are cast through `float()` before formatting, so the popup
always reads e.g. `Perfect Lemon Recipe Found — 3 lemon · 2 sugar`.

---

### RC-6L — Thermometer numbers render through geometry

**Symptom:** The °C/°F labels are visible through walls and objects.

**Cause:** `LabelStyle` autoload forces `no_depth_test = true` on every
`Label3D` unless the node carries `metadata/no_depth_override`. The
thermometer labels lack the opt-out.

**Fix:** Add `metadata/no_depth_override = true` to `LabelC`/`LabelF`.

---

### RC-6M — Patience meter survives serving/leaving

**Symptom:** The patience circle stays visible after a customer is served or
walks away.

**Cause:** Nothing ever hides `_patience_circle` — `_resolve()` and
`_start_leaving()` change state but leave the sprite visible, and clients
replicating `REACTING`/`LEAVING` never touch it either.

**Fix:** Hide the circle in `_resolve()` and `_start_leaving()` on the host,
and in `_sync_state()` whenever the replicated state is `REACTING` or
`LEAVING` (kept visible through `RECEIVING` — the customer is still waiting).

---

### RC-6N — Overpaid customer leaves silently

**Symptom:** An overpaid customer leaves instantly with no feedback.

**Cause:** `_leave_after_change()` calls `_start_leaving()` directly whenever
`tendered > change_due`, skipping the feedback bubble entirely.

**Fix:** Overpay now shows the normal feedback plus a second line —
`And thanks for the extra $X.XX!` — then leaves via
`_show_feedback_then_leave()` (which also reports evaluations, see RC-6F).

---

### RC-6O — Thrown trash vanishes on pickup

**Symptom:** Picking up trash thrown downward sometimes deletes it instead of
adding it to the hand — reproducible after a few tries (i.e. while the item is
still a falling `ThrownTrash`, not yet a landed `TrashItem`).

**Cause:** `ThrownTrash.pickup_by()` looks up
`player.get_node_or_null("Inventory")`, but after the player-component split
the node is named `PlayerInventory`. `inv` is null → `make_held_trash` is
skipped → the node despawns anyway → the item disappears. `TrashItem` uses
`p.inventory` correctly, which is why only mid-air pickups fail.

**Fix:** Use the `player.inventory` property like `TrashItem` does.

---

### RC-6P — Cups are indistinguishable across pitchers

**Symptom:** Cups poured from different pitchers can't be told apart — no
recipe info on the cup.

**Fix:** `Cup.get_hint()` for a filled cup now lists the recipe snapshot taken
at pour time — `Cup | 3 lemon · 2 sugar · 4 ice | LMB: pick up` — same
format as the pitcher's contents line.

---

## Feature updates

### FU-6A — Natural-language orders

Customer order bubbles now read
`Can I please have 2 of lemon lemonade?` (multi-fruit orders join with
"and") instead of `2 Lemon`.

### FU-6B — Retroactive task credit

`OnboardingManager` now keeps a per-stand `event_history` (capped). After any
task completes or a stand initializes, the recorded events are replayed through
the existing `_part_matches` rules against the *current* task — so a player who
bought equipment/supplies or did work before being asked gets credit when the
task arrives. Purchases made early satisfy their future purchase tasks instead
of silently counting nothing.

---

## Verification

- Headless editor launch: `godotsteam.471.editor.win64.console.exe --headless
  --main-scene res://scenes/main.tscn` — clean, no parse/script errors.
- Manual: covered by playtest — board "?" until written, golden mark appears on
  discovery, cups pour only from full pitchers, thrown-trash pickup keeps the
  item, overpay shows thanks line, timeout customers speak, patience circle
  hides on resolution/departure.

# Test 8 — Batch 3 Feedback

## Root Cause A — Blackboard only commits on Enter
**Symptoms:**
1. Recipe board values only register when you press Enter on the last edited field.
2. Navigating with arrows / clicking another field / exiting the board leaves the last typed value unapplied.

**Fix:** `_store_buffer()` now applies the current field to the owning stand before moving focus. The
value is committed the moment the field is left (arrow keys, mouse click, Esc, or Enter).

## Root Cause B — Onboarding task wording is ambiguous
**Symptoms:**
- "Ask a customer what they would like" is too active — players try to prompt the customer instead of waiting.

**Fix:** Reword the task to: "Wait for a customer to come to your stand and ask them what they would like."

## Root Cause C — Recipe formatting inconsistent / still shows decimals
**Symptoms:**
1. Cup tooltip shows the recipe inline instead of in `[...]` brackets above the action line like the pitcher does.
2. Recipe values can render with decimal points in pitcher, cup, and perfect-recipe discovery popups.

**Fix:**
- Cup/held-cup hints moved to a bracketed recipe line above the action text.
- All recipe counts are cast to integers before formatting (`int()` / `%d`) so `3.0` prints as `3`.
- Discovery popups for perfect recipes and perfect ice ratio use integer formatting.

## Root Cause D — Fruit unlocks leak across stands
**Symptoms:**
- Joiner unlocking a second fruit makes the *host's* price board and recipe board show that fruit as unlocked.
- The joiner's own shop still shows the fruit as locked because the morning hub uses a separate active-stand
context, but the world boards (`price_board.gd`, `blackboard.gd`) read the global
`UpgradeManager.purchased_nodes` set, which was left pointing at the joiner's stand after the host
processed the purchase.

**Fix:**
- `StandUnit` now exposes `is_fruit_unlocked(fruit)` based on its own `purchased_upgrade_nodes`.
- World price boards and recipe boards use their owning stand's method instead of the global active set.
- `purchased_upgrade_nodes` is included in the stand's synced state so clients also see correct unlocks.
- The host pushes stand state after an upgrade purchase so the unlock set reaches all peers.

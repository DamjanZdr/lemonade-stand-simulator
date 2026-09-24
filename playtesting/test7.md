# Test 7 — Batch Testing Feedback

Reported symptoms are grouped under the shared root causes that explain them.

## Root causes

### RC-7A — `%g` is not a supported GDScript format specifier (~21k errors)

**Symptoms:** Cup hint shows the recipe as garbled format text; the perfect-
recipe popup shows the same; ~21,000 logged errors, one per `poll_hint`
frame while a filled cup is held or looked at.

**Cause:** `"%g"` is unsupported by `String %` formatting — every call throws
"unsupported format character" and returns the raw format string. The
pre-existing discovery popups had this bug already (the RC-6K "% shown"
report); the new cup/held-cup recipe helpers repeated the mistake.

**Fix:** All `%g` sites replaced with `%s` + `str()` — `str(3.0)` prints
"3", `str(2.5)` prints "2.5". Sites: `cup.gd::_recipe_string`,
`player_interaction.gd::_recipe_hint_string`, `stand_unit.gd` + 
`onboarding_manager.gd` discovery announcements, ice-ratio announce.

---

### RC-7B — Price not locked at order agreement (10x exploit)

**Symptom:** Ask for order at $1 → raise board to $10 → customer pays $10.

**Cause:** `try_serve` accumulated `_get_price()` — the LIVE board price —
at serve time. The customer agreed to the price shown at order time.

**Fix:** `_locked_prices` dictionary — every fruit in the order is
snapshotted during `_run_price_check_and_show_order` (the loop is
synchronous, so all prices lock atomically). `_get_price` returns the
locked value once set. Board changes only affect customers whose price
check hasn't run yet.

---

### RC-7C — Blackboard Fahrenheit field reverts on commit

**Symptom (joiner-observed, reproduces everywhere):** typing in the °F
field "changes to the previous number" when moving to the next field.

**Cause:** `_apply_ice_to_stand` always gave Celsius priority when `v1`
was non-empty — and the auto-fill writes C after the first edit, so C is
never empty afterwards. Editing F then committed C×1.8 back into F.

**Fix:** `_apply_ice_to_stand` takes `prefer_fahrenheit` — true when the
just-committed field is F (`_field_index == 1`). The edited unit drives
the conversion; the other field is auto-filled from it.

---

### RC-7D — Digit limits per field type

**Request:** temperature fields max 2 digits; fruit/sugar fields 1 digit.

**Fix:** `_append_char` caps the buffer by label type — ice fields
(degrees-per-scoop, °C/°F deltas) allow 2 chars; fruit/sugar fields 1.

---

### RC-7E — Patience circle frozen for joiners on street offers

**Symptom:** When a joiner stops a pedestrian for the free-lemonade
offer, the patience meter stays full — never drains.

**Cause:** The OFFERED-state countdown lives in `_physics_process`, which
early-returns on clients (`_physics_client_interpolate`). `_sync_offered`
shows the circle at 1.0 but nothing ever decrements it client-side.

**Fix:** `_sync_offered` initializes `_offer_patience = _offer_patience_max`,
and `_process` (runs on all peers) ticks a visual-only countdown while
`_state == OFFERED`. The real timeout stays host-authoritative — when it
fires, `_sync_resume`/`_sync_serving` hide the circle.

---

### RC-7F — "Equipment" header doubled on joiner's shop

**Symptom:** The shop page shows the "Equipment" header twice, stacked.

**Cause:** `_build_shop` freed the old list with `queue_free()`, which
leaves the node in the tree until frame end. A same-frame rebuild (e.g.
multiple fruit-unlock sync RPCs landing together on a joiner) adds the
new list while the old one still renders, and with 3+ same-frame builds
the stale lookup (`get_node_or_null("ShopList")` finds the queued node,
not the new one) lets two lists survive permanently.

**Fix:** Detach-then-free: `remove_child` + `queue_free` on every child,
so any number of same-frame rebuilds leaves exactly one list.

---

## Text tweaks

- Timeout line: "This takes too long, I have places to be!" (em-dash
  removed — the bubble font doesn't render it well).
- Orders: quantity 1 drops "of" — "Can I please have 1 Lemon lemonade?"
  Multi-quantity keeps "2 of Strawberry lemonade".

## Verification

- Headless editor launch clean — no parse/script errors.

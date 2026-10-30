# Progression Rework — Bar-Based Upgrades

Replaces the node-tree upgrade system. Each branch is ONE bar tracking ONE
cumulative counter per stand. Crossing a threshold makes a tier CLAIMABLE —
the player clicks the pulsing badge to claim it. Money stays for
equipment/supplies; bars are earned by playing.

## Design rules

- One branch = one bar = one counter. No compound conditions.
- Counters are cumulative (no "in a row" resets). A counted event is proof of
  the skill by itself; resets only add frustration.
- Per-stand counters on `StandUnit` progression data — co-op partners on the
  same stand fill the same bar; host-authoritative via the report pipeline.
- Tiers are claimed, not auto-granted: a reached tier pulses until clicked
  (`claim_upgrade` event routes through host authority). Effects, fruit
  unlocks, and machine shop gating all key off claimed level.
- Escalating thresholds: cheap early unlocks, grindy late ones.
- Gameplay effects are scoped to the owning stand
  (`get_effect_total_for_stand` / `get_effect_total_for_node`) — never the
  UI's `_active_stand` — so versus stands get their own bonuses.

## Branches

| Branch | Counter (event) | Thresholds | Per-tier benefit |
|---|---|---|---|
| Fruit | perfect-recipe serves of current fruit | 8 / 20 / 35 / 55 / 80 | unlock next fruit tier |
| Technology | cups served (sold + free samples) | 50 / 200 | Squeeze-E-Z → Fruit-O-Matic purchasable |
| Squeeze Speed | fruit pressed by hand | 30 / 90 / 180 / 320 / 500 | +20% squeeze speed (press AND machines) |
| Nimbleness | deposits from supply box | 25 / 70 / 150 / 260 / 420 | +20% deposit speed |
| Sunroof | customers lost to impatience | 5 / 15 / 35 / 65 / 100 | +patience |
| Water Dispenser | water fills | 10 / 30 / 65 / 115 / 180 | +20% fill speed |
| Trash Rebate | NPC litter trashed | 15 / 40 / 80 / 140 / 220 | +10% refund |
| Negotiation | $ spent (all spending) | 50 / 130 / 250 / 420 / 650 | -10% prices (shop + phone) |

Removed: MovementSpeed (miswired nodes), Word of Mouth/Samples (free samples
keep their intrinsic +2 popularity reward; a claimed bar double-dipped).
PressSpeed is replaced by Squeeze Speed (also speeds machines — machines
squeeze slightly slower than hand at base).

## Fruit chain details

- A "perfect serve" = the served recipe candidate exactly matches ideal
  fruit+sugar (ice excluded — separate discovery track, unchanged).
- Bar sits at 0 while experimenting; the first exact serve ticks it to 1 —
  the movement IS the "you found it" feedback.
- Each fruit tier's threshold is its OWN count of perfect serves of that
  fruit (8 lemon, then 20 of the next, etc.) — escalating work per fruit.

## Event → counter map

| Counter | Source |
|---|---|
| perfect_serves[fruit] | `customer_feedback` mastery eval, perfect candidate |
| cups_served | `customer_served` + `sample_served` |
| pitchers_made | `pitcher_prepared` (dispenser) + machine `finish_batch` (recorded; no branch — kept for stats) |
| hand_presses | `fruit_pressed` (manual press only) |
| box_deposits | `supply_deposited` (fires only when held == SUPPLY_BOX) |
| samples_given | free-sample serve in `pedestrian.gd` (recorded; no branch — kept for stats) |
| customers_lost | customer `_resolve("timeout")` |
| water_fills | `pitcher_water_filled` |
| litter_trashed | `trash_disposed` where type ∈ {apple, banana, can, cigarettes, cup} |
| supply_spend | `spend_money(amount, ...)` — all spending counts |

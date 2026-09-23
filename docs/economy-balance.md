# Economy Balance — Base Values

Planning doc for default costs, revenue math, and refund rules.
Upgrades will modify these later — this file is the **baseline** they modify.

## Anchor constraints

- **Base lemonade price: $1.00/cup** — should be accepted by essentially every
  customer for a lemon recipe. Current acceptance bands: `PRICE_FAIR_MAX = 2.00`,
  `PRICE_TOO_EXPENSIVE = 2.75` (see `scripts/autoloads/balancing.gd`), so $1 is
  already safe.
- **Pitcher = 10 liquid units = 10 cups** → **$10 revenue per sold-out pitcher.**
- **Every supply box contains 10 units** (lemons, sugar, ice, cups).
- **Water box: $5 → 5 pitcher fillings** → $1.00 per pitcher of water.

## Ideal lemon pitcher (recipe math)

From `balancing.gd`: `IDEAL_LEMON_RATIO = 0.30` (3 lemons/pitcher),
`IDEAL_SUGAR_PER_LIQUID = 0.20` (2 sugar/pitcher), ice ~1–3 scoops depending on
temperature (`PERFECT_ICE_DEGREES_PER_SCOOP = 7.0`, temp range 10–40 °C).

### Proposed box prices (vs current)

| Item | Box qty | Current | Proposed | Per unit |
|------|---------|---------|----------|----------|
| Lemons | 10 | $2.00 | **$4.00** | $0.40 |
| Sugar | 10 | $1.50 | **$2.00** | $0.20 |
| Ice | 10 | $1.00 | **$1.50** | $0.15 |
| Cups | 10 | $0.50 | **$1.00** | $0.10 |
| Water | 5 fills | $5.00 | $5.00 (keep) | $1.00/fill |

### Cost of one ideal pitcher

| Component | Amount | Cost |
|-----------|--------|------|
| Lemons | 3 | $1.20 |
| Sugar | 2 | $0.40 |
| Ice | ~2 | $0.30 |
| Water fill | 1 | $1.00 |
| Cups | 10 | $1.00 |
| **Total** | | **$3.90** |

**Revenue $10 − cost $3.90 = $6.10 gross profit (~61% margin).**

That is the intended ceiling: a perfect day at $1/cup clears ~60%.
Sloppy play (dumped pitchers, wrong ratios, unsold stock, spoiled batches) pulls
the realized margin down fast, which is where the difficulty lives. If playtests
show it's still too easy, raise lemons to $5/box first ($0.50 each → pitcher cost
$4.20, 58% margin) before touching anything else.

### Current values for comparison

At today's prices a perfect pitcher costs **$2.60** (~74% margin) — too easy,
and the margins get worse when you factor in the box-refund exploit below.

## Refund / recycling rules

### The cup-box exploit (fix required)

Cups cost $0.50/box, but the trashcan pays a flat `$1.00` for the empty box
(`empty_box_refund` / `TRASH_REFUND_EMPTY_BOX`). Result: buy box → take 10 cups
→ sell box → **+$0.50 profit and 10 free cups.** Repeatable forever.

Rule: **an empty box must always refund less than its purchase price**, and
loose enough that it can't fund free contents.

### Proposed refund table

| Item | Refund | Rationale |
|------|--------|-----------|
| Empty/opened supply box | **$0.25** flat scrap | Below cheapest box ($1 cups). Kills the exploit while still rewarding cleanup. |
| Unopened supply box (`amount` untouched) | **50% of purchase cost** | Softens over-ordering, never profitable. |
| **Partially-emptied box** (e.g. ice with 3/10 left) | **$0.25 scrap + 50% of remaining contents' value** | `refund = 0.25 + 0.5 × per_unit_cost × amount`. 3 ice left at $0.15 → ~$0.47. Never exceeds half of what the remaining stock cost, so dumping is always a loss vs. using it. |

Partial boxes are a real state — `held_item_data["amount"]` decrements per
cup/scoop deposited and only becomes `empty_box` at 0 (`player_placement.gd`).
The trashcan must read `amount`, not just the box type. Today it pays the flat
$1 for ANY non-equipment box — a 9/10 lemon box sells for $1 and a 1/10 box
does too. Per-unit cost can be looked up from the (unified) shop price table.
| Unopened equipment box | **70% of equipment cost** | Current behavior — keep. |
| Placed containers (crate, bowl, bucket, pitcher, press, dispenser, table) | **70% of cost** | Current `_get_container_cost_for_trash` behavior — keep. |
| Loose world trash (used cups, apple cores, etc.) | **$0** (or $0.05 flavor) | Pickup is its own reward; cash-for-trash invites farming. |
| Partially-used bins/pitchers | Container 70% **only if empty**; contents lost | Prevents dumping stock for cash. |
| Bad/spoiled lemonade | **$0** — pour out | A mistake should cost ingredients, not refund them. |

### Things that should NOT be refundable

- Used cups / dirty cups.
- Spoiled or wrong-ratio pitcher contents.
- Opened boxes' contents (once scooped, ingredients are spent).
- One-shot consumables after partial use.

## Known structural issues to fix alongside the numbers

1. **Shop prices are duplicated** in `shop_ui.gd` (`SHOP_ITEMS`) and
   `morning_hub.gd` (`shop_items`). Move both to `Balancing` so this doc maps
   1:1 to code.
2. **Phone ordering uses a different pricing model** —
   `DELIVERY_COST_PER_UNIT ($0.20) × qty` = $2/box regardless of item, versus
   morning-hub item prices. Decide: phone = item cost + flat delivery fee
   (e.g. $2/order) so it's never cheaper than walking to the shop.
3. `empty_box_refund` is an exported per-instance value AND
   `TRASH_REFUND_EMPTY_BOX` — unify to one constant.

## Sanity check — day 1

Starting money $150. Reasonable opening basket at proposed prices:

- 1 pitcher ($20) + 1 cup stack ($10) + 3 ingredient bins ($45) ≈ $75
- 1 lemons + 1 sugar + 1 ice + 1 cups + 1 water ≈ $13.50
- Total ≈ $88.50 → ~3 pitchers ≈ 30 cups ≈ $30 revenue day 1.

Leaves headroom for a press/dispenser next day and upgrade tiers
(`UPGRADE_TIER1_COST = $25`, `UPGRADE_TIER2_COST = $75`) stay meaningful
for the first few days.

## Upgrade hooks already in code

`bulk_buy`, `negotiation` (delivery discount), `larger_crates` (bigger boxes),
`trash_rebate` (refund bonus) — all read via `UpgradeManager.get_effect_total`.
New prices should live in `Balancing` so upgrades multiply one place.

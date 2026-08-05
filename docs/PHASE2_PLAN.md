# Phase 2 Development Plan — Lemonade Stand Simulator

> **Status:** Planning complete. Do not start implementing until explicitly instructed.

---

## Overview

Phase 2 transforms the existing customer-queue prototype into a full lemonade production and serving loop. The player must prepare lemonade in a pitcher, serve it to customers, and receive feedback based on recipe quality, temperature, and speed.

**Current State:**
- ✅ Customer queue, patience, walking, facing, leaving
- ✅ Payment handover animation + CashPickup
- ✅ Basic recipe evaluator stub exists (`recipe_evaluator.gd`)

**Phase 2 Goal:** A playable daily loop where the player can:
1. Buy ingredients (fruits, sugar, ice, water)
2. Place items on the stand
3. Press fruits + add sugar/water/ice into a pitcher
4. Fill cups from the pitcher
5. Serve customers
6. Receive feedback (sweetness, strength, fruit count, temperature)
7. End the day, persist state, start next day with new temperature

---

## Phase 2A: Core Production Loop (Foundation)

### 2A.1 — Ingredient System
**What:** Define base ingredients and their properties.

| Ingredient | Properties |
|---|---|
| Lemon | Strong flavor, tart, 3 lemons + 7 water = ideal base |
| Strawberry | Mild, needs more fruit (4 strawberries + 5 water = ideal) |
| Blueberry | Rich, subtle tartness, 4 blueberries + 6 water = ideal |
| Peach | Dense, naturally sweet, 4 peaches + 6 water = ideal |
| Watermelon | Massive, heavy, 7 cups puree + 3 water = ideal |
| Sugar | Adds sweetness per unit |
| Ice | Cools drink; ideal count depends on daily temperature |
| Water | Dilutes flavor; required base for all recipes |

**How it works:**
- Each fruit type has an `ingredient_data` resource with:
  - `flavor_strength: float` (how much 1 fruit contributes to "strength")
  - `sweetness: float` (how much 1 fruit contributes to "sweetness")
  - `ideal_water_ratio: float` (e.g., 7.0 for lemon)
  - `ideal_fruit_count: int` (e.g., 3 for lemon)
- Sugar has `sweetness_per_unit: float`
- Ice has `cooling_power: float` (each cube reduces drink temp by X degrees)

**Goal:** A data-driven ingredient system that the recipe evaluator can query.

**Expected Result:** An `IngredientDatabase` autoload or resource that holds all fruit/sugar/ice/water stats. New fruits can be added by creating a new resource file.

---

### 2A.2 — Pitcher System
**What:** A finite container that holds prepared lemonade.

**How it works:**
- Pitcher has `max_cups: int = 10`
- Pitcher has `current_cups: float` (can be fractional during fill)
- Pitcher holds a `RecipeSnapshot` — the exact ratios of what was put into it
  - `fruit_type: StringName`
  - `fruit_count: int`
  - `water_cups: float`
  - `sugar_units: int`
  - `ice_cubes: int`
- Player can ONLY serve from a pitcher that has contents
- Once empty, pitcher must be refilled (old recipe is discarded)

**Goal:** Centralize production into a batch system. The player prepares 10 cups at once, then serves from that batch.

**Expected Result:** A `Pitcher` scene/node that tracks its contents and can report how many cups remain. Player can see a visual fill level.

---

### 2A.3 — Press + Cup Filling Interaction
**What:** The physical act of making lemonade and filling cups.

**How it works — Pressing:**
1. Player places fruits into the press (hold to add one at a time, or click to add)
2. Player clicks/holds to press — a progress bar fills
3. Pressed fruit juice goes into the pitcher
4. Player adds water, sugar, ice (click or drag onto pitcher)
5. Once ingredients are in, pitcher is "mixed" and ready

**How it works — Filling Cups:**
1. Player grabs an empty cup (from a stack on the stand)
2. Holds interact over the pitcher
3. Cup fills gradually (longer hold = more filled)
4. Cup can be underfilled (<100%) or overfilled (>100% spills?)
5. Cup now holds a "serving" — a reference to the pitcher's `RecipeSnapshot`

**Goal:** Create tactile, satisfying interactions for the core loop.

**Expected Result:**
- Pressing fruits has a short animation/progress bar
- Pitcher visually updates as ingredients are added
- Cup fill level is visible (liquid rises)
- Overfilling causes spill (wastes pitcher contents, maybe a small penalty)

---

### 2A.4 — Handing Cup to Customer
**What:** Connect the filled cup to the existing customer serve flow.

**How it works:**
- When customer reaches front of queue, they enter WAITING → RECEIVING state
- Player holds a filled cup and interacts with the customer
- Cup is "handed over" (disappears from player, customer plays receiving anim)
- Recipe is evaluated immediately upon handover
- Customer reacts based on evaluation result

**Goal:** Hook the production output into the existing customer flow.

**Expected Result:** Player can serve a customer. The drink is evaluated. Customer shows emoji/reaction. Cash is handed over (existing payment anim).

---

## Phase 2B: Recipe Evaluation

### 2B.1 — 4-Axis Scoring System
**What:** Evaluate every served drink on 4 dimensions.

**How it works:**
Given a `RecipeSnapshot` and the day's `ideal_temperature`:

1. **Sweetness Score**
   - Calculate ideal sugar for the fruit count used
   - `ideal_sugar = fruit_count * fruit_data.sweetness * target_sweetness_multiplier`
   - Score = 1.0 - abs(actual_sugar - ideal_sugar) / ideal_sugar
   - If score < threshold → feedback: "Not sweet enough" or "Too sweet"

2. **Strength Score**
   - Calculate ideal fruit count for the water amount used
   - `ideal_fruit = water_cups / fruit_data.ideal_water_ratio * fruit_data.ideal_fruit_count`
   - Score = 1.0 - abs(actual_fruit - ideal_fruit) / ideal_fruit
   - If score < threshold → feedback: "Too strong" or "Not enough fruit"

3. **Fruit Count Score**
   - Same as strength but inverted framing (customer-facing)
   - Actually the same metric as strength — just different feedback copy
   - If too much fruit → "Too strong"
   - If too little fruit → "Not enough fruit / too watery"

4. **Temperature Score**
   - Daily temperature determines ideal ice count
   - `ideal_ice = base_ice + (hotter_days_need_more_ice)`
   - `actual_temp = ambient_temp - (ice_cubes * cooling_per_cube)`
   - Score based on distance from ideal temp
   - If too cold → "Too cold"
   - If too warm → "Not cold enough"

**Goal:** Every drink gets an objective quality score. Feedback is specific and actionable.

**Expected Result:** A `RecipeEvaluator.evaluate(recipe: RecipeSnapshot, day_temp: float) -> EvaluationResult` function that returns:
```gdscript
class_name EvaluationResult
var sweetness_score: float  # 0.0 to 1.0
var strength_score: float
var temperature_score: float
var overall_score: float    # average of above
var feedback: Array[String]   # e.g., ["Too sweet", "Not cold enough"]
var is_perfect: bool          # all scores >= 0.95
```

---

### 2B.2 — Customer Reaction Mapping
**What:** Map evaluation scores to the 8 reaction types from the design doc.

**Reaction Priority (checked in order):**
1. **Takes too long** — patience meter expired before serve
2. **Wrong order** — player served wrong fruit type (if/when multi-fruit is implemented)
3. **Too sweet** — sweetness_score < 0.5 and sugar was above ideal
4. **Not sweet enough** — sweetness_score < 0.5 and sugar was below ideal
5. **Too strong** — strength_score < 0.5 and fruit was above ideal
6. **Not enough fruit / too watery** — strength_score < 0.5 and fruit was below ideal
7. **Too cold** — temp_score < 0.5 and temp was below ideal (too much ice)
8. **Not cold enough** — temp_score < 0.5 and temp was above ideal (too little ice)

**How it works:**
- If `overall_score >= 0.8` and no complaints → happy customer, full pay, +popularity
- If `overall_score >= 0.5` and 1-2 minor complaints → neutral, pays but -small popularity
- If `overall_score < 0.5` or major complaint → unhappy, may still pay but -popularity
- "Takes too long" and "Wrong order" are binary — they override all other feedback

**Goal:** Customers give specific, understandable feedback.

**Expected Result:** Customer shows the correct emoji(s) above their head. If multiple issues exist, show the most severe one (or cycle through them).

---

### 2B.3 — Popularity System
**What:** Track how well the player is doing and affect future customer traffic.

**How it works:**
- `popularity: float` (0.0 to 1.0, starts at 0.5)
- Each served drink modifies popularity:
  - Perfect serve: +0.05
  - Good serve (score >= 0.8): +0.02
  - Okay serve (score >= 0.5): 0.0
  - Bad serve (score < 0.5): -0.03
  - Timeout (takes too long): -0.05
- Popularity affects `conversion_rate` — the chance a spawned pedestrian becomes a customer
- `conversion_rate = base_rate * popularity` (e.g., base 60% → 30% at 0.5 popularity, 60% at 1.0)

**Goal:** Consequence for poor performance. Good players get more customers.

**Expected Result:** A `PopularityManager` autoload that tracks score. UI shows current popularity (maybe a star rating or bar). Pedestrian spawner reads this for conversion rate.

---

## Phase 2C: Store & Economy

### 2C.1 — Ingredient Shop
**What:** A UI where the player buys ingredients before the day starts.

**How it works:**
- At end-of-day or beginning-of-day, a shop UI appears
- Player starts with a budget ($X)
- Can buy:
  - Fruit crates (each crate holds N fruits)
  - Sugar bags (each bag holds N sugar units)
  - Ice bags (each bag holds N ice cubes)
  - Water is free/infinite (or costs per pitcher fill)
- Prices vary by fruit type (exotic fruits = more expensive)
- Player can only buy what they can afford

**Goal:** Resource management. Player must budget wisely.

**Expected Result:** A `ShopUI` panel with buy buttons, quantities, prices, and current money display. Items are added to inventory.

---

### 2C.2 — Inventory System
**What:** Track what the player owns and where items are placed.

**How it works:**
- `Inventory` is a dictionary: `item_type -> count`
- When player buys a crate, `Inventory["lemon_crate"] += 1`
- When player places a crate on the stand, inventory decreases, a physical `Crate` node appears
- When player takes a fruit from a placed crate, crate's internal count decreases
- When crate is empty, it disappears (or becomes an empty crate that can be restocked)

**Goal:** Bridge the shop and the physical stand.

**Expected Result:** Player can see how many fruits/sugar/ice they have. Placed crates show a number (e.g., "12/20 lemons remaining").

---

### 2C.3 — Pricing & Money
**What:** Player sets lemonade price. Customers pay.

**How it works:**
- Before each day, player sets a price per cup (via UI slider or input)
- Higher price → lower patience (customers less willing to wait)
- Lower price → higher patience
- Customer pays with the smallest bill that covers price (as already designed)
- Player must give change at the register (existing CashPickup flow)

**Goal:** Price is a strategic dial.

**Expected Result:** A `PriceSetter` UI before each day. Price affects customer patience via `patience_multiplier = 1.0 / (price / market_rate)`.

---

## Phase 2D: Day Cycle & Persistence

### 2D.1 — Day Structure
**What:** A clear beginning → middle → end flow.

**How it works:**
1. **Morning (Shop Phase)**
   - Show yesterday's summary (revenue, serves, avg score)
   - Open shop UI — player buys ingredients
   - Set price for the day
   - Place/rearrange items on stand
2. **Day Phase (Serve Phase)**
   - Weather/temperature is revealed
   - Customers spawn and queue
   - Player produces and serves
   - Day timer runs (e.g., 5 minutes or until sunset)
3. **Evening (Summary Phase)**
   - Show day's stats
   - Calculate net profit (revenue - ingredient costs)
   - Save progress

**Goal:** Give the game a daily rhythm.

**Expected Result:** A `DayManager` autoload that handles phase transitions. UI screens for shop, serving, and summary.

---

### 2D.2 — Weather & Temperature
**What:** Daily random temperature that affects ideal ice count.

**How it works:**
- Each day, `temperature = randi_range(20, 35)` degrees (Celsius)
- `ideal_ice = map(temperature, 20->1, 35->5)` (linear interpolation)
- UI shows a sun icon + temperature reading
- Players must observe and adjust ice per day

**Goal:** Daily variety. Prevents "one recipe wins forever."

**Expected Result:** A `WeatherManager` autoload. UI shows "Today: 28°C — Recommended ice: 3 cubes."

---

### 2D.3 — Persistence
**What:** Save money, inventory, popularity, and unlocked items between sessions.

**How it works:**
- Save file stores:
  - `money: int`
  - `popularity: float`
  - `unlocked_fruits: Array[StringName]`
  - `owned_upgrades: Array[StringName]`
- Stand layout is NOT saved (simpler for now; items go back to inventory at end of day)
- Or: Stand layout IS saved and persists

**Goal:** Progression over multiple play sessions.

**Expected Result:** `SaveManager` that loads/saves a `PlayerProfile` resource. Game resumes where player left off.

---

## Phase 2E: Upgrades

### 2E.1 — Upgrade Definitions
**What:** Unlockable improvements bought with money.

| Upgrade | Effect | Cost |
|---|---|---|
| Press | Faster fruit pressing speed | $100 |
| Nimbleness | Increases ingredient placement speed while holding LMB | $100 |
| Sunroof/Umbrella | Increases customer patience; decreases refill rate | $150 |
| Crates | Larger fruit crates (hold more fruits) | $200 |
| Fruits | Unlocks new fruit type for shop | $300 |
| Sales | Increases price flexibility (customers tolerate higher prices) | $250 |
| Psychology | Reveals exact feedback (e.g., "You used 2 sugar but needed 3") | $400 |

**How it works:**
- Upgrades are bought in the shop UI (separate tab)
- Once bought, effect is permanent
- `Unlocks` opens new fruit types in the ingredient shop

**Goal:** Long-term progression. Player feels growth.

**Expected Result:** An `UpgradeManager` that checks which upgrades are owned and applies their effects to relevant systems.

---

## Phase 2F: Item Placement (Build Mode)

### 2F.1 — Placement Rules
**What:** Grid-based or free placement of stand items.

**How it works:**
- Player enters "build mode" (before day starts)
- Can place: empty/full crates, press, sugar, ice containers, cups
- **Rules:**
  - Crates: anywhere (floor, counter)
  - Press, sugar, ice, cups: only on the stand/workbench
  - Cups: must be reachable from player position
  - Maximum 1 press per stand
- Items snap to a grid or surface
- Visual indicators show valid (green) vs invalid (red) placement

**Goal:** Physical, spatial organization of the stand.

**Expected Result:** A `BuildMode` controller that handles placement validation, snapping, and saving the layout.

---

## Implementation Order (Recommended)

**Week 1 — Core Loop:**
1. ✅ Ingredient data resources (2A.1)
2. ✅ Pitcher system (2A.2)
3. ✅ Press + fill interactions (2A.3)
4. ✅ Hand cup to customer (2A.4)

**Week 2 — Evaluation & Feedback:**
5. ✅ 4-axis recipe evaluator (2B.1)
6. ✅ Customer reaction mapping (2B.2)
7. ✅ Popularity system (2B.3)

**Week 3 — Economy & Day Cycle:**
8. ✅ Ingredient shop (2C.1)
9. ✅ Inventory system (2C.2)
10. ✅ Pricing & money flow (2C.3)
11. ✅ Day structure + weather (2D.1, 2D.2)

**Week 4 — Progression & Polish:**
12. ✅ Upgrades (2E.1)
13. ✅ Item placement (2F.1)
14. ✅ Persistence / save system (2D.3)
15. ✅ Juice particle effects, pitcher liquid visual, cup fill animation

---

## Open Questions

1. **Does the player hold a cup in their hand while filling, or does the cup stay on the counter?**
2. **Can the player prepare multiple pitchers at once (e.g., one lemon, one strawberry)?**
3. **What happens to leftover lemonade at end of day?** (Dumped? Saved for tomorrow?)
4. **Does the stand layout persist between days, or does everything go back to inventory?**
5. **Is there a hard day timer, or does the day end when the queue is empty?**

---

## Files to Create / Modify

### New Files
- `scripts/systems/ingredient_database.gd` — Ingredient stats
- `scripts/systems/recipe_snapshot.gd` — Pitcher contents data
- `scripts/systems/evaluation_result.gd` — Scoring result
- `scripts/systems/recipe_evaluator.gd` — Already exists, needs full implementation
- `scripts/systems/popularity_manager.gd` — Popularity tracking
- `scripts/systems/weather_manager.gd` — Daily temperature
- `scripts/systems/day_manager.gd` — Day phase control
- `scripts/systems/save_manager.gd` — Save/load profile
- `scripts/systems/upgrade_manager.gd` — Owned upgrades
- `scripts/systems/inventory.gd` — Item counts
- `scripts/objects/pitcher.gd` + `pitcher.tscn`
- `scripts/objects/cup.gd` + `cup.tscn`
- `scripts/objects/fruit_crate.gd` + `fruit_crate.tscn`
- `scripts/objects/press.gd` + `press.tscn`
- `scripts/ui/shop_ui.gd` + `shop_ui.tscn`
- `scripts/ui/price_setter.gd` + `price_setter.tscn`
- `scripts/ui/day_summary.gd` + `day_summary.tscn`
- `scripts/ui/build_mode.gd` — Placement controller

### Modified Files
- `scripts/customer/customer.gd` — Hook evaluation result into reaction
- `scripts/customer/customer_spawner.gd` — Read popularity for conversion rate
- `scripts/main.gd` — Wire day phases together
- `scripts/player/player.gd` — Add hold/carry state for cups
- `scripts/objects/cash_pickup.gd` — May need price display update
- `scripts/balancing.gd` — Add new constants (pitcher size, base patience, etc.)

---

**Plan approved? Reply with which week/section to start, or any changes needed.**

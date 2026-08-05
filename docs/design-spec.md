# Lemonade Stand Simulator — Game Design Specification
### Version 1.0 | Godot 4 Vertical Slice

---

## Overview

A fully connected 3D first-person Lemonade Stand Simulator. All visuals use primitive shapes (boxes, cylinders, spheres) so it is instantly playable before 3D models are added. The architecture is completely modular — every major system is isolated from the others and communicates only through a central EventBus. This makes individual systems safe to rewrite or rebalance without side-effects.

**Starting Money:** $50.00  
**Engine:** Godot 4.6 (GL Compatibility renderer, Jolt Physics)

---

## Core Architecture Rules

- **EventBus (autoload):** All cross-system communication goes through a single global signal dispatcher. No script holds a direct reference to another system's script.
- **GameState (autoload):** Holds all live game data — money, popularity, temperature, current price, upgrade level. Listens to the EventBus and re-emits derived signals.
- **Balancing (autoload):** Every tunable number lives in one file. Nothing is hardcoded anywhere else.
- **Editor-first scenes:** All static geometry, collision shapes, slots, labels, and queue markers are built as real child nodes inside `.tscn` files — fully visible and tweakable in the Godot editor without running the game. Scripts handle only game logic.
- **Held-item model:** The player holds one item at a time via a typed slot (HandSlot Node3D, child of Camera3D). No complex scene reparenting required.

### What Is Instantiated at Runtime (and why)

| Object | Reason |
|---|---|
| Customer NPCs | Spawned dynamically by CustomerSpawner based on popularity |
| Supply boxes | Spawned by DeliverySystem when an order is placed |
| Cash pickups | Dropped on the counter when a customer pays |
| Emoji displays | Created above a customer's head on transaction result |

---

## Physical Layout (Bird's-Eye)

```
[Customer Despawn]         Z = -10
[Customer Spawn]           Z = -7
[Customer Queue — 3 spots] Z = -2, -3, -4
[Stand Counter — FRONT]    Z = -0.5   ← customers face here
[Stand Frame]              Z: -0.5 to 1.5
[Stand Counter — BACK]     Z = 1.5    ← player serves from here
[Prep Table]               Z = 2.5    ← behind the stand
[Player Start]             Z = 3.5

[Delivery Zone]            X=5, Z=5   ← off to the side
```

- Ground: Y = 0
- Counter top height: Y = 1.0
- Prep table height: Y = 0.9

---

## Controls

| Action | Input |
|---|---|
| Move | WASD |
| Look | Mouse |
| Interact (primary) | Left Click |
| Throw Out / Secondary Interact | E |
| Open/Close Phone Menu | Tab |
| Release Mouse Cursor | Esc |

---

## System 1 — The Pitcher & Prep Workflow

The pitcher is the central object in the game. It has three locked states that enforce the physical workflow.

### Pitcher States

**PREPPING** (snapped to prep table slot)
- Player clicks ingredient bins to add lemons, water, sugar, or ice one unit at a time.
- Bins show "Add to Pitcher" as the interaction hint.
- Player clicks the pitcher itself when satisfied → pitcher seals and is picked up (→ SEALED).
- Clicking an empty pitcher shows: *"Add lemon and water first."*

**SEALED** (in player's hand)
- No ingredients can be added. Contents are locked.
- Player walks to the stand and clicks the front counter → pitcher placed (→ SERVING). Requires liquid_volume > 0.
- Clicking the counter with a liquid-empty pitcher shows: *"Pitcher has no lemonade."*
- Press **E** to **Throw Out** → all contents cleared, pitcher returns to prep table (→ PREPPING).

**SERVING** (snapped to front counter slot)
- Player clicks pitcher while holding an empty cup → cup fills with a snapshot of the current recipe.
- Pitcher **cannot** be picked up unless it is completely empty (lemons + water + sugar + ice = 0).
- Press **E** to **Throw Out** at any time → all contents cleared, pitcher returns to prep table (→ PREPPING).

### Pitcher Interaction Table

| Player Action | Pitcher State | Result |
|---|---|---|
| Hold pitcher + click prep table | Any (empty contents) | Snaps to prep slot → PREPPING |
| Hold pitcher + click prep table | Has contents | Blocked: *"Seal pitcher first or throw it out"* |
| Click a bin | PREPPING | Adds 1 unit of that ingredient |
| Click pitcher (has liquid) | PREPPING | Seals, player picks up → SEALED |
| Click pitcher (empty) | PREPPING | Blocked: *"Add lemon and water first"* |
| Hold pitcher + click counter | SEALED, liquid > 0 | Places on counter → SERVING |
| Hold pitcher + click counter | SEALED, liquid = 0 | Blocked: *"Pitcher has no lemonade"* |
| Click pitcher while holding cup | SERVING | Fills cup, deducts one portion from liquid |
| Click pitcher (fully empty) | SERVING | Player picks up, pitcher now empty in hand |
| Press E on pitcher | Any state | Throw Out — clears all contents → PREPPING |

### Pitcher Volume Rules
- **liquid_volume = lemons + water ONLY.** Hard cap: 10 units.
- **Sugar** and **ice** are tracked separately and do NOT count toward the 10-unit liquid cap.
- The pitcher label displays: `Liquid: X/10 | Sugar: X | Ice: X`

---

## System 2 — The Recipe & Balancing Logic

### Ingredient Roles

| Ingredient | Counts Toward Liquid Cap | Role |
|---|---|---|
| Lemons | YES | Determines sharpness / sourness of the drink |
| Water | YES | Dilutes the lemon concentration |
| Sugar | NO | Sweetness — must scale with total liquid volume |
| Ice | NO | Temperature satisfaction — must match current weather |

### Rule 1 — Sharpness (Lemon-to-Water Ratio)

```
sharpness   = lemons / liquid_volume
ideal range = 0.30 ± 0.08   (i.e., 22% to 38% lemon)
```

- Too high → outcome: **"too_sour"**
- Too low → outcome: **"too_watery"**

### Rule 2 — Sugar Scaling (Dynamic, Based on Liquid Volume)

```
ideal_sugar = liquid_volume × 0.15
tolerance   = ± 0.05 × liquid_volume
```

Examples:
- Full pitcher (10 liquid) → needs **1.5 sugar** ± 0.5
- Half pitcher (5 liquid) → needs **0.75 sugar** ± 0.25
- Quarter pitcher (2.5 liquid) → needs **0.375 sugar** ± 0.125

- Too high → outcome: **"too_sweet"**
- Too low → outcome: **"not_sweet_enough"**

### Rule 3 — Ice (Dynamic, Based on Current Temperature)

```
temp_normalized = (temperature − 10) / (40 − 10)   [clamped 0.0 to 1.0]
ideal_ice       = lerp(0, 5, temp_normalized)
tolerance       = ± 1 ice unit
```

- Ice does NOT count toward liquid volume.
- Too little ice on a hot day → outcome: **"lukewarm"**
- Too much ice on a cold day → outcome: **"freezing"**

### Evaluation Priority Order

The recipe evaluator always checks in this exact order. The first failing check wins.

1. Patience timer expired → **"timeout"**
2. Price > $2.75 → **"too_expensive"**
3. liquid_volume = 0 → **"too_watery"** (nothing in the pitcher)
4. Lemon ratio too high → **"too_sour"**
5. Lemon ratio too low → **"too_watery"**
6. Sugar too high for liquid volume → **"too_sweet"**
7. Sugar too low for liquid volume → **"not_sweet_enough"**
8. Ice too low for current temperature → **"lukewarm"**
9. Ice too high for current temperature → **"freezing"**
10. All pass → **"happy"**

---

## System 3 — Customer Feedback & Emoji Progression

### The Feedback Tier System

Customer emoji feedback is locked behind an upgrade level tracked globally. Players start blind to recipe specifics and must invest in upgrades to learn what is going wrong.

**Tier 0 — Basic Feedback (Default)**

Customers show one of only two reactions:
- 😊 Happy — recipe passed all checks
- 😞 Unhappy — something is wrong (player receives no clue what)

**Tier 1 — Category Clue** (unlocked via "Customer Relations" upgrade, costs $25)

Unhappy feedback now shows which *category* failed — but not the direction:
- 🍋 Lemon icon — concentration is wrong (too sour OR too watery)
- 🍬 Sugar icon — sweetness is wrong (too sweet OR not sweet enough)
- 🌡️ Thermometer icon — temperature is wrong (too lukewarm OR too freezing)

**Tier 2 — Precision Direction** (unlocked after Tier 1, costs $75)

Full directional feedback. Customers pinpoint the exact problem:
- 😖 Too sour (too many lemons for the water)
- 💧 Too watery (not enough lemons for the water)
- 🍯 Too sweet / syrupy (excess sugar for the liquid volume)
- 😐 Bland / not sweet enough (insufficient sugar for the liquid volume)
- 🥵 Lukewarm (not enough ice for the heat)
- 🥶 Freezing (too much ice for a cold day)

### Full Emoji Mapping Table

| Outcome | Tier 0 | Tier 1 | Tier 2 |
|---|---|---|---|
| happy | 😊 | 😊 | 😊 |
| too_sour | 😞 | 🍋 | 😖 |
| too_watery | 😞 | 🍋 | 💧 |
| too_sweet | 😞 | 🍬 | 🍯 |
| not_sweet_enough | 😞 | 🍬 | 😐 |
| lukewarm | 😞 | 🌡️ | 🥵 |
| freezing | 😞 | 🌡️ | 🥶 |
| too_expensive | 💸 | 💸 | 💸 |
| timeout | ⏰ | ⏰ | ⏰ |

> **Note:** "too_expensive" and "timeout" always show their specific emoji at every tier — these are business failures, not recipe failures, so the player should always understand them immediately.

### Customer AI States

```
SPAWNING → WALKING → WAITING → RECEIVING → REACTING → LEAVING
```

- **WALKING:** Customer moves toward their assigned queue spot.
- **WAITING:** Patience countdown begins (45 seconds base). A visible timer above their head counts down.
- **RECEIVING:** Triggered when player hands them a filled cup. Recipe evaluator runs immediately.
- **REACTING:** Emoji floats up above the customer's head and fades out over 2 seconds.
- **LEAVING:** Customer walks to despawn point and is removed from the scene.

### Popularity System

Serving happy customers increases global popularity (0.0 → 1.0). Higher popularity forces the spawner to send new customers faster.

```
spawn_interval = lerp(5 seconds, 30 seconds, 1.0 - popularity)
```

| Event | Popularity Change |
|---|---|
| Happy customer served | +0.05 |
| Bad taste (any recipe failure) | -0.03 |
| Too expensive | -0.02 |
| Customer timeout | -0.04 |

Maximum queue size: 3 customers at once.

---

## System 4 — Smartphone Ordering & Delivery

The player orders ingredient restocks through the phone menu (Tab key).

**Phone Menu contains:**
- 4 ingredient rows: Lemons, Water, Sugar, Ice — each with +/− quantity buttons and a running cost preview
- Price slider ($0.25 to $5.00) — sets the selling price per cup of lemonade
- "Order" button — places the order and deducts cost from money immediately
- Upgrade shop — Customer Relations Tier 1 and Tier 2 upgrades purchasable here

**Delivery flow:**
1. Player places order → cost deducted immediately from money
2. After a short delay, a physical supply box drops from the air at the delivery zone (off to the side of the stand) with a falling animation
3. Box displays a floating text label showing its contents (e.g., "Lemons ×10")
4. Player walks to the box and clicks it → picks it up (held item becomes the supply box)
5. Player walks to the matching ingredient bin and clicks → box deposits into the bin and disappears
6. Bin fill meter updates visually

**Ingredient cost:** $0.20 per unit. Ordering 10 units costs $2.00.

---

## System 5 — Developer Balancing Panel

Always visible on the right side of the screen. Never hidden during play. Designed for rapid iteration during development and balancing sessions.

### Quick Cheat Buttons

| Button | Effect |
|---|---|
| +$50 | Instantly adds $50 to current money |
| Refill All Bins | Sets all 4 ingredient bins to maximum (20 units each) |
| Empty Pitcher | Clears all pitcher contents, returns pitcher to PREPPING state |
| Force Spawn Customer | Immediately sends one customer to the queue |

### Feedback Tier Override

- **Set Tier 0 / Tier 1 / Tier 2** — Instantly sets the feedback upgrade tier without purchasing it, for testing emoji display

### Live Temperature Slider

- Range: 10°C (Cold Day) → 40°C (Scorching Heatwave)
- Changes take effect immediately in real-time
- Updates the Ideal Ice readout and HUD temperature indicator instantly

### Live Stats Readout (refreshes every 0.1 seconds)

```
=== ECONOMY ===
Money:              $XX.XX
Price Per Cup:      $X.XX
Popularity:         X.XX  (XX%)

=== WEATHER ===
Temperature:        XX°C
Ideal Ice Units:    X.X

=== PITCHER (LIVE) ===
State:              PREPPING / SEALED / SERVING
Liquid Volume:      X.X / 10.0
  Lemons:           X.X
  Water:            X.X
Sugar:              X.X   (ideal: X.X ± X.X)
Ice:                X.X   (ideal: X.X ± 1.0)
Sharpness Ratio:    X.XX  (ideal: 0.30 ± 0.08)
Recipe Verdict:     PASS  /  [failing check name]

=== CUSTOMERS ===
Queue Length:       X / 3
Next Spawn In:      X.Xs
Feedback Tier:      X (Basic / Category / Precision)

=== SESSION TOTALS ===
Served (happy):     X
Lost (bad/timeout): X
```

---

## All Balancing Constants

| Constant | Default Value | Description |
|---|---|---|
| STARTING_MONEY | $50.00 | Player starting funds |
| PATIENCE_BASE | 45.0 s | How long a customer waits before timing out |
| PRICE_FAIR_MAX | $2.00 | Price above this makes customers unhappy |
| PRICE_TOO_EXPENSIVE | $2.75 | Price above this → "too_expensive" emoji |
| IDEAL_LEMON_RATIO | 0.30 | Target: lemons / liquid_volume |
| LEMON_RATIO_TOLERANCE | ± 0.08 | Acceptable deviation from ideal ratio |
| IDEAL_SUGAR_PER_LIQUID | 0.15 | Sugar units needed per 1 unit of liquid volume |
| SUGAR_TOLERANCE | ± 0.05 | Acceptable sugar deviation per liquid unit |
| ICE_MIN_COUNT | 0.0 units | Ice needed at minimum temperature (10°C) |
| ICE_MAX_COUNT | 5.0 units | Ice needed at maximum temperature (40°C) |
| ICE_TOLERANCE | ± 1.0 unit | Acceptable deviation from ideal ice count |
| ICE_MIN_TEMP | 10°C | Lower bound of temperature range |
| ICE_MAX_TEMP | 40°C | Upper bound of temperature range |
| PITCHER_MAX_LIQUID | 10.0 units | Hard cap on lemons + water combined |
| PORTION_SIZE | 2.0 units | Liquid deducted from pitcher per cup filled |
| BIN_MAX_CAPACITY | 20.0 units | Maximum stock per ingredient bin |
| GRAB_AMOUNT | 1.0 unit | Units added to pitcher per bin click |
| DELIVERY_COST | $0.20 / unit | Cost per unit when ordering supplies |
| DELIVERY_QUANTITY | 10.0 units | Default order size per ingredient |
| SPAWN_RATE_MIN | 5.0 s | Fastest customer arrival (at max popularity) |
| SPAWN_RATE_MAX | 30.0 s | Slowest customer arrival (at min popularity) |
| QUEUE_MAX | 3 | Maximum concurrent customers in queue |
| CUSTOMER_WALK_SPEED | 3.0 m/s | How fast customers move to their queue spot |
| POPULARITY_GAIN_HAPPY | +0.05 | Popularity gained per happy customer |
| POPULARITY_LOSS_BAD | -0.03 | Popularity lost per bad taste outcome |
| POPULARITY_LOSS_EXPENSIVE | -0.02 | Popularity lost per too expensive outcome |
| POPULARITY_LOSS_TIMEOUT | -0.04 | Popularity lost per customer timeout |
| UPGRADE_TIER1_COST | $25.00 | Cost to unlock Category Clue feedback |
| UPGRADE_TIER2_COST | $75.00 | Cost to unlock Precision Direction feedback |

---

## End-to-End Game Loop (Full Walkthrough)

1. Player opens Phone Menu (Tab) → sets price per cup → orders 10 lemons and 10 water ($4.00 deducted)
2. Two supply boxes drop at the delivery zone with a falling animation
3. Player picks up each box and deposits it into the matching bin — fill meters rise
4. Player walks to the empty pitcher on the prep table — pitcher is in PREPPING state, snapped to slot
5. Player clicks Lemon bin 3× (3 lemons added), Water bin 7× (7 water added) → liquid_volume = 10
6. Player clicks Sugar bin 1× → 1 sugar added, within ideal range for 10 units of liquid
7. Player clicks Ice bin 3× based on current temperature (e.g., 30°C → ideal ≈ 3.3 ice units)
8. Player clicks the pitcher → seals, player picks it up (→ SEALED)
9. Player walks to the front counter and clicks → pitcher placed (→ SERVING)
10. A customer walks in, reaches queue spot 1, patience timer starts (45 seconds)
11. Player picks up an empty cup from the cup stack on the counter
12. Player clicks the pitcher → cup fills with a snapshot of the pitcher's recipe
13. Player clicks the waiting customer while holding the filled cup → recipe evaluator runs
14. Outcome: **"happy"** → 😊 emoji floats above customer's head, physical cash drops on the counter, popularity +0.05
15. Player clicks the cash on the counter → collected, money updates in HUD
16. Spawn interval tightens due to increased popularity — next customer arrives sooner

---

## File Structure & Editor Scene Trees

All geometry, colliders, slots, and labels are real child nodes set up in the editor.
Scripts contain only game logic — no mesh or shape creation at runtime.

### Scripts (no scene, logic only)

```
scripts/
├── autoloads/
│   ├── event_bus.gd          — all ~50 signals, the only cross-system channel
│   ├── game_state.gd         — money, popularity, temperature, tier, price
│   └── balancing.gd          — every constant, single source of truth
├── core/
│   └── interactable.gd       — base class (class_name Interactable); virtual interact() + get_hint()
├── player/
│   └── player.gd             — WASD, mouse look, raycast, held-item logic
├── objects/
│   ├── ingredient_bin.gd     — tracks amount, updates fill mesh scale, handles interact
│   ├── pitcher.gd            — PREPPING/SEALED/SERVING state machine
│   ├── supply_box.gd         — holds ingredient type + amount, deposits on bin click
│   ├── cup.gd                — EMPTY/FILLED states, fills from pitcher, serves to customer
│   └── cash_pickup.gd        — collect on click, emit cash_collected, queue_free
├── customer/
│   ├── customer.gd           — WALKING/WAITING/RECEIVING/REACTING/LEAVING state machine
│   ├── customer_spawner.gd   — manages 3-slot queue, timer driven by popularity
│   └── emoji_display.gd      — tier-aware lookup, float+fade Tween, queue_free
├── systems/
│   ├── recipe_evaluator.gd   — pure static evaluate() function, no autoload dependencies
│   └── delivery_system.gd    — listens for order signal, instances supply_box, drop Tween
└── ui/
    ├── hud.gd                — updates money, popularity bar, temp, held-item label, hint
    ├── phone_menu.gd         — order rows, price slider, upgrade shop buttons
    └── debug_panel.gd        — cheat buttons, temp slider, live stats label (_process)
```

---

### main.tscn — Root Scene (editor tree)

```
Main  [Node]
├── World  [Node3D]
│   ├── Ground  [StaticBody3D]
│   │   ├── MeshInstance3D  (BoxMesh, large flat plane)
│   │   └── CollisionShape3D  (BoxShape3D)
│   ├── LemonadeStand  [Node3D]
│   │   ├── Post_FL  [StaticBody3D > MeshInstance3D + CollisionShape3D]  (front-left leg)
│   │   ├── Post_FR  [StaticBody3D > MeshInstance3D + CollisionShape3D]  (front-right leg)
│   │   ├── Post_BL  [StaticBody3D > MeshInstance3D + CollisionShape3D]  (back-left leg)
│   │   ├── Post_BR  [StaticBody3D > MeshInstance3D + CollisionShape3D]  (back-right leg)
│   │   ├── Counter  [StaticBody3D > MeshInstance3D + CollisionShape3D]  (serving surface)
│   │   ├── Roof  [StaticBody3D > MeshInstance3D + CollisionShape3D]
│   │   ├── Sign  [MeshInstance3D + Label3D]  ("LEMONADE")
│   │   └── PitcherCounterSlot  [Area3D > CollisionShape3D]  (detects pitcher placed here)
│   ├── PrepTable  [Node3D]
│   │   ├── TableTop  [StaticBody3D > MeshInstance3D + CollisionShape3D]
│   │   └── PitcherPrepSlot  [Area3D > CollisionShape3D]  (detects pitcher placed here)
│   ├── Bins  [Node3D]
│   │   ├── LemonBin  [ingredient_bin.tscn]  (exported: type=lemon, color=yellow)
│   │   ├── WaterBin  [ingredient_bin.tscn]  (exported: type=water, color=blue)
│   │   ├── SugarBin  [ingredient_bin.tscn]  (exported: type=sugar, color=white)
│   │   └── IceBin   [ingredient_bin.tscn]  (exported: type=ice, color=cyan)
│   ├── CupStack  [StaticBody3D > MeshInstance3D + CollisionShape3D + Label3D]
│   │   └── script: cup_stack.gd  (dispenses cup.tscn on interact)
│   ├── DeliveryZone  [Marker3D]  (spawn point for supply boxes — visible as gizmo)
│   └── CustomerQueue  [Node3D]
│       ├── Spot1  [Marker3D]  (Z = -2)
│       ├── Spot2  [Marker3D]  (Z = -3)
│       └── Spot3  [Marker3D]  (Z = -4)
├── Pitcher  [pitcher.tscn]  (placed at prep table in editor)
├── Player  [player.tscn]
├── CustomerSpawner  [Node, customer_spawner.gd]
├── DeliverySystem  [Node, delivery_system.gd]
└── UI  [CanvasLayer]
    ├── HUD  [hud.tscn]
    ├── PhoneMenu  [phone_menu.tscn]  (hidden by default)
    └── DebugPanel  [debug_panel.tscn]
```

---

### player.tscn

```
Player  [CharacterBody3D, player.gd]
├── CollisionShape3D  (CapsuleShape3D — player body)
├── Head  [Node3D]  (Y = 1.6, rotates on mouse Y)
│   ├── Camera3D
│   │   └── HandSlot  [Node3D]  (held item visual parented here; offset forward+down)
│   └── RayCast3D  (length 3.5m, forward)
└── BodyMesh  [MeshInstance3D]  (CapsuleMesh so player casts shadow)
```

---

### ingredient_bin.tscn

```
IngredientBin  [StaticBody3D, ingredient_bin.gd]
│   Exported: ingredient_type: String, tint: Color
├── Container  [MeshInstance3D]  (BoxMesh — the outer bin shell)
├── FillMesh  [MeshInstance3D]  (BoxMesh — script scales Y to show fill level)
├── CollisionShape3D
└── AmountLabel  [Label3D]  (shows "X / 20" above bin)
```

---

### pitcher.tscn

```
Pitcher  [RigidBody3D, pitcher.gd]
├── BodyMesh  [MeshInstance3D]  (CylinderMesh)
├── CollisionShape3D  (CylinderShape3D)
└── ContentsLabel  [Label3D]  (shows "Liquid: X/10 | Sugar: X | Ice: X")
```

---

### cup.tscn

```
Cup  [RigidBody3D, cup.gd]
├── BodyMesh  [MeshInstance3D]  (CylinderMesh, small)
├── CollisionShape3D
└── StateLabel  [Label3D]  (shows "EMPTY" or recipe summary when filled)
```

---

### supply_box.tscn  *(runtime-spawned by DeliverySystem)*

```
SupplyBox  [RigidBody3D, supply_box.gd]
├── BodyMesh  [MeshInstance3D]  (BoxMesh)
├── CollisionShape3D
└── ContentsLabel  [Label3D]  (e.g. "Lemons ×10")
```

---

### cash_pickup.tscn  *(runtime-spawned when customer pays)*

```
CashPickup  [Area3D, cash_pickup.gd]
├── BodyMesh  [MeshInstance3D]  (flat CylinderMesh, green tint)
├── CollisionShape3D
└── Label3D  (shows "$X.XX")
```

---

### customer.tscn  *(runtime-spawned by CustomerSpawner)*

```
Customer  [CharacterBody3D, customer.gd]
├── CollisionShape3D  (CapsuleShape3D)
├── Body  [MeshInstance3D]  (CapsuleMesh — randomised tint per instance)
├── Head  [MeshInstance3D]  (SphereMesh)
├── PatienceBar  [Node3D]
│   ├── BarBG  [MeshInstance3D]  (thin BoxMesh, dark)
│   └── BarFill  [MeshInstance3D]  (thin BoxMesh, green→red, script scales X)
└── EmojiAnchor  [Node3D]  (Y above head — emoji_display.gd instances Label3D here)
```

---

### UI scenes (2D, CanvasLayer children)

```
hud.tscn
└── Control  [hud.gd]
    ├── MoneyLabel
    ├── PopularityBar  [TextureProgressBar or ColorRect]
    ├── TemperatureLabel
    ├── HeldItemLabel
    └── InteractionHint  (bottom-centre, updates from player raycast)

phone_menu.tscn  (hidden by default, Tab toggles)
└── Panel  [phone_menu.gd]
    ├── Title  [Label]  ("📱 Phone")
    ├── IngredientRows  [VBoxContainer]
    │   ├── LemonRow   [HBoxContainer > Label + SpinBox + CostLabel]
    │   ├── WaterRow
    │   ├── SugarRow
    │   └── IceRow
    ├── PriceSlider  [HSlider]  (0.25 – 5.00)
    ├── PriceLabel
    ├── TotalCostLabel
    ├── OrderButton
    └── UpgradeShop  [VBoxContainer]
        ├── Tier1Button  ("Customer Relations — $25")
        └── Tier2Button  ("Precision Feedback — $75", disabled until Tier 1 owned)

debug_panel.tscn  (always visible, anchored right)
└── Panel  [debug_panel.gd]
    ├── Title  [Label]  ("⚙ DEV PANEL")
    ├── Cheats  [VBoxContainer]
    │   ├── AddMoneyButton
    │   ├── RefillBinsButton
    │   ├── EmptyPitcherButton
    │   └── ForceSpawnButton
    ├── TierOverride  [HBoxContainer]
    │   ├── Tier0Btn, Tier1Btn, Tier2Btn
    ├── TempSlider  [HSlider]  (10 – 40)
    ├── TempLabel
    └── StatsLabel  [Label]  (multiline, refreshed every 0.1 s in _process)
```

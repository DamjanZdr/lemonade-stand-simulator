extends Node
## Every tunable number lives here. Nothing is hardcoded elsewhere.

# === ECONOMY ===
const STARTING_MONEY: float = 150.0
const STARTING_POPULARITY: float = 300.0
const MAX_POPULARITY: float = 1000.0
const PRICE_FAIR_MAX: float = 2.00
const PRICE_TOO_EXPENSIVE: float = 2.75
const PRICE_MIN: float = 0.25
const PRICE_MAX: float = 5.00

# === CUSTOMER PATIENCE ===
const PATIENCE_BASE: float = 45.0

# === RECIPE — SHARPNESS (Lemon / liquid_volume ratio) ===
const IDEAL_LEMON_RATIO: float = 0.30 # 3 lemon scoops out of 10 total liquid

# === RECIPE — SUGAR (ratio to liquid volume) ===
const IDEAL_SUGAR_PER_LIQUID: float = 0.20 # 2 scoops out of 10 liquid = perfect

# === TEMPERATURE RANGE ===
const TEMP_MIN: float = 15.0
const TEMP_MAX: float = 45.0
const PERFECT_ICE_DEGREES_PER_SCOOP: float = 10.0
# Daily temperatures use 5 °C steps from 15 to 45. Ice is added in whole
# scoops: 1 scoop covers 0–10 °C, 2 covers 11–20 °C, ..., 5 covers 41–50 °C.
const DAY_TEMPERATURES: Array[float] = [15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0]
const DAY_TEMPERATURE_WEIGHTS: Array[float] = [1.0, 2.0, 4.0, 4.0, 4.0, 2.0, 1.0]
const TEMP_DEFAULT: float = 30.0


## Pick a daily temperature weighted toward the 25–35 °C range.
static func random_day_temperature() -> float:
	var total := 0.0
	for w in DAY_TEMPERATURE_WEIGHTS:
		total += w
	var roll := randf() * total
	for i in DAY_TEMPERATURES.size():
		roll -= DAY_TEMPERATURE_WEIGHTS[i]
		if roll <= 0.0:
			return DAY_TEMPERATURES[i]
	return DAY_TEMPERATURES[-1]


## Nearest legal daily temperature — used to migrate saves created while
## temperature was a continuous random roll.
static func snap_temperature(temp: float) -> float:
	var best: float = DAY_TEMPERATURES[0]
	var best_dist: float = INF
	for t in DAY_TEMPERATURES:
		var d: float = absf(t - temp)
		if d < best_dist:
			best_dist = d
			best = t
	return best


# === PITCHER ===
const PITCHER_MAX_LIQUID: float = 10.0
const PORTION_SIZE: float = 1.0

# === BINS ===
const BIN_MAX_CAPACITY: float = 10.0
const GRAB_AMOUNT: float = 1.0

# === CUPS ===
const CUP_STACK_MAX: int = 10
const CUP_STACK_START: int = 5

# === CONTAINERS (purchasable & placeable) ===
const CONTAINER_COST_FRUIT_BIN: float = 15.0
const CONTAINER_COST_SUGAR_BIN: float = 15.0
const CONTAINER_COST_ICE_BIN: float = 15.0
const CONTAINER_COST_CUP_STACK: float = 10.0
const CONTAINER_COST_PITCHER: float = 20.0
const CONTAINER_COST_PRESS: float = 30.0
const CONTAINER_COST_WATER_DISPENSER: float = 25.0
const CONTAINER_COST_WORKSTATION: float = 40.0

# === SUPPLY PRICES (per box) ===
# Baseline economics: an ideal lemon pitcher (3 lemons + 2 sugar + 4–9 ice
# + 1 water fill + 10 cups) costs ~$4.20–$4.95 and sells 10 cups at $1 = $10.
const SUPPLY_BOX_QTY: float = 10.0
const SUPPLY_COST_LEMON: float = 4.0
const SUPPLY_COST_RASPBERRY: float = 5.0
const SUPPLY_COST_STRAWBERRY: float = 5.0
const SUPPLY_COST_BLUEBERRY: float = 5.5
const SUPPLY_COST_PEACH: float = 6.0
const SUPPLY_COST_WATERMELON: float = 7.0
const SUPPLY_COST_SUGAR: float = 2.0
const SUPPLY_COST_ICE: float = 1.5
const SUPPLY_COST_CUPS: float = 1.0


## Price of one full box of the given supply id.
static func supply_box_cost(item_id: String) -> float:
	match item_id:
		"lemon":
			return SUPPLY_COST_LEMON
		"raspberry":
			return SUPPLY_COST_RASPBERRY
		"strawberry":
			return SUPPLY_COST_STRAWBERRY
		"blueberry":
			return SUPPLY_COST_BLUEBERRY
		"peach":
			return SUPPLY_COST_PEACH
		"watermelon":
			return SUPPLY_COST_WATERMELON
		"sugar":
			return SUPPLY_COST_SUGAR
		"ice":
			return SUPPLY_COST_ICE
		"cups":
			return SUPPLY_COST_CUPS
		"water":
			return WATER_COST
	return 0.0


## Units per box for the given supply id (water sells in fills, not scoops).
static func supply_box_qty(item_id: String) -> float:
	if item_id == "water":
		return WATER_BOX_FILLINGS
	return SUPPLY_BOX_QTY


## Cost of a single unit (scoop/cup/fill) of the given supply id.
static func supply_unit_cost(item_id: String) -> float:
	return supply_box_cost(item_id) / supply_box_qty(item_id)


# === DELIVERY ===
# Phone orders cost the goods at their normal per-unit rate plus a flat
# delivery fee — never cheaper than buying at the morning shop.
const DELIVERY_FLAT_FEE: float = 2.0
const DELIVERY_QUANTITY: float = 10.0
const DELIVERY_DROP_HEIGHT: float = 4.0

# === TRASH ===
# An empty box refunds less than the cheapest box so box-cycling can
# never be profitable.
const TRASH_REFUND_EMPTY_BOX: float = 0.25
# Fraction of the remaining contents' value refunded for a non-empty
# supply box, and NPC/world litter value.
const CONTENTS_REFUND_RATIO: float = 0.5
const LOOSE_TRASH_VALUE: float = 0.10

# === WATER DISPENSER ===
const WATER_COST: float = 5.0
const WATER_BOX_FILLINGS: float = 5.0

# === CUSTOMERS ===
const SPAWN_RATE_MIN: float = 5.0
const SPAWN_RATE_MAX: float = 30.0
const QUEUE_MAX: int = 50
const CUSTOMER_WALK_SPEED: float = 3.0
const CUSTOMER_SPAWN_Z: float = -15.0 # debug-spawn only; behind the queue line
const CUSTOMER_DESPAWN_Z: float = -27.0

# === POPULARITY ===
# Customer walked away / was priced out / got wrong order.
const POPULARITY_LOSS_NO_SERVICE: float = 5.0
# Served a water-only cup (scam).
const POPULARITY_LOSS_SCAM: float = 10.0
# Per-axis popularity when a customer complains. Index = units away from ideal.
const POPULARITY_FRUIT_SCORES: Array[float] = [4.0, 2.0, 0.0, -2.0, -4.0]
const POPULARITY_SUGAR_SCORES: Array[float] = [3.0, 1.0, 0.0, -1.0, -3.0]
const POPULARITY_ICE_SCORES: Array[float] = [3.0, 1.0, 0.0, -1.0, -3.0]
const POPULARITY_HIT_PENALTY: float = 1.0
const POPULARITY_TRASH_DISPOSED_BONUS: float = 1.0
const POPULARITY_TRASH_LEFT_PENALTY: float = 1.0
const REGULAR_TRASH_TYPES: Array[String] = ["apple", "banana", "can", "cigarettes", "cup"]

# === UPGRADES ===
const UPGRADE_TIER1_COST: float = 25.0
const UPGRADE_TIER2_COST: float = 75.0


static func spawn_interval_for_popularity(popularity: float) -> float:
	return lerpf(
		SPAWN_RATE_MAX,
		SPAWN_RATE_MIN,
		clampf(popularity, 0.0, MAX_POPULARITY) / MAX_POPULARITY,
	)


# === PEDESTRIANS ===
## Chance a pedestrian decides to join the queue when passing a convertable waypoint.
## Scales linearly with popularity: 5 % at 0 %, 100 % at 100 %.
const PEDESTRIAN_CONVERT_MIN: float = 0.05
const PEDESTRIAN_CONVERT_MAX: float = 1.0


static func pedestrian_convert_chance(popularity: float) -> float:
	return lerpf(
		PEDESTRIAN_CONVERT_MIN,
		PEDESTRIAN_CONVERT_MAX,
		clampf(popularity, 0.0, MAX_POPULARITY) / MAX_POPULARITY,
	)


static func is_regular_trash_type(trash_type: String) -> bool:
	return trash_type in REGULAR_TRASH_TYPES


static func adjust_popularity_for_stand(stand_name: String, delta: float) -> void:
	if not WorldSync.is_host():
		return
	if stand_name != "":
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.current_scene != null:
			for s in tree.current_scene.find_children("*", "StandUnit", true, false):
				if s.name == stand_name and s.has_method("set_popularity"):
					s.set_popularity(s.popularity + delta)
					# Sync the new value so all peers see the change (free samples,
					# trash hits, etc. aren't followed by a StandUnit push_state).
					if s.has_method("push_state"):
						s.push_state()
					return
	GameState.set_popularity(GameState.popularity + delta)

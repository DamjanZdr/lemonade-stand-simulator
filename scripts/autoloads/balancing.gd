extends Node
## Every tunable number lives here. Nothing is hardcoded elsewhere.

# === ECONOMY ===
const STARTING_MONEY: float = 50.0
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
const TEMP_MIN: float = 10.0
const TEMP_MAX: float = 40.0

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

# === DELIVERY ===
const DELIVERY_COST_PER_UNIT: float = 0.20
const DELIVERY_QUANTITY: float = 10.0
const DELIVERY_DROP_HEIGHT: float = 4.0

# === WATER DISPENSER ===
const WATER_COST: float = 5.0
const WATER_BOX_FILLINGS: float = 5.0

# === CUSTOMERS ===
const SPAWN_RATE_MIN: float = 5.0
const SPAWN_RATE_MAX: float = 30.0
const QUEUE_MAX: int = 6
const CUSTOMER_WALK_SPEED: float = 3.0
const CUSTOMER_SPAWN_Z: float = -15.0 # debug-spawn only; behind the queue line
const CUSTOMER_DESPAWN_Z: float = -27.0

# === POPULARITY ===
const POPULARITY_GAIN_HAPPY: float = 0.05
const POPULARITY_LOSS_BAD: float = 0.03
const POPULARITY_LOSS_EXPENSIVE: float = 0.02
const POPULARITY_LOSS_TIMEOUT: float = 0.04

# === UPGRADES ===
const UPGRADE_TIER1_COST: float = 25.0
const UPGRADE_TIER2_COST: float = 75.0


static func spawn_interval_for_popularity(popularity: float) -> float:
	return lerpf(SPAWN_RATE_MAX, SPAWN_RATE_MIN, popularity)

# === PEDESTRIANS ===
## Chance a pedestrian decides to join the queue when passing a convertable waypoint.
## Scales linearly with popularity: 5 % at 0 %, 65 % at 100 %.
const PEDESTRIAN_CONVERT_MIN: float = 0.05
const PEDESTRIAN_CONVERT_MAX: float = 0.65


static func pedestrian_convert_chance(popularity: float) -> float:
	return lerpf(PEDESTRIAN_CONVERT_MIN, PEDESTRIAN_CONVERT_MAX, popularity)

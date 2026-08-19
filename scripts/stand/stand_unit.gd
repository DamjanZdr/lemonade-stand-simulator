class_name StandUnit
extends Node3D
## A single, self-contained lemonade stand: counter, price board, delivery
## grid/marker, thermometer, water dispenser, and customer queue markers —
## AND its own independent economy (money, prices, recipes, popularity,
## upgrades, inventory). Two StandUnit instances can run side-by-side with
## fully separate economies; nothing here is shared between stands.
##
## Signals below are LOCAL to this stand (not the global EventBus). Code
## that cares about "my stand" connects directly to that stand's StandUnit
## signals — there is no filtering needed, because you simply never connect
## to another stand's signals.
##
## Cross-stand interactions (e.g. stealing a cup from a rival stand) are
## handled by code that holds references to both StandUnit instances and
## calls methods directly on each (e.g. `other_stand.remove_cup()` then
## `my_stand.add_cup()`), not through these per-stand signals.
##
## NOTE: This is Stage A of the Phase 2 migration. GameState/Inventory/
## UpgradeManager/DeliverySystem still exist as global autoloads and are
## still the actual source of truth used by the running game. This class
## currently only mirrors their API additively — nothing yet reads from or
## writes to it. Migrating each consumer (HUD, price board, save system,
## etc.) to use a specific StandUnit instead of the globals is future work,
## tracked in the plan file.

const FRUIT_TYPES: Array[String] = ["lemon", "strawberry", "blueberry", "peach", "watermelon"]

signal money_changed(new_amount: float)
signal price_changed(fruit_type: String, new_price: float)
signal recipe_changed(fruit_type: String, recipe: Dictionary)
signal popularity_changed(new_rating: float)
signal feedback_tier_changed(new_tier: int)

## Which peer (network) or debug slot controls this stand. -1 = uncontrolled
## (AI/empty). Set by whatever assigns players to stands (lobby, debug
## Tab-switch in Stage A, etc.) — this class doesn't decide that itself.
var controller_id: int = -1

## TEMPORARY (Stage A migration): true for exactly one StandUnit — the
## original stand that existed before multi-stand support — so it stays
## mirrored to/from the legacy global GameState/EventBus for systems that
## haven't been migrated yet (upgrades UI, shop/phone purchases, debug
## panel, save/load). A second (or third, ...) StandUnit must NOT mirror
## the legacy globals — it needs to be a fully independent economy from
## the start, or its money/prices would leak into/from the primary stand's.
## Set to true only on the primary StandUnit's node in the scene.
@export var is_legacy_primary: bool = false

var money: float = 0.0
var popularity: float = 0.1
var feedback_tier: int = 0
var prices: Dictionary = { }
var recipes: Dictionary = { }

## Mirrors UpgradeManager.purchased_nodes (node_name -> true) for this
## stand. The upgrade TREE STRUCTURE (tree_nodes, connections, positions,
## definitions) is legitimately shared/global — same tree exists for every
## stand — only which nodes are purchased is per-stand data. See the
## TEMPORARY bridge note in _ready() for how this is kept in sync for now.
var purchased_upgrade_nodes: Dictionary = { }

var customers_served_happy: int = 0
var customers_lost: int = 0
var total_customers_served: int = 0
var total_cups_sold: int = 0
var total_money_earned: float = 0.0
var total_money_spent: float = 0.0
var highest_purchase: float = 0.0
var highest_money: float = 0.0

@onready var delivery_grid: DeliveryGrid = $DeliveryGrid as DeliveryGrid
@onready var delivery_marker: Marker3D = $DeliveryMarker
@onready var queue_marker_active: Marker3D = $QueueMarkerActive
@onready var queue_marker_1: Marker3D = $QueueMarker1
@onready var queue_marker_2: Marker3D = $QueueMarker2
@onready var price_board: Node3D = $PriceBoard
@onready var thermometer: Node3D = $Thermometer
@onready var water_dispenser: Node3D = $WaterDispenser
@onready var stand_mesh: Node3D = $Stand


## Networked (Stage B): replicates this stand's economy state from
## whichever peer has authority over it (the host, in our host-authoritative
## design — see the plan doc) out to every other connected peer.
var _sync: MultiplayerSynchronizer = null


func _setup_replication() -> void:
	_sync = MultiplayerSynchronizer.new()
	_sync.name = "MultiplayerSynchronizer"
	# Set authority BEFORE adding to tree and before config, so the
	# synchronizer knows from the very first frame it is NOT the sender
	# on client peers (host-authoritative: peer 1 always owns stand state).
	_sync.set_multiplayer_authority(1)
	add_child(_sync)
	var config := SceneReplicationConfig.new()
	for prop in [
		"money",
		"popularity",
		"feedback_tier",
		"prices",
		"recipes",
		"purchased_upgrade_nodes",
		"customers_served_happy",
		"customers_lost",
		"total_customers_served",
		"total_cups_sold",
		"total_money_earned",
		"total_money_spent",
		"highest_purchase",
		"highest_money",
	]:
		config.add_property(NodePath("../:" + prop))
	_sync.replication_config = config
	# Host-authoritative: this node (and therefore its synchronizer) is
	# always owned by peer 1, regardless of which player is "assigned" to
	# play this stand (see controller_id) — the host's simulation is the
	# single source of truth for every stand's data.
	set_multiplayer_authority(1)
	# Diagnostic: verify the synchronizer can actually see our properties.
	# The "..:money" errors come from the synchronizer being unable to
	# resolve the parent's property — this print helps confirm whether
	# the parent reference and property are valid at setup time.
	if _sync.get_parent() == self:
		var money_val = _sync.get_parent().get("money")
		print(
			"[StandUnit:%s] Sync setup OK — parent has money=%s, authority=%d, is_auth=%s"
			% [
				name,
				str(money_val),
				_sync.get_multiplayer_authority(),
				_sync.is_multiplayer_authority(),
			]
		)
	else:
		push_warning("[StandUnit:%s] Sync parent mismatch!" % name)


func _ready() -> void:
	_setup_replication()
	_init_default_prices()
	_init_default_recipes()
	highest_money = money

	if not is_legacy_primary:
		# Clean, fully independent stand — no legacy bridge, no GameState
		# involvement at all. Starts from its own defaults (set above).
		return

	# Sync the initial value — GameState.money is already correctly set by
	# the time this runs (starting money or loaded save applied during its
	# own _ready(), which as an autoload always runs before this node's),
	# but it doesn't emit money_changed for that initial assignment, so we
	# read it directly here rather than waiting for the first future change.
	money = GameState.money
	highest_money = maxf(highest_money, money)

	# TEMPORARY migration bridge (primary stand only): many systems still
	# read/write GameState.money directly (upgrades, shop/phone purchases,
	# debug panel, save/load, day summary) rather than going through
	# StandUnit yet. All of those paths ultimately re-emit the global
	# EventBus.money_changed signal with the new total, so mirror that
	# value here rather than GameState.money's actual source of truth.
	# Once each of those systems is migrated to operate on a specific
	# StandUnit directly (tracked in the plan), this bridge — and
	# GameState's money field entirely — should be removed.
	EventBus.money_changed.connect(_on_global_money_changed_bridge)

	# Same reasoning for prices: customer.gd still charges based on
	# GameState.get_price() at checkout, and morning_hub/debug_panel/
	# save_manager still read/write GameState.prices directly. Mirror
	# both directions until those are migrated too.
	for ft in FRUIT_TYPES:
		prices[ft] = GameState.get_price(ft)
	EventBus.price_changed.connect(_on_global_price_changed_bridge)

	# Popularity: same bridging approach. NOTE: on_customer_served() below is
	# NOT wired to EventBus.customer_served here on purpose — GameState's own
	# listener remains the sole place popularity/stats are actually computed
	# for now (avoiding double-counting), and we just mirror the resulting
	# value. Once there are multiple stands, customer_served needs to route
	# to the correct stand's on_customer_served() directly instead — that's
	# deferred until the second stand exists (tracked in the plan).
	popularity = GameState.popularity
	EventBus.popularity_changed.connect(_on_global_popularity_changed_bridge)

	# Upgrades: UpgradeManager.purchased_nodes remains the actual source of
	# truth for now (the upgrade tree UI reads/writes it directly in many
	# places). Mirror the whole dict here so future per-stand consumers
	# (e.g. is_fruit_unlocked checks scoped to a specific stand) already
	# have something to read. Once a second stand exists and purchases
	# genuinely need to diverge per stand, UpgradeManager's purchase logic
	# itself should be parameterized by stand instead of this mirror.
	purchased_upgrade_nodes = UpgradeManager.purchased_nodes.duplicate()
	EventBus.upgrade_purchased.connect(_on_global_upgrade_purchased_bridge)


func _on_global_money_changed_bridge(new_amount: float) -> void:
	if is_equal_approx(new_amount, money):
		return
	money = new_amount
	if money > highest_money:
		highest_money = money
	money_changed.emit(money)


func _on_global_price_changed_bridge(fruit_type: String, new_price: float) -> void:
	if is_equal_approx(prices.get(fruit_type, -1.0), new_price):
		return
	prices[fruit_type] = new_price
	price_changed.emit(fruit_type, new_price)


func _on_global_popularity_changed_bridge(new_rating: float) -> void:
	if is_equal_approx(new_rating, popularity):
		return
	popularity = new_rating
	popularity_changed.emit(popularity)


func _on_global_upgrade_purchased_bridge(_upgrade_id: int, _cost: float) -> void:
	purchased_upgrade_nodes = UpgradeManager.purchased_nodes.duplicate()


func _init_default_prices() -> void:
	for ft in FRUIT_TYPES:
		var res := load("res://resources/data/" + ft + ".tres") as IngredientData
		prices[ft] = res.default_price if res else 1.50


func _init_default_recipes() -> void:
	for ft in FRUIT_TYPES:
		recipes[ft] = _default_recipe_for(ft)


func _default_recipe_for(fruit_type: String) -> Dictionary:
	var res := load("res://resources/data/" + fruit_type + ".tres") as IngredientData
	if res:
		return { "fruit_count": float(res.ideal_fruit_count), "sugar": res.ideal_sugar }
	return { "fruit_count": 3.0, "sugar": 2.0 }

## --- Economy API (mirrors GameState's public methods) ---


func add_money(amount: float) -> void:
	money += amount
	total_money_earned += amount
	if money > highest_money:
		highest_money = money
	money_changed.emit(money)


func spend_money(amount: float) -> bool:
	if money < amount:
		return false
	money -= amount
	total_money_spent += amount
	if amount > highest_purchase:
		highest_purchase = amount
	money_changed.emit(money)
	return true


func set_popularity(value: float) -> void:
	popularity = clampf(value, 0.0, 1.0)
	popularity_changed.emit(popularity)


func get_price(fruit_type: String) -> float:
	return prices.get(fruit_type, 1.50)


func set_price(fruit_type: String, new_price: float) -> void:
	prices[fruit_type] = new_price
	price_changed.emit(fruit_type, new_price)
	if not is_legacy_primary:
		return
	# TEMPORARY (primary stand only): also write through to GameState so
	# other not-yet-migrated systems (morning_hub/debug_panel/save_manager)
	# see the new price. A non-primary stand's prices are fully local and
	# must never touch GameState. Remove this once those are migrated too.
	GameState.prices[fruit_type] = new_price
	EventBus.price_changed.emit(fruit_type, new_price)


func get_recipe(fruit_type: String) -> Dictionary:
	return recipes.get(fruit_type, _default_recipe_for(fruit_type))

## --- Networked mutation requests (Stage B) ---
## Call these instead of the direct methods above so the change is routed
## to whichever peer has authority (the host, in our host-authoritative
## design) via RPC, applied there, and the resulting property change
## replicated back out to every peer via the MultiplayerSynchronizer.
## In solo/offline play (no real network peer), rpc_id(1, ...) targeting
## yourself just runs locally immediately — the same call site works
## correctly either way, no branching needed at the call site.


func request_add_money(amount: float) -> void:
	_rpc_add_money.rpc_id(1, amount)


@rpc("any_peer", "call_local", "reliable")
func _rpc_add_money(amount: float) -> void:
	if not is_multiplayer_authority():
		return
	add_money(amount)


func request_set_price(fruit_type: String, new_price: float) -> void:
	_rpc_set_price.rpc_id(1, fruit_type, new_price)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_price(fruit_type: String, new_price: float) -> void:
	if not is_multiplayer_authority():
		return
	set_price(fruit_type, new_price)


func request_set_recipe(fruit_type: String, recipe: Dictionary) -> void:
	_rpc_set_recipe.rpc_id(1, fruit_type, recipe)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_recipe(fruit_type: String, recipe: Dictionary) -> void:
	if not is_multiplayer_authority():
		return
	set_recipe(fruit_type, recipe)


func request_customer_served(outcome: String) -> void:
	_rpc_on_customer_served.rpc_id(1, outcome)


@rpc("any_peer", "call_local", "reliable")
func _rpc_on_customer_served(outcome: String) -> void:
	if not is_multiplayer_authority():
		return
	on_customer_served(outcome)


func set_recipe(fruit_type: String, recipe: Dictionary) -> void:
	recipes[fruit_type] = recipe.duplicate()
	recipe_changed.emit(fruit_type, recipes[fruit_type])


func set_feedback_tier(tier: int) -> void:
	feedback_tier = clampi(tier, 0, 2)
	feedback_tier_changed.emit(feedback_tier)


func on_customer_served(outcome: String) -> void:
	total_customers_served += 1
	match outcome:
		"happy":
			customers_served_happy += 1
			total_cups_sold += 1
			set_popularity(popularity + Balancing.POPULARITY_GAIN_HAPPY)
		"timeout":
			customers_lost += 1
			set_popularity(popularity - Balancing.POPULARITY_LOSS_TIMEOUT)
		"too_expensive", "wrong_order":
			customers_lost += 1
			set_popularity(popularity - Balancing.POPULARITY_LOSS_EXPENSIVE)
		_:
			customers_lost += 1
			set_popularity(popularity - Balancing.POPULARITY_LOSS_BAD)


func reset_daily_stats() -> void:
	customers_served_happy = 0
	customers_lost = 0


## --- Scoped inventory: totals of items physically placed within THIS
## stand's subtree only (bins, pitcher, cup stacks, unopened supply boxes,
## water dispenser), instead of scanning the entire scene tree. ---
func get_inventory() -> Dictionary:
	var result := {
		"lemon": 0,
		"strawberry": 0,
		"blueberry": 0,
		"peach": 0,
		"watermelon": 0,
		"sugar": 0.0,
		"ice": 0.0,
		"water": 0.0,
		"cups": 0,
	}
	for node in get_tree().get_nodes_in_group("container"):
		if not is_ancestor_of(node):
			continue
		if node is FruitBin:
			for ftype in node.fruit_amounts:
				result[ftype] = result.get(ftype, 0) + node.fruit_amounts[ftype]
		elif node is IngredientBin:
			var itype: String = node.ingredient_type
			result[itype] = result.get(itype, 0.0) + node.current_amount
		elif node is CupStack:
			result["cups"] = result.get("cups", 0) + node.current_count
		elif node is Pitcher:
			if node.fruit_type != "" and node.fruit_count > 0.0:
				result[node.fruit_type] = result.get(node.fruit_type, 0) + node.fruit_count
			result["water"] = result.get("water", 0.0) + node.water
			result["sugar"] = result.get("sugar", 0.0) + node.sugar
			result["ice"] = result.get("ice", 0.0) + node.ice
	for node in get_tree().get_nodes_in_group("supply_box"):
		if not is_ancestor_of(node):
			continue
		var box := node as SupplyBox
		if box == null or box.is_equipment:
			continue
		var btype: String = box.ingredient_type
		result[btype] = result.get(btype, 0.0) + box.quantity
	if water_dispenser and "water_fillings" in water_dispenser:
		result["water"] = result.get("water", 0.0) + water_dispenser.water_fillings
	return result


## Returns the customer queue spots (active spot + up to 299 waiting spots),
## matching the logic previously inlined in main.gd.
func get_queue_spots() -> Array[Vector3]:
	var active_pos := Vector3(0.0, 0.0, -1.0)
	var start := Vector3(0.0, 0.0, -2.0)
	var step := Vector3(0.0, 0.0, -1.0)
	if queue_marker_active:
		active_pos = queue_marker_active.global_position
	if queue_marker_1:
		start = queue_marker_1.global_position
		if queue_marker_2:
			step = queue_marker_2.global_position - queue_marker_1.global_position
	var spots: Array[Vector3] = []
	spots.append(active_pos)
	for i in range(299):
		spots.append(start + step * float(i))
	return spots


func get_queue_step() -> Vector3:
	if queue_marker_1 and queue_marker_2:
		return queue_marker_2.global_position - queue_marker_1.global_position
	return Vector3(0.0, 0.0, -1.0)


func get_delivery_grid() -> DeliveryGrid:
	return delivery_grid


func get_delivery_marker_position() -> Vector3:
	if delivery_marker:
		return delivery_marker.global_position
	return global_position


## Whether the given player is allowed to serve/interact with this stand's
## customers. In solo/offline play (no other connected peer) this is
## always true — there's no "your customers vs their customers" concept
## with only one person playing, and locking it down would break being
## able to test every stand locally. In real multiplayer (at least one
## other peer connected), a player may only interact with the stand they
## were actually assigned to.
func can_be_served_by(player: Node) -> bool:
	if multiplayer.get_peers().is_empty():
		return true
	if player == null or not ("assigned_stand" in player):
		return false
	return player.assigned_stand == self

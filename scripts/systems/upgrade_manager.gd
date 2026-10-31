extends Node

## Bar-based progression. Each branch tracks ONE cumulative counter stored
## per stand in stand.onboarding_progress["progress"] — tiers unlock
## automatically when the counter crosses a threshold. Play is the cost;
## money stays for equipment and supplies. See docs/progression-bars.md.

signal progress_changed(stand: StandUnit)
signal tier_reached(stand: StandUnit, branch_id: String, level: int)

const FRUIT_ORDER: Array[String] = [
	"lemon",
	"raspberry",
	"strawberry",
	"blueberry",
	"peach",
	"watermelon",
]
## Perfect-recipe serves of the PREVIOUS fruit needed to unlock each tier.
const FRUIT_THRESHOLDS: Array[float] = [8.0, 20.0, 35.0, 55.0, 80.0]

## kind "" = plain counter bar; "fruit" = per-fruit perfect-serve chain;
## "machines" = thresholds grant shop unlocks (lemonader, fruitomatic).
const BRANCHES: Array[Dictionary] = [
	{
		"id": "fruit",
		"color": Color(0.90, 0.78, 0.22),
		"icon": "res://assets/textures/ui/upgrades/fruitunlock.png",
		"action": "Serve perfect-recipe cups",
		"rewards": [
			"Unlock Raspberry",
			"Unlock Strawberry",
			"Unlock Blueberry",
			"Unlock Peach",
			"Unlock Watermelon",
		],
		"name": "Fruit",
		"description": "Perfect a fruit's recipe to unlock the next fruit.",
		"kind": "fruit",
	},
	{
		"id": "technology",
		"color": Color(0.56, 0.45, 0.90),
		"icon": "res://assets/textures/ui/upgrades/technology.png",
		"action": "Serve cups",
		"rewards": ["Squeeze-E-Z in shop", "Fruit-O-Matic in shop"],
		"name": "Technology",
		"description": "Serve cups to unlock machines in the shop.",
		"counter": "cups_served",
		"thresholds": [50.0, 200.0],
		"kind": "machines",
	},
	{
		"id": "squeeze_speed",
		"color": Color(0.93, 0.47, 0.15),
		"icon": "res://assets/textures/ui/upgrades/pressspeed.png",
		"action": "Press fruit by hand",
		"rewards": [
			"+20% juice speed",
			"+40% juice speed",
			"+60% juice speed",
			"+80% juice speed",
			"+100% juice speed",
		],
		"name": "Squeeze Speed",
		"description": "Juice faster — hand press and machines.",
		"counter": "hand_presses",
		"thresholds": [30.0, 90.0, 180.0, 320.0, 500.0],
		"effect": "press_speed",
		"per": 0.2,
	},
	{
		"id": "nimbleness",
		"color": Color(0.40, 0.72, 0.28),
		"icon": "res://assets/textures/ui/upgrades/nimbleness.png",
		"action": "Deposit from supply boxes",
		"rewards": [
			"+20% deposit speed",
			"+40% deposit speed",
			"+60% deposit speed",
			"+80% deposit speed",
			"+100% deposit speed",
		],
		"name": "Nimbleness",
		"description": "Place ingredients faster.",
		"counter": "box_deposits",
		"thresholds": [25.0, 70.0, 150.0, 260.0, 420.0],
		"effect": "nimbleness",
		"per": 0.2,
	},
	{
		"id": "sunroof",
		"color": Color(0.93, 0.62, 0.33),
		"icon": "res://assets/textures/ui/upgrades/patience.png",
		"action": "Lose customers to impatience",
		"rewards": [
			"+20% patience",
			"+40% patience",
			"+60% patience",
			"+80% patience",
			"+100% patience",
		],
		"name": "Sunroof",
		"description": "Every lost customer teaches patience — yours and theirs.",
		"counter": "customers_lost",
		"thresholds": [5.0, 15.0, 35.0, 65.0, 100.0],
		"effect": "sunroof",
		"per": 0.2,
	},
	{
		"id": "water_dispenser",
		"color": Color(0.25, 0.65, 0.88),
		"icon": "res://assets/textures/ui/upgrades/waterdispenser.png",
		"action": "Fill pitchers with water",
		"rewards": [
			"+20% fill speed",
			"+40% fill speed",
			"+60% fill speed",
			"+80% fill speed",
			"+100% fill speed",
		],
		"name": "Water Dispenser",
		"description": "Fill water faster.",
		"counter": "water_fills",
		"thresholds": [10.0, 30.0, 65.0, 115.0, 180.0],
		"effect": "water_dispenser",
		"per": 0.2,
	},
	{
		"id": "trash_rebate",
		"color": Color(0.28, 0.75, 0.60),
		"icon": "res://assets/textures/ui/upgrades/trashrebate.png",
		"action": "Throw away street litter",
		"rewards": [
			"+10% litter refund",
			"+20% litter refund",
			"+30% litter refund",
			"+40% litter refund",
			"+50% litter refund",
		],
		"name": "Trash Rebate",
		"description": "Street litter refunds pay more.",
		"counter": "litter_trashed",
		"thresholds": [15.0, 40.0, 80.0, 140.0, 220.0],
		"effect": "trash_rebate",
		"per": 0.1,
	},
	{
		"id": "negotiation",
		"color": Color(0.88, 0.35, 0.52),
		"icon": "res://assets/textures/ui/upgrades/negotiation.png",
		"action": "Spend money",
		"rewards": ["-10% prices", "-20% prices", "-30% prices", "-40% prices", "-50% prices"],
		"name": "Negotiation",
		"description": "Spending teaches haggling — lower prices.",
		"counter": "supply_spend",
		"unit": "$",
		"thresholds": [50.0, 130.0, 250.0, 420.0, 650.0],
		"effect": "negotiation",
		"per": 0.1,
	},
]

## Shop item ids gated behind technology tiers (tier index + 1).
const MACHINE_ITEMS: Array[String] = ["lemonader", "fruitomatic"]

var _active_stand: String = ""


## Which stand's bars the local UI is showing.
func set_active_stand(stand_name: String) -> void:
	_active_stand = stand_name


func flush_active_stand() -> void:
	_active_stand = ""


func reset() -> void:
	_active_stand = ""


## Find a stand by name; falls back to active stand, then the primary stand.
func _find_stand(stand_name: String = "") -> StandUnit:
	var target := stand_name if stand_name != "" else _active_stand
	var fallback: StandUnit = null
	for node in get_tree().get_nodes_in_group("stand"):
		var s := node as StandUnit
		if s == null:
			continue
		if fallback == null or s.is_legacy_primary:
			fallback = s
		if target != "" and s.name == target:
			return s
	return fallback


## Event → counter. Called by OnboardingManager._apply_report, which is
## host-routed, so counters only ever mutate on the host.
func record_event(stand: StandUnit, event_name: String, _data: Dictionary) -> void:
	if stand == null:
		return
	match event_name:
		"claim_upgrade":
			try_claim(str(_data.get("branch", "")), stand)
			return
		"debug_fill_branch":
			debug_fill_to_next(str(_data.get("branch", "")), stand)
			return
		"pitcher_prepared", "pitcher_made":
			stand.record_progress("pitchers_made")
		"customer_served":
			stand.record_progress("cups_served")
		"fruit_pressed":
			stand.record_progress("hand_presses")
		"supply_deposited":
			stand.record_progress("box_deposits")
		"sample_served":
			stand.record_progress("samples_given")
			# A free cup is still a cup — feeds the Technology bar too.
			stand.record_progress("cups_served")
		"customer_lost":
			stand.record_progress("customers_lost")
		"pitcher_water_filled":
			stand.record_progress("water_fills")
		"litter_trashed":
			stand.record_progress("litter_trashed")
		_:
			return
	progress_changed.emit(stand)


func get_counter(key: String, stand: StandUnit) -> float:
	return stand.get_progress(key) if stand != null else 0.0


func get_perfect_serves(fruit: String, stand: StandUnit) -> int:
	return stand.get_perfect_serves(fruit) if stand != null else 0


func _branch(branch_id: String) -> Dictionary:
	for b in BRANCHES:
		if b.get("id") == branch_id:
			return b
	return { }


func get_branches() -> Array[Dictionary]:
	return BRANCHES


## How many tiers the player has CLAIMED on this branch — the counter
## reaching a threshold only makes the badge claimable; effects and
## unlocks apply once the tier is claimed from the Upgrades page.
func get_branch_level(branch_id: String, stand: StandUnit) -> int:
	if stand == null or _branch(branch_id).is_empty():
		return 0
	return stand.get_claimed(branch_id)


## The raw counter the bar measures — cumulative perfect serves across
## ALL fruits (so each unlock doesn't zero the bar), or the branch's
## plain progress counter.
func get_branch_value(branch_id: String, stand: StandUnit) -> float:
	var b := _branch(branch_id)
	if b.is_empty() or stand == null:
		return 0.0
	if b.get("kind") == "fruit":
		var total := 0.0
		for ft in FRUIT_ORDER:
			total += float(get_perfect_serves(ft, stand))
		return total
	return get_counter(str(b.get("counter", "")), stand)


## Click-to-claim: the next tier unlocks only when the counter has
## reached its threshold AND the player claims it from the Upgrades page.
func try_claim(branch_id: String, stand: StandUnit) -> bool:
	var b := _branch(branch_id)
	if b.is_empty() or stand == null:
		return false
	var thresholds: Array = b.get("thresholds", FRUIT_THRESHOLDS)
	var level := get_branch_level(branch_id, stand)
	if level >= thresholds.size():
		return false
	if get_branch_value(branch_id, stand) < float(thresholds[level]):
		return false
	stand.claim_progress_tier(branch_id, level + 1)
	progress_changed.emit(stand)
	return true


## Display data for one bar: current fill, next threshold, max, level, and
## (for the fruit branch) which fruit the bar is currently measuring.
func get_branch_progress(branch_id: String, stand: StandUnit) -> Dictionary:
	var b := _branch(branch_id)
	if b.is_empty():
		return { }
	var level := get_branch_level(branch_id, stand)
	var thresholds: Array = b.get("thresholds", FRUIT_THRESHOLDS)
	var out := {
		"level": level,
		"max_level": thresholds.size(),
		"max_value": float(thresholds[thresholds.size() - 1]),
		"next_threshold": float(thresholds[level]) if level < thresholds.size() else -1.0,
	}
	if b.get("kind") == "fruit":
		# The bar measures perfect serves of the fruit that gates the NEXT tier.
		var gate_idx := mini(level, FRUIT_ORDER.size() - 2)
		out["target_fruit"] = FRUIT_ORDER[gate_idx]
	out["value"] = get_branch_value(branch_id, stand)
	out["claimable"] = (level < thresholds.size() and out["value"] >= float(thresholds[level]))
	return out


## Dev tool (F1 panel, debug builds): bumps the branch's counter up to
## the first threshold above its current value — exactly one claimable
## tier per click. Host-gated like every other mutation.
func debug_fill_to_next(branch_id: String, stand: StandUnit) -> void:
	if not (OS.is_debug_build() or GameState.DEV_TOOLS) or not WorldSync.is_host() or stand == null:
		return
	var b := _branch(branch_id)
	if b.is_empty():
		return
	var thresholds: Array = b.get("thresholds", FRUIT_THRESHOLDS)
	var value := get_branch_value(branch_id, stand)
	# Start at the CLAIMED level, not index 0 — the fruit bar's counter
	# resets per fruit, so scanning from 0 would only ever fill the
	# first threshold and never make later tiers claimable.
	var k := get_branch_level(branch_id, stand)
	while k < thresholds.size() and value >= float(thresholds[k]):
		k += 1
	if k >= thresholds.size():
		return
	var target := float(thresholds[k])
	if b.get("kind") == "fruit":
		var gate_idx := mini(get_branch_level(branch_id, stand), FRUIT_ORDER.size() - 2)
		var fruit: String = FRUIT_ORDER[gate_idx]
		for i in range(int(target - value)):
			stand.record_perfect_serve(fruit)
	else:
		stand.record_progress(str(b.get("counter", "")), target - value)
	progress_changed.emit(stand)


func is_fruit_unlocked_for_stand(fruit: String, stand: StandUnit) -> bool:
	var idx := FRUIT_ORDER.find(fruit)
	if idx <= 0:
		return fruit == "lemon"
	return get_branch_level("fruit", stand) >= idx


func is_fruit_unlocked(fruit: String) -> bool:
	return is_fruit_unlocked_for_stand(fruit, _find_stand())


func get_unlocked_fruits() -> Array[String]:
	var result: Array[String] = []
	var stand := _find_stand()
	for ft in GameState.FRUIT_TYPES:
		if is_fruit_unlocked_for_stand(ft, stand):
			result.append(ft)
	return result


## Shop-item gating: machines need technology tiers; everything else open.
func is_item_unlocked(item_id: String, stand: StandUnit) -> bool:
	var idx := MACHINE_ITEMS.find(item_id)
	if idx < 0:
		return true
	return get_branch_level("technology", stand) > idx


## Sum of a numeric effect for a stand: branch level × per-level effect.
func get_effect_total_for_stand(upgrade_id: String, stand_name: String) -> float:
	var stand := _find_stand(stand_name)
	if stand == null:
		return 0.0
	var total := 0.0
	for b in BRANCHES:
		if b.get("effect", "") == upgrade_id:
			total += float(b.get("per", 0.0)) * get_branch_level(b["id"], stand)
	return total


func get_effect_total(upgrade_id: String) -> float:
	return get_effect_total_for_stand(upgrade_id, _active_stand)


## Effect lookup scoped to whatever stand owns a node (press, lemonader,
## dispenser…). Falls back to the active stand when the node is unclaimed.
func get_effect_total_for_node(upgrade_id: String, node: Node) -> float:
	var stand := OnboardingManager.stand_for_node(node)
	if stand == null:
		return get_effect_total(upgrade_id)
	return get_effect_total_for_stand(upgrade_id, stand.name)


## Effects are computed on demand — nothing to re-apply on load.
func apply_all_effects() -> void:
	pass

# ---------------------------------------------------------------------------
# Legacy node-tree API shims. The tree is gone — these exist only so old
# callers (phone menu, save migration paths) degrade gracefully instead of
# crashing. Purchases no longer exist: bars auto-unlock.
# ---------------------------------------------------------------------------


func purchase(_upgrade_id: String) -> bool:
	return false


func purchase_node(_node_name: String) -> bool:
	return false


func can_afford(_upgrade_id: String) -> bool:
	return false


func can_afford_node(_node_name: String) -> bool:
	return false


func can_unlock(_node_name: String) -> bool:
	return false


func is_node_purchased(_node_name: String) -> bool:
	return false


func get_categories() -> Array:
	return []


func get_upgrades_in_category(_cat: String) -> Array:
	return []


func get_upgrade_data(_id: String) -> Dictionary:
	return { }


func get_node_data(_node_name: String) -> Dictionary:
	return { }


func get_cost(_id: String) -> float:
	return 0.0


func get_purchased_count(_upgrade_id: String) -> int:
	return 0


func get_total_nodes_for(_upgrade_id: String) -> int:
	return 0


func get_purchased_for_stand(_stand_name: String) -> Dictionary:
	return { }


func mark_node_purchased_for_stand(_stand_name: String, _node_name: String) -> void:
	pass


func set_purchased_for_stand(_stand_name: String, _node_names: Array) -> void:
	pass


func load_purchased_nodes(_node_names: Array) -> void:
	pass


func load_legacy_upgrades(_owned_list: Array) -> void:
	pass


func get_save_data() -> Array:
	return []


func get_save_data_for_stand(_stand_name: String) -> Array:
	return []

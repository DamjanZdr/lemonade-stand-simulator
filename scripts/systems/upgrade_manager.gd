extends Node
## Tracks upgrade levels with scaling costs (incremental style).

const UPGRADES: Dictionary = {
	"press_speed": {
		"name": "Press Speed",
		"description": "Faster fruit pressing.",
		"category": "equipment",
		"base_cost": 50.0,
		"cost_multiplier": 1.4,
		"max_level": 10,
		"effect_per_level": 0.08,
	},
	"nimbleness": {
		"name": "Nimbleness",
		"description": "Faster ingredient placement while holding LMB.",
		"category": "equipment",
		"base_cost": 50.0,
		"cost_multiplier": 1.4,
		"max_level": 10,
		"effect_per_level": 0.08,
	},
	"larger_crates": {
		"name": "Larger Crates",
		"description": "Supply deliveries contain more ingredients.",
		"category": "equipment",
		"base_cost": 75.0,
		"cost_multiplier": 1.5,
		"max_level": 5,
		"effect_per_level": 1.0,
	},
	"bin_capacity": {
		"name": "Bin Capacity",
		"description": "Ingredient bins hold more units.",
		"category": "equipment",
		"base_cost": 60.0,
		"cost_multiplier": 1.5,
		"max_level": 5,
		"effect_per_level": 5.0,
	},
	"sunroof": {
		"name": "Sunroof",
		"description": "Customers are more patient in any weather.",
		"category": "customer",
		"base_cost": 80.0,
		"cost_multiplier": 1.5,
		"max_level": 5,
		"effect_per_level": 0.10,
	},
	"price_flex": {
		"name": "Sales Training",
		"description": "Customers tolerate higher prices.",
		"category": "customer",
		"base_cost": 100.0,
		"cost_multiplier": 1.6,
		"max_level": 5,
		"effect_per_level": 0.05,
	},
	"marketing": {
		"name": "Marketing",
		"description": "More pedestrians decide to join the queue.",
		"category": "customer",
		"base_cost": 90.0,
		"cost_multiplier": 1.5,
		"max_level": 5,
		"effect_per_level": 0.10,
	},
	"queue_appeal": {
		"name": "Queue Appeal",
		"description": "More customers can wait in line.",
		"category": "customer",
		"base_cost": 120.0,
		"cost_multiplier": 1.6,
		"max_level": 5,
		"effect_per_level": 1.0,
	},
	"speed_serve": {
		"name": "Speed Serve",
		"description": "Customers drink and leave faster.",
		"category": "customer",
		"base_cost": 70.0,
		"cost_multiplier": 1.4,
		"max_level": 5,
		"effect_per_level": 0.10,
	},
	"ice_mastery": {
		"name": "Ice Mastery",
		"description": "Ice scores more generously.",
		"category": "recipe",
		"base_cost": 60.0,
		"cost_multiplier": 1.4,
		"max_level": 5,
		"effect_per_level": 0.10,
	},
	"sugar_rush": {
		"name": "Sugar Rush",
		"description": "Sugar scores more generously.",
		"category": "recipe",
		"base_cost": 60.0,
		"cost_multiplier": 1.4,
		"max_level": 5,
		"effect_per_level": 0.10,
	},
	"psychology": {
		"name": "Psychology",
		"description": "Reveals exact feedback after each serve.",
		"category": "recipe",
		"base_cost": 300.0,
		"cost_multiplier": 1.0,
		"max_level": 1,
		"effect_per_level": 1.0,
	},
	"tip_magnet": {
		"name": "Tip Magnet",
		"description": "Happy customers tip more often.",
		"category": "economy",
		"base_cost": 80.0,
		"cost_multiplier": 1.5,
		"max_level": 5,
		"effect_per_level": 0.10,
	},
	"bulk_buy": {
		"name": "Bulk Buy",
		"description": "Supply orders cost less.",
		"category": "economy",
		"base_cost": 60.0,
		"cost_multiplier": 1.4,
		"max_level": 5,
		"effect_per_level": 0.03,
	},
}

var levels: Dictionary = { } # upgrade_id -> current level


func _ready() -> void:
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)


func get_level(id: String) -> int:
	return levels.get(id, 0)


func get_cost(id: String) -> float:
	var data: Dictionary = UPGRADES.get(id, { })
	var base: float = data.get("base_cost", 0.0)
	var mult: float = data.get("cost_multiplier", 1.0)
	var level: int = get_level(id)
	return roundf(base * pow(mult, level))


func is_maxed(id: String) -> bool:
	var data: Dictionary = UPGRADES.get(id, { })
	var max_level: int = data.get("max_level", 1)
	return get_level(id) >= max_level


func can_afford(id: String) -> bool:
	return GameState.money >= get_cost(id)


func purchase(id: String) -> bool:
	if is_maxed(id):
		return false
	var cost: float = get_cost(id)
	if not GameState.spend_money(cost):
		return false
	levels[id] = get_level(id) + 1
	_apply_effect(id)
	EventBus.game_saved.emit()
	return true


func get_effect_total(id: String) -> float:
	var data: Dictionary = UPGRADES.get(id, { })
	var per_level: float = data.get("effect_per_level", 0.0)
	return get_level(id) * per_level


func get_categories() -> Array:
	var cats: Dictionary = { }
	for id in UPGRADES:
		var cat: String = UPGRADES[id].get("category", "")
		cats[cat] = true
	return cats.keys()


func get_upgrades_in_category(category: String) -> Array:
	var result: Array = []
	for id in UPGRADES:
		if UPGRADES[id].get("category", "") == category:
			result.append(id)
	return result


func get_upgrade_data(id: String) -> Dictionary:
	var data: Dictionary = UPGRADES.get(id, { }).duplicate()
	data["id"] = id
	data["level"] = get_level(id)
	data["cost"] = get_cost(id)
	data["maxed"] = is_maxed(id)
	return data


func _apply_effect(id: String) -> void:
	match id:
		"psychology":
			GameState.feedback_tier = 2
			EventBus.feedback_tier_changed.emit(2)


func apply_all_effects() -> void:
	for id in levels:
		_apply_effect(id)


func _on_upgrade_purchased(_id: int, _cost: float) -> void:
	pass # Legacy signal; new system uses direct purchase()


func load_legacy_upgrades(owned_list: Array) -> void:
	for u in owned_list:
		if u is int:
			match u:
				0:
					levels["press_speed"] = maxi(levels.get("press_speed", 0), 1)
				1:
					levels["nimbleness"] = maxi(levels.get("nimbleness", 0), 1)
				2:
					levels["sunroof"] = maxi(levels.get("sunroof", 0), 1)
				3:
					levels["larger_crates"] = maxi(levels.get("larger_crates", 0), 1)
				5:
					levels["price_flex"] = maxi(levels.get("price_flex", 0), 1)
				6:
					levels["psychology"] = maxi(levels.get("psychology", 0), 1)


func reset() -> void:
	levels.clear()

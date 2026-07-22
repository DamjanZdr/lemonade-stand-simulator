extends Node
## Holds all live game data. Updated via EventBus signals only.

const FRUIT_TYPES: Array[String] = ["lemon", "strawberry", "blueberry", "peach", "watermelon"]

var money: float
var popularity: float
var temperature: float
var prices: Dictionary = { }
var recipes: Dictionary = { }
var ice_degrees_per_scoop: float = 4.0
var feedback_tier: int

var customers_served_happy: int = 0
var customers_lost: int = 0


func _ready() -> void:
	# Try loading save; fall back to defaults if none exists.
	if SaveManager.has_save():
		var data := SaveManager.load_game()
		SaveManager.apply_save_to_game_state(data)
	else:
		money = Balancing.STARTING_MONEY
		popularity = 0.1
		temperature = 25.0
		_init_default_prices()
		_init_default_recipes()
		feedback_tier = 0

	EventBus.debug_add_money.connect(_on_debug_add_money)
	EventBus.debug_set_temperature.connect(_on_debug_set_temperature)
	EventBus.debug_set_feedback_tier.connect(_on_debug_set_feedback_tier)
	EventBus.debug_set_popularity.connect(func(v: float): set_popularity(v))
	EventBus.change_finalized.connect(_on_change_finalized)
	EventBus.price_changed.connect(_on_price_changed)
	EventBus.recipe_changed.connect(_on_recipe_changed)
	EventBus.customer_served.connect(_on_customer_served)
	EventBus.weather_changed.connect(_on_weather_changed)

	# Auto-save whenever key state changes.
	EventBus.money_changed.connect(func(_v: float): EventBus.game_saved.emit())
	EventBus.popularity_changed.connect(func(_v: float): EventBus.game_saved.emit())
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.feedback_tier_changed.connect(func(_v: int): EventBus.game_saved.emit())


func add_money(amount: float) -> void:
	money += amount
	EventBus.money_changed.emit(money)


func spend_money(amount: float) -> bool:
	if money < amount:
		return false
	money -= amount
	EventBus.money_changed.emit(money)
	return true


func set_popularity(value: float) -> void:
	popularity = clampf(value, 0.0, 1.0)
	EventBus.popularity_changed.emit(popularity)


func _on_debug_add_money(amount: float) -> void:
	add_money(amount)


func _on_debug_set_temperature(temp: float) -> void:
	temperature = clampf(temp, Balancing.TEMP_MIN, Balancing.TEMP_MAX)
	EventBus.weather_changed.emit(temperature)


func _on_debug_set_feedback_tier(tier: int) -> void:
	feedback_tier = clampi(tier, 0, 2)
	EventBus.feedback_tier_changed.emit(feedback_tier)


func _on_change_finalized(earned: float) -> void:
	add_money(earned)


func get_price(fruit_type: String) -> float:
	return prices.get(fruit_type, 1.50)


func set_price(fruit_type: String, new_price: float) -> void:
	prices[fruit_type] = new_price
	EventBus.price_changed.emit(fruit_type, new_price)


func _on_price_changed(fruit_type: String, new_price: float) -> void:
	prices[fruit_type] = new_price


func _on_recipe_changed(fruit_type: String, recipe: Dictionary) -> void:
	recipes[fruit_type] = recipe


func _on_weather_changed(temp: float) -> void:
	temperature = temp


func _on_customer_served(_customer: Node, outcome: String) -> void:
	match outcome:
		"happy":
			customers_served_happy += 1
			set_popularity(popularity + Balancing.POPULARITY_GAIN_HAPPY)
		"timeout":
			customers_lost += 1
			set_popularity(popularity - Balancing.POPULARITY_LOSS_TIMEOUT)
		"too_expensive", "wrong_order":
			customers_lost += 1
			set_popularity(popularity - Balancing.POPULARITY_LOSS_EXPENSIVE)
		_:
			# Any quality complaint (too sweet, too strong, too cold, etc.)
			customers_lost += 1
			set_popularity(popularity - Balancing.POPULARITY_LOSS_BAD)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.EVENING:
		EventBus.game_saved.emit()
	elif phase == DayManager.Phase.MORNING:
		# Reset daily stats
		customers_served_happy = 0
		customers_lost = 0


func _default_recipe_for(fruit_type: String) -> Dictionary:
	var res := load("res://resources/data/" + fruit_type + ".tres") as IngredientData
	if res:
		return {
			"fruit_count": float(res.ideal_fruit_count),
			"sugar": res.ideal_sugar,
		}
	return { "fruit_count": 3.0, "sugar": 2.0 }


func get_recipe(fruit_type: String) -> Dictionary:
	return recipes.get(fruit_type, _default_recipe_for(fruit_type))


func set_recipe(fruit_type: String, recipe: Dictionary) -> void:
	recipes[fruit_type] = recipe.duplicate()
	EventBus.recipe_changed.emit(fruit_type, recipes[fruit_type])


func _init_default_prices() -> void:
	for ft in FRUIT_TYPES:
		var res := load("res://resources/data/" + ft + ".tres") as IngredientData
		if res:
			prices[ft] = res.default_price
		else:
			prices[ft] = 1.50


func _init_default_recipes() -> void:
	for ft in FRUIT_TYPES:
		recipes[ft] = _default_recipe_for(ft)

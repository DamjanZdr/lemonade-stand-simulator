extends Node
## Holds all live game data. Updated via EventBus signals only.

const FRUIT_TYPES: Array[String] = ["lemon", "strawberry", "blueberry", "peach", "watermelon"]

## Game mode enum. Stored in save data and read by the lobby to determine
## how many stands to show and how players are assigned.
enum GameMode {
	SOLO,
	COOP,
	VERSUS,
}

## The current game mode. Set when creating/loading a save.
var game_mode: GameMode = GameMode.SOLO

var money: float
var popularity: float
var temperature: float
var stand_name: String = "Lemonade Stand"
var prices: Dictionary = { }
var recipes: Dictionary = { }
var ice_degrees_per_scoop: float = 4.0
var feedback_tier: int
var _debug_popularity: float = -1.0

# Dev panel toggles for house coloring.
var color_roofs: bool = false
var color_walls: bool = true

var customers_served_happy: int = 0
var customers_lost: int = 0

# Lifetime analytics
var total_customers_served: int = 0
var total_cups_sold: int = 0
var total_money_earned: float = 0.0
var total_money_spent: float = 0.0
var highest_purchase: float = 0.0
var highest_money: float = 0.0


func _ready() -> void:
	# Defaults only — the host explicitly loads a save via SaveManager
	# (start_new_game or load_existing_game) from the Host menu. Clients
	# receive state from the host via RPCs. Do NOT auto-load here.
	money = Balancing.STARTING_MONEY
	popularity = 0.1
	temperature = 25.0
	_init_default_prices()
	_init_default_recipes()
	feedback_tier = 0
	highest_money = money

	EventBus.debug_add_money.connect(_on_debug_add_money)
	EventBus.debug_set_temperature.connect(_on_debug_set_temperature)
	EventBus.debug_set_feedback_tier.connect(_on_debug_set_feedback_tier)
	EventBus.debug_set_popularity.connect(
		func(v: float):
			_debug_popularity = clampf(v, 0.0, 1.0)
			set_popularity(_debug_popularity),
	)
	# NOTE: change_finalized and customer_served are deliberately NOT
	# connected here anymore. With more than one StandUnit in the world,
	# blindly crediting money/popularity for every sale regardless of
	# which stand it was for would leak into this (primary/legacy) stand's
	# totals even when the sale was actually for a different stand.
	# customer.gd now explicitly routes each sale: to GameState directly
	# (calling add_money()/on_customer_served() below) when the customer
	# belongs to the primary stand (or no stand, e.g. a debug-spawned
	# customer), or to that specific StandUnit's own add_money()/
	# on_customer_served() otherwise.
	EventBus.price_changed.connect(_on_price_changed)
	EventBus.recipe_changed.connect(_on_recipe_changed)
	EventBus.weather_changed.connect(_on_weather_changed)

	# Auto-save whenever key state changes.
	EventBus.money_changed.connect(
		func(_v: float):
			EventBus.game_saved.emit(),
	)
	EventBus.popularity_changed.connect(
		func(_v: float):
			EventBus.game_saved.emit(),
	)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.feedback_tier_changed.connect(
		func(_v: int):
			EventBus.game_saved.emit(),
	)
	EventBus.game_reset.connect(_on_game_reset)


func add_money(amount: float) -> void:
	money += amount
	total_money_earned += amount
	if money > highest_money:
		highest_money = money
	EventBus.money_changed.emit(money)


func spend_money(amount: float) -> bool:
	if money < amount:
		return false
	money -= amount
	total_money_spent += amount
	if amount > highest_purchase:
		highest_purchase = amount
	EventBus.money_changed.emit(money)
	return true


func set_popularity(value: float) -> void:
	if _debug_popularity >= 0.0:
		popularity = _debug_popularity
	else:
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


## Public (unlike the other _on_* handlers here) because customer.gd now
## calls this directly for the primary stand instead of GameState listening
## to EventBus.customer_served globally — see the note above _ready().
func on_customer_served(_customer: Node, outcome: String) -> void:
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
		return { "fruit_count": float(res.ideal_fruit_count), "sugar": res.ideal_sugar }
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


func _on_game_reset() -> void:
	_debug_popularity = -1.0

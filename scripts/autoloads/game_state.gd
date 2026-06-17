extends Node
## Holds all live game data. Updated via EventBus signals only.

var money: float
var popularity: float
var temperature: float
var current_price: float
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
		current_price = 1.50
		feedback_tier = 0

	EventBus.debug_add_money.connect(_on_debug_add_money)
	EventBus.debug_set_temperature.connect(_on_debug_set_temperature)
	EventBus.debug_set_feedback_tier.connect(_on_debug_set_feedback_tier)
	EventBus.debug_set_popularity.connect(func(v: float): set_popularity(v))
	EventBus.change_finalized.connect(_on_change_finalized)
	EventBus.price_changed.connect(_on_price_changed)
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
	temperature = clampf(temp, Balancing.ICE_MIN_TEMP, Balancing.ICE_MAX_TEMP)
	EventBus.weather_changed.emit(temperature)


func _on_debug_set_feedback_tier(tier: int) -> void:
	feedback_tier = clampi(tier, 0, 2)
	EventBus.feedback_tier_changed.emit(feedback_tier)


func _on_change_finalized(earned: float) -> void:
	add_money(earned)


func _on_price_changed(new_price: float) -> void:
	current_price = new_price


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

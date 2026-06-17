extends CanvasLayer
## Always-visible right panel for balancing tweaks. Never needs to be opened.

@onready var stats_label: Label = $Panel/VBox/StatsLabel
@onready var verdict_label: Label = $Panel/VBox/VerdictLabel

var _refresh_timer: float = 0.0


func _ready() -> void:
	layer = 10
	$Panel/VBox/BtnMoney.pressed.connect(func(): EventBus.debug_add_money.emit(50.0))
	$Panel/VBox/BtnRefill.pressed.connect(func(): EventBus.debug_refill_all_bins.emit())
	$Panel/VBox/BtnEmpty.pressed.connect(func(): EventBus.debug_empty_pitcher.emit())
	$Panel/VBox/BtnSpawn.pressed.connect(func(): EventBus.debug_force_spawn_customer.emit())
	$Panel/VBox/BtnForceHappy.pressed.connect(func(): EventBus.debug_force_happy_serve.emit())
	$Panel/VBox/BtnTestPayment.pressed.connect(
		func():
			# Mirror customer._customer_payment() so the bill reflects the live price.
			var price := GameState.current_price
			var payment: float
			if price <= 1.0:
				payment = 1.0
			elif price <= 5.0:
				payment = 5.0
			else:
				payment = 10.0
			var change_due := roundf((payment - price) * 100.0) / 100.0
			EventBus.cash_dropped.emit(Vector3(0.0, 1.054, -0.40), payment, change_due)
	)
	$Panel/VBox/TempSlider.value_changed.connect(
		func(v: float): EventBus.debug_set_temperature.emit(v)
	)
	$Panel/VBox/TierSlider.value_changed.connect(
		func(v: float): EventBus.debug_set_feedback_tier.emit(int(v))
	)
	$Panel/VBox/SpawnSlider.value_changed.connect(
		func(v: float): EventBus.debug_set_spawn_rate.emit(v)
	)
	$Panel/VBox/QueueMaxSlider.value_changed.connect(
		func(v: float): EventBus.debug_set_queue_max.emit(int(v))
	)
	$Panel/VBox/OutlineWidthSlider.value_changed.connect(
		func(v: float): EventBus.debug_set_outline_width.emit(v)
	)
	$Panel/VBox/OutlineColorPicker.color_changed.connect(
		func(c: Color): EventBus.debug_set_outline_color.emit(c)
	)

	# Popularity override — added in script to avoid editing the .tscn.
	var vbox := $Panel/VBox
	var pop_label := Label.new()
	pop_label.text = "Popularity:"
	vbox.add_child(pop_label)
	var pop_slider := HSlider.new()
	pop_slider.min_value = 0.0
	pop_slider.max_value = 1.0
	pop_slider.step = 0.01
	pop_slider.value = GameState.popularity
	pop_slider.custom_minimum_size = Vector2(0, 20)
	pop_slider.value_changed.connect(func(v: float): EventBus.debug_set_popularity.emit(v))
	vbox.add_child(pop_slider)

	# Reset save button
	var reset_btn := Button.new()
	reset_btn.text = "Reset Save"
	reset_btn.pressed.connect(
		func():
			EventBus.game_reset.emit()
			# Also reset GameState to defaults
			GameState.money = Balancing.STARTING_MONEY
			GameState.popularity = 0.1
			GameState.temperature = 25.0
			GameState.current_price = 1.5
			GameState.feedback_tier = 0
			GameState.customers_served_happy = 0
			GameState.customers_lost = 0
			DayManager.day_number = 1
			EventBus.money_changed.emit(GameState.money)
			EventBus.popularity_changed.emit(GameState.popularity)
			EventBus.weather_changed.emit(GameState.temperature)
			EventBus.price_changed.emit(GameState.current_price)
			EventBus.feedback_tier_changed.emit(GameState.feedback_tier)
	)
	vbox.add_child(reset_btn)

	_refresh()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= 0.1:
		_refresh_timer = 0.0
		_refresh()


func _refresh() -> void:
	var pitcher: Pitcher = get_tree().get_first_node_in_group("pitcher") as Pitcher
	var recipe: Dictionary = pitcher.get_recipe_snapshot() if pitcher else { }
	var verdict := RecipeEvaluator.get_verdict_string(recipe, GameState.temperature) if pitcher \
	else "No pitcher"

	stats_label.text = (
			"Money: $%.2f\nPop: %d%%\nTemp: %.0f°C\nTier: %d\nPrice: $%.2f" % [
				GameState.money,
				int(GameState.popularity * 100),
				GameState.temperature,
				GameState.feedback_tier,
				GameState.current_price,
			]
	)
	verdict_label.text = "Recipe: " + verdict

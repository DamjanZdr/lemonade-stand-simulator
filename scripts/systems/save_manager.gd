extends Node
## Save/load game progress to user://save.json.

const SAVE_PATH: String = "user://save.json"


func _ready() -> void:
	EventBus.game_saved.connect(_on_game_saved)
	EventBus.game_reset.connect(_on_game_reset)


func save_game() -> void:
	var data := _build_save_dict()
	var json := JSON.stringify(data)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		print("Game saved.")
	else:
		push_error("Failed to save game to %s" % SAVE_PATH)


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return { }
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return { }
	var json := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json)
	if parsed is Dictionary:
		return parsed
	return { }


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("Save deleted.")


func apply_save_to_game_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	GameState.money = data.get("money", Balancing.STARTING_MONEY)
	GameState.popularity = data.get("popularity", 0.1)
	GameState.temperature = data.get("temperature", 25.0)
	GameState.current_price = data.get("current_price", 1.5)
	GameState.feedback_tier = data.get("feedback_tier", 0)
	GameState.customers_served_happy = data.get("customers_served_happy", 0)
	GameState.customers_lost = data.get("customers_lost", 0)
	DayManager.day_number = data.get("day_number", 1)

	UpgradeManager.reset()
	var upgrade_data = data.get("upgrade_levels", { })
	if upgrade_data is Dictionary:
		for id in upgrade_data:
			UpgradeManager.levels[id] = int(upgrade_data[id])
	else:
		# Legacy array format
		var owned_upgrades: Array = data.get("owned_upgrades", [])
		UpgradeManager.load_legacy_upgrades(owned_upgrades)
	UpgradeManager.apply_all_effects()

	var unlocked: Array = data.get("unlocked_fruits", ["lemon"])
	# TODO: wire to fruit unlock system when implemented

	EventBus.money_changed.emit(GameState.money)
	EventBus.popularity_changed.emit(GameState.popularity)
	EventBus.weather_changed.emit(GameState.temperature)
	EventBus.price_changed.emit(GameState.current_price)
	EventBus.feedback_tier_changed.emit(GameState.feedback_tier)


func _build_save_dict() -> Dictionary:
	return {
		"money": GameState.money,
		"popularity": GameState.popularity,
		"temperature": GameState.temperature,
		"current_price": GameState.current_price,
		"feedback_tier": GameState.feedback_tier,
		"customers_served_happy": GameState.customers_served_happy,
		"customers_lost": GameState.customers_lost,
		"day_number": DayManager.day_number,
		"upgrade_levels": UpgradeManager.levels,
		"unlocked_fruits": ["lemon"], # TODO: dynamic
		"version": 1,
	}


func _on_game_saved() -> void:
	save_game()


func _on_game_reset() -> void:
	delete_save()

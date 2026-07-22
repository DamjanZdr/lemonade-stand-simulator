extends Node
## Central manager for recipe evaluation logic.
## Exposes per-fruit ideal values and scoring tolerances in the inspector.

@export_group("Ice")
@export var ice_unhappy_chance: float = 0.3

@export_group("Fruit Recipes")
@export var fruit_recipes: Array[IngredientData] = []


func get_ideal_ice(temperature: float) -> float:
	var deg_per_scoop: float = GameState.ice_degrees_per_scoop
	if deg_per_scoop <= 0.0:
		deg_per_scoop = 4.0
	return temperature / deg_per_scoop


func get_ingredient_data(fruit_type: String) -> IngredientData:
	for data in fruit_recipes:
		if data != null and data.id == fruit_type:
			return data
	# Fallback to lemon
	for data in fruit_recipes:
		if data != null and data.id == &"lemon":
			return data
	return null


func get_ideal_sugar(fruit_type: String, fruit_count: float) -> float:
	var data := get_ingredient_data(fruit_type)
	if data == null:
		return 2.0
	return data.get_ideal_sugar_for(fruit_count)


func get_ideal_water(fruit_type: String, fruit_count: float) -> float:
	var data := get_ingredient_data(fruit_type)
	if data == null:
		return 7.0
	return data.get_ideal_water_for(fruit_count)


func get_unhappy_chance_fruit(fruit_type: String, fruit_count: float) -> float:
	var data := get_ingredient_data(fruit_type)
	if data == null:
		return 1.0
	var delta := absf(fruit_count - data.ideal_fruit_count)
	return clampf(delta * data.fruit_unhappy_chance, 0.0, 1.0)


func get_unhappy_chance_sugar(fruit_type: String, sugar: float, fruit_count: float) -> float:
	var data := get_ingredient_data(fruit_type)
	if data == null:
		return 1.0
	var ideal := data.get_ideal_sugar_for(fruit_count)
	var delta := absf(sugar - ideal)
	return clampf(delta * data.sugar_unhappy_chance, 0.0, 1.0)


func get_unhappy_chance_ice(ice: float, temperature: float) -> float:
	var ideal := get_ideal_ice(temperature)
	var delta := absf(ice - ideal)
	return clampf(delta * ice_unhappy_chance, 0.0, 1.0)

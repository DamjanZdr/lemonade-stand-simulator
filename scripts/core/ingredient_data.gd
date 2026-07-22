class_name IngredientData
extends Resource
## Defines the stats for a fruit ingredient used in recipe evaluation.
## Each fruit type gets its own .tres file so values are editable in the inspector.

## Unique identifier, e.g., "lemon", "strawberry".
@export var id: StringName = &"lemon"

## Display name shown to the player.
@export var display_name: String = "Lemon"

## Ideal number of fruits for a standard pitcher.
@export var ideal_fruit_count: int = 3

## Ideal water amount for that fruit count (cups).
@export var ideal_water: float = 7.0

## Ideal sugar units for that fruit count.
@export var ideal_sugar: float = 2.0

## How many seconds it takes to press one unit of this fruit.
@export var press_time_per_fruit: float = 1.0

## Chance per unit away from ideal that the customer complains (0.0 to 1.0).
## e.g. 0.3 = 30% chance per wrong unit.
@export_group("Unhappy Chance Per Unit")
@export var fruit_unhappy_chance: float = 0.3
@export var sugar_unhappy_chance: float = 0.3

@export_group("Pricing")
@export var default_price: float = 1.50
@export var price_min: float = 0.25
@export var price_max: float = 5.00


func get_ideal_sugar_for(fruit_count: float) -> float:
	## Sugar scales linearly with fruit count.
	if ideal_fruit_count <= 0:
		return ideal_sugar
	return ideal_sugar * (fruit_count / float(ideal_fruit_count))


func get_ideal_water_for(fruit_count: float) -> float:
	## Water scales linearly with fruit count.
	if ideal_fruit_count <= 0:
		return ideal_water
	return ideal_water * (fruit_count / float(ideal_fruit_count))

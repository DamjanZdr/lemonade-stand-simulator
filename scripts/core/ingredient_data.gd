class_name IngredientData
extends Resource
## Defines the stats for a fruit ingredient used in recipe evaluation.
## Each fruit type gets its own .tres file so values are editable in the inspector.

## Unique identifier, e.g., "lemon", "strawberry".
@export var id: StringName = &"lemon"

## Display name shown to the player.
@export var display_name: String = "Lemon"

## How much flavor 1 unit of this fruit contributes to "strength".
@export var flavor_strength: float = 1.0

## How much sweetness 1 unit of this fruit contributes.
@export var sweetness: float = 0.0

## Ideal number of fruits for a standard pitcher.
@export var ideal_fruit_count: int = 3

## Ideal water amount for that fruit count (cups).
@export var ideal_water: float = 7.0

## Ideal sugar units for that fruit count.
@export var ideal_sugar: float = 2.0

## How many seconds it takes to press one unit of this fruit.
@export var press_time_per_fruit: float = 1.0

## Scoring thresholds — how far from ideal before the score drops.
@export_group("Scoring Tolerance")
@export var fruit_count_inner: float = 0.5 ## ±0.5 fruits = perfect
@export var fruit_count_outer: float = 2.0 ## beyond this = 0 score
@export var sugar_inner: float = 0.5
@export var sugar_outer: float = 2.0


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

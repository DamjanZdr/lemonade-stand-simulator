extends Node
## Evaluation logic for served drinks. Registered as an autoload singleton
## (hence these are plain instance methods, not `static` — Godot warns when
## a static function is called through a singleton instance). Uses
## RecipeManager for per-fruit ideal values.
##
## Returns one of 8 specific customer reactions:
##   happy, timeout, too_expensive, wrong_order,
##   too_sweet, not_sweet_enough, too_strong, not_enough_fruit,
##   too_cold, not_cold_enough

var _manager: Node = null


func set_manager(manager: Node) -> void:
	_manager = manager


func _get_manager() -> Node:
	if _manager == null:
		_manager = Engine.get_main_loop().current_scene.get_node_or_null(
			"World/Managers/RecipeManager"
		)
		if _manager == null:
			push_warning("RecipeEvaluator: RecipeManager not found, using fallback values")
	return _manager


func get_base_price(fruit_type: String) -> float:
	## The "ideal" price customers mentally compare the current price against
	## when deciding whether it's a rip-off or a steal. Falls back to a
	## reasonable default if the fruit's data can't be found.
	var mgr := _get_manager()
	if mgr == null:
		return 1.5
	var data: IngredientData = mgr.get_ingredient_data(fruit_type)
	if data == null:
		return 1.5
	return data.default_price


func evaluate(
	recipe: Dictionary,
	temperature: float,
	price: float,
	wait_ratio: float,
	expected_fruit_type: String = "",
) -> String:
	## Main entry point. Returns a single string outcome for the customer flow.
	if wait_ratio <= 0.0:
		return "timeout"
	if price > Balancing.PRICE_TOO_EXPENSIVE:
		return "too_expensive"

	var result := evaluate_detailed(recipe, temperature, expected_fruit_type)
	if result.complaints.is_empty():
		return "happy"
	# Return the first (most severe) complaint.
	return result.complaints[0]


func evaluate_detailed(
	recipe: Dictionary,
	temperature: float,
	expected_fruit_type: String = "",
) -> EvaluationResult:
	## Returns full per-axis scores and an ordered list of complaints.
	var result := EvaluationResult.new()

	var fruit_type: String = recipe.get("fruit_type", "")
	var fruit_count: float = recipe.get("fruit_count", recipe.get("lemons", 0.0))
	var water: float = recipe.get("water", 0.0)
	var sugar: float = recipe.get("sugar", 0.0)
	var ice: float = recipe.get("ice", 0.0)
	var liquid: float = fruit_count + water

	if liquid <= 0.0:
		result.complaints.append("not_enough_fruit")
		result.summary = "FAIL: empty pitcher"
		return result

	# Wrong order check (only if we know what they ordered).
	if expected_fruit_type != "" and fruit_type != expected_fruit_type:
		result.complaints.append("wrong_order")
		result.summary = "FAIL: wrong fruit type"
		return result

	# Use RecipeManager for all ideal values and unhappy chances.
	var mgr := _get_manager()
	if mgr == null:
		result.complaints.append("not_enough_fruit")
		result.summary = "FAIL: RecipeManager not found"
		return result

	var data: IngredientData = mgr.get_ingredient_data(fruit_type)
	if data == null:
		result.complaints.append("wrong_order")
		result.summary = "FAIL: unknown fruit type"
		return result

	# --- Calculate deltas and unhappy chances ---
	var ideal_sugar: float = data.get_ideal_sugar_for(fruit_count)
	var ideal_ice: float = mgr.get_ideal_ice(temperature)

	result.fruit_delta = absf(fruit_count - data.ideal_fruit_count)
	result.sugar_delta = absf(sugar - ideal_sugar)
	result.ice_delta = absf(ice - ideal_ice)

	var fruit_unhappy: float = mgr.get_unhappy_chance_fruit(fruit_type, fruit_count)
	var sugar_unhappy: float = mgr.get_unhappy_chance_sugar(fruit_type, sugar, fruit_count)
	var ice_unhappy: float = mgr.get_unhappy_chance_ice(ice, temperature)

	# Store scores as 1.0 - unhappy_chance for debug display.
	result.strength_score = 1.0 - fruit_unhappy
	result.sweetness_score = 1.0 - sugar_unhappy
	result.temperature_score = 1.0 - ice_unhappy
	result.overall_score = result.strength_score * result.sweetness_score * result.temperature_score
	result.is_perfect = (
		result.fruit_delta == 0.0 and result.sugar_delta == 0.0 and result.ice_delta == 0.0
	)

	# --- Complaint generation: roll for each axis ---
	if randf() < fruit_unhappy:
		if fruit_count > data.ideal_fruit_count:
			result.complaints.append("too_strong")
		else:
			result.complaints.append("not_enough_fruit")

	if randf() < sugar_unhappy:
		if sugar > ideal_sugar:
			result.complaints.append("too_sweet")
		else:
			result.complaints.append("not_sweet_enough")

	if randf() < ice_unhappy:
		if ice > ideal_ice:
			result.complaints.append("too_cold")
		else:
			result.complaints.append("not_cold_enough")

	result.summary = get_verdict_string(recipe, temperature)
	return result


func get_verdict_string(recipe: Dictionary, temperature: float) -> String:
	## Human-readable summary for debug panel.
	var fruit_type: String = recipe.get("fruit_type", "")
	var fruit_count: float = recipe.get("fruit_count", recipe.get("lemons", 0.0))
	var water: float = recipe.get("water", 0.0)
	var sugar: float = recipe.get("sugar", 0.0)
	var ice: float = recipe.get("ice", 0.0)
	var liquid: float = fruit_count + water

	if liquid <= 0.0:
		return "FAIL: empty pitcher"

	var mgr := _get_manager()
	if mgr == null:
		return "FAIL: RecipeManager not found"

	var data: IngredientData = mgr.get_ingredient_data(fruit_type)
	if data == null:
		return "FAIL: unknown fruit type"

	var ideal_ice: float = mgr.get_ideal_ice(temperature)
	var f_delta: float = absf(fruit_count - data.ideal_fruit_count)
	var s_delta: float = absf(sugar - data.get_ideal_sugar_for(fruit_count))
	var i_delta: float = absf(ice - ideal_ice)

	var f_chance: float = mgr.get_unhappy_chance_fruit(fruit_type, fruit_count) * 100.0
	var s_chance: float = mgr.get_unhappy_chance_sugar(fruit_type, sugar, fruit_count) * 100.0
	var i_chance: float = mgr.get_unhappy_chance_ice(ice, temperature) * 100.0

	return "%s  Fruit: %.1f off (%d%%)  Sugar: %.1f off (%d%%)  Ice: %.1f off (%d%%)" % [
		data.display_name,
		f_delta,
		roundi(f_chance),
		s_delta,
		roundi(s_chance),
		i_delta,
		roundi(i_chance),
	]

# --- Helpers ---

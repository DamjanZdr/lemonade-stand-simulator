extends Node
## Pure static evaluation logic. Uses IngredientData resources for per-fruit ideal values.
##
## Returns one of 8 specific customer reactions:
##   happy, timeout, too_expensive, wrong_order,
##   too_sweet, not_sweet_enough, too_strong, not_enough_fruit,
##   too_cold, not_cold_enough

static func evaluate(
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


static func evaluate_detailed(
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

	# Load the ingredient data for this fruit.
	var data := _load_ingredient_data(fruit_type)

	# --- Scoring ---
	var ideal_sugar: float = data.get_ideal_sugar_for(fruit_count)
	var ideal_water: float = data.get_ideal_water_for(fruit_count)

	result.sweetness_score = _score(
		sugar,
		ideal_sugar,
		data.sugar_inner,
		data.sugar_outer,
	)
	result.strength_score = _score(
		fruit_count,
		data.ideal_fruit_count,
		data.fruit_count_inner,
		data.fruit_count_outer,
	)

	var ideal_ice: float = Balancing.ideal_ice_for_temp(temperature)
	result.temperature_score = _score(
		ice,
		ideal_ice,
		Balancing.ICE_SCORE_INNER,
		Balancing.ICE_SCORE_OUTER,
	)

	result.overall_score = result.sweetness_score * result.strength_score * result.temperature_score
	result.is_perfect = result.overall_score >= 0.95

	# --- Complaint generation (worst first) ---
	var scores: Array[float] = [
		result.sweetness_score,
		result.strength_score,
		result.temperature_score,
	]
	var worst_idx := scores.find(scores.min())

	# Check each axis; if score is bad, add the directional complaint.
	if result.sweetness_score < 0.8:
		if sugar > ideal_sugar:
			result.complaints.append("too_sweet")
		else:
			result.complaints.append("not_sweet_enough")

	if result.strength_score < 0.8:
		if fruit_count > data.ideal_fruit_count:
			result.complaints.append("too_strong")
		else:
			result.complaints.append("not_enough_fruit")

	if result.temperature_score < 0.8:
		if ice > ideal_ice:
			result.complaints.append("too_cold")
		else:
			result.complaints.append("not_cold_enough")

	result.summary = get_verdict_string(recipe, temperature)
	return result


static func get_verdict_string(recipe: Dictionary, temperature: float) -> String:
	## Human-readable summary for debug panel.
	var fruit_type: String = recipe.get("fruit_type", "")
	var fruit_count: float = recipe.get("fruit_count", recipe.get("lemons", 0.0))
	var water: float = recipe.get("water", 0.0)
	var sugar: float = recipe.get("sugar", 0.0)
	var ice: float = recipe.get("ice", 0.0)
	var liquid: float = fruit_count + water

	if liquid <= 0.0:
		return "FAIL: empty pitcher"

	var data := _load_ingredient_data(fruit_type)
	var ideal_sugar: float = data.get_ideal_sugar_for(fruit_count)
	var ideal_ice: float = Balancing.ideal_ice_for_temp(temperature)

	var ss: float = _score(sugar, ideal_sugar, data.sugar_inner, data.sugar_outer)
	var st: float = _score(
		fruit_count,
		data.ideal_fruit_count,
		data.fruit_count_inner,
		data.fruit_count_outer,
	)
	var is_: float = _score(
		ice,
		ideal_ice,
		Balancing.ICE_SCORE_INNER,
		Balancing.ICE_SCORE_OUTER,
	)
	var overall: float = ss * st * is_

	return "%s %d%%  Sugar %d%%  Ice %d%%  →  %d%% happy" % [
		data.display_name,
		roundi(st * 100),
		roundi(ss * 100),
		roundi(is_ * 100),
		roundi(overall * 100),
	]

# --- Helpers ---


static func _load_ingredient_data(fruit_type: String) -> IngredientData:
	if fruit_type != "":
		var res := load("res://resources/data/" + fruit_type + ".tres")
		if res is IngredientData:
			return res
	# Fallback to lemon if unknown.
	return load("res://resources/data/lemon.tres") as IngredientData


static func _score(actual: float, ideal: float, inner: float, outer: float) -> float:
	## Plateau-then-decay scoring.
	## Score = 1.0 within ideal ± inner. Decays linearly to 0 over the next 'outer' distance.
	var delta: float = absf(actual - ideal)
	if delta <= inner:
		return 1.0
	return maxf(0.0, 1.0 - (delta - inner) / outer)

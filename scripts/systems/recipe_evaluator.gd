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

const FEEDBACK_LINES := {
	"not_enough_fruit": [
		"Just a little more fruit.",
		"Could use more fruit.",
		"Way too little fruit.",
	],
	"too_strong": ["Just a little too strong.", "Too much fruit.", "Far too much fruit."],
	"not_sweet_enough": [
		"Just a little more sugar.",
		"Could use more sugar.",
		"Way too little sugar.",
	],
	"too_sweet": ["Just a little too sweet.", "Too much sugar.", "Far too much sugar."],
	"not_cold_enough": ["Just a little more ice.", "Could use more ice.", "Way too little ice."],
	"too_cold": ["Just a little too cold.", "Too much ice.", "Far too much ice."],
}

var _manager: Node = null


func set_manager(manager: Node) -> void:
	_manager = manager


func _get_manager() -> Node:
	if _manager == null:
		var scene: Node = Engine.get_main_loop().current_scene
		if scene:
			_manager = scene.find_child("RecipeManager", true, false)
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
	return data.ideal_price


func get_price_max(fruit_type: String) -> float:
	## Maximum acceptable price before every customer rejects the drink as
	## too expensive. Falls back to the global ceiling if data is missing.
	var mgr := _get_manager()
	if mgr == null:
		return Balancing.PRICE_MAX
	var data: IngredientData = mgr.get_ingredient_data(fruit_type)
	if data == null:
		return Balancing.PRICE_MAX
	var maxp: float = data.price_max
	var ideal: float = data.ideal_price
	if maxp <= ideal:
		maxp = Balancing.PRICE_MAX
	return maxp


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
	var fruit_type: String = recipe.get("fruit_type", expected_fruit_type)
	if price > get_price_max(fruit_type):
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
	deterministic: bool = true,
) -> EvaluationResult:
	## Returns full per-axis scores and an ordered list of complaints.
	## When `deterministic` is true, every axis that deviates produces its
	## complaint instead of rolling the unhappy chance — used for free-sample
	## NPCs whose whole purpose is accurate recipe feedback.
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
	result.fruit_high = fruit_count > data.ideal_fruit_count
	result.sugar_high = sugar > ideal_sugar
	result.ice_high = ice > ideal_ice

	var fruit_unhappy: float = mgr.get_unhappy_chance_fruit(fruit_type, fruit_count)
	var sugar_unhappy: float = mgr.get_unhappy_chance_sugar(fruit_type, sugar, fruit_count)
	var ice_unhappy: float = mgr.get_unhappy_chance_ice(ice, temperature)

	# Store scores as 1.0 - unhappy_chance for debug display.
	result.strength_score = 1.0 - fruit_unhappy
	result.sweetness_score = 1.0 - sugar_unhappy
	result.temperature_score = 1.0 - ice_unhappy
	result.overall_score = result.strength_score * result.sweetness_score * result.temperature_score
	result.is_perfect = (
		is_zero_approx(result.fruit_delta) and is_zero_approx(result.sugar_delta)
		and is_zero_approx(result.ice_delta)
	)

	# --- Complaint generation: roll for each axis ---
	# In deterministic mode every off-ideal axis complains; otherwise each
	# axis rolls its unhappy chance so mild misses sometimes get a pass.
	var complains_fruit := not is_zero_approx(result.fruit_delta) if deterministic else randf() < fruit_unhappy
	var complains_sugar := not is_zero_approx(result.sugar_delta) if deterministic else randf() < sugar_unhappy
	var complains_ice := not is_zero_approx(result.ice_delta) if deterministic else randf() < ice_unhappy
	if complains_fruit:
		if fruit_count > data.ideal_fruit_count:
			result.complaints.append("too_strong")
		else:
			result.complaints.append("not_enough_fruit")

	if complains_sugar:
		if sugar > ideal_sugar:
			result.complaints.append("too_sweet")
		else:
			result.complaints.append("not_sweet_enough")

	if complains_ice:
		if ice > ideal_ice:
			result.complaints.append("too_cold")
		else:
			result.complaints.append("not_cold_enough")

	result.summary = get_verdict_string(recipe, temperature)
	return result


func get_feedback_lines(complaints: Array, deltas: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for complaint in complaints:
		if not FEEDBACK_LINES.has(complaint):
			continue
		var axis := "fruit"
		if complaint in ["too_sweet", "not_sweet_enough"]:
			axis = "sugar"
		elif complaint in ["too_cold", "not_cold_enough"]:
			axis = "ice"
		var tier := clampi(roundi(float(deltas.get(axis + "_delta", 1.0))), 1, 3) - 1
		var text: String = FEEDBACK_LINES[complaint][tier]
		if not lines.has(text):
			lines.append(text)
	return lines


func join_feedback_lines(lines: Array) -> String:
	## Flatten complaint lines into one flowing sentence. The bubble wraps
	## on width on its own, so nothing here forces line breaks.
	var fragments: Array[String] = []
	for line in lines:
		var text := str(line).strip_edges().trim_suffix(".")
		if text != "" and not fragments.has(text):
			fragments.append(text)
	for i in range(1, fragments.size()):
		fragments[i] = fragments[i].substr(0, 1).to_lower() + fragments[i].substr(1)
	return ", ".join(fragments) + ("." if not fragments.is_empty() else "")


func format_feedback(evaluations: Array) -> String:
	var groups: Array[Dictionary] = []
	var seen := { }
	var fruits := { }
	for index in evaluations.size():
		var evaluation: Dictionary = evaluations[index]
		var fruit := str(evaluation.get("snapshot", { }).get("fruit_type", ""))
		fruits[fruit] = true
		var lines := get_feedback_lines(evaluation.get("complaints", []), evaluation)
		if lines.is_empty():
			continue
		var text := join_feedback_lines(lines)
		var key := fruit + ":" + text
		if seen.has(key):
			continue
		seen[key] = true
		groups.append({ "fruit": fruit, "cup": index + 1, "text": text })
	if groups.is_empty():
		return "Delicious!"
	if groups.size() == 1 and fruits.size() <= 1:
		return str(groups[0].text)
	var sections: Array[String] = []
	for group in groups:
		var label := str(group.fruit).capitalize() if group.fruit != "" else "Drink"
		var text: String = str(group.text)
		sections.append(
			"%s cup %d: %s" % [label, group.cup, text.substr(0, 1).to_lower() + text.substr(1)]
		)
	return " ".join(sections)


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

	if fruit_count <= 0.0 and water > 0.0:
		return "Just water"

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

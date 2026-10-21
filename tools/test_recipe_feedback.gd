extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var evaluator := root.get_node("RecipeEvaluator")
	if not evaluator.has_method("get_feedback_lines") or not evaluator.has_method("format_feedback"):
		print("FAIL: shared full-feedback formatter is not implemented")
		quit(1)
		return
	var manager: Node = load("res://scripts/systems/recipe_manager.gd").new()
	var data: Resource = load("res://resources/data/lemon.tres").duplicate()
	manager.fruit_recipes.append(data)
	evaluator.set_manager(manager)
	var first := {
		"fruit_type": "lemon",
		"fruit_count": 1.0,
		"water": 9.0,
		"sugar": 1.0,
		"ice": 1.0,
	}
	var second := {
		"fruit_type": "lemon",
		"fruit_count": 1.0,
		"water": 9.0,
		"sugar": 2.0,
		"ice": 1.0,
	}
	var perfect := {
		"fruit_type": "lemon",
		"fruit_count": 2.0,
		"water": 8.0,
		"sugar": 4.0,
		"ice": 1.0,
	}
	for index in 100:
		var result: RefCounted = evaluator.evaluate_detailed(first, 15.0, "lemon")
		check(
			result.complaints == ["not_enough_fruit", "not_sweet_enough"],
			"every incorrect axis reported on first test batch",
		)
		result = evaluator.evaluate_detailed(second, 15.0, "lemon")
		check(
			result.complaints == ["not_enough_fruit"],
			"sugar correction removes only sugar complaint",
		)
		result = evaluator.evaluate_detailed(perfect, 15.0, "lemon")
		check(result.complaints.is_empty() and result.is_perfect, "correct recipe always succeeds")
	var cold: RefCounted = evaluator.evaluate_detailed(perfect, 35.0, "lemon")
	check(
		cold.complaints == ["not_cold_enough"] and cold.ice_delta == 2.0,
		"ice distance is cubes for current temperature",
	)
	data.fruit_unhappy_chance = 0.0
	data.sugar_unhappy_chance = 0.0
	manager.ice_unhappy_chance = 0.0
	check(
		evaluator.evaluate_detailed(first, 15.0, "lemon").complaints.size() == 2,
		"guaranteed feedback independent of old probability settings",
	)
	var dust := perfect.duplicate()
	dust.fruit_count += 0.0000001
	check(
		evaluator.evaluate_detailed(dust, 15.0, "lemon").complaints.is_empty(),
		"float dust does not create false complaints",
	)
	var directions := [
		"too_strong",
		"not_enough_fruit",
		"too_sweet",
		"not_sweet_enough",
		"too_cold",
		"not_cold_enough",
	]
	for complaint in directions:
		var previous := ""
		for distance in [1, 2, 3]:
			var text: String = evaluator.get_feedback_lines(
				[complaint],
				{ "fruit_delta": distance, "sugar_delta": distance, "ice_delta": distance },
			)[0]
			check(
				not text.is_empty() and text != previous,
				"distinct severity tiers for " + complaint,
			)
			previous = text
		check(
			evaluator.get_feedback_lines(
				[complaint],
				{ "fruit_delta": 7, "sugar_delta": 7, "ice_delta": 7 },
			)[0]
			== previous,
			"3+ severity cap for " + complaint,
		)
	var evaluation := {
		"snapshot": first,
		"complaints": ["not_enough_fruit", "not_sweet_enough"],
		"fruit_delta": 1.0,
		"sugar_delta": 1.0,
		"ice_delta": 0.0,
	}
	var lines: Array = evaluator.get_feedback_lines(evaluation.complaints, evaluation)
	check(lines.size() == 2, "full feedback contains both ingredient corrections")
	check(
		evaluator.format_feedback([evaluation]) == "\n".join(lines),
		"customer uses shared wording",
	)
	check(
		evaluator.format_feedback([evaluation, evaluation]) == "\n".join(lines),
		"repeated cups do not repeat identical feedback",
	)
	var different := { "snapshot": perfect, "complaints": ["too_sweet"], "sugar_delta": 3.0 }
	var mixed: String = evaluator.format_feedback([evaluation, different])
	check(
		mixed.contains("cup 1") and mixed.contains("cup 2"),
		"different cups receive labeled feedback rather than contradictory unqualified instructions",
	)
	check(evaluator.format_feedback([]) == "Delicious!", "success wording preserved")
	check(
		evaluator.evaluate(first, 15.0, 999.0, 1.0) == "too_expensive",
		"price rejection unchanged",
	)
	check(evaluator.evaluate(first, 15.0, 1.0, 0.0) == "timeout", "timeout unchanged")
	check(
		evaluator.evaluate_detailed(perfect, 15.0, "raspberry").complaints == ["wrong_order"],
		"wrong-order rejection unchanged",
	)
	var pedestrian: Node = load("res://scripts/customer/pedestrian.gd").new()
	var feedback: String = pedestrian._feedback_text(
		evaluator.evaluate_detailed(first, 15.0, "", true)
	)
	check(feedback == "\n".join(lines), "free-sample and customer wording match")
	pedestrian.free()
	var customer: Node = load("res://scripts/customer/customer.gd").new()
	customer._served_evaluations.append(evaluation)
	check(
		customer._feedback_for_outcome("not_enough_fruit") == "\n".join(lines),
		"actual customer flow reports all axes",
	)
	check(
		customer._feedback_for_outcome("timeout") == "This takes too long, I have places to be!",
		"customer timeout message preserved",
	)
	customer.free()
	manager.free()
	print(
		"Recipe feedback tests: ",
		"PASS" if failures == 0 else "FAIL",
		" (",
		failures,
		" failures)",
	)
	quit(0 if failures == 0 else 1)

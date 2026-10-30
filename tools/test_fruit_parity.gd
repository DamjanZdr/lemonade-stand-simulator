extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var upgrades := root.get_node("UpgradeManager")
	var evaluator := root.get_node("RecipeEvaluator")
	var manager: Node = load("res://scripts/systems/recipe_manager.gd").new()
	var stand_script: Script = load("res://scripts/stand/stand_unit.gd")
	var own: Node = stand_script.new()
	var rival: Node = stand_script.new()
	own.name = "FruitTestOwn"
	rival.name = "FruitTestRival"
	var spawner: Node = load("res://scripts/customer/customer_spawner.gd").new()
	spawner.set_stand(own)
	for fruit in root.get_node("GameState").FRUIT_TYPES:
		var data := load("res://resources/data/" + fruit + ".tres") as IngredientData
		check(data != null, fruit + " ingredient data")
		if data != null:
			manager.fruit_recipes.append(data)
	evaluator.set_manager(manager)
	for fruit in root.get_node("GameState").FRUIT_TYPES:
		var idx: int = upgrades.FRUIT_ORDER.find(fruit)
		check(idx >= 0, fruit + " in unlock order")
		# Bar model: a fruit unlocks when the previous tiers are claimed,
		# and each tier is claimable only with enough perfect serves of
		# the gating fruit. Simulate mastery on the owning stand only.
		if idx > 0:
			var serves := { }
			for j in range(idx):
				serves[upgrades.FRUIT_ORDER[j]] = 99
			own.onboarding_progress["progress"] = { "perfect_serves": serves }
			for j in range(idx):
				check(upgrades.try_claim("fruit", own), "claim tier %d for %s" % [j + 1, fruit])
		rival.onboarding_progress["progress"] = { }
		check(own.is_fruit_unlocked(fruit), fruit + " own stand unlock")
		check(rival.is_fruit_unlocked(fruit) == (fruit == "lemon"), fruit + " rival remains locked")
		upgrades.set_active_stand(str(rival.name))
		for attempt in range(40):
			var order: Dictionary = spawner.call("_random_order")
			for ordered in order:
				check(own.is_fruit_unlocked(ordered), fruit + " order scoped to owning stand")
		var seen := false
		for attempt in range(100):
			seen = seen or spawner.call("_random_order").has(fruit)
		check(seen, fruit + " can be ordered despite rival active tree")
		var data := load("res://resources/data/" + fruit + ".tres") as IngredientData
		var pitcher: Node = load("res://scenes/objects/pitcher.tscn").instantiate()
		world.add_child(pitcher)
		var press: Node = load("res://scenes/objects/press.tscn").instantiate()
		world.add_child(press)
		press.snap_pitcher(pitcher)
		press.fruit_type = fruit
		press.fruit_count = float(data.ideal_fruit_count)
		press.call("_finish_press")
		check(press.fruit_count == 0.0, fruit + " press transfers all fruit")
		check(pitcher.fruit_type == fruit, fruit + " pressed juice retains fruit identity")
		press.free()
		check(
			pitcher.add_ingredient("water", 10.0 - data.ideal_fruit_count),
			fruit + " water accepted",
		)
		check(pitcher.add_ingredient("sugar", 1.0), fruit + " sugar accepted")
		check(pitcher.add_ingredient("ice", 1.0), fruit + " ice accepted")
		for cup_index in range(10):
			var portion: Dictionary = pitcher.pour_portion()
			check(portion.get("fruit_type", "") == fruit, fruit + " cup retains fruit identity")
		check(pitcher.get_liquid_volume() < 0.05, fruit + " drains after ten cups")
		check(
			ResourceLoader.exists("res://assets/textures/ui/products/" + fruit + ".png"),
			fruit + " shop icon",
		)
		pitcher.free()
	var customer: Node = load("res://scenes/customer/customer.tscn").instantiate()
	world.add_child(customer)
	var unknown: Label = customer.get("_order_unknown_label")
	var icon: TextureRect = customer.get("_order_icon")
	var count_label: Label = customer.get("_order_count_label")
	check(unknown.visible and not icon.visible, "unasked customer displays question mark")
	customer.order = { "lemon": 2 }
	customer.set("_order_taken", true)
	customer.call("_show_order")
	check(icon.visible and not unknown.visible, "asked customer displays fruit icon")
	check(count_label.text == "2", "badge displays remaining quantity")
	customer.order = { "lemon": 1 }
	customer.call("_show_order")
	check(count_label.text == "1", "badge updates after serving")
	customer.call("_tick_order_dialogue", 6.0)
	var bubble: Sprite3D = customer.get("_bubble_sprite")
	check(not bubble.visible and icon.visible, "order dialogue expires without hiding badge")
	customer.call("_set_order_text", "Too sweet", false)
	customer.call("_tick_order_dialogue", 6.0)
	check(bubble.visible, "feedback is not expired by the order dialogue timer")
	customer.free()
	spawner.free()
	own.free()
	rival.free()
	manager.free()
	print("FRUIT PARITY: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

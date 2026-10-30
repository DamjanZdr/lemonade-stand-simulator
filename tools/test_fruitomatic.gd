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
	var scene: PackedScene = load("res://scenes/objects/fruitomatic.tscn")
	var machine: Node = scene.instantiate()
	world.add_child(machine)

	check(
		str(machine.get_script().resource_path).ends_with("fruitomatic.gd"),
		"scene has FruitOMatic script",
	)
	check(machine._machine_type() == "fruitomatic", "machine type is fruitomatic")
	check(machine.get_node_or_null("FocusCamera") != null, "focus camera present")
	check(machine.get_node_or_null("Pickupable") != null, "machine is pickupable")

	# Multi-fruit stock: different fruits coexist, non-ingredients rejected.
	check(machine.deposit("lemon", 5.0) == 5.0, "accepts lemon")
	check(machine.deposit("peach", 4.0) == 4.0, "accepts a second fruit too")
	check(machine.deposit("water", 1.0) == 0.0, "rejects water like the EZ")
	check(machine.deposit("sugar", 8.0) == 8.0, "accepts sugar")
	check(machine.deposit("ice", 2.0) == 2.0, "accepts ice")

	machine.machine_state["pitcher"] = true
	var recipe := { "fruit_count": 2.0, "water": 8.0, "sugar": 1.0, "ice": 1.0 }
	check(machine.start_batch(recipe, "peach") == "Mixing...", "starts peach batch")
	check(
		float((machine.machine_state["fruits"] as Dictionary)["peach"]) == 2.0,
		"consumes the selected fruit only",
	)
	check(
		float((machine.machine_state["fruits"] as Dictionary)["lemon"]) == 5.0,
		"other fruit untouched by the batch",
	)
	machine.finish_batch()
	check(str(machine.machine_state["output"]["fruit_type"]) == "peach", "output is peach")
	check(
		machine.start_batch(recipe, "peach") != "Mixing...",
		"blocks second batch with output waiting",
	)

	# _resolve_mix drives the UI's start click like an action request.
	var player: Node = load("res://scripts/player/player.gd").new()
	player.set_multiplayer_authority(1)
	world.add_child(player)
	var stand: Node = load("res://scripts/stand/stand_unit.gd").new()
	world.add_child(stand)
	player.assigned_stand = stand
	var empty_msg: String = machine._resolve_mix(player, "mix:raspberry")
	check(empty_msg.begins_with("Set a"), "resolve_mix reports missing board recipe")
	check(
		(machine.machine_state["output"] as Dictionary).is_empty() == false
		or machine.machine_state["output"].has("fruit_type"),
		"output state unchanged by failed mix",
	)

	# 3D START buttons — one per fruit, each routing mix:<fruit> to the
	# machine's host action.
	for fruit in ["lemon", "raspberry", "strawberry", "blueberry", "peach", "watermelon"]:
		var btn: Node = machine.get_node_or_null("StockPanels/Fruits/Start" + fruit.capitalize())
		check(btn != null, "start button exists for %s" % fruit)
		if btn == null:
			continue
		check(str(btn.fruit) == fruit, "start button knows its fruit")
		check(btn._machine() == machine, "start button finds the machine")
	# Clicking a button goes through the machine's mix resolution (missing
	# board recipe here — the action path itself is what matters).
	var lemon_btn: Node = machine.get_node("StockPanels/Fruits/StartLemon")
	lemon_btn.interact(player)
	check(lemon_btn.get_hint(player).begins_with("Start"), "start button hint")

	# "Missing: ..." results shake the named panels' X marks — the flash
	# shows even when the fruit has partial stock (deficit, not empty).
	machine.show_result("Missing: 1.0 peach, 1.0 sugar")
	check(
		(machine.get_node("StockPanels/Fruits/Peach/Empty") as Label3D).visible,
		"missing-fruit flash shows the X",
	)
	check(
		(machine.get_node("StockPanels/SugarIce/Sugar/Empty") as Label3D).visible,
		"missing-sugar flash shows the X",
	)

	# Focus lifecycle (the camera path is skipped — the bare test player
	# has no controller, same as the other harness players).
	machine.get_node("FocusCamera").free()
	machine.open_fruit_select(player)
	check(machine._focused_player == null, "no focus without a focus camera")
	machine.close_fruit_select()

	player.free()
	stand.free()
	machine.free()
	world.free()
	print("FRUITOMATIC: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

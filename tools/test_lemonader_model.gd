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
	var machine: Node = load("res://scenes/objects/lemonader.tscn").instantiate()
	world.add_child(machine)
	machine.refresh_display()
	for kind in ["Sugar", "Fruit", "Ice"]:
		var panel: Node = machine.get_node("StockPanels/" + kind)
		check(panel.get_node("Empty").visible, kind + " empty panel shows X")
		check(panel.get_node("Quantity").text == "0", kind + " empty count is zero")
		for icon in panel.get_node("Icons").get_children():
			check(not icon.visible, kind + " empty panel hides icons")
	machine.machine_state["stock"]["sugar"] = 1.5
	machine.machine_state["stock"]["ice"] = 4.0
	machine.refresh_display()
	check(machine.get_node("StockPanels/Sugar/Icons/sugar").visible, "sugar icon when stocked")
	check(machine.get_node("StockPanels/Ice/Icons/ice").visible, "ice icon when stocked")
	check(machine.get_node("StockPanels/Sugar/Quantity").text == "1.5", "fractional sugar count")
	for fruit in root.get_node("GameState").FRUIT_TYPES:
		machine.machine_state["fruit"] = fruit
		machine.machine_state["stock"]["fruit"] = 3.0
		machine.refresh_display()
		var fruit_panel: Node = machine.get_node("StockPanels/Fruit")
		check(not fruit_panel.get_node("Empty").visible, "stocked fruit hides X")
		check(fruit_panel.get_node("Quantity").text == "3", "fruit count below icon")
		for icon in fruit_panel.get_node("Icons").get_children():
			check(icon.visible == (str(icon.name) == fruit), "only loaded fruit icon is visible")
	machine.machine_state["stock"]["fruit"] = 0.0
	machine.refresh_display()
	check(machine.get_node("StockPanels/Fruit/Empty").visible, "depleted fruit shows X again")
	for icon in machine.get_node("StockPanels/Fruit/Icons").get_children():
		check(not icon.visible, "depleted fruit hides previous fruit icon")
	var hoppers: Dictionary = machine.get("_hopper_meshes")
	for kind in ["sugar", "fruit", "ice"]:
		check(hoppers.has(kind), kind + " mesh has an imported blend shape")
		check(machine.has_node(kind.capitalize() + "Drop"), kind + " has a drop marker")
	var preview := machine.get_node("PitcherPoint/PitcherPreview") as Node3D
	var bottom := machine.get_node("PitcherPosition") as Node3D
	var bounds: AABB = machine.visual_bounds(preview)
	check(absf(bounds.position.y - bottom.global_position.y) < 0.0001, "pitcher bottom aligned")
	check(absf(preview.global_position.x - bottom.global_position.x) < 0.0001, "pitcher X aligned")
	check(absf(preview.global_position.z - bottom.global_position.z) < 0.0001, "pitcher Z aligned")
	var ingredients := { "sugar": "sugar", "fruit": "lemon", "ice": "ice" }
	for kind in ingredients:
		machine.animate_deposit(ingredients[kind], 2.0, Vector3(1, 1, 1))
	await create_timer(0.2).timeout
	for kind in ingredients:
		var mesh := hoppers.get(kind) as MeshInstance3D
		if mesh != null:
			check(mesh.get_blend_shape_value(0) > 0.99, kind + " opens to one before landing")
	await create_timer(0.7).timeout
	for kind in ingredients:
		var mesh := hoppers.get(kind) as MeshInstance3D
		if mesh != null:
			check(mesh.get_blend_shape_value(0) < 0.01, kind + " closes after final item")
	machine.animate_deposit("sugar", 4.0, Vector3(1, 1, 1))
	await create_timer(0.3).timeout
	machine.animate_deposit("sugar", 4.0, Vector3(1, 1, 1))
	await create_timer(0.45).timeout
	var sugar := hoppers.get("sugar") as MeshInstance3D
	if sugar != null:
		check(sugar.get_blend_shape_value(0) > 0.99, "overlapping deposits keep lid open")
	await create_timer(0.6).timeout
	if sugar != null:
		check(sugar.get_blend_shape_value(0) < 0.01, "last overlapping deposit closes lid")
	var visuals: Node = machine.get("_deposit_visuals")
	check(visuals.get_child_count() == 0, "flight visuals clean themselves up")
	machine.free()
	print("LEMONADER MODEL: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

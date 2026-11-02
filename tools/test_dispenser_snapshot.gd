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
	var sync: Node = load("res://tools/dispenser_snapshot_harness.gd").new()
	world.add_child(sync)
	var scene: PackedScene = load("res://scenes/objects/water_dispenser.tscn")
	var dispensers: Array[Node3D] = []
	var entries: Array[Dictionary] = []
	for index in range(2):
		var stand := Node3D.new()
		stand.name = "StandUnit" if index == 0 else "StandUnit2"
		world.add_child(stand)
		var dispenser: Node3D = scene.instantiate()
		dispenser.name = "WaterDispenser"
		stand.add_child(dispenser)
		dispenser.owner = world
		dispenser.set("stand_owner", str(stand.name))
		dispenser.position = Vector3(5 + index * 20, 1, 2)
		dispensers.append(dispenser)
		entries.append(sync.capture_container(dispenser))
	for dispenser in dispensers:
		dispenser.remove_meta("_net_id")
	sync.reset_client_ids()
	for entry in entries:
		sync.apply_container(entry, world)
	for index in range(2):
		var dispenser := dispensers[index]
		check(
			dispenser.global_position.is_equal_approx(Vector3(5 + index * 20, 1, 2)),
			"dispenser %d stays at authored position" % index,
		)
		check(
			dispenser.get("stand_owner") == ("StandUnit" if index == 0 else "StandUnit2"),
			"dispenser %d keeps stand owner" % index,
		)
		check(
			sync.get_net_id(dispenser) == entries[index]["net_id"],
			"dispenser %d receives its own network ID" % index,
		)
		check(
			sync.find_node_by_net_id(entries[index]["net_id"]) == dispenser,
			"dispenser %d resolves by ID" % index,
		)
	for entry in entries:
		sync.apply_container(entry, world)
	for index in range(2):
		var entry := entries[index].duplicate(true)
		entry["net_id"] = 100 + index
		sync.apply_container(entry, world)
		check(
			sync.get_net_id(dispensers[index]) == 100 + index,
			"new session rebinds dispenser %d ID" % index,
		)
		check(
			sync.find_node_by_net_id(100 + index) == dispensers[index],
			"new session resolves dispenser %d" % index,
		)
		check(
			sync.find_node_by_net_id(entries[index]["net_id"]) == null,
			"old dispenser %d ID removed" % index,
		)
	check(
		get_nodes_in_group("water_dispenser").size() == 2,
		"snapshot creates no duplicate dispensers",
	)
	world.free()
	print("Dispenser snapshot regression: %d failures" % failures)
	quit(1 if failures else 0)

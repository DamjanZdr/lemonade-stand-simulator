extends SceneTree

var failures := 0
var _last_hint := ""


func _record_hint(m: String) -> void:
	_last_hint = m


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
	var scene: PackedScene = load("res://scenes/objects/lemonader.tscn")
	var sync := root.get_node("WorldSync")
	var saves := root.get_node("SaveManager")
	for fruit in root.get_node("GameState").FRUIT_TYPES:
		var machine: Node = scene.instantiate()
		world.add_child(machine)
		machine.position = Vector3(3, 1, 3)
		check(saves.get_container_type(machine) == "lemonader", "save registration")
		check(machine.deposit(fruit, 5.0) == 5.0, fruit + " accepts first fruit")
		var other := "peach" if fruit != "peach" else "lemon"
		check(machine.deposit(other, 5.0) == 0.0, "rejects mixed fruit storage")
		check(machine.deposit("sugar", -1.0) == 0.0, "rejects negative deposit")
		check(machine.deposit("sugar", INF) == 0.0, "rejects infinite deposit")
		var recipe := { "fruit_count": 2.0, "water": 8.0, "sugar": 4.0, "ice": 1.0 }
		var before: Dictionary = machine.machine_state.duplicate(true)
		check(machine.start_batch(recipe) != "Mixing...", "requires pitcher")
		check(machine.machine_state == before, "failed start never consumes stock")
		machine.machine_state["pitcher"] = true
		check(machine.batch_problem(recipe).begins_with("Missing:"), "reports missing supplies")
		check(machine.deposit("water", 1.0) == 0.0, "plumbed machine rejects water")
		machine.deposit("sugar", 8.0)
		machine.deposit("ice", 2.0)
		check(machine.start_batch(recipe) == "Mixing...", "starts complete batch")
		check(machine.machine_state["stock"]["fruit"] == 3.0, "consumes exact fruit")
		check(machine.machine_state["stock"]["sugar"] == 4.0, "consumes exact sugar")
		before = machine.machine_state.duplicate(true)
		machine.start_batch(recipe)
		check(machine.machine_state == before, "second start does not consume twice")
		recipe["sugar"] = 0.0
		check(machine.machine_state["batch"]["sugar"] == 4.0, "batch recipe is immutable")
		var entry: Dictionary = sync.call("_serialize_container", machine)
		check(
			entry.get("machine_state") == machine.machine_state,
			"snapshot captures running batch",
		)
		var restored: Node = scene.instantiate()
		restored.machine_state = JSON.parse_string(JSON.stringify(machine.machine_state))
		world.add_child(restored)
		restored.finish_batch()
		check(restored.machine_state["stock"] == before["stock"], "resume never deducts twice")
		var output: Dictionary = restored.machine_state["output"]
		check(
			output["fruit_type"] == fruit and output["sugar"] == 4.0,
			"output matches locked batch",
		)
		restored.finish_batch()
		check(restored.machine_state["output"] == output, "finish is idempotent")
		var pitcher: Node = load("res://scenes/objects/pitcher.tscn").instantiate()
		world.add_child(pitcher)
		for key in ["fruit_type", "fruit_count", "water", "sugar", "ice"]:
			pitcher.set(key, output[key])
		var portion: Dictionary = pitcher.pour_portion()
		check(portion.get("fruit_type") == fruit, "machine output pours correct flavor")
		pitcher.free()
		restored.free()
		machine.finish_batch()
		machine.machine_state["output"] = { }
		var last_recipe := { "fruit_count": 3.0, "water": 7.0, "sugar": 4.0, "ice": 1.0 }
		check(machine.start_batch(last_recipe) == "Mixing...", "uses remaining fruit")
		machine.finish_batch()
		check(machine.deposit(other, 5.0) == 5.0, "empty hopper can change fruit")
		machine.free()
	var fixture: Node = scene.instantiate()
	world.add_child(fixture)
	var placement: Node = load("res://scripts/player/player_placement.gd").new()
	var decoration := Node3D.new()
	decoration.position.y = -20.0
	fixture.add_child(decoration)
	var offset: float = placement.call("_get_container_bottom_offset", fixture)
	check(
		is_equal_approx(offset, fixture.placement_bottom_offset()),
		"placement uses collision only",
	)
	check(offset > -0.01, "decorative origins cannot lift the machine")
	placement.free()
	var player: Node = load("res://scripts/player/player.gd").new()
	player.set_multiplayer_authority(1)
	world.add_child(player)
	var inventory: Node = load("res://scripts/player/player_inventory.gd").new()
	player.add_child(inventory)
	player.inventory = inventory
	inventory._player = player
	var placement2: Node = load("res://scripts/player/player_placement.gd").new()
	player.add_child(placement2)
	player.placement = placement2
	placement2._player = player
	player.hand_slot = Node3D.new()
	player.add_child(player.hand_slot)
	var items := root.get_node("HeldItem")
	for ingredient in ["lemon", "sugar", "ice"]:
		var held := { "ingredient_type": ingredient, "amount": 1.0, "source": "bin_scoop" }
		player.held_item = items.SUPPLY_BOX
		player.held_item_data = held
		inventory.held_item = items.SUPPLY_BOX
		inventory.held_item_data = held
		fixture.settle_inventory(player, "deposit", 1.0, { })
		check(inventory.held_item == items.NONE, "loose " + ingredient + " leaves no trash box")
	var stand_early: Node = load("res://scripts/stand/stand_unit.gd").new()
	player.assigned_stand = stand_early
	var box := { "ingredient_type": "sugar", "amount": 5.0, "source": "delivery" }
	player.held_item = items.SUPPLY_BOX
	player.held_item_data = box
	inventory.held_item = items.SUPPLY_BOX
	inventory.held_item_data = box
	fixture.execute_action(player, "deposit")
	check(
		fixture.machine_state["stock"]["sugar"] == 1.0,
		"delivery box deposits one unit per click",
	)
	check(float(inventory.held_item_data.get("amount", 0.0)) == 4.0, "box keeps the remainder")
	var preview := fixture.get_node("PitcherPoint/PitcherPreview")
	check(preview.get_meta("lemonader_host", null) == fixture, "slot preview routes to machine")
	check(
		preview.get_node_or_null("Pickupable") == null,
		"slot preview cannot be picked up directly",
	)
	fixture.machine_state["pitcher"] = true
	fixture.machine_state["output"] = {
		"fruit_type": "lemon",
		"fruit_count": 3.0,
		"water": 7.0,
		"sugar": 2.0,
		"ice": 1.0,
	}
	fixture.refresh_display()
	var phys := preview.get_node("Physics") as StaticBody3D
	check(phys.collision_layer == 1, "inserted preview is clickable")
	player.held_item = items.NONE
	player.held_item_data = { }
	inventory.held_item = items.NONE
	inventory.held_item_data = { }
	fixture.execute_action(player, "take")
	check(inventory.held_item == items.CONTAINER, "take yields the actual pitcher")
	check(
		float(inventory.held_item_data.get("saved_recipe", { }).get("sugar", 0.0)) == 2.0,
		"output recipe carried into held pitcher",
	)
	var hidden := 0
	for mesh in fixture.get_node("sqeeze-e-z").find_children("*", "MeshInstance3D", true, false):
		if not (mesh as MeshInstance3D).visible:
			hidden += 1
	check(hidden == 0, "machine meshes stay visible after take")
	check(phys.collision_layer == 0, "empty slot is not clickable")
	player.free()
	stand_early.free()
	var stand: Node = load("res://scripts/stand/stand_unit.gd").new()
	fixture.machine_state["fruit"] = "lemon"
	fixture.machine_state["pitcher"] = true
	fixture.machine_state["stock"] = { "fruit": 10.0, "sugar": 10.0, "ice": 10.0 }
	var before_board: Dictionary = fixture.machine_state.duplicate(true)
	var missing: String = fixture.start_from_board(stand)
	check(missing == "Please set a recipe on the board.", "unconfigured board refuses mixing")
	check(fixture.machine_state == before_board, "missing recipe consumes nothing")
	# Results go through the on-screen hint event, not a floating label.
	# (Autoloads aren't named-visible at test compile time — go via root.)
	var bus: Node = root.get_node("EventBus")
	var sig: Signal = bus.interaction_hint_changed
	if not sig.is_connected(_record_hint):
		sig.connect(_record_hint)
	fixture.show_result(missing)
	check(_last_hint == missing, "missing recipe message sent to UI hint")
	check(not fixture.has_method("open_menu"), "no machine recipe panel")
	stand.recipes["lemon"] = { "fruit_count": 3.0, "sugar": 2.0, "water": 99.0, "ice": 99.0 }
	stand.ice_degrees_per_scoop = 10.0
	root.get_node("GameState").temperature = 35.0
	var configured: Dictionary = fixture.board_recipe(stand)
	check(configured["fruit_count"] == 3.0 and configured["sugar"] == 2.0, "own board recipe")
	check(configured["water"] == 7.0, "plumbed water fills pitcher, board water ignored")
	check(configured["ice"] == 3.0, "ice auto-computed from temperature, board ice ignored")
	check(fixture.start_from_board(stand) == "Mixing...", "one-click board-driven mixing")
	check(
		bool(fixture.get_node("PitcherPoint/PitcherPreview").get("_suppress_eraser_updates")),
		"mixing animates the slot pitcher's fill",
	)
	stand.recipes["lemon"] = { "fruit_count": 5.0, "sugar": 1.0 }
	check(
		fixture.machine_state["batch"]["fruit_count"] == 3.0,
		"board edits do not alter running batch",
	)
	fixture.finish_batch()
	var inserted: Node = fixture.get_node("PitcherPoint/PitcherPreview")
	check(inserted.get_script().resource_path.ends_with("pitcher.gd"), "uses actual pitcher scene")
	check(
		inserted.fruit_count == 3.0 and inserted.sugar == 2.0,
		"inserted pitcher shows batch contents",
	)
	check(not inserted.is_in_group("container"), "inserted pitcher does not duplicate in saves")
	stand.free()
	fixture.free()
	# --- Machine pickup semantics (RMB machine+ pitcher / LMB pitcher-or-machine) ---
	var machine2: Node = scene.instantiate()
	world.add_child(machine2)
	machine2.position = Vector3(5, 1, 5)
	var player2: Node = load("res://scripts/player/player.gd").new()
	player2.set_multiplayer_authority(1)
	world.add_child(player2)
	var inventory2: Node = load("res://scripts/player/player_inventory.gd").new()
	player2.add_child(inventory2)
	player2.inventory = inventory2
	inventory2._player = player2
	var placement3: Node = load("res://scripts/player/player_placement.gd").new()
	player2.add_child(placement3)
	player2.placement = placement3
	placement3._player = player2
	player2.hand_slot = Node3D.new()
	player2.add_child(player2.hand_slot)
	player2.held_item = items.NONE
	player2.held_item_data = { }
	inventory2.held_item = items.NONE
	inventory2.held_item_data = { }
	var machine_pickupable := machine2.get_node_or_null("Pickupable")
	check(machine_pickupable != null, "machine body has a Pickupable for RMB pickup")
	check(
		machine_pickupable != null and bool(machine_pickupable.call("can_pick_up", player2)),
		"empty machine can be picked up",
	)
	# RMB with an inserted full pitcher picks up machine+pitcher together.
	machine2.machine_state["pitcher"] = true
	machine2.machine_state["output"] = {
		"fruit_type": "lemon",
		"fruit_count": 3.0,
		"water": 7.0,
		"sugar": 2.0,
		"ice": 1.0,
	}
	machine2.refresh_display()
	machine2.interact_secondary(player2)
	check(inventory2.held_item == items.CONTAINER, "RMB picks up the machine")
	check(
		inventory2.held_item_data.get("container_type") == "lemonader",
		"held container type is lemonader",
	)
	check(
		inventory2.held_item_data.get("source_node") == machine2,
		"original machine kept as source node",
	)
	check(not machine2.visible, "machine hidden while carried")
	check(machine2.get_parent() != null, "machine stays in tree while held")
	check(bool(machine2.machine_state["pitcher"]), "slot pitcher state travels with the machine")
	var carried_recipe: Dictionary = inventory2.held_item_data.get("saved_recipe", { })
	check(carried_recipe.get("pitcher", false) == true, "hand mesh gets machine state")
	# Place it back — the original node is restored, not respawned.
	var ghost_node := Node3D.new()
	world.add_child(ghost_node)
	ghost_node.global_transform = Transform3D(Basis(), Vector3(7, 1, 7))
	placement3._ghost = ghost_node
	placement3._ghost_valid = true
	var placed: Node = placement3._try_place_container()
	check(placed == machine2, "placement restores the same machine instance")
	check(machine2.visible, "machine visible again after place")
	check(bool(machine2.machine_state["pitcher"]), "placed machine still has its pitcher")
	check(inventory2.held_item == items.NONE, "hands free after placing the machine")
	# LMB on the inserted pitcher takes the pitcher only — machine stays.
	player2.held_item = items.NONE
	player2.held_item_data = { }
	inventory2.held_item = items.NONE
	inventory2.held_item_data = { }
	# execute_action enforces a 4m reach — stand next to the placed machine.
	player2.global_position = machine2.global_position + Vector3(0.0, 0.0, 1.5)
	machine2.execute_action(player2, "take")
	check(inventory2.held_item == items.CONTAINER, "LMB take yields a container")
	check(
		inventory2.held_item_data.get("container_type") == "pitcher",
		"LMB takes the pitcher, not the machine",
	)
	check(machine2.visible, "machine stays behind after pitcher take")
	check(not bool(machine2.machine_state["pitcher"]), "slot cleared after pitcher take")
	# LMB on the empty machine picks the machine up.
	inventory2.clear_held()
	player2.held_item = items.NONE
	player2.held_item_data = { }
	machine2.interact(player2)
	check(
		inventory2.held_item == items.CONTAINER
		and inventory2.held_item_data.get("container_type") == "lemonader",
		"LMB on an empty machine picks the machine up",
	)
	check(not machine2.visible, "empty machine hidden after LMB pickup")
	player2.free()
	machine2.free()
	print("LEMONADER: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)


func reload_hands(saves: Node, player: Node, data: Dictionary, stand: Node) -> void:
	player.inventory.clear_held()
	player.placement.destroy_ghost()
	if player.has_meta("_saved_inventory_restored"):
		player.remove_meta("_saved_inventory_restored")
	saves.apply_save_to_game_state(JSON.parse_string(JSON.stringify(data)))
	for frame in range(3):
		await process_frame
	if saves.is_world_restore_pending():
		await saves.world_restore_completed
	player.assigned_stand = stand
	player.assigned_stand_name = stand.name
	saves.restore_player_inventory(player)
	await physics_frame
	await physics_frame
	await process_frame


func _run() -> void:
	root.get_node("AchievementManager").set_script(load("res://tools/achievement_test_harness.gd"))
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var saves = root.get_node("SaveManager")
	root.get_node("GameState").game_mode = 2
	var stands: Array = []
	for name in ["StandUnit", "StandUnit2"]:
		var stand = load("res://tools/stand_access_test_harness.gd").new()
		stand.name = name
		stand.is_legacy_primary = name == "StandUnit"
		world.add_child(stand)
		stand.add_to_group("stand")
		stands.append(stand)
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.set_script(load("res://tools/local_player_test_actor.gd"))
	player.get_node("PlayerPlacement").set_script(load("res://tools/box_placement_test_harness.gd"))
	player.get_node("PlayerPlacement").workstation_scene = load("res://scenes/stand/workstation.tscn")
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(player)
	player.assigned_stand = stands[0]
	player.assigned_stand_name = stands[0].name
	var key: String = saves._player_inventory_key(player)
	var pitcher = load("res://scenes/objects/pitcher.tscn").instantiate()
	world.add_child(pitcher)
	pitcher.position = Vector3(2, 1, 3)
	pitcher.stand_owner = stands[0].name
	pitcher.fruit_type = "lemon"
	pitcher.fruit_count = 1.2
	pitcher.water = 4.8
	pitcher.sugar = 2.4
	pitcher.ice = 1.2
	pitcher.cups_poured = 4
	pitcher.state = 2
	pitcher.serving_recipe = {
		"fruit_type": "lemon", "fruit_count": 2.0, "sugar": 4.0,
		"water": 8.0, "ice": 2.0, "_initial_volume": 10.0,
	}
	player.placement.pickup_container(pitcher, "pitcher")
	await process_frame
	player.inventory.get_hand_mesh().pour_portion()
	var data: Dictionary = saves._build_save_dict()
	check(data.placed_containers.is_empty(), "carried pitcher is not duplicated in world save")
	check(data.player_inventories[key].data.saved_recipe.cups_poured == 5, "live held pour saved")
	await reload_hands(saves, player, data, stands[1])
	check(player.held_item == 4, "pitcher restored to same player's hands")
	check(player.inventory.get_hand_mesh().cups_poured == 5, "latest serving count restored")
	check(player.inventory.get_hand_mesh().serving_recipe.sugar == 4.0, "original batch restored")
	check(not stands[0].can_be_served_by(player), "stand change does not preserve old privileges")
	check(stands[1].can_be_served_by(player), "new stand access follows lobby assignment")
	check(get_nodes_in_group("pitcher").is_empty(), "no pitcher auto-placed at occupied old location")
	player.inventory.clear_held()
	var box = load("res://scenes/objects/supply_box.tscn").instantiate()
	box.is_equipment = true
	box.equipment_type = "lemonader"
	box.stand_owner = stands[0].name
	world.add_child(box)
	box.position = Vector3(4, 1, 3)
	box._pick_up_player(player)
	await process_frame
	data = saves._build_save_dict()
	check(data.supply_boxes.is_empty(), "carried equipment box not duplicated")
	await reload_hands(saves, player, data, stands[0])
	check(player.held_item == 3, "equipment box restored to hand")
	check(player.held_item_data.equipment_type == "lemonader", "equipment type retained")
	check(player.held_item_data.box_stand_owner == stands[0].name, "box belongs to new stand")
	player.inventory.set_held(3, {"ingredient_type": "sugar", "amount": 8.0})
	player.inventory.update_held_amount(3.0)
	data = saves._build_save_dict()
	await reload_hands(saves, player, data, stands[1])
	check(player.held_item_data.amount == 3.0, "partly consumed supply box restores remaining stock")
	player.inventory.set_held(2, {"recipe": {"color": Color(0.2, 0.3, 0.4, 0.8), "sugar": 4.0}})
	data = saves._build_save_dict()
	await reload_hands(saves, player, data, stands[0])
	check(player.held_item == 2 and player.held_item_data.recipe.color is Color, "cup color restored")
	player.inventory.clear_held()
	player.placement.destroy_ghost()
	var table = load("res://scenes/stand/workstation.tscn").instantiate()
	world.add_child(table)
	table.position = Vector3(6, 1, 3)
	table.stand_owner = stands[0].name
	table.add_to_group("container")
	var loaded_cup = load("res://scenes/objects/cup.tscn").instantiate()
	table.add_child(loaded_cup)
	loaded_cup.position = Vector3(0, 0.5, 0)
	loaded_cup.stand_owner = stands[0].name
	loaded_cup.restore_state(1, {"sugar": 4.0}, Color.YELLOW)
	loaded_cup.add_to_group("container")
	player.placement.pickup_container(table, "workstation")
	await process_frame
	data = saves._build_save_dict()
	check(data.placed_containers.size() == 2, "table and carried cup each saved once")
	check(data.placed_containers.any(
		func(entry): return entry.get("inventory_owner", "") == key,
	), "hidden source linked to player")
	await reload_hands(saves, player, data, stands[1])
	check(player.held_item == 4, "table restored to hand")
	var source: Variant = player.held_item_data.get("source_node")
	check(is_instance_valid(source) and not source.visible, "table source stays hidden")
	if is_instance_valid(source):
		check(source.stand_owner == stands[1].name, "table ownership transfers to selected stand")
	data = saves._build_save_dict()
	check(data.placed_containers.size() == 2, "restored table and cup are not duplicated")
	if is_instance_valid(source):
		check(source.get_children().any(
			func(node): return saves.get_container_type(node) == "cup",
		), "table keeps attached cup")
	player.inventory.clear_held()
	player.placement.destroy_ghost()
	if is_instance_valid(source):
		source.free()
	var machine = load("res://scenes/objects/lemonader.tscn").instantiate()
	machine.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(machine)
	machine.position = Vector3(8, 1, 3)
	machine.stand_owner = stands[1].name
	machine.machine_state.stock.sugar = 17.0
	machine.machine_state.pitcher = true
	machine.machine_state.output = {"fruit_type": "lemon", "sugar": 4.0, "color": Color.YELLOW}
	player.placement.pickup_container(machine, "lemonader")
	data = saves._build_save_dict()
	check(data.placed_containers.size() == 1, "machine preview and ghost are not saved as items")
	await reload_hands(saves, player, data, stands[0])
	source = player.held_item_data.get("source_node")
	check(is_instance_valid(source), "machine source restored for held appliance")
	if is_instance_valid(source):
		check(source.machine_state.stock.sugar == 17.0, "held machine keeps stock")
		check(source.machine_state.output.color is Color, "machine output color survives JSON")
		check(source.stand_owner == stands[0].name, "machine transfers to selected stand")
	player.inventory.clear_held()
	if is_instance_valid(source):
		source.free()
	data = saves._build_save_dict()
	await reload_hands(saves, player, data, stands[0])
	check(player.held_item == 0, "empty hands do not create a phantom item")
	saves._save_use_defaults = true
	check(saves._build_save_dict().player_inventories.is_empty(), "new save never inherits held items")
	saves._save_use_defaults = false
	await test_inventory_rpc(world, stands)
	var writer = load("res://tools/save_write_test_harness.gd").new()
	world.add_child(writer)
	DirAccess.make_dir_recursive_absolute("user://saves")
	var slot := "save-write-test-%d" % Time.get_ticks_usec()
	var path := "user://saves/" + slot + ".json"
	check(writer._write_save_atomic(path, {"value": 1}) == OK, "first save commits")
	writer.fail_replace = true
	writer.fail_target = path
	check(writer._write_save_atomic(path, {"value": 2}) != OK, "failed final rename reported")
	check(writer.load_slot(slot).value == 1, "failed final rename preserves previous save")
	writer.fail_replace = false
	check(writer._write_save_atomic(path, {"value": 3}) == OK, "replacement commits")
	check(writer._read_save_file(path + ".bak").value == 1, "backup keeps previous valid save")
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{incomplete")
	broken.close()
	check(writer.load_slot(slot).value == 1, "corrupt main falls back to backup")
	check(writer._write_save_atomic(path, {"value": 4}) == OK, "save can replace corrupt main")
	check(writer._read_save_file(path + ".bak").value == 1, "corrupt main never replaces good backup")
	DirAccess.remove_absolute(path)
	check(writer.load_slot(slot).value == 1, "missing main falls back to backup")
	var found := 0
	for info in writer.list_saves():
		if info.slot == slot:
			found += 1
	check(found == 1, "backup-only slot remains listed once")
	writer.delete_slot(slot)
	check(writer.load_slot(slot).is_empty(), "deleted slot cannot resurrect from backup")
	world.free()
	await process_frame
	print("SAVE PERSISTENCE: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)


func test_inventory_rpc(world: Node, stands: Array) -> void:
	var host := Node.new()
	host.name = "Host"
	world.add_child(host)
	var client := Node.new()
	client.name = "Client"
	world.add_child(client)
	var host_peer := ENetMultiplayerPeer.new()
	check(host_peer.create_server(0) == OK, "inventory RPC server starts")
	var client_peer := ENetMultiplayerPeer.new()
	check(client_peer.create_client(
		"127.0.0.1", host_peer.get_host().get_local_port(),
	) == OK, "inventory RPC client starts")
	var host_api := SceneMultiplayer.new()
	host_api.multiplayer_peer = host_peer
	set_multiplayer(host_api, host.get_path())
	var client_api := SceneMultiplayer.new()
	client_api.multiplayer_peer = client_peer
	set_multiplayer(client_api, client.get_path())
	var peer_id := client_peer.get_unique_id()
	var actors: Array = []
	for side in [host, client]:
		var actor = load("res://scenes/player/player.tscn").instantiate()
		actor.set_script(load("res://tools/local_player_test_actor.gd"))
		actor.get_node("PlayerInventory").set_script(
			load("res://tools/inventory_restore_test_harness.gd"),
		)
		actor.name = "Player"
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.set_multiplayer_authority(peer_id)
		side.add_child(actor)
		actor.assigned_stand = stands[1]
		actor.assigned_stand_name = stands[1].name
		actors.append(actor)
	for attempt in range(40):
		if host_api.get_peers().has(peer_id) and client_api.get_peers().has(1):
			break
		await create_timer(0.025).timeout
	check(host_api.get_peers().has(peer_id), "inventory test peers connect")
	actors[0].inventory.restore_saved_inventory.rpc_id(peer_id, 3, {
		"is_equipment": true, "equipment_type": "lemonader", "stand_name": stands[1].name,
	})
	for attempt in range(40):
		if actors[1].held_item == 3:
			break
		await create_timer(0.025).timeout
	check(actors[1].held_item == 3, "host restores remote owner's held box over RPC")
	check(is_instance_valid(actors[1].inventory.get_hand_mesh()), "remote hand mesh is rebuilt")
	check(actors[1].held_item_data.get("box_stand_owner") == stands[1].name,
		"remote restored box follows new stand")
	actors[1].inventory.restore_saved_inventory.rpc_id(1, 3, {"amount": 99.0})
	await create_timer(0.1).timeout
	check(actors[0].held_item == 0, "client cannot grant inventory using restore RPC")
	client_peer.close()
	host_peer.close()
	set_multiplayer(null, host.get_path())
	set_multiplayer(null, client.get_path())
	host.free()
	client.free()

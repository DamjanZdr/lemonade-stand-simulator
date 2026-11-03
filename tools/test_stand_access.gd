extends SceneTree

var failures := 0
var _interactable_script: Script


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	_interactable_script = load("res://scripts/core/interactable.gd")
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	var stand_script: Script = load("res://tools/stand_access_test_harness.gd")
	var first: Node = stand_script.new()
	first.name = "StandUnit"
	world.add_child(first)
	var second: Node = stand_script.new()
	second.name = "StandUnit2"
	world.add_child(second)
	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	player.set_script(load("res://tools/local_player_test_actor.gd"))
	player.name = "2"
	player.set_multiplayer_authority(2)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	players.add_child(player)
	player.assigned_stand = second
	player.assigned_stand_name = second.name
	var inventory: Node = load("res://tools/inventory_mesh_test_harness.gd").new()
	player.add_child(inventory)
	player.inventory = inventory
	check(inventory.clear_freed_mesh(), "clearing a freed hand mesh resets its cached reference")
	check(not first.can_be_served_by(player), "no remote peers does not grant rival stand access")
	check(second.can_be_served_by(player), "assigned stand remains usable without remote peers")
	var modes: Dictionary = load("res://scripts/autoloads/game_state.gd").get_script_constant_map()[
		"GameMode"
	]
	var item: Node = _interactable_script.new()
	item.stand_owner = second.name
	world.add_child(item)
	var shared: Node = _interactable_script.new()
	world.add_child(shared)
	var box: Node = load("res://scripts/objects/supply_box.gd").new()
	box.process_mode = Node.PROCESS_MODE_DISABLED
	box.stand_owner = first.name
	var sync := root.get_node("WorldSync")
	if sync.has_method("can_peer_use_object"):
		check(sync.can_peer_use_object(item, 2), "own stand request authorized")
		check(sync.can_peer_use_object(shared, 2), "shared interactable remains usable")
		check(sync.can_peer_use_object(box, 2), "rival box pickup allowed")
		check(not sync.can_peer_use_object(item, 99), "missing player rejected")
		player.assigned_stand = first
		player.assigned_stand_name = first.name
		check(not sync.can_peer_use_object(item, 2), "old stand access revoked after reassignment")
		item.stand_owner = first.name
		check(sync.can_peer_use_object(item, 2), "new stand access granted")
		player.assigned_stand = null
		player.assigned_stand_name = ""
		check(not sync.can_peer_use_object(item, 2), "unassigned player rejected")
	else:
		check(false, "host authorization helper exists")
	box.free()
	await _test_host_requests(world, player, first, second)
	var lobby: Node = load("res://tools/lobby_access_test_harness.gd").new()
	world.add_child(lobby)
	lobby.game_mode = modes.VERSUS
	lobby.roster = {
		1: { "stand_index": 0, "ready": false },
		2: { "stand_index": 1, "ready": false },
		3: { "stand_index": -1, "ready": false },
	}
	check(lobby.free_stand() == 0, "late join uses spare slot on occupied stand")
	lobby.roster[4] = { "stand_index": 0, "ready": false }
	check(lobby.free_stand() == 1, "late join skips a genuinely full stand")
	lobby.choose_stand(0)
	check(lobby.roster[3].stand_index == -1, "full stand selection rejected")
	lobby.choose_stand(1)
	check(lobby.roster[3].stand_index == 1, "stand with capacity accepted")
	lobby.choose_stand(8)
	check(lobby.roster[3].stand_index == 1, "invalid stand index rejected")
	lobby.roster[3].ready = true
	lobby.choose_stand(1)
	check(lobby.roster[3].ready, "reselecting current stand preserves ready state")
	lobby.game_mode = modes.COOP
	lobby.roster[3].stand_index = 0
	lobby.choose_stand(1)
	check(lobby.roster[3].stand_index == 0, "co-op cannot select hidden stand")
	lobby.roster.erase(4)
	lobby.game_mode = modes.VERSUS
	lobby.roster[3].stand_index = 1
	lobby.choose_stand(0)
	check(not lobby.roster[3].ready, "changing stand clears ready state")
	var saves: Node = load("res://tools/save_restore_test_harness.gd").new()
	world.add_child(saves)
	saves.respawn_placed_containers()
	saves.respawn_placed_containers()
	if saves.has_method("is_world_restore_pending"):
		check(saves.is_world_restore_pending(), "restore is pending before deferred work")
		while saves.is_world_restore_pending():
			await process_frame
	else:
		check(false, "save restore completion API exists")
		await process_frame
		await process_frame
	check(saves.restore_calls == 1, "duplicate restore requests are coalesced")
	world.free()
	await process_frame
	print("STAND ACCESS: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _test_host_requests(world: Node, player: Node, first: Node, second: Node) -> void:
	var host := Node.new()
	host.name = "Host"
	world.add_child(host)
	var client := Node.new()
	client.name = "Client"
	world.add_child(client)
	var server_peer := ENetMultiplayerPeer.new()
	check(server_peer.create_server(0) == OK, "local test server starts")
	var client_peer := ENetMultiplayerPeer.new()
	check(
		client_peer.create_client("127.0.0.1", server_peer.get_host().get_local_port()) == OK,
		"local test client starts",
	)
	var host_api := SceneMultiplayer.new()
	host_api.multiplayer_peer = server_peer
	set_multiplayer(host_api, host.get_path())
	var client_api := SceneMultiplayer.new()
	client_api.multiplayer_peer = client_peer
	set_multiplayer(client_api, client.get_path())
	var script: Script = load("res://tools/stand_request_test_harness.gd")
	var server: Node = script.new()
	server.name = "Sync"
	host.add_child(server)
	var remote: Node = script.new()
	remote.name = "Sync"
	client.add_child(remote)
	var peer_id := client_peer.get_unique_id()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.assigned_stand = second
	player.assigned_stand_name = second.name
	for attempt in range(40):
		if host_api.get_peers().has(peer_id) and client_api.get_peers().has(1):
			break
		await create_timer(0.025).timeout
	check(host_api.get_peers().has(peer_id), "local test peers connect")
	var item: Node = _interactable_script.new()
	item.name = "RequestTarget"
	item.stand_owner = first.name
	world.add_child(item)
	var net_id: int = server.register_object(item)
	remote.send_property(item, net_id, false)
	remote.send_call(item, net_id)
	await create_timer(0.1).timeout
	check(item.visible, "host rejects rival property and method requests over RPC")
	player.assigned_stand = first
	player.assigned_stand_name = first.name
	remote.send_property(item, net_id, false)
	await create_timer(0.1).timeout
	check(not item.visible, "host accepts own-stand property request over RPC")
	item.visible = true
	remote.send_call(item, net_id)
	await create_timer(0.1).timeout
	check(not item.visible, "host accepts own-stand method request over RPC")
	player.assigned_stand = second
	player.assigned_stand_name = second.name
	remote.send_despawn(item, net_id)
	await create_timer(0.1).timeout
	check(is_instance_valid(item), "host rejects rival equipment pickup over RPC")
	var box: Node = load("res://scenes/objects/supply_box.tscn").instantiate()
	box.stand_owner = first.name
	world.add_child(box)
	var box_id: int = server.register_object(box)
	remote.send_despawn(box, box_id)
	await create_timer(0.1).timeout
	check(not is_instance_valid(box), "host permits rival box pickup over RPC")
	client_peer.close()
	server_peer.close()
	set_multiplayer(null, host.get_path())
	set_multiplayer(null, client.get_path())
	host.free()
	client.free()
	player.name = "2"
	player.set_multiplayer_authority(2)

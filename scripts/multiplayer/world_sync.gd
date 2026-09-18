extends Node
## Helper for host-authoritative world object spawning. The host is the
## single source of truth for all world objects — only it spawns them,
## and it broadcasts spawn/despawn events to clients via RPCs.
##
## This uses a generic RPC approach instead of MultiplayerSpawner because
## world objects are parented to various nodes (truck grids, world root,
## stands, etc.) and MultiplayerSpawner only supports one spawn_path.
##
## Usage from any script (host only spawns; clients receive via RPC):
##   var obj = WorldSync.spawn_networked(scene, parent, pos, rot, state)
##   WorldSync.despawn_networked(obj)
##
## On the host: instantiates locally + sends RPC to clients.
## On clients: receives RPC and instantiates locally.

signal object_spawned(node: Node)
signal object_despawned(node_path: String)
## Emitted on a client after _apply_world_snapshot finishes instantiating
## everything — lets the late-join transition hold its loading screen
## until the world is actually ready.
signal world_snapshot_applied

## scene_path -> PackedScene cache
var _scene_cache: Dictionary = { }

## Counter for generating unique object names across all spawned objects.
var _spawn_counter: int = 0

## Cache of object name -> Node for fast lookup in RPCs. Avoids doing
## a full scene tree search every frame for transform syncs.
var _node_cache: Dictionary = { }

## Stable network ID system. Every object spawned through WorldSync gets a
## unique integer ID that survives reparenting, unlike name/path lookups.
const NET_ID_META := "_net_id"
var _net_id_counter: int = 0
var _net_id_to_node: Dictionary = { }
var _node_to_net_id: Dictionary = { }

## Host-side registry of all placed world objects. Used instead of scanning
## the "container"/"supply_box" groups, which can miss objects or include
## stale/duplicate entries on client join.
var _placed_objects: Dictionary = { }


func setup(_world_objects: Node, _spawner: MultiplayerSpawner) -> void:
	# Currently unused (we use RPC-based spawning instead of MultiplayerSpawner),
	# but kept for future use if we switch to spawner-based replication.
	pass


func is_host() -> bool:
	if multiplayer == null:
		# No multiplayer peer set up yet (or tree is being torn down). Treat
		# as local-host mode so single-player and initialization paths work.
		return true
	if multiplayer.multiplayer_peer == null:
		# No peer assigned — treat as local-host.
		return true
	return multiplayer.is_server()


## Broadcast an RPC to all peers, or skip the send when no multiplayer
## peer is active. is_host() is deliberately true with no peer
## (local-host mode), so a bare .rpc() in that state errors with
## ERR_UNCONFIGURED — and the world keeps ticking in the menu/lobby
## where no peer exists. Local work still runs; only the send is skipped.
func _broadcast(method: StringName, args: Array = []) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	callv("rpc", [method] + args)


## Send a client→host request (rpc_id(1)) only when a peer is active —
## same ERR_UNCONFIGURED guard as _broadcast.
func _request_host(method: StringName, args: Array = []) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	callv("rpc_id", [1, method] + args)


## Find the local player (the one this peer has authority over).
## Returns null if no local player exists yet. In single-player, returns
## the first player found.
static func get_local_player() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return null
	for p in tree.current_scene.find_children("*", "Player", true, false):
		if p.is_multiplayer_authority():
			return p
	# Fallback: first player (single-player or not yet claimed authority).
	var players := tree.get_nodes_in_group("player")
	if not players.is_empty():
		return players[0]
	return null


## Returns the StandUnit node name the local player is assigned to,
## or "" if no stand is assigned. Used by delivery signals to route
## orders to the correct stand's DeliverySystem.
static func get_local_stand_name() -> String:
	var p := get_local_player()
	if p == null:
		return ""
	var stand: Node = p.get("assigned_stand")
	if stand != null and is_instance_valid(stand):
		return stand.name
	return ""


## Returns the StandUnit node the local player is assigned to, or null.
static func get_local_stand() -> Node:
	var p := get_local_player()
	if p == null:
		return null
	var stand: Node = p.get("assigned_stand")
	if stand != null and is_instance_valid(stand):
		return stand
	return null


## Spend money from the local player's assigned stand.
## Falls back to GameState for single-player / legacy primary stand.
## Returns true if the money was spent successfully.
static func spend_local_money(amount: float) -> bool:
	var stand := get_local_stand()
	if stand != null and stand.has_method("spend_money"):
		return stand.spend_money(amount)
	return GameState.spend_money(amount)


## Assign a stable network ID to a node. Returns the ID. If the node is
## freed, the ID is automatically unregistered.
func _assign_net_id(obj: Node) -> int:
	var id := _net_id_counter
	_net_id_counter += 1
	obj.set_meta(NET_ID_META, id)
	_net_id_to_node[id] = obj
	_node_to_net_id[obj] = id
	_placed_objects[id] = obj
	obj.tree_exited.connect(_on_net_object_tree_exited.bind(id))
	return id


func get_net_id(obj: Node) -> int:
	if obj == null or not is_instance_valid(obj):
		return -1
	if obj.has_meta(NET_ID_META):
		return obj.get_meta(NET_ID_META) as int
	return -1


func _get_net_id(obj: Node) -> int:
	return get_net_id(obj)


func _find_node_by_net_id(net_id: int) -> Node:
	if net_id < 0:
		return null
	var node: Node = _net_id_to_node.get(net_id, null)
	if node != null and is_instance_valid(node):
		return node
	# If the node is no longer valid, clean the stale entry.
	_net_id_to_node.erase(net_id)
	return null


## Public wrapper for finding a networked object by its net_id.
func find_node_by_net_id(net_id: int) -> Node:
	return _find_node_by_net_id(net_id)


func _on_net_object_tree_exited(net_id: int) -> void:
	var node: Node = _net_id_to_node.get(net_id, null)
	# tree_exited also fires on remove_child() during reparenting (delivery
	# truck arcs, workstation item attachments, client-side pickup
	# prediction). Only unregister when the node is actually being deleted —
	# otherwise the surviving node loses its stable id and later despawn /
	# state RPCs can no longer find it, leaving stale duplicates on peers.
	if node == null or not is_instance_valid(node) or not node.is_queued_for_deletion():
		return
	_node_to_net_id.erase(node)
	_net_id_to_node.erase(net_id)
	_placed_objects.erase(net_id)


## Public helper to remove a stale name from the node cache.
## Used when a peer disconnects and its player node is freed.
func erase_node_cache(obj_name: String) -> void:
	_node_cache.erase(obj_name)


## Send a full snapshot of all placed containers and supply boxes to
## clients. Called after the host respawns saved/default containers.
## This ensures clients see objects that were placed before they joined
## or that were loaded from a save.
func sync_world_state_to_clients() -> void:
	if not is_host():
		return
	var snapshot := _collect_world_snapshot()
	if snapshot.is_empty():
		return
	_broadcast(&"_apply_world_snapshot", [snapshot])


## Same as sync_world_state_to_clients but only sent to a specific peer.
## Used when a client joins mid-game (late join).
## Always sends — even an empty snapshot — so the joiner knows the world
## state push completed and can leave its loading screen.
func sync_world_state_to_peer(peer_id: int) -> void:
	if not is_host():
		return
	var snapshot := _collect_world_snapshot()
	_apply_world_snapshot.rpc_id(peer_id, snapshot)


## Collects all containers and supply boxes in the world into a
## serializable dictionary. Each entry has: scene_path, name, net_id,
## position, rotation, scale, and state (contents/amounts).
func _collect_world_snapshot() -> Dictionary:
	var containers: Array = []
	var supply_boxes: Array = []
	if get_tree() == null or get_tree().current_scene == null:
		return { }
	_ensure_default_objects_registered()
	var to_remove: Array[int] = []
	for net_id in _placed_objects.keys():
		var node: Node = _placed_objects[net_id]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			to_remove.append(net_id)
			continue
		if node.is_in_group("ghost"):
			continue
		if node.is_in_group("container"):
			var entry := _serialize_container(node)
			if entry != null:
				containers.append(entry)
		elif node.is_in_group("supply_box"):
			var entry := _serialize_supply_box(node)
			if entry != null:
				supply_boxes.append(entry)
	for id in to_remove:
		_placed_objects.erase(id)
	return { "containers": containers, "supply_boxes": supply_boxes }


## Ensure default-scene objects (not spawned through WorldSync) are in the
## host registry so they are included in snapshots and can be looked up by
## net_id. Called once per snapshot.
func _ensure_default_objects_registered() -> void:
	for group in ["container", "supply_box"]:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			var net_id := get_net_id(node)
			if net_id < 0:
				net_id = _assign_net_id(node)
			_placed_objects[net_id] = node


func _serialize_container(node: Node) -> Dictionary:
	var ctype := SaveManager._get_container_type(node)
	if ctype == "" or not SaveManager._is_known_container_type(ctype):
		return { }
	var scene_path: String = ""
	match ctype:
		"fruit_bin":
			scene_path = "res://scenes/objects/fruit_bin.tscn"
		"sugar_bin":
			scene_path = "res://scenes/objects/sugar_bin.tscn"
		"ice_bin":
			scene_path = "res://scenes/objects/ice_bin.tscn"
		"cup_stack":
			scene_path = "res://scenes/objects/cup_stack.tscn"
		"pitcher":
			scene_path = "res://scenes/objects/pitcher.tscn"
		"press":
			scene_path = "res://scenes/objects/press.tscn"
		"water_dispenser":
			scene_path = "res://scenes/objects/water_dispenser.tscn"
		"workstation":
			scene_path = "res://scenes/stand/workstation.tscn"
		_:
			return { }
	var net_id := _get_net_id(node)
	if net_id < 0:
		net_id = _assign_net_id(node)
	var entry := {
		"scene_path": scene_path,
		"name": node.name,
		"net_id": net_id,
		"ctype": ctype,
		"position": [node.global_position.x, node.global_position.y, node.global_position.z],
		"rotation": [node.global_rotation.x, node.global_rotation.y, node.global_rotation.z],
		"scale": [node.scale.x, node.scale.y, node.scale.z],
		"stand_owner": node.get("stand_owner") if "stand_owner" in node else "",
	}
	# Capture container-specific state
	if node is FruitBin:
		var fb := node as FruitBin
		var amounts: Array = []
		for key in fb.fruit_amounts:
			amounts.append([key, fb.fruit_amounts[key]])
		entry["fruit_amounts"] = amounts
	elif node is IngredientBin:
		var ib := node as IngredientBin
		entry["current_amount"] = ib.current_amount
		entry["ingredient_type"] = ib.ingredient_type
	elif node is Pitcher:
		var p := node as Pitcher
		entry["fruit_type"] = p.fruit_type
		entry["fruit_count"] = p.fruit_count
		entry["water"] = p.water
		entry["sugar"] = p.sugar
		entry["ice"] = p.ice
		entry["cups_poured"] = p.cups_poured
		entry["pitcher_state"] = int(p.state)
	elif node is CupStack:
		entry["current_count"] = (node as CupStack).current_count
	elif node is WaterDispenser:
		entry["water_fillings"] = (node as WaterDispenser).max_fillings
	elif node is Press:
		entry["fruit_type"] = (node as Press).fruit_type
		entry["fruit_count"] = (node as Press).fruit_count
	return entry


func _serialize_supply_box(node: Node) -> Dictionary:
	var box := node as SupplyBox
	if box == null:
		return { }
	var net_id := _get_net_id(node)
	if net_id < 0:
		net_id = _assign_net_id(node)
	return {
		"scene_path": "res://scenes/objects/supply_box.tscn",
		"name": box.name,
		"net_id": net_id,
		"position": [box.global_position.x, box.global_position.y, box.global_position.z],
		"rotation": [box.global_rotation.x, box.global_rotation.y, box.global_rotation.z],
		"scale": [box.scale.x, box.scale.y, box.scale.z],
		"ingredient_type": box.ingredient_type,
		"quantity": box.quantity,
		"is_equipment": box.is_equipment,
		"equipment_type": box.equipment_type,
		"stand_owner": box.stand_owner,
		"delivery_cell_idx": box.get_meta("delivery_cell_idx", -1) as int,
		"delivery_grid_path": str(box.get_meta("delivery_grid_path", "")),
	}


## Clients receive the full world snapshot and instantiate all
## containers and supply boxes to match the host's world.
## Instantiation is chunked across frames — a mid-game world can hold
## hundreds of objects and spawning them all in one call freezes the
## client for seconds (the "0.1 fps on join" hitch).
@rpc("authority", "call_local", "reliable")
func _apply_world_snapshot(snapshot: Dictionary) -> void:
	if is_host():
		return
	var root := get_tree().current_scene
	if root == null:
		world_snapshot_applied.emit()
		return
	_clear_client_world_objects()
	# Spawn containers + supply boxes, yielding periodically so the frame
	# stays responsive (the late-join Day X screen can keep animating).
	var spawned_since_yield := 0
	for entry in snapshot.get("containers", []):
		_spawn_container_from_snapshot(entry, root)
		spawned_since_yield += 1
		if spawned_since_yield >= 12:
			spawned_since_yield = 0
			await get_tree().process_frame
	for entry in snapshot.get("supply_boxes", []):
		_spawn_supply_box_from_snapshot(entry, root)
		spawned_since_yield += 1
		if spawned_since_yield >= 12:
			spawned_since_yield = 0
			await get_tree().process_frame
	GameLog.log(
		"[WorldSync] Applied world snapshot: %d containers, %d supply boxes"
		% [snapshot.get("containers", []).size(), snapshot.get("supply_boxes", []).size()]
	)
	world_snapshot_applied.emit()


func _clear_client_world_objects() -> void:
	var removed: Dictionary = { }
	for group_name in ["container", "supply_box"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if node.is_in_group("ghost") or removed.has(node.get_instance_id()):
				continue
			var ctype := SaveManager._get_container_type(node)
			if group_name == "container" and not SaveManager._is_known_container_type(ctype):
				continue
			removed[node.get_instance_id()] = true
			_node_cache.erase(node.name)
			# queue_free() first so tree_exited sees is_queued_for_deletion()
			# and the net_id registration is dropped alongside the node.
			node.queue_free()
			var parent := node.get_parent()
			if parent != null:
				parent.remove_child(node)


func _spawn_container_from_snapshot(entry: Dictionary, root: Node) -> void:
	var scene_path: String = entry.get("scene_path", "")
	if scene_path == "":
		return
	var scene := _get_scene(scene_path)
	if scene == null:
		return
	var obj_name: String = entry.get("name", "")
	# If an object with this name already exists under the expected root,
	# update its transform/contents instead of spawning a duplicate.
	var existing := root.get_node_or_null(obj_name)
	if existing != null:
		_update_container_from_snapshot(existing, entry)
		return
	var instance := scene.instantiate()
	# Set state BEFORE add_child so _ready() sees correct values
	var ctype: String = entry.get("ctype", "")
	if instance is CupStack:
		instance.starting_count = int(entry.get("current_count", instance.starting_count))
	if instance is WaterDispenser:
		instance.water_fillings = int(entry.get("water_fillings", instance.water_fillings))
	if instance is Press:
		instance.fruit_type = entry.get("fruit_type", "")
		instance.fruit_count = float(entry.get("fruit_count", 0.0))
	if instance is IngredientBin:
		instance.ingredient_type = entry.get("ingredient_type", "")
	if "stand_owner" in instance:
		instance.stand_owner = entry.get("stand_owner", "")
	# Apply scale before adding to tree
	var scl: Array = entry.get("scale", [1.0, 1.0, 1.0])
	if scl.size() >= 3:
		instance.scale = Vector3(scl[0], scl[1], scl[2])
	instance.name = obj_name
	var net_id: int = entry.get("net_id", -1)
	if net_id >= 0:
		instance.set_meta(NET_ID_META, net_id)
		_net_id_to_node[net_id] = instance
		_node_to_net_id[instance] = net_id
		instance.tree_exited.connect(_on_net_object_tree_exited.bind(net_id))
	root.add_child(instance)
	var pos: Array = entry.get("position", [0, 0, 0])
	var rot: Array = entry.get("rotation", [0, 0, 0])
	instance.global_position = Vector3(pos[0], pos[1], pos[2])
	instance.global_rotation = Vector3(
		rot[0] if rot.size() > 0 else 0.0,
		rot[1] if rot.size() > 1 else 0.0,
		rot[2] if rot.size() > 2 else 0.0,
	)
	instance.add_to_group("container")
	# Restore contents AFTER _ready() has run
	if instance is FruitBin:
		var fb := instance as FruitBin
		var amounts: Array = entry.get("fruit_amounts", [])
		fb.fruit_amounts.clear()
		for pair in amounts:
			if pair is Array and pair.size() >= 2:
				fb.fruit_amounts[pair[0]] = pair[1]
		fb.update_display()
	elif instance is IngredientBin:
		var ib := instance as IngredientBin
		ib.current_amount = float(entry.get("current_amount", 0.0))
		ib.update_display()
	elif instance is Pitcher:
		var p := instance as Pitcher
		p.fruit_type = entry.get("fruit_type", "")
		p.fruit_count = float(entry.get("fruit_count", 0.0))
		p.water = float(entry.get("water", 0.0))
		p.sugar = float(entry.get("sugar", 0.0))
		p.ice = float(entry.get("ice", 0.0))
		p.cups_poured = int(entry.get("cups_poured", 0))
		p.state = int(entry.get("pitcher_state", 0)) as Pitcher.PitcherState
		p.add_to_group("pitcher")
		p.set_pitcher_visible(true)
		p.sync_fill_display()
		p.update_liquid_color()
		p.call_deferred("update_label")
	# Cache for fast lookup
	_node_cache[instance.name] = instance


## Update an existing container (e.g. default scene object) from a snapshot
## entry instead of spawning a duplicate.
func _update_container_from_snapshot(existing: Node, entry: Dictionary) -> void:
	var net_id: int = entry.get("net_id", -1)
	if net_id >= 0 and _get_net_id(existing) < 0:
		existing.set_meta(NET_ID_META, net_id)
		_net_id_to_node[net_id] = existing
		_node_to_net_id[existing] = net_id
		existing.tree_exited.connect(_on_net_object_tree_exited.bind(net_id))
	var pos: Array = entry.get("position", [0, 0, 0])
	var rot: Array = entry.get("rotation", [0, 0, 0])
	var scl: Array = entry.get("scale", [1.0, 1.0, 1.0])
	if existing is Node3D:
		existing.global_position = Vector3(pos[0], pos[1], pos[2])
		existing.global_rotation = Vector3(
			rot[0] if rot.size() > 0 else 0.0,
			rot[1] if rot.size() > 1 else 0.0,
			rot[2] if rot.size() > 2 else 0.0,
		)
		if scl.size() >= 3:
			existing.scale = Vector3(scl[0], scl[1], scl[2])
	if "stand_owner" in existing:
		existing.stand_owner = entry.get("stand_owner", "")
	if existing is FruitBin:
		var fb := existing as FruitBin
		var amounts: Array = entry.get("fruit_amounts", [])
		fb.fruit_amounts.clear()
		for pair in amounts:
			if pair is Array and pair.size() >= 2:
				fb.fruit_amounts[pair[0]] = pair[1]
		fb.update_display()
	elif existing is IngredientBin:
		var ib := existing as IngredientBin
		ib.current_amount = float(entry.get("current_amount", 0.0))
		ib.update_display()
	elif existing is Pitcher:
		var p := existing as Pitcher
		p.fruit_type = entry.get("fruit_type", "")
		p.fruit_count = float(entry.get("fruit_count", 0.0))
		p.water = float(entry.get("water", 0.0))
		p.sugar = float(entry.get("sugar", 0.0))
		p.ice = float(entry.get("ice", 0.0))
		p.cups_poured = int(entry.get("cups_poured", 0))
		p.state = int(entry.get("pitcher_state", 0)) as Pitcher.PitcherState
		p.add_to_group("pitcher")
		p.set_pitcher_visible(true)
		p.sync_fill_display()
		p.update_liquid_color()
		p.call_deferred("update_label")
	elif existing is CupStack:
		existing.starting_count = int(entry.get("current_count", existing.starting_count))
	elif existing is WaterDispenser:
		existing.water_fillings = int(entry.get("water_fillings", existing.water_fillings))
	elif existing is Press:
		existing.fruit_type = entry.get("fruit_type", "")
		existing.fruit_count = float(entry.get("fruit_count", 0.0))
	_node_cache[existing.name] = existing


func _spawn_supply_box_from_snapshot(entry: Dictionary, root: Node) -> void:
	var scene := _get_scene("res://scenes/objects/supply_box.tscn")
	if scene == null:
		return
	var box_name: String = entry.get("name", "")
	var existing := root.get_node_or_null(box_name) as SupplyBox
	if existing != null:
		_update_supply_box_from_snapshot(existing, entry)
		return
	var box := scene.instantiate() as SupplyBox
	box.ingredient_type = entry.get("ingredient_type", "lemon")
	box.quantity = float(entry.get("quantity", 10.0))
	box.is_equipment = bool(entry.get("is_equipment", false))
	box.equipment_type = entry.get("equipment_type", "")
	box.stand_owner = entry.get("stand_owner", "")
	var scl: Array = entry.get("scale", [1.0, 1.0, 1.0])
	if scl.size() >= 3:
		box.scale = Vector3(scl[0], scl[1], scl[2])
	box.name = box_name
	var net_id: int = entry.get("net_id", -1)
	if net_id >= 0:
		box.set_meta(NET_ID_META, net_id)
		_net_id_to_node[net_id] = box
		_node_to_net_id[box] = net_id
		box.tree_exited.connect(_on_net_object_tree_exited.bind(net_id))
	root.add_child(box)
	var pos: Array = entry.get("position", [0, 0, 0])
	var rot: Array = entry.get("rotation", [0, 0, 0])
	box.global_position = Vector3(pos[0], pos[1], pos[2])
	box.global_rotation = Vector3(
		rot[0] if rot.size() > 0 else 0.0,
		rot[1] if rot.size() > 1 else 0.0,
		rot[2] if rot.size() > 2 else 0.0,
	)
	box.add_to_group("supply_box")
	_node_cache[box.name] = box
	# Restore delivery grid slot metas so clients can release the slot
	# when picking up the box.
	var cell_idx: int = entry.get("delivery_cell_idx", -1)
	if cell_idx >= 0:
		box.set_meta("delivery_cell_idx", cell_idx)
		var grid_path_str: String = entry.get("delivery_grid_path", "")
		if grid_path_str != "":
			box.set_meta("delivery_grid_path", NodePath(grid_path_str))


## Update an existing supply box from a snapshot entry instead of spawning
## a duplicate.
func _update_supply_box_from_snapshot(existing: SupplyBox, entry: Dictionary) -> void:
	var net_id: int = entry.get("net_id", -1)
	if net_id >= 0 and _get_net_id(existing) < 0:
		existing.set_meta(NET_ID_META, net_id)
		_net_id_to_node[net_id] = existing
		_node_to_net_id[existing] = net_id
		existing.tree_exited.connect(_on_net_object_tree_exited.bind(net_id))
	existing.ingredient_type = entry.get("ingredient_type", "lemon")
	existing.quantity = float(entry.get("quantity", 10.0))
	existing.is_equipment = bool(entry.get("is_equipment", false))
	existing.equipment_type = entry.get("equipment_type", "")
	var pos: Array = entry.get("position", [0, 0, 0])
	var rot: Array = entry.get("rotation", [0, 0, 0])
	var scl: Array = entry.get("scale", [1.0, 1.0, 1.0])
	existing.global_position = Vector3(pos[0], pos[1], pos[2])
	existing.global_rotation = Vector3(
		rot[0] if rot.size() > 0 else 0.0,
		rot[1] if rot.size() > 1 else 0.0,
		rot[2] if rot.size() > 2 else 0.0,
	)
	if scl.size() >= 3:
		existing.scale = Vector3(scl[0], scl[1], scl[2])
	existing.update_metrics()
	_node_cache[existing.name] = existing
	# Restore delivery grid slot metas for existing boxes too.
	var cell_idx: int = entry.get("delivery_cell_idx", -1)
	if cell_idx >= 0:
		existing.set_meta("delivery_cell_idx", cell_idx)
		var grid_path_str: String = entry.get("delivery_grid_path", "")
		if grid_path_str != "":
			existing.set_meta("delivery_grid_path", NodePath(grid_path_str))


## The node where world objects should be added. All spawned world objects
## go here so they're easy to find and manage.
func get_world_objects() -> Node:
	var root := get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("WorldObjects")


## Request a spawn from any peer. On the host, spawns directly and returns
## the node. On a client, sends an RPC to the host to spawn and returns
## null (the client will receive the replicated object via _spawn_on_clients).
## All player-placed objects should use this instead of instantiating locally.
func request_spawn(scene_path: String, pos: Vector3, rot: Vector3, state: Dictionary = { }) -> Node:
	if is_host():
		return spawn_networked(scene_path, get_world_objects(), pos, rot, state)
	_request_host(&"_rpc_request_spawn", [scene_path, pos, rot, state])
	return null


@rpc("any_peer", "reliable")
func _rpc_request_spawn(scene_path: String, pos: Vector3, rot: Vector3, state: Dictionary) -> void:
	if not is_host():
		return
	var authoritative_state := state.duplicate(true)
	var sender := multiplayer.get_remote_sender_id()
	var root := get_tree().current_scene
	var player := root.get_node_or_null("Players/" + str(sender)) as Player if root else null
	if player != null:
		var stand_name := player.assigned_stand_name
		if player.assigned_stand != null and is_instance_valid(player.assigned_stand):
			stand_name = player.assigned_stand.name
		if stand_name != "":
			authoritative_state["stand_owner"] = stand_name
	spawn_networked(scene_path, get_world_objects(), pos, rot, authoritative_state)


func request_pitcher_snap(target: Node, recipe: Dictionary, stand_owner: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	var net_id := get_net_id(target)
	var target_type := "press" if target is Press else "water_dispenser"
	if is_host():
		var accepted := _apply_pitcher_snap(net_id, target_type, recipe, stand_owner)
		_apply_pitcher_snap_result(accepted, target_type)
	else:
		_request_host(&"_rpc_request_pitcher_snap", [net_id, target_type, recipe, stand_owner])


@rpc("any_peer", "reliable")
func _rpc_request_pitcher_snap(
	net_id: int,
	target_type: String,
	recipe: Dictionary,
	stand_owner: String,
) -> void:
	if not is_host():
		return
	var requester := multiplayer.get_remote_sender_id()
	var root := get_tree().current_scene
	var player := root.get_node_or_null("Players/" + str(requester)) as Player if root else null
	if player != null:
		if player.assigned_stand != null and is_instance_valid(player.assigned_stand):
			stand_owner = player.assigned_stand.name
		elif player.assigned_stand_name != "":
			stand_owner = player.assigned_stand_name
	var accepted := _apply_pitcher_snap(net_id, target_type, recipe, stand_owner)
	_apply_pitcher_snap_result.rpc_id(requester, accepted, target_type)


func _apply_pitcher_snap(
	net_id: int,
	target_type: String,
	recipe: Dictionary,
	stand_owner: String,
) -> bool:
	var target := _find_node_by_net_id(net_id)
	if target is Interactable and target.stand_owner != "" and target.stand_owner != stand_owner:
		return false
	if target_type == "press" and target is Press:
		return target.apply_pitcher_snap_request(recipe, stand_owner)
	if target_type == "water_dispenser" and target is WaterDispenser:
		return target.apply_pitcher_snap_request(recipe, stand_owner)
	return false


@rpc("authority", "call_local", "reliable")
func _apply_pitcher_snap_result(accepted: bool, target_type: String) -> void:
	var player := get_local_player()
	if player == null or player.held_item != HeldItem.CONTAINER:
		return
	if player.held_item_data.get("container_type", "") != "pitcher":
		return
	if not player.held_item_data.get("snap_pending", false):
		return
	player.held_item_data.erase("snap_pending")
	if accepted:
		player.placement._destroy_ghost()
		player.inventory.clear_held()
	else:
		var label := "Press" if target_type == "press" else "Water dispenser"
		EventBus.interaction_hint_changed.emit(label + " could not accept pitcher")


func request_container_action(obj: Node, action: String, args: Array) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var net_id := get_net_id(obj)
	if is_host():
		_apply_container_action(net_id, action, args)
	else:
		_request_host(&"_rpc_request_container_action", [net_id, action, args])


@rpc("any_peer", "reliable")
func _rpc_request_container_action(net_id: int, action: String, args: Array) -> void:
	if not is_host():
		return
	_apply_container_action(net_id, action, args)


func _apply_container_action(net_id: int, action: String, args: Array) -> void:
	var obj := _find_node_by_net_id(net_id)
	if obj is IngredientBin:
		if action == "add" and args.size() >= 2:
			obj._apply_add_amount(float(args[0]), args[1] as Vector3)
			obj._sync_state_to_peers(args[1] as Vector3)
		elif action == "take" and not args.is_empty():
			obj._apply_take_amount(float(args[0]))
			obj._sync_state_to_peers()
	elif obj is FruitBin:
		if action == "add" and args.size() >= 3:
			obj.add_amount(str(args[0]), float(args[1]), args[2] as Vector3)
		elif action == "take" and args.size() >= 2:
			obj.take_amount(str(args[0]), float(args[1]))
	elif obj is WaterDispenser:
		if action == "refill" and not args.is_empty():
			obj._apply_refill(int(args[0]))
		elif action == "start_fill" and not args.is_empty():
			obj._start_fill(float(args[0]))
		elif action == "finish_fill":
			obj._apply_finish_fill()
		elif action == "take_pitcher":
			obj._snapped_pitcher = null
			obj._pending_snap_pitcher_net_id = -1
			obj._is_filling = false
			obj._fill_progress = 0.0
			obj._reset_tap()


## Request a despawn from any peer. On the host, despawns directly.
## On a client, sends an RPC to the host.
func request_despawn(obj: Node, confirm_pickup: bool = false) -> void:
	if obj == null or not is_instance_valid(obj):
		GameLog.log("[WorldSync] request_despawn: obj is null/invalid")
		return
	var net_id := _get_net_id(obj)
	GameLog.log(
		"[WorldSync] request_despawn name=%s net_id=%d is_host=%s" % [obj.name, net_id, is_host()]
	)
	if is_host():
		despawn_networked(obj)
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	GameLog.log(
		"[WorldSync] Client sending despawn RPC to host: parent=%s name=%s net_id=%d"
		% [parent_path, obj.name, net_id]
	)
	_request_host(&"_rpc_request_despawn", [parent_path, obj.name, net_id, confirm_pickup])


@rpc("any_peer", "reliable")
func _rpc_request_despawn(
	parent_path_str: String,
	obj_name: String,
	net_id: int,
	confirm_pickup: bool,
) -> void:
	if not is_host():
		return
	var requester := multiplayer.get_remote_sender_id()
	GameLog.log(
		"[WorldSync] Host received despawn request: parent=%s name=%s net_id=%d"
		% [parent_path_str, obj_name, net_id]
	)
	# Prefer net_id lookup, fall back to name/path for pre-existing scene objects.
	var obj := _find_node_by_net_id(net_id)
	if obj == null:
		var parent := _string_to_node(parent_path_str)
		if parent != null:
			obj = parent.get_node_or_null(obj_name)
	if obj:
		despawn_networked(obj)
	else:
		GameLog.log("[WorldSync] Host despawn: object not found: " + obj_name)
	if confirm_pickup:
		await get_tree().create_timer(0.3).timeout
		_confirm_pickup_despawn.rpc_id(requester)


@rpc("authority", "reliable")
func _confirm_pickup_despawn() -> void:
	var player := get_local_player()
	if player != null:
		player.held_item_data.erase("pickup_pending")


## Request a thrown-trash pickup from any peer. On the host, picks up
## directly. On a client, sends an RPC to the host.
func request_thrown_trash_pickup(obj: Node, player_path: String) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var net_id := _get_net_id(obj)
	if is_host():
		_do_thrown_trash_pickup(net_id, player_path)
		return
	_request_host(&"_rpc_request_thrown_trash_pickup", [net_id, player_path])


@rpc("any_peer", "reliable")
func _rpc_request_thrown_trash_pickup(net_id: int, player_path: String) -> void:
	if not is_host():
		return
	_do_thrown_trash_pickup(net_id, player_path)


func _do_thrown_trash_pickup(net_id: int, player_path: String) -> void:
	var obj := _find_node_by_net_id(net_id)
	if obj == null or not is_instance_valid(obj):
		return
	if not obj is ThrownTrash:
		return
	var player := _string_to_node(player_path)
	if player == null or not is_instance_valid(player):
		return
	(obj as ThrownTrash).pickup_by(player)


## Spawn a world object on the host and replicate to all clients.
## 'state' is a Dictionary of property_name -> value pairs to set on the
## object before adding it to the tree (so its _ready sees them).
## Returns the spawned node on the host, null on clients.
func spawn_networked(
	scene_path: String,
	parent: Node,
	global_pos: Vector3,
	global_rot: Vector3,
	state: Dictionary = { },
) -> Node:
	if not is_host():
		return null
	var scene := _get_scene(scene_path)
	if scene == null:
		GameLog.log("[WorldSync] Failed to load scene: " + scene_path)
		return null
	var obj := scene.instantiate()
	# Set state BEFORE adding to tree so _ready() sees configured values.
	# Special keys starting with "_net_" are not properties — they're
	# post-spawn actions handled below.
	var net_groups: Array = state.get("_net_groups", [])
	var net_scale: Vector3 = state.get("_net_scale", Vector3.ZERO)
	var net_fruit_amounts: Dictionary = state.get("_net_fruit_amounts", { })
	var net_pitcher_recipe: Dictionary = state.get("_net_pitcher_recipe", { })
	var net_delivery_cell_idx: int = state.get("_net_delivery_cell_idx", -1)
	var net_delivery_grid_path: String = state.get("_net_delivery_grid_path", "")
	var clean_state := state.duplicate()
	clean_state.erase("_net_groups")
	clean_state.erase("_net_scale")
	clean_state.erase("_net_fruit_amounts")
	clean_state.erase("_net_pitcher_recipe")
	clean_state.erase("_net_delivery_cell_idx")
	clean_state.erase("_net_delivery_grid_path")
	for key in clean_state:
		obj.set(key, clean_state[key])
	# Give the object a unique name and stable network ID so despawn and
	# reparenting can find it reliably even when its path changes.
	var base_name := obj.name
	obj.name = base_name + "_" + str(_spawn_counter)
	_spawn_counter += 1
	var net_id := _assign_net_id(obj)
	parent.add_child(obj)
	obj.global_position = global_pos
	obj.global_rotation = global_rot
	# Apply scale from state if provided, otherwise use the object's current scale
	if net_scale != Vector3.ZERO:
		obj.scale = net_scale
	# Apply post-ready state (fruit amounts, pitcher recipe) AFTER
	# _ready() has run so the object's internal structures are set up.
	if not net_fruit_amounts.is_empty() and obj is FruitBin:
		(obj as FruitBin).fruit_amounts = net_fruit_amounts.duplicate()
		(obj as FruitBin).update_display()
	if not net_pitcher_recipe.is_empty() and obj is Pitcher:
		var p := obj as Pitcher
		p.fruit_type = net_pitcher_recipe.get("fruit_type", "")
		p.fruit_count = net_pitcher_recipe.get("fruit_count", 0.0)
		p.water = net_pitcher_recipe.get("water", 0.0)
		p.sugar = net_pitcher_recipe.get("sugar", 0.0)
		p.ice = net_pitcher_recipe.get("ice", 0.0)
		p.cups_poured = net_pitcher_recipe.get("cups_poured", 0)
		p.set_pitcher_visible(true)
		p.sync_fill_display()
		p.call_deferred("update_label")
	# Restore delivery grid slot metas so clients can release the slot
	# when picking up the box.
	if net_delivery_cell_idx >= 0:
		obj.set_meta("delivery_cell_idx", net_delivery_cell_idx)
		if net_delivery_grid_path != "":
			obj.set_meta("delivery_grid_path", NodePath(net_delivery_grid_path))
	# Capture the object's scale after adding to the parent (parent's
	# transform may affect it). We'll send this to clients so they
	# match the host's scale.
	var obj_scale: Vector3 = obj.scale
	# Broadcast to clients
	var parent_path := _node_path_to_string(parent.get_path())
	_broadcast(
		&"_spawn_on_clients",
		[scene_path, parent_path, obj.name, net_id, global_pos, global_rot, obj_scale, state],
	)
	return obj


## Despawn a world object on the host and tell all clients to despawn it too.
## If the object is a SupplyBox, also makes boxes above fall on the host
## and tells clients to do the same.
func despawn_networked(obj: Node) -> void:
	if not is_host():
		return
	if obj == null or not is_instance_valid(obj):
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	var obj_name := obj.name
	var net_id := _get_net_id(obj)
	# If this is a supply box, release any delivery-grid slot it occupies
	# (host-authoritative) and make boxes above fall on the host AND clients.
	if obj is SupplyBox:
		SupplyBox.release_delivery_slot(obj as SupplyBox)
		SupplyBox.make_boxes_above_pos_fall(obj.global_position)
		_broadcast(&"_sync_boxes_fall", [obj.global_position])
	obj.queue_free()
	_broadcast(&"_despawn_on_clients", [parent_path, obj_name, net_id])


@rpc("authority", "call_local", "reliable")
func _sync_boxes_fall(box_pos: Vector3) -> void:
	if is_host():
		return
	SupplyBox.make_boxes_above_pos_fall(box_pos)


## Tell all clients to reparent an object to a new parent. Used when
## the host moves an object (e.g. a supply box from the truck grid to
## the world) and clients need to match the hierarchy.
@rpc("authority", "call_local", "reliable")
func reparent_on_clients(new_parent_path_str: String, obj_name: String, net_id: int) -> void:
	if is_host():
		return
	var obj := _find_node("", obj_name, net_id)
	if obj == null:
		GameLog.log("[WorldSync] Client reparent: object not found: " + obj_name)
		return
	var new_parent := _string_to_node(new_parent_path_str)
	if new_parent == null:
		GameLog.log("[WorldSync] Client reparent: parent not found: " + new_parent_path_str)
		return
	var old_pos: Vector3 = obj.global_position
	var old_rot: Vector3 = obj.global_rotation
	obj.get_parent().remove_child(obj)
	new_parent.add_child(obj)
	obj.global_position = old_pos
	obj.global_rotation = old_rot
	# Update cache
	_node_cache[obj_name] = obj
	GameLog.log("[WorldSync] Client reparented %s to %s" % [obj_name, new_parent_path_str])


## Sync item attachments for a workstation across all peers. When a
## player picks up a table, the items on top must be reparented to that
## table on every client so they follow the table when it moves.
## 'item_data' is an Array[Dictionary] of { name, net_id } for attached items.
## 'parent_name' is the workstation name.
func sync_workstation_items(parent_name: String, item_data: Array[Dictionary]) -> void:
	if not is_host():
		_request_host(&"_rpc_request_workstation_items", [parent_name, item_data])
		return
	_reparent_workstation_items_on_host(parent_name, item_data)


@rpc("any_peer", "reliable")
func _rpc_request_workstation_items(parent_name: String, item_data: Array[Dictionary]) -> void:
	if not is_host():
		return
	_reparent_workstation_items_on_host(parent_name, item_data)


func _reparent_workstation_items_on_host(parent_name: String, item_data: Array[Dictionary]) -> void:
	var parent := _find_node_by_name_only(parent_name)
	if parent == null or not is_instance_valid(parent):
		GameLog.log("[WorldSync] Workstation items: parent not found: " + parent_name)
		return
	var parent_path := _node_path_to_string(parent.get_path())
	for entry in item_data:
		var item_name: String = entry.get("name", "")
		var net_id: int = entry.get("net_id", -1)
		var item := _find_node("", item_name, net_id)
		if item == null or not is_instance_valid(item):
			GameLog.log("[WorldSync] Workstation items: item not found: " + item_name)
			continue
		if item.get_parent() == parent:
			# Already parented on the host, but still broadcast to clients
			# in case they haven't reparented yet (e.g. late joiner or
			# previous reparent RPC was lost).
			_broadcast(&"reparent_on_clients", [parent_path, item_name, net_id])
			continue
		var old_pos: Vector3 = item.global_position
		var old_rot: Vector3 = item.global_rotation
		item.get_parent().remove_child(item)
		parent.add_child(item)
		item.global_position = old_pos
		item.global_rotation = old_rot
		# Tell all clients to do the same reparent
		_broadcast(&"reparent_on_clients", [parent_path, item_name, net_id])


## Move an existing object to a new position/rotation on the host and
## sync to all clients. Used when a workstation (table) is picked up
## and placed somewhere else — the same node is reused (not destroyed
## and re-spawned) so items on top follow it.
func sync_move_object(obj: Node, new_pos: Vector3, new_rot: Vector3) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var net_id := _get_net_id(obj)
	var obj_name := obj.name
	if not is_host():
		_request_host(&"_rpc_request_move", [obj_name, net_id, new_pos, new_rot])
		return
	obj.global_position = new_pos
	obj.global_rotation = new_rot
	_broadcast(&"_move_on_clients", [obj_name, net_id, new_pos, new_rot])


@rpc("any_peer", "reliable")
func _rpc_request_move(obj_name: String, net_id: int, new_pos: Vector3, new_rot: Vector3) -> void:
	if not is_host():
		return
	var obj := _find_node("", obj_name, net_id)
	if obj == null or not is_instance_valid(obj):
		GameLog.log("[WorldSync] Host _rpc_request_move: object not found: " + obj_name)
		return
	obj.global_position = new_pos
	obj.global_rotation = new_rot
	_broadcast(&"_move_on_clients", [obj.name, net_id, new_pos, new_rot])


## Move AND show/hide an object in a single RPC. More reliable than
## calling sync_move_object + sync_show_object separately, since the
## position and visibility are set atomically on the client.
func sync_move_and_show(
	obj: Node,
	new_pos: Vector3,
	new_rot: Vector3,
	new_scale: Vector3,
	show: bool,
) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var net_id := _get_net_id(obj)
	var obj_name := obj.name
	if not is_host():
		_request_host(
			&"_rpc_request_move_and_show",
			[obj_name, net_id, new_pos, new_rot, new_scale, show],
		)
		return
	obj.global_position = new_pos
	obj.global_rotation = new_rot
	obj.scale = new_scale
	obj.visible = show
	for child in obj.find_children("*", "CollisionShape3D", true, false):
		var col := child as CollisionShape3D
		if col:
			col.disabled = not show
	_broadcast(&"_move_and_show_on_clients", [obj_name, net_id, new_pos, new_rot, new_scale, show])


@rpc("any_peer", "reliable")
func _rpc_request_move_and_show(
	obj_name: String,
	net_id: int,
	new_pos: Vector3,
	new_rot: Vector3,
	new_scale: Vector3,
	show: bool,
) -> void:
	if not is_host():
		return
	var obj := _find_node("", obj_name, net_id)
	if obj == null or not is_instance_valid(obj):
		GameLog.log("[WorldSync] Host _rpc_request_move_and_show: object not found: " + obj_name)
		return
	obj.global_position = new_pos
	obj.global_rotation = new_rot
	obj.scale = new_scale
	obj.visible = show
	for child in obj.find_children("*", "CollisionShape3D", true, false):
		var col := child as CollisionShape3D
		if col:
			col.disabled = not show
	_broadcast(&"_move_and_show_on_clients", [obj.name, net_id, new_pos, new_rot, new_scale, show])


## Reparent an object to a new parent on the host and sync to clients.
func sync_reparent_object(obj: Node, new_parent: Node) -> void:
	if not is_host() or obj == null or not is_instance_valid(obj):
		return
	if new_parent == null or not is_instance_valid(new_parent):
		return
	var old_pos: Vector3 = obj.global_position
	var old_rot: Vector3 = obj.global_rotation
	obj.get_parent().remove_child(obj)
	new_parent.add_child(obj)
	obj.global_position = old_pos
	obj.global_rotation = old_rot
	var new_parent_path := _node_path_to_string(new_parent.get_path())
	_broadcast(&"reparent_on_clients", [new_parent_path, obj.name, _get_net_id(obj)])


@rpc("authority", "call_local", "reliable")
func _move_on_clients(obj_name: String, net_id: int, new_pos: Vector3, new_rot: Vector3) -> void:
	if is_host():
		return
	var obj := _find_node("", obj_name, net_id)
	if obj:
		obj.global_position = new_pos
		obj.global_rotation = new_rot


@rpc("authority", "call_local", "reliable")
func _move_and_show_on_clients(
	obj_name: String,
	net_id: int,
	new_pos: Vector3,
	new_rot: Vector3,
	new_scale: Vector3,
	show: bool,
) -> void:
	if is_host():
		return
	var obj := _find_node("", obj_name, net_id)
	if obj:
		obj.global_position = new_pos
		obj.global_rotation = new_rot
		obj.scale = new_scale
		obj.visible = show
		for child in obj.find_children("*", "CollisionShape3D", true, false):
			var col := child as CollisionShape3D
			if col:
				col.disabled = not show
	else:
		GameLog.log("[WorldSync] Client move_and_show: object not found: " + obj_name)


## Hide an object on all clients (e.g. when a workstation is picked up
## and is now "in the player's hands"). The object stays in the tree
## on the host but is removed from the holder's scene tree, so we hide
## it on clients instead of despawning it.
func sync_hide_object(obj: Node) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var net_id := _get_net_id(obj)
	var obj_name := obj.name
	if not is_host():
		_request_host(&"_rpc_request_set_visible", [obj_name, net_id, false])
		return
	# Hide on the host too — the host should see the table disappear
	# when any player picks it up.
	obj.visible = false
	for child in obj.find_children("*", "CollisionShape3D", true, false):
		var col := child as CollisionShape3D
		if col:
			col.disabled = true
	_broadcast(&"_set_visible_on_clients", [obj_name, net_id, false])


## Show an object on all clients (e.g. when a workstation is placed
## back down after being picked up).
func sync_show_object(obj: Node) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var net_id := _get_net_id(obj)
	var obj_name := obj.name
	if not is_host():
		_request_host(&"_rpc_request_set_visible", [obj_name, net_id, true])
		return
	obj.visible = true
	for child in obj.find_children("*", "CollisionShape3D", true, false):
		var col := child as CollisionShape3D
		if col:
			col.disabled = false
	_broadcast(&"_set_visible_on_clients", [obj_name, net_id, true])


@rpc("any_peer", "reliable")
func _rpc_request_set_visible(obj_name: String, net_id: int, show: bool) -> void:
	if not is_host():
		return
	var obj := _find_node("", obj_name, net_id)
	if obj == null or not is_instance_valid(obj):
		GameLog.log(
			"[WorldSync] Host _rpc_request_set_visible: object not found: %s net_id=%d"
			% [obj_name, net_id]
		)
		return
	# Apply on the host too — the host needs to hide/show the object
	# just like clients do, not just broadcast.
	obj.visible = show
	for child in obj.find_children("*", "CollisionShape3D", true, false):
		var col := child as CollisionShape3D
		if col:
			col.disabled = not show
	# Broadcast to all non-host clients
	_broadcast(&"_set_visible_on_clients", [obj.name, net_id, show])


@rpc("authority", "call_local", "reliable")
func _set_visible_on_clients(obj_name: String, net_id: int, visible: bool) -> void:
	if is_host():
		return
	var obj := _find_node("", obj_name, net_id)
	if obj:
		obj.visible = visible
		# Also disable collision so hidden objects don't block the player
		for child in obj.find_children("*", "CollisionShape3D", true, false):
			var col := child as CollisionShape3D
			if col:
				col.disabled = not visible


@rpc("authority", "call_local", "reliable")
func _spawn_on_clients(
	scene_path: String,
	parent_path_str: String,
	obj_name: String,
	net_id: int,
	global_pos: Vector3,
	global_rot: Vector3,
	obj_scale: Vector3,
	state: Dictionary,
) -> void:
	if is_host():
		return # Host already spawned it locally
	GameLog.log(
		"[WorldSync] Client received spawn: %s name=%s net_id=%d parent=%s"
		% [scene_path, obj_name, net_id, parent_path_str]
	)
	var parent := _string_to_node(parent_path_str)
	if parent == null:
		GameLog.log("[WorldSync] Client: parent not found: " + parent_path_str)
		return
	var scene := _get_scene(scene_path)
	if scene == null:
		GameLog.log("[WorldSync] Client: scene not found: " + scene_path)
		return
	var obj := scene.instantiate()
	# Set state BEFORE adding to tree so _ready() sees configured values.
	# Special keys starting with "_net_" are not properties — they're
	# post-spawn actions handled below.
	var net_groups: Array = state.get("_net_groups", [])
	var net_scale: Vector3 = state.get("_net_scale", Vector3.ZERO)
	var net_fruit_amounts: Dictionary = state.get("_net_fruit_amounts", { })
	var net_pitcher_recipe: Dictionary = state.get("_net_pitcher_recipe", { })
	var net_delivery_cell_idx: int = state.get("_net_delivery_cell_idx", -1)
	var net_delivery_grid_path: String = state.get("_net_delivery_grid_path", "")
	var clean_state := state.duplicate()
	clean_state.erase("_net_groups")
	clean_state.erase("_net_scale")
	clean_state.erase("_net_fruit_amounts")
	clean_state.erase("_net_pitcher_recipe")
	clean_state.erase("_net_delivery_cell_idx")
	clean_state.erase("_net_delivery_grid_path")
	for key in clean_state:
		obj.set(key, clean_state[key])
	obj.name = obj_name
	# Register the same net_id the host assigned, so future RPCs can find
	# this object regardless of its name or parent path.
	if net_id >= 0:
		obj.set_meta(NET_ID_META, net_id)
		_net_id_to_node[net_id] = obj
		_node_to_net_id[obj] = net_id
		obj.tree_exited.connect(_on_net_object_tree_exited.bind(net_id))
	parent.add_child(obj)
	obj.global_position = global_pos
	obj.global_rotation = global_rot
	if net_scale != Vector3.ZERO:
		obj.scale = net_scale
	else:
		obj.scale = obj_scale
	# Apply post-ready state AFTER _ready() has run
	if not net_fruit_amounts.is_empty() and obj is FruitBin:
		(obj as FruitBin).fruit_amounts = net_fruit_amounts.duplicate()
		(obj as FruitBin).update_display()
	if not net_pitcher_recipe.is_empty() and obj is Pitcher:
		var p := obj as Pitcher
		p.fruit_type = net_pitcher_recipe.get("fruit_type", "")
		p.fruit_count = net_pitcher_recipe.get("fruit_count", 0.0)
		p.water = net_pitcher_recipe.get("water", 0.0)
		p.sugar = net_pitcher_recipe.get("sugar", 0.0)
		p.ice = net_pitcher_recipe.get("ice", 0.0)
		p.cups_poured = net_pitcher_recipe.get("cups_poured", 0)
		p.set_pitcher_visible(true)
		p.sync_fill_display()
		p.call_deferred("update_label")
	# Restore delivery grid slot metas so clients can release the slot
	# when picking up the box.
	if net_delivery_cell_idx >= 0:
		obj.set_meta("delivery_cell_idx", net_delivery_cell_idx)
		if net_delivery_grid_path != "":
			obj.set_meta("delivery_grid_path", NodePath(net_delivery_grid_path))
	# Add to groups after spawning so clients match the host
	for g in net_groups:
		obj.add_to_group(g)
	_node_cache[obj_name] = obj
	GameLog.log("[WorldSync] Client spawned %s OK scale=%s" % [obj_name, str(obj_scale)])


@rpc("authority", "call_local", "reliable")
func _despawn_on_clients(parent_path_str: String, obj_name: String, net_id: int) -> void:
	if is_host():
		return
	GameLog.log(
		"[WorldSync] Client received despawn: parent=%s name=%s net_id=%d"
		% [parent_path_str, obj_name, net_id]
	)
	# Prefer stable net_id lookup, then fall back to name/path for objects
	# that pre-date the net_id system or default scene objects. The fallback
	# must also run when the net_id lookup fails — a stale registration (e.g.
	# from an object reparented before the tree_exited guard existed) would
	# otherwise leave a zombie copy on this client forever.
	var obj: Node = null
	if net_id >= 0:
		obj = _find_node_by_net_id(net_id)
	if obj == null:
		var parent := _string_to_node(parent_path_str)
		if parent:
			obj = parent.get_node_or_null(obj_name)
		if obj == null:
			obj = _find_node_by_name(get_tree().current_scene, obj_name)
	if obj:
		# Release any delivery-grid slot this box occupied so the client's
		# grid matches the host's.
		if obj is SupplyBox:
			SupplyBox.release_delivery_slot(obj as SupplyBox)
		obj.queue_free()
		_node_cache.erase(obj_name)
		GameLog.log("[WorldSync] Client despawned %s OK" % obj_name)
	else:
		# Object was likely already removed locally (e.g. picked up and
		# freed by the client before the host's despawn RPC arrived).
		_node_cache.erase(obj_name)
		GameLog.log("[WorldSync] Client despawn: object already removed: " + obj_name)


## Recursively search a node tree for a child with the given name.
func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root == null:
		return null
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found := _find_node_by_name(child, target_name)
		if found:
			return found
	return null


## Like _find_node_by_name but only matches a node whose parent's path
## equals parent_path_str — disambiguates same-named nodes across stands.
func _find_node_by_name_and_parent(
	root: Node,
	target_name: String,
	parent_path_str: String,
) -> Node:
	if root == null:
		return null
	if (root.name == target_name and str(root.get_parent().get_path()) == parent_path_str):
		return root
	for child in root.get_children():
		var found := _find_node_by_name_and_parent(child, target_name, parent_path_str)
		if found:
			return found
	return null


## Sync a transform (position + rotation) using unreliable RPCs for
## high-frequency updates (e.g. moving trucks). Only call this from
## the host's _process.
func sync_transform(obj: Node, pos: Vector3, rot: Vector3) -> void:
	if not is_host() or obj == null or not is_instance_valid(obj):
		return
	var net_id := _get_net_id(obj)
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	# 1 = unreliable channel
	_broadcast(&"_apply_transform", [parent_path, obj.name, net_id, pos, rot, 1])


## Batch sync: sends ALL NPC transforms in a single RPC instead of one
## RPC per NPC. Dramatically reduces network overhead when many NPCs
## are active. Each entry in the arrays corresponds to one NPC:
## names[i] / positions[i] / rotations[i].
func sync_transforms_batch(
	names: PackedStringArray,
	positions: PackedVector3Array,
	rotations: PackedVector3Array,
	net_ids: PackedInt32Array = PackedInt32Array(),
) -> void:
	if not is_host():
		return
	if not multiplayer.multiplayer_peer:
		return
	_apply_transforms_batch.rpc_id(0, names, positions, rotations, net_ids)


@rpc("authority", "call_local", "unreliable")
func _apply_transforms_batch(
	names: PackedStringArray,
	positions: PackedVector3Array,
	rotations: PackedVector3Array,
	net_ids: PackedInt32Array = PackedInt32Array(),
) -> void:
	if is_host():
		return
	var count := names.size()
	for i in count:
		# Prefer stable net_id — survives reparenting and name mismatches.
		# Fall back to the name for entries that pre-date net_id support.
		var obj: Node = null
		if i < net_ids.size() and net_ids[i] >= 0:
			obj = _find_node_by_net_id(net_ids[i])
		if obj == null:
			obj = _find_node_by_name_only(names[i])
		if obj and obj.has_method("net_set_target"):
			obj.net_set_target(positions[i], rotations[i])


## Sync a property change on a world object from host to all clients.
## Use this for container contents (fruit amounts, water, sugar, ice,
## cup counts, etc.) so all peers see the same state.
## On a client, sends the change to the host first (host-authoritative),
## which then broadcasts to all other clients.
func sync_property(obj: Node, prop: String, value: Variant) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var net_id := _get_net_id(obj)
	var obj_name := obj.name
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	if not is_host():
		_request_host(&"_rpc_request_property", [parent_path, obj_name, net_id, prop, value])
		return
	_broadcast(&"_apply_property", [parent_path, obj_name, net_id, prop, value])


@rpc("any_peer", "reliable")
func _rpc_request_property(
	parent_path_str: String,
	obj_name: String,
	net_id: int,
	prop: String,
	value: Variant,
) -> void:
	if not is_host():
		return
	var obj := _find_node(parent_path_str, obj_name, net_id)
	if obj == null or not is_instance_valid(obj):
		return
	obj.set(prop, value)
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_broadcast(&"_apply_property", [parent_path, obj_name, net_id, prop, value])


## Sync multiple property changes at once (more efficient than calling
## sync_property for each one individually).
func sync_properties(obj: Node, props: Dictionary) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var net_id := _get_net_id(obj)
	var obj_name := obj.name
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	if not is_host():
		_request_host(&"_rpc_request_properties", [parent_path, obj_name, net_id, props])
		return
	_broadcast(&"_apply_properties", [parent_path, obj_name, net_id, props])


@rpc("any_peer", "reliable")
func _rpc_request_properties(
	parent_path_str: String,
	obj_name: String,
	net_id: int,
	props: Dictionary,
) -> void:
	if not is_host():
		return
	var obj := _find_node(parent_path_str, obj_name, net_id)
	if obj == null or not is_instance_valid(obj):
		return
	for key in props:
		obj.set(key, props[key])
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_broadcast(&"_apply_properties", [parent_path, obj_name, net_id, props])


## Call a method on a world object on all clients (e.g. update_display).
func sync_call(obj: Node, method: String, args: Array = []) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var net_id := _get_net_id(obj)
	var obj_name := obj.name
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	if not is_host():
		_request_host(&"_rpc_request_call", [parent_path, obj_name, net_id, method, args])
		return
	_broadcast(&"_call_method", [parent_path, obj_name, net_id, method, args])


@rpc("any_peer", "reliable")
func _rpc_request_call(
	parent_path_str: String,
	obj_name: String,
	net_id: int,
	method: String,
	args: Array,
) -> void:
	if not is_host():
		return
	var obj := _find_node(parent_path_str, obj_name, net_id)
	if obj == null or not is_instance_valid(obj):
		return
	if obj.has_method(method):
		obj.callv(method, args)
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_broadcast(&"_call_method", [parent_path, obj_name, net_id, method, args])


@rpc("authority", "call_local", "reliable")
func _apply_property(
	parent_path_str: String,
	obj_name: String,
	net_id: int,
	prop: String,
	value: Variant,
) -> void:
	if is_host():
		return
	var obj := _find_node(parent_path_str, obj_name, net_id)
	if obj:
		obj.set(prop, value)


@rpc("authority", "call_local", "unreliable")
func _apply_transform(
	parent_path_str: String,
	obj_name: String,
	net_id: int,
	pos: Vector3,
	rot: Vector3,
	_channel: int,
) -> void:
	if is_host():
		return
	var obj := _find_node(parent_path_str, obj_name, net_id)
	if obj:
		# If the object supports interpolation (e.g. NPCs), set the target
		# instead of snapping position directly
		if obj.has_method("net_set_target"):
			obj.net_set_target(pos, rot)
		else:
			obj.global_position = pos
			obj.global_rotation = rot


@rpc("authority", "call_local", "reliable")
func _apply_properties(
	parent_path_str: String,
	obj_name: String,
	net_id: int,
	props: Dictionary,
) -> void:
	if is_host():
		return
	var obj := _find_node(parent_path_str, obj_name, net_id)
	if obj:
		for key in props:
			obj.set(key, props[key])


@rpc("authority", "call_local", "reliable")
func _call_method(
	parent_path_str: String,
	obj_name: String,
	net_id: int,
	method: String,
	args: Array,
) -> void:
	if is_host():
		return
	var obj := _find_node(parent_path_str, obj_name, net_id)
	if obj and obj.has_method(method):
		obj.callv(method, args)


func _find_node(parent_path_str: String, obj_name: String, net_id: int = -1) -> Node:
	# Prefer stable net_id lookup (survives reparenting).
	if net_id >= 0:
		var by_id := _find_node_by_net_id(net_id)
		if by_id != null:
			return by_id
	var parent := _string_to_node(parent_path_str)
	if parent:
		var obj := parent.get_node_or_null(obj_name)
		if obj:
			return obj
	# Same-named nodes can exist under different parents in versus mode
	# (e.g. a spawned "Pitcher" on each stand). Prefer a name match whose
	# parent path matches the sender's.
	var scoped := _find_node_by_name_and_parent(get_tree().current_scene, obj_name, parent_path_str)
	if scoped:
		return scoped
	# Last resort: name-only match covers nodes reparented since the sender
	# computed the path (e.g. a supply box picked into a player's hand).
	# Do NOT cache by bare name here — a stale hit would silently return a
	# same-named node from the wrong stand.
	return _find_node_by_name(get_tree().current_scene, obj_name)


## Fast name-only lookup for batch syncs (avoids serializing parent
## paths for every NPC every tick). Uses the cache, falls back to
## tree search only on cache miss.
## Misses are negative-cached with a TTL: a late joiner never receives
## NPCs that spawned before they connected (RPCs don't replay), so every
## transform batch would otherwise re-walk the whole scene tree for each
## missing NPC — a continuous CPU storm starting at connect.
var _name_miss_cache: Dictionary = { } ## name -> Time.get_ticks_msec()
const NAME_MISS_TTL_MSEC := 2000


func _find_node_by_name_only(obj_name: String) -> Node:
	if _node_cache.has(obj_name):
		var cached: Node = _node_cache[obj_name]
		if is_instance_valid(cached):
			return cached
		else:
			_node_cache.erase(obj_name)
	var last_miss: int = _name_miss_cache.get(obj_name, 0)
	if last_miss > 0 and Time.get_ticks_msec() - last_miss < NAME_MISS_TTL_MSEC:
		return null
	var found := _find_node_by_name(get_tree().current_scene, obj_name)
	if found:
		_node_cache[obj_name] = found
		_name_miss_cache.erase(obj_name)
	else:
		_name_miss_cache[obj_name] = Time.get_ticks_msec()
	return found


func _get_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path] as PackedScene
	var scene := load(path) as PackedScene
	if scene:
		_scene_cache[path] = scene
	return scene


func _node_path_to_string(path: NodePath) -> String:
	return str(path)


func _string_to_node(path_str: String) -> Node:
	var root := get_tree().current_scene
	if path_str == "/root/Main" or path_str == "/root":
		return root
	# Try absolute path first
	var node := get_node_or_null(NodePath(path_str))
	if node:
		return node
	# Try relative to current scene
	return root.get_node_or_null(NodePath(path_str.replace("/root/Main/", "")))

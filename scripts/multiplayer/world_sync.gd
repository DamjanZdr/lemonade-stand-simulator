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

## scene_path -> PackedScene cache
var _scene_cache: Dictionary = { }

## Counter for generating unique object names across all spawned objects.
var _spawn_counter: int = 0

## Cache of object name -> Node for fast lookup in RPCs. Avoids doing
## a full scene tree search every frame for transform syncs.
var _node_cache: Dictionary = { }


func setup(world_objects: Node, spawner: MultiplayerSpawner) -> void:
	# Currently unused (we use RPC-based spawning instead of MultiplayerSpawner),
	# but kept for future use if we switch to spawner-based replication.
	pass


func is_host() -> bool:
	return multiplayer.is_server()


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
	_apply_world_snapshot.rpc(snapshot)


## Same as sync_world_state_to_clients but only sent to a specific peer.
## Used when a client joins mid-game (late join).
func sync_world_state_to_peer(peer_id: int) -> void:
	if not is_host():
		return
	var snapshot := _collect_world_snapshot()
	if snapshot.is_empty():
		return
	_apply_world_snapshot.rpc_id(peer_id, snapshot)


## Collects all containers and supply boxes in the world into a
## serializable dictionary. Each entry has: scene_path, name,
## position, rotation, scale, and state (contents/amounts).
func _collect_world_snapshot() -> Dictionary:
	var containers: Array = []
	var supply_boxes: Array = []
	var root := get_tree().current_scene
	if root == null:
		return { }
	# Collect containers
	for node in get_tree().get_nodes_in_group("container"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.is_in_group("ghost"):
			continue
		var entry := _serialize_container(node)
		if entry != null:
			containers.append(entry)
	# Collect supply boxes
	for node in get_tree().get_nodes_in_group("supply_box"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var entry := _serialize_supply_box(node)
		if entry != null:
			supply_boxes.append(entry)
	return { "containers": containers, "supply_boxes": supply_boxes }


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
	var entry := {
		"scene_path": scene_path,
		"name": node.name,
		"ctype": ctype,
		"position": [node.global_position.x, node.global_position.y, node.global_position.z],
		"rotation": [node.global_rotation.x, node.global_rotation.y, node.global_rotation.z],
		"scale": [node.scale.x, node.scale.y, node.scale.z],
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
	return {
		"scene_path": "res://scenes/objects/supply_box.tscn",
		"name": box.name,
		"position": [box.global_position.x, box.global_position.y, box.global_position.z],
		"rotation": [box.global_rotation.x, box.global_rotation.y, box.global_rotation.z],
		"scale": [box.scale.x, box.scale.y, box.scale.z],
		"ingredient_type": box.ingredient_type,
		"quantity": box.quantity,
		"is_equipment": box.is_equipment,
		"equipment_type": box.equipment_type,
	}


## Clients receive the full world snapshot and instantiate all
## containers and supply boxes to match the host's world.
@rpc("authority", "call_local", "reliable")
func _apply_world_snapshot(snapshot: Dictionary) -> void:
	if is_host():
		return
	var root := get_tree().current_scene
	if root == null:
		return
	# Spawn containers
	for entry in snapshot.get("containers", []):
		_spawn_container_from_snapshot(entry, root)
	# Spawn supply boxes
	for entry in snapshot.get("supply_boxes", []):
		_spawn_supply_box_from_snapshot(entry, root)
	GameLog.log(
		"[WorldSync] Applied world snapshot: %d containers, %d supply boxes"
		% [snapshot.get("containers", []).size(), snapshot.get("supply_boxes", []).size()]
	)


func _spawn_container_from_snapshot(entry: Dictionary, root: Node) -> void:
	var scene_path: String = entry.get("scene_path", "")
	if scene_path == "":
		return
	var scene := _get_scene(scene_path)
	if scene == null:
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
	# Apply scale before adding to tree
	var scl: Array = entry.get("scale", [1.0, 1.0, 1.0])
	if scl.size() >= 3:
		instance.scale = Vector3(scl[0], scl[1], scl[2])
	instance.name = entry.get("name", instance.name)
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


func _spawn_supply_box_from_snapshot(entry: Dictionary, root: Node) -> void:
	var scene := _get_scene("res://scenes/objects/supply_box.tscn")
	if scene == null:
		return
	var box := scene.instantiate() as SupplyBox
	box.ingredient_type = entry.get("ingredient_type", "lemon")
	box.quantity = float(entry.get("quantity", 10.0))
	box.is_equipment = bool(entry.get("is_equipment", false))
	box.equipment_type = entry.get("equipment_type", "")
	var scl: Array = entry.get("scale", [1.0, 1.0, 1.0])
	if scl.size() >= 3:
		box.scale = Vector3(scl[0], scl[1], scl[2])
	box.name = entry.get("name", box.name)
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
	_rpc_request_spawn.rpc_id(1, scene_path, pos, rot, state)
	return null


@rpc("any_peer", "reliable")
func _rpc_request_spawn(scene_path: String, pos: Vector3, rot: Vector3, state: Dictionary) -> void:
	if not is_host():
		return
	spawn_networked(scene_path, get_world_objects(), pos, rot, state)


## Request a despawn from any peer. On the host, despawns directly.
## On a client, sends an RPC to the host.
func request_despawn(obj: Node) -> void:
	if obj == null or not is_instance_valid(obj):
		GameLog.log("[WorldSync] request_despawn: obj is null/invalid")
		return
	GameLog.log("[WorldSync] request_despawn name=%s is_host=%s" % [obj.name, is_host()])
	if is_host():
		despawn_networked(obj)
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	GameLog.log(
		"[WorldSync] Client sending despawn RPC to host: parent=%s name=%s"
		% [parent_path, obj.name]
	)
	_rpc_request_despawn.rpc_id(1, parent_path, obj.name)


@rpc("any_peer", "reliable")
func _rpc_request_despawn(parent_path_str: String, obj_name: String) -> void:
	if not is_host():
		return
	GameLog.log(
		"[WorldSync] Host received despawn request: parent=%s name=%s" % [parent_path_str, obj_name]
	)
	var parent := _string_to_node(parent_path_str)
	if parent == null:
		GameLog.log("[WorldSync] Host despawn: parent not found: " + parent_path_str)
		return
	var obj := parent.get_node_or_null(obj_name)
	if obj:
		despawn_networked(obj)
	else:
		GameLog.log("[WorldSync] Host despawn: object not found: " + obj_name)


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
	var clean_state := state.duplicate()
	clean_state.erase("_net_groups")
	clean_state.erase("_net_scale")
	clean_state.erase("_net_fruit_amounts")
	clean_state.erase("_net_pitcher_recipe")
	for key in clean_state:
		obj.set(key, clean_state[key])
	# Give the object a unique name so despawn can find it reliably.
	# Without this, multiple objects of the same type would all be named
	# e.g. "SupplyBox" and despawn would only find the first one.
	var base_name := obj.name
	obj.name = base_name + "_" + str(_spawn_counter)
	_spawn_counter += 1
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
	# Capture the object's scale after adding to the parent (parent's
	# transform may affect it). We'll send this to clients so they
	# match the host's scale.
	var obj_scale: Vector3 = obj.scale
	# Broadcast to clients
	var parent_path := _node_path_to_string(parent.get_path())
	GameLog.log(
		"[WorldSync] Host spawned %s name=%s parent=%s pos=%s scale=%s"
		% [scene_path, obj.name, parent_path, str(global_pos), str(obj_scale)]
	)
	_spawn_on_clients.rpc(
		scene_path,
		parent_path,
		obj.name,
		global_pos,
		global_rot,
		obj_scale,
		state,
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
	GameLog.log("[WorldSync] Host despawning %s parent=%s" % [obj_name, parent_path])
	# If this is a supply box, make boxes above fall on the host AND clients
	if obj is SupplyBox:
		SupplyBox.make_boxes_above_pos_fall(obj.global_position)
		_sync_boxes_fall.rpc(obj.global_position)
	obj.queue_free()
	_despawn_on_clients.rpc(parent_path, obj_name)


@rpc("authority", "call_local", "reliable")
func _sync_boxes_fall(box_pos: Vector3) -> void:
	if is_host():
		return
	SupplyBox.make_boxes_above_pos_fall(box_pos)


## Tell all clients to reparent an object to a new parent. Used when
## the host moves an object (e.g. a supply box from the truck grid to
## the world) and clients need to match the hierarchy.
@rpc("authority", "call_local", "reliable")
func _reparent_on_clients(new_parent_path_str: String, obj_name: String) -> void:
	if is_host():
		return
	var obj := _find_node("", obj_name)
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


## Move an existing object to a new position/rotation on the host and
## sync to all clients. Used when a workstation (table) is picked up
## and placed somewhere else — the same node is reused (not destroyed
## and re-spawned) so items on top follow it.
func sync_move_object(obj: Node, new_pos: Vector3, new_rot: Vector3) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	if not is_host():
		_rpc_request_move.rpc_id(1, obj.name, new_pos, new_rot)
		return
	obj.global_position = new_pos
	obj.global_rotation = new_rot
	_move_on_clients.rpc(obj.name, new_pos, new_rot)


@rpc("any_peer", "reliable")
func _rpc_request_move(obj_name: String, new_pos: Vector3, new_rot: Vector3) -> void:
	if not is_host():
		return
	var obj := _find_node_by_name_only(obj_name)
	if obj == null or not is_instance_valid(obj):
		GameLog.log("[WorldSync] Host _rpc_request_move: object not found: " + obj_name)
		return
	obj.global_position = new_pos
	obj.global_rotation = new_rot
	_move_on_clients.rpc(obj_name, new_pos, new_rot)


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
	if not is_host():
		_rpc_request_move_and_show.rpc_id(1, obj.name, new_pos, new_rot, new_scale, show)
		return
	obj.global_position = new_pos
	obj.global_rotation = new_rot
	obj.scale = new_scale
	_move_and_show_on_clients.rpc(obj.name, new_pos, new_rot, new_scale, show)


@rpc("any_peer", "reliable")
func _rpc_request_move_and_show(
	obj_name: String,
	new_pos: Vector3,
	new_rot: Vector3,
	new_scale: Vector3,
	show: bool,
) -> void:
	if not is_host():
		return
	var obj := _find_node_by_name_only(obj_name)
	if obj == null or not is_instance_valid(obj):
		GameLog.log("[WorldSync] Host _rpc_request_move_and_show: object not found: " + obj_name)
		return
	obj.global_position = new_pos
	obj.global_rotation = new_rot
	obj.scale = new_scale
	_move_and_show_on_clients.rpc(obj_name, new_pos, new_rot, new_scale, show)


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
	_reparent_on_clients.rpc(new_parent_path, obj.name)


@rpc("authority", "call_local", "reliable")
func _move_on_clients(obj_name: String, new_pos: Vector3, new_rot: Vector3) -> void:
	if is_host():
		return
	var obj := _find_node_by_name_only(obj_name)
	if obj:
		obj.global_position = new_pos
		obj.global_rotation = new_rot


@rpc("authority", "call_local", "reliable")
func _move_and_show_on_clients(
	obj_name: String,
	new_pos: Vector3,
	new_rot: Vector3,
	new_scale: Vector3,
	show: bool,
) -> void:
	if is_host():
		return
	var obj := _find_node_by_name_only(obj_name)
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
func sync_hide_object(obj_name: String) -> void:
	if not is_host():
		_rpc_request_set_visible.rpc_id(1, obj_name, false)
		return
	_set_visible_on_clients.rpc(obj_name, false)


## Show an object on all clients (e.g. when a workstation is placed
## back down after being picked up).
func sync_show_object(obj_name: String) -> void:
	if not is_host():
		_rpc_request_set_visible.rpc_id(1, obj_name, true)
		return
	_set_visible_on_clients.rpc(obj_name, true)


@rpc("any_peer", "reliable")
func _rpc_request_set_visible(obj_name: String, show: bool) -> void:
	if not is_host():
		return
	var obj := _find_node_by_name_only(obj_name)
	if obj == null or not is_instance_valid(obj):
		GameLog.log("[WorldSync] Host _rpc_request_set_visible: object not found: " + obj_name)
		return
	_set_visible_on_clients.rpc(obj_name, show)


@rpc("authority", "call_local", "reliable")
func _set_visible_on_clients(obj_name: String, visible: bool) -> void:
	if is_host():
		return
	var obj := _find_node_by_name_only(obj_name)
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
	global_pos: Vector3,
	global_rot: Vector3,
	obj_scale: Vector3,
	state: Dictionary,
) -> void:
	if is_host():
		return # Host already spawned it locally
	GameLog.log(
		"[WorldSync] Client received spawn: %s name=%s parent=%s"
		% [scene_path, obj_name, parent_path_str]
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
	var clean_state := state.duplicate()
	clean_state.erase("_net_groups")
	clean_state.erase("_net_scale")
	clean_state.erase("_net_fruit_amounts")
	clean_state.erase("_net_pitcher_recipe")
	for key in clean_state:
		obj.set(key, clean_state[key])
	obj.name = obj_name
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
	# Add to groups after spawning so clients match the host
	for g in net_groups:
		obj.add_to_group(g)
	_node_cache[obj_name] = obj
	GameLog.log("[WorldSync] Client spawned %s OK scale=%s" % [obj_name, str(obj_scale)])


@rpc("authority", "call_local", "reliable")
func _despawn_on_clients(parent_path_str: String, obj_name: String) -> void:
	if is_host():
		return
	GameLog.log(
		"[WorldSync] Client received despawn: parent=%s name=%s" % [parent_path_str, obj_name]
	)
	var parent := _string_to_node(parent_path_str)
	var obj: Node = null
	if parent:
		obj = parent.get_node_or_null(obj_name)
	# Fallback: search the entire scene tree by name in case the object
	# was re-parented on the host without the client knowing.
	if obj == null:
		obj = _find_node_by_name(get_tree().current_scene, obj_name)
	if obj:
		obj.queue_free()
		_node_cache.erase(obj_name)
		GameLog.log("[WorldSync] Client despawned %s OK" % obj_name)
	else:
		GameLog.log("[WorldSync] Client despawn: object not found anywhere: " + obj_name)


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


## Sync a transform (position + rotation) using unreliable RPCs for
## high-frequency updates (e.g. moving trucks). Only call this from
## the host's _process.
func sync_transform(obj: Node, pos: Vector3, rot: Vector3) -> void:
	if not is_host() or obj == null or not is_instance_valid(obj):
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_apply_transform.rpc_id(0, parent_path, obj.name, pos, rot, 1) # 1 = unreliable channel


## Batch sync: sends ALL NPC transforms in a single RPC instead of one
## RPC per NPC. Dramatically reduces network overhead when many NPCs
## are active. Each entry in the arrays corresponds to one NPC:
## names[i] / positions[i] / rotations[i].
func sync_transforms_batch(
	names: PackedStringArray,
	positions: PackedVector3Array,
	rotations: PackedVector3Array,
) -> void:
	if not is_host():
		return
	_apply_transforms_batch.rpc_id(0, names, positions, rotations)


@rpc("authority", "call_local", "unreliable")
func _apply_transforms_batch(
	names: PackedStringArray,
	positions: PackedVector3Array,
	rotations: PackedVector3Array,
) -> void:
	if is_host():
		return
	var count := names.size()
	for i in count:
		var obj := _find_node_by_name_only(names[i])
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
	if not is_host():
		_rpc_request_property.rpc_id(1, obj.name, prop, value)
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_apply_property.rpc(parent_path, obj.name, prop, value)


@rpc("any_peer", "reliable")
func _rpc_request_property(obj_name: String, prop: String, value: Variant) -> void:
	if not is_host():
		return
	var obj := _find_node_by_name_only(obj_name)
	if obj == null or not is_instance_valid(obj):
		return
	obj.set(prop, value)
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_apply_property.rpc(parent_path, obj_name, prop, value)


## Sync multiple property changes at once (more efficient than calling
## sync_property for each one individually).
func sync_properties(obj: Node, props: Dictionary) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	if not is_host():
		_rpc_request_properties.rpc_id(1, obj.name, props)
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_apply_properties.rpc(parent_path, obj.name, props)


@rpc("any_peer", "reliable")
func _rpc_request_properties(obj_name: String, props: Dictionary) -> void:
	if not is_host():
		return
	var obj := _find_node_by_name_only(obj_name)
	if obj == null or not is_instance_valid(obj):
		return
	for key in props:
		obj.set(key, props[key])
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_apply_properties.rpc(parent_path, obj_name, props)


## Call a method on a world object on all clients (e.g. update_display).
func sync_call(obj: Node, method: String, args: Array = []) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	if not is_host():
		_rpc_request_call.rpc_id(1, obj.name, method, args)
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_call_method.rpc(parent_path, obj.name, method, args)


@rpc("any_peer", "reliable")
func _rpc_request_call(obj_name: String, method: String, args: Array) -> void:
	if not is_host():
		return
	var obj := _find_node_by_name_only(obj_name)
	if obj == null or not is_instance_valid(obj):
		return
	if obj.has_method(method):
		obj.callv(method, args)
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_call_method.rpc(parent_path, obj_name, method, args)


@rpc("authority", "call_local", "reliable")
func _apply_property(
	parent_path_str: String,
	obj_name: String,
	prop: String,
	value: Variant,
) -> void:
	if is_host():
		return
	var obj := _find_node(parent_path_str, obj_name)
	if obj:
		obj.set(prop, value)


@rpc("authority", "call_local", "unreliable")
func _apply_transform(
	parent_path_str: String,
	obj_name: String,
	pos: Vector3,
	rot: Vector3,
	_channel: int,
) -> void:
	if is_host():
		return
	var obj := _find_node(parent_path_str, obj_name)
	if obj:
		# If the object supports interpolation (e.g. NPCs), set the target
		# instead of snapping position directly
		if obj.has_method("net_set_target"):
			obj.net_set_target(pos, rot)
		else:
			obj.global_position = pos
			obj.global_rotation = rot


@rpc("authority", "call_local", "reliable")
func _apply_properties(parent_path_str: String, obj_name: String, props: Dictionary) -> void:
	if is_host():
		return
	var obj := _find_node(parent_path_str, obj_name)
	if obj:
		for key in props:
			obj.set(key, props[key])


@rpc("authority", "call_local", "reliable")
func _call_method(parent_path_str: String, obj_name: String, method: String, args: Array) -> void:
	if is_host():
		return
	var obj := _find_node(parent_path_str, obj_name)
	if obj and obj.has_method(method):
		obj.callv(method, args)


func _find_node(parent_path_str: String, obj_name: String) -> Node:
	# Check cache first
	if _node_cache.has(obj_name):
		var cached: Node = _node_cache[obj_name]
		if is_instance_valid(cached):
			return cached
		else:
			_node_cache.erase(obj_name)
	var parent := _string_to_node(parent_path_str)
	if parent:
		var obj := parent.get_node_or_null(obj_name)
		if obj:
			_node_cache[obj_name] = obj
			return obj
	# Fallback: search the entire scene tree by name in case the object
	# was re-parented on the host without the client knowing.
	var found := _find_node_by_name(get_tree().current_scene, obj_name)
	if found:
		_node_cache[obj_name] = found
	return found


## Fast name-only lookup for batch syncs (avoids serializing parent
## paths for every NPC every tick). Uses the cache, falls back to
## tree search only on cache miss.
func _find_node_by_name_only(obj_name: String) -> Node:
	if _node_cache.has(obj_name):
		var cached: Node = _node_cache[obj_name]
		if is_instance_valid(cached):
			return cached
		else:
			_node_cache.erase(obj_name)
	var found := _find_node_by_name(get_tree().current_scene, obj_name)
	if found:
		_node_cache[obj_name] = found
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

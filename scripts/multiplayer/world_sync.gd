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
	# Set state BEFORE adding to tree so _ready() sees configured values
	for key in state:
		obj.set(key, state[key])
	# Give the object a unique name so despawn can find it reliably.
	# Without this, multiple objects of the same type would all be named
	# e.g. "SupplyBox" and despawn would only find the first one.
	var base_name := obj.name
	obj.name = base_name + "_" + str(_spawn_counter)
	_spawn_counter += 1
	parent.add_child(obj)
	obj.global_position = global_pos
	obj.global_rotation = global_rot
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
func despawn_networked(obj: Node) -> void:
	if not is_host():
		return
	if obj == null or not is_instance_valid(obj):
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	var obj_name := obj.name
	GameLog.log("[WorldSync] Host despawning %s parent=%s" % [obj_name, parent_path])
	obj.queue_free()
	_despawn_on_clients.rpc(parent_path, obj_name)


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
	for key in state:
		obj.set(key, state[key])
	obj.name = obj_name
	parent.add_child(obj)
	obj.global_position = global_pos
	obj.global_rotation = global_rot
	obj.scale = obj_scale
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


## Sync a property change on a world object from host to all clients.
## Use this for container contents (fruit amounts, water, sugar, ice,
## cup counts, etc.) so all peers see the same state.
func sync_property(obj: Node, prop: String, value: Variant) -> void:
	if not is_host() or obj == null or not is_instance_valid(obj):
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_apply_property.rpc(parent_path, obj.name, prop, value)


## Sync multiple property changes at once (more efficient than calling
## sync_property for each one individually).
func sync_properties(obj: Node, props: Dictionary) -> void:
	if not is_host() or obj == null or not is_instance_valid(obj):
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_apply_properties.rpc(parent_path, obj.name, props)


## Call a method on a world object on all clients (e.g. update_display).
func sync_call(obj: Node, method: String, args: Array = []) -> void:
	if not is_host() or obj == null or not is_instance_valid(obj):
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	_call_method.rpc(parent_path, obj.name, method, args)


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

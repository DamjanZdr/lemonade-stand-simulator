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


func setup(world_objects: Node, spawner: MultiplayerSpawner) -> void:
	# Currently unused (we use RPC-based spawning instead of MultiplayerSpawner),
	# but kept for future use if we switch to spawner-based replication.
	pass


func is_host() -> bool:
	return multiplayer.is_server()


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
		push_warning("[WorldSync] Failed to load scene: " + scene_path)
		return null
	var obj := scene.instantiate()
	# Set state BEFORE adding to tree so _ready() sees configured values
	for key in state:
		obj.set(key, state[key])
	parent.add_child(obj)
	obj.global_position = global_pos
	obj.global_rotation = global_rot
	# Broadcast to clients
	var parent_path := _node_path_to_string(parent.get_path())
	_spawn_on_clients.rpc(scene_path, parent_path, obj.name, global_pos, global_rot, state)
	return obj


## Despawn a world object on the host and tell all clients to despawn it too.
func despawn_networked(obj: Node) -> void:
	if not is_host():
		return
	if obj == null or not is_instance_valid(obj):
		return
	var parent_path := _node_path_to_string(obj.get_parent().get_path())
	var obj_name := obj.name
	obj.queue_free()
	_despawn_on_clients.rpc(parent_path, obj_name)


@rpc("authority", "call_local", "reliable")
func _spawn_on_clients(
	scene_path: String,
	parent_path_str: String,
	obj_name: String,
	global_pos: Vector3,
	global_rot: Vector3,
	state: Dictionary,
) -> void:
	if is_host():
		return # Host already spawned it locally
	var parent := _string_to_node(parent_path_str)
	if parent == null:
		push_warning("[WorldSync] Client: parent not found: " + parent_path_str)
		return
	var scene := _get_scene(scene_path)
	if scene == null:
		push_warning("[WorldSync] Client: scene not found: " + scene_path)
		return
	var obj := scene.instantiate()
	for key in state:
		obj.set(key, state[key])
	obj.name = obj_name
	parent.add_child(obj)
	obj.global_position = global_pos
	obj.global_rotation = global_rot


@rpc("authority", "call_local", "reliable")
func _despawn_on_clients(parent_path_str: String, obj_name: String) -> void:
	if is_host():
		return
	var parent := _string_to_node(parent_path_str)
	if parent == null:
		return
	var obj := parent.get_node_or_null(obj_name)
	if obj:
		obj.queue_free()


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

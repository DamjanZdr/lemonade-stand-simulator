class_name Pickupable
extends Node
## Base component for world objects that can be picked up and placed.
##
## Attach this to a Node3D and either:
##   A) extend this script and override the virtual methods, or
##   B) set the Callable callbacks from the owner script for composition.
##
## Expected usage:
##   - Player raycasts an interactable.
##   - If the interactable has a Pickupable child, call pickupable.pick_up(player).
##   - Player stores the returned hand data.
##   - On place, call pickupable.place(player, world_parent, pos, rot).
##   - Pickupable handles spawning/restoring, reparenting children, and
##     despawn so the host stays authoritative.

## Type from HeldItem autoload used by the player.
@export var held_item_type: int = 0

## PackedScene instantiated for the first-person hand mesh.
## If null, get_hand_mesh_callback / get_hand_mesh() should provide one.
@export var hand_mesh_scene: PackedScene = null

## Optional Callable callbacks for composition. When set, the default
## virtual methods use them instead of doing nothing.
@export var can_pickup_callback: Callable
@export var save_state_callback: Callable
@export var get_held_data_callback: Callable
@export var get_hand_mesh_callback: Callable
@export var pick_up_callback: Callable
@export var place_callback: Callable


## Return true if this object can currently be picked up by the given player.
func can_pick_up(player: Node) -> bool:
	if can_pickup_callback.is_valid():
		return can_pickup_callback.call(player) as bool
	return _can_pick_up(player)


## Virtual: override in subclasses.
func _can_pick_up(_player: Node) -> bool:
	return true


## Return a Dictionary of state needed to recreate this object when placed.
func save_state() -> Dictionary:
	if save_state_callback.is_valid():
		return save_state_callback.call() as Dictionary
	return _save_state()


func _save_state() -> Dictionary:
	return { }


## Return per-frame data needed by the player while holding this object.
func get_held_data() -> Dictionary:
	if get_held_data_callback.is_valid():
		return get_held_data_callback.call() as Dictionary
	return _get_held_data()


func _get_held_data() -> Dictionary:
	return save_state()


## Return the hand mesh Node3D to attach to the player's camera/hand slot.
func get_hand_mesh() -> Node3D:
	if get_hand_mesh_callback.is_valid():
		return get_hand_mesh_callback.call() as Node3D
	return _get_hand_mesh()


func _get_hand_mesh() -> Node3D:
	if hand_mesh_scene == null:
		return null
	return hand_mesh_scene.instantiate() as Node3D


## Called on the authoritative peer when the object is picked up.
## Should release world slots, request despawn, and return the hand data.
func pick_up(player: Node) -> Dictionary:
	if pick_up_callback.is_valid():
		return pick_up_callback.call(player) as Dictionary
	return _pick_up(player)


func _pick_up(_player: Node) -> Dictionary:
	return get_held_data()


## Called on the authoritative peer when the object is placed.
## `state` is the dictionary returned by pick_up()/save_state().
## `parent` is the world node to attach the placed instance to.
## Should spawn/restore the object and return the placed Node.
func place(state: Dictionary, parent: Node, pos: Vector3, rot: Vector3) -> Node:
	if place_callback.is_valid():
		return place_callback.call(state, parent, pos, rot) as Node
	return _place(state, parent, pos, rot)


func _place(_state: Dictionary, _parent: Node, _pos: Vector3, _rot: Vector3) -> Node:
	return null


## Helper for container-type Interactables (FruitBin, IngredientBin, etc.)
## to add a Pickupable component that delegates to PlayerPlacement.pickup_container().
## Call this from the container's _ready().
static func setup_for_container(container: Interactable, container_type: String) -> Pickupable:
	var p := Pickupable.new()
	p.name = "Pickupable"
	p.held_item_type = HeldItem.CONTAINER
	p.can_pickup_callback = func(player: Node) -> bool:
		return player != null and player.get("held_item") == HeldItem.NONE
	p.pick_up_callback = func(player: Node) -> Dictionary:
		var pl := player as Player
		if pl == null or pl.held_item != HeldItem.NONE:
			return { }
		pl.pickup_container(container, container_type)
		return { }
	container.add_child(p)
	return p

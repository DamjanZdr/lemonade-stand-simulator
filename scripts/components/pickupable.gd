class_name Pickupable
extends Node
## Base component for world objects that can be picked up and placed.
##
## Attach this to a Node3D and implement the virtual methods (or connect
## to an owning script) to get a single pickup/placement path instead of
## special-casing every interactable in Player.gd.
##
## Expected usage:
##   - Player raycasts an interactable.
##   - If the interactable has a Pickupable child, call pickupable.pick_up(player).
##   - Player stores the returned hand data.
##   - On place, call pickupable.place(player, world_parent, pos, rot).
##   - Pickupable handles spawning/restoring, reparenting children, and
##     despawn so the host stays authoritative.

## Type from Player.HeldItem (or another inventory enum) used by the player.
@export var held_item_type: int = 0

## PackedScene instantiated for the first-person hand mesh.
## If null, get_hand_mesh() should be overridden or the player uses a generic mesh.
@export var hand_mesh_scene: PackedScene = null

## Return true if this object can currently be picked up by the given player.
## Override to add permission checks (e.g. not already held, correct team).
func can_pick_up(_player: Node) -> bool:
	return true

## Return a Dictionary of state needed to recreate this object when placed.
## Common keys: scene_path, transform, custom properties.
func save_state() -> Dictionary:
	return {}

## Return per-frame data needed by the player while holding this object.
## This often mirrors save_state() but may include extra runtime data.
func get_held_data() -> Dictionary:
	return save_state()

## Return the hand mesh Node3D to attach to the player's camera/hand slot.
## Default implementation instantiates hand_mesh_scene if set.
func get_hand_mesh() -> Node3D:
	if hand_mesh_scene == null:
		return null
	return hand_mesh_scene.instantiate() as Node3D

## Called on the authoritative peer when the object is picked up.
## Should release world slots, request despawn, and return the hand data.
## The default just returns get_held_data(); override for networked cleanup.
func pick_up(_player: Node) -> Dictionary:
	return get_held_data()

## Called on the authoritative peer when the object is placed.
## `state` is the dictionary returned by pick_up()/save_state().
## `parent` is the world node to attach the placed instance to.
## Should spawn/restore the object and return the placed Node.
func place(_state: Dictionary, _parent: Node, _pos: Vector3, _rot: Vector3) -> Node:
	return null

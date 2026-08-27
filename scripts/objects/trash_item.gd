class_name TrashItem
extends Interactable
## A piece of litter the player can pick up and throw in the trashcan for a refund.
## Each trash type has its own scene (trash_apple.tscn, trash_banana.tscn, etc.)
## with the model and collision shapes as direct children of the root Area3D.

@export var trash_value: float = 1.0
@export var trash_type: String = "trash"

## Set by WorldSync spawn state before _ready(). When set, the trash uses
## this variant instead of picking a random one — so all peers see the same.
var trash_variant: String = ""

var _visible_variant: Node3D = null
const _VARIANT_NAMES: Array[String] = ["apple", "banana", "can", "cigarettes", "cup"]

## Map from trash type to its scene path.
const _VARIANT_SCENES: Dictionary = {
	"apple": "res://scenes/objects/trash_apple.tscn",
	"banana": "res://scenes/objects/trash_banana.tscn",
	"can": "res://scenes/objects/trash_can.tscn",
	"cigarettes": "res://scenes/objects/trash_cigarettes.tscn",
	"cup": "res://scenes/objects/trash_cup.tscn",
}


func _ready() -> void:
	add_to_group("trash_item")
	# Find the visible model child (the GLB instance).
	# In the split scenes, the model is a direct child named after the variant.
	for child in get_children():
		if child is Node3D and not child is CollisionShape3D:
			_visible_variant = child as Node3D
			break
	if trash_variant != "" and trash_type != trash_variant:
		# If trash_variant was set but doesn't match the current scene's type,
		# swap to the correct variant scene.
		_swap_to_variant(trash_variant)
	# Set trash_type from the visible variant if not already set.
	if trash_type == "trash" and _visible_variant != null:
		trash_type = _visible_variant.name
	# Set trash_value from the trash manager if not already set.
	if trash_value <= 0.0:
		var manager := _get_trash_manager()
		if manager != null and _visible_variant != null:
			trash_value = manager.get_value(_visible_variant.name)


## Swap this trash item to a different variant by replacing it with
## the appropriate scene instance at the same position/rotation.
func _swap_to_variant(variant_name: String) -> void:
	var scene_path: String = _VARIANT_SCENES.get(variant_name, "")
	if scene_path == "":
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var pos := global_position
	var rot := global_rotation
	var parent := get_parent()
	# Hide current variant.
	if _visible_variant:
		_visible_variant.visible = false
	# Instance the new variant scene as a child.
	var inst := scene.instantiate()
	# We only want the model child, not the Area3D root.
	# So we'll grab the model node from the instanced scene.
	var model_node: Node3D = null
	for child in inst.get_children():
		if child is Node3D and not child is CollisionShape3D:
			model_node = child as Node3D
			break
	if model_node:
		# Remove from the instanced scene and add to ourself.
		inst.remove_child(model_node)
		# Remove old model if any.
		if _visible_variant and is_instance_valid(_visible_variant):
			_visible_variant.queue_free()
		add_child(model_node)
		_visible_variant = model_node
		_visible_variant.visible = true
	inst.queue_free()
	trash_type = variant_name


func show_variant(variant_name: String) -> void:
	trash_variant = variant_name
	_swap_to_variant(variant_name)


func interact(player: Node) -> void:
	var p := player as Player
	if p == null:
		return
	if p.held_item != HeldItem.NONE:
		return
	set_highlight(false)
	p.inventory.make_held_trash(trash_value, trash_type, _create_hand_mesh())
	# Despawn via WorldSync so all players see the trash removed.
	# request_despawn works on both host (despawns directly) and
	# clients (sends RPC to host to despawn).
	WorldSync.request_despawn(self)


func interact_secondary(player: Node) -> void:
	interact(player)


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null or p.held_item != HeldItem.NONE:
		return ""
	return "Trash | LMB: pick up"


func _create_hand_mesh() -> Node3D:
	if _visible_variant == null:
		return null
	var copy := _visible_variant.duplicate() as Node3D
	if copy == null:
		return null
	copy.visible = true
	copy.position = Vector3.ZERO
	copy.rotation = Vector3.ZERO
	copy.scale = Vector3.ONE * 0.1
	_remove_outline(copy)
	_disable_collisions(copy)
	return copy


func _disable_collisions(node: Node) -> void:
	var col := node as CollisionObject3D
	if col != null:
		col.collision_layer = 0
		col.collision_mask = 0
		if col is Area3D:
			col.monitoring = false
			col.monitorable = false
	for child in node.get_children():
		_disable_collisions(child)


func _remove_outline(node: Node) -> void:
	for child in node.get_children():
		if child.name == "_Outline":
			child.queue_free()
		else:
			_remove_outline(child)


func _get_trash_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("trash_manager")

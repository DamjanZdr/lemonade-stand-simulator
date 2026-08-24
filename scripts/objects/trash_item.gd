class_name TrashItem
extends Interactable
## A piece of litter the player can pick up and throw in the trashcan for a refund.

@export var trash_value: float = 1.0
@export var trash_type: String = "trash"

## Set by WorldSync spawn state before _ready(). When set, the trash uses
## this variant instead of picking a random one — so all peers see the same.
var trash_variant: String = ""

var _visible_variant: Node3D = null
const _VARIANT_NAMES: Array[String] = ["apple", "banana", "can", "cigarettes", "cup"]


func _ready() -> void:
	add_to_group("trash_item")
	if trash_variant != "":
		show_variant(trash_variant)
	else:
		_pick_random_variant()
	# Clients can interact with trash — the pickup routes through the
	# host via WorldSync.despawn_networked() which sends a despawn RPC
	# to all peers. The host handles the actual despawn.
	# We keep collision enabled on all peers so raycasts can hit trash.


func _pick_random_variant() -> void:
	var available: Array[Node3D] = []
	for variant_name in _VARIANT_NAMES:
		var node := get_node_or_null(variant_name) as Node3D
		if node != null:
			node.visible = false
			available.append(node)
	if available.is_empty():
		return
	_visible_variant = available[randi() % available.size()]
	_visible_variant.visible = true
	trash_type = _visible_variant.name
	var manager := _get_trash_manager()
	if manager != null:
		trash_value = manager.get_value(_visible_variant.name)


func show_variant(variant_name: String) -> void:
	for variant_name_ in _VARIANT_NAMES:
		var node := get_node_or_null(variant_name_) as Node3D
		if node != null:
			node.visible = (variant_name_ == variant_name)
	_visible_variant = get_node_or_null(variant_name) as Node3D
	if _visible_variant != null:
		trash_type = variant_name
		var manager := _get_trash_manager()
		if manager != null:
			trash_value = manager.get_value(variant_name)


func interact(player: Node) -> void:
	var p := player as Player
	if p == null:
		return
	if p.held_item != Player.HeldItem.NONE:
		return
	set_highlight(false)
	p.make_held_trash(trash_value, trash_type, _create_hand_mesh())
	# Despawn via WorldSync so all players see the trash removed.
	# request_despawn works on both host (despawns directly) and
	# clients (sends RPC to host to despawn).
	WorldSync.request_despawn(self)


func interact_secondary(player: Node) -> void:
	interact(player)


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null or p.held_item != Player.HeldItem.NONE:
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

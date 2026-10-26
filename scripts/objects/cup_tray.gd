class_name CupTray
extends Node3D
## A fixed tray on the counter holding filled cups in authored slots.
## The server assistant fills free slots; players pick cups off it like
## any other placed cup (cups are regular networked Cup objects).
## Not pickupable — it's stand furniture once spawned.

@onready var _slots: Node3D = $Slots


## World position of the first free slot, or Vector3.INF when full.
func free_slot_position() -> Vector3:
	for m in _slots.get_children():
		var p: Vector3 = m.global_position
		if not _slot_occupied(p):
			return p
	return Vector3.INF


func has_free_slot() -> bool:
	return free_slot_position() != Vector3.INF


func _slot_occupied(p: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group("container"):
		if n is Cup and is_instance_valid(n) \
				and n.global_position.distance_to(p) < 0.12:
			return true
	return false

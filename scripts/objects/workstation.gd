class_name Workstation
extends Interactable
## A placeable/movable table surface that other equipment can sit on.


func _ready() -> void:
	add_to_group("container")
	Pickupable.setup_for_container(self, "workstation")


func get_hint(_player: Node) -> String:
	return "Table"


## True when a container is sitting on this table — either already
## reparented to it (after a pickup) or resting on its surface in the
## world. Items placed on a table live as world siblings, so children
## alone don't tell the story. Bounds mirror _attach_items_to_workstation.
func has_items_on() -> bool:
	for child in get_children():
		if child.is_in_group("container"):
			return true
	for item in get_tree().get_nodes_in_group("container"):
		if item == self or item is Workstation or not item is Node3D:
			continue
		var parent := (item as Node).get_parent()
		if parent == null:
			continue
		if parent != get_tree().current_scene and parent.name != "WorldObjects":
			continue
		var pos := (item as Node3D).global_position
		if pos.y < global_position.y + 0.8 or pos.y > global_position.y + 1.5:
			continue
		if absf(pos.x - global_position.x) > 1.0 \
				or absf(pos.z - global_position.z) > 1.0:
			continue
		return true
	return false

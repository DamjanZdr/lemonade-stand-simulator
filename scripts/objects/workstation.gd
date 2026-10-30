class_name Workstation
extends Interactable
## A placeable/movable table surface that other equipment can sit on.


func _ready() -> void:
	add_to_group("container")
	Pickupable.setup_for_container(self, "workstation")


func get_hint(_player: Node) -> String:
	return "Table"


func supports_item(item: Node3D) -> bool:
	if item == self:
		return false
	if is_ancestor_of(item):
		return true
	var local := to_local(item.global_position)
	return local.y >= 0.8 and local.y <= 1.5 and absf(local.x) <= 0.8 and absf(local.z) <= 0.8


func nearest_access_marker(from: Vector3) -> Marker3D:
	var best: Marker3D = null
	var best_distance := INF
	for marker_name in ["1", "2", "3", "4"]:
		var marker := get_node_or_null(marker_name) as Marker3D
		if marker == null:
			continue
		var distance := Vector2(
			marker.global_position.x - from.x,
			marker.global_position.z - from.z,
		).length_squared()
		if distance < best_distance:
			best = marker
			best_distance = distance
	return best


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

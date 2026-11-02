extends "res://scripts/player/player_placement.gd"

var ghost: Node3D:
	get:
		return _ghost
	set(value):
		_ghost = value

var ghost_valid: bool:
	get:
		return _ghost_valid

var workstation_scene: PackedScene:
	get:
		return _workstation_scene
	set(value):
		_workstation_scene = value


func is_box_floor_hit(collider: Object) -> bool:
	return _is_box_floor_hit(collider)


func get_bottom_box_in_stack(box: SupplyBox) -> SupplyBox:
	return _get_bottom_box_in_stack(box)


func get_topmost_box_in_stack(box: SupplyBox) -> SupplyBox:
	return _get_topmost_box_in_stack(box)


func stack_base_is_placeable(box: SupplyBox) -> bool:
	return _stack_base_is_placeable(box)


func update_equipment_box_ghost() -> void:
	_update_equipment_box_ghost()


func destroy_ghost() -> void:
	_destroy_ghost()


func disable_physics(node: Node) -> void:
	_disable_physics(node)


func check_ghost_overlap() -> bool:
	return _check_ghost_overlap()


func create_ghost(container_type: String) -> void:
	_create_ghost(container_type)

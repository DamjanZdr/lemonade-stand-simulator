class_name DeliveryGrid
extends Node3D
## Defines a 3x3 grid of delivery drop points using Marker3D children.
## Boxes fill the grid in order, then stack upward on the same cell.

const STACK_MAX_OFFSET: float = 0.04
const STACK_MAX_YAW: float = 0.14

@export var grid_width: int = 3
@export var grid_depth: int = 3
@export var is_truck_grid: bool = false
## Offset from marker to box origin. Set to the box's bottom offset so it sits on the marker.

var _cells: Array[Marker3D] = []
var _stacks: Array[int] = []
var _cell_offsets: Dictionary = { }
var _cell_yaws: Dictionary = { }


func _ready() -> void:
	_find_cells()
	if not is_truck_grid:
		add_to_group("delivery_grid")
		# Defer counting so save manager has time to respawn boxes
		get_tree().create_timer(0.5).timeout.connect(_count_existing_boxes)


func _count_existing_boxes() -> void:
	if is_truck_grid:
		return
	# Boxes are children of the world root, not the grid.
	# Search the supply_box group for boxes near this grid's cells.
	var boxes: Array[Node] = get_tree().get_nodes_in_group("supply_box")
	for node in boxes:
		if not is_instance_valid(node) or node is not SupplyBox:
			continue
		if node.is_in_group("ghost"):
			continue
		var box := node as SupplyBox
		# Check if this box is on our grid by finding the closest cell
		var cell_idx := get_closest_cell(box.global_position)
		if cell_idx < 0:
			continue
		# Verify the box is actually near this grid (not just closest by default)
		var marker := _cells[cell_idx]
		if marker == null:
			continue
		var dx := marker.global_position.x - box.global_position.x
		var dz := marker.global_position.z - box.global_position.z
		var dist_sq := dx * dx + dz * dz
		if dist_sq > 1.0: # within 1 unit of a cell marker
			continue
		_stacks[cell_idx] += 1
		box.set_meta("delivery_cell_idx", cell_idx)
		if not box.is_connected("tree_exited", release_slot_index):
			box.tree_exited.connect(release_slot_index.bind(cell_idx))


func _find_cells() -> void:
	_cells.clear()
	_stacks.clear()
	var cell_count := grid_width * grid_depth
	for i in range(cell_count):
		var marker := get_node_or_null("Cell_" + str(i)) as Marker3D
		if marker == null:
			marker = get_node_or_null("Cell" + str(i)) as Marker3D
		if marker == null:
			push_warning("DeliveryGrid missing marker for cell %d" % i)
		_cells.append(marker)
		_stacks.append(0)


## Reserves the next free slot and returns its index, world position and rotation.
func reserve_next_slot() -> Dictionary:
	var best_idx := 0
	var best_height := _stacks[0]
	for i in range(_stacks.size()):
		if _stacks[i] < best_height:
			best_height = _stacks[i]
			best_idx = i
	return reserve_slot(best_idx)


## Reserves a specific cell and returns its index, world position and rotation.
func reserve_slot(cell_index: int) -> Dictionary:
	if cell_index < 0 or cell_index >= _stacks.size():
		push_warning("DeliveryGrid.reserve_slot: invalid cell index %d" % cell_index)
		return { "index": -1, "position": global_position, "rotation": Vector3.ZERO }

	var pos := get_slot_position(cell_index)
	var rot := get_slot_rotation(cell_index)
	_stacks[cell_index] += 1
	return { "index": cell_index, "position": pos, "rotation": rot }


## Returns the position for the next box in a cell without reserving it.
func get_slot_position(cell_index: int) -> Vector3:
	if cell_index < 0 or cell_index >= _cells.size():
		push_warning("DeliveryGrid.get_slot_position: invalid cell index %d" % cell_index)
		return global_position
	var marker := _cells[cell_index]
	var base := marker.global_position if marker != null else global_position
	var grid_scale_y: float = absf(global_transform.basis.y.y)
	var sh: float = SupplyBox.stack_height * grid_scale_y
	var bo: float = SupplyBox.bottom_offset * grid_scale_y
	var height: float = _stacks[cell_index] * sh + bo
	return base + Vector3(0, height, 0) + _get_cell_offset(cell_index, _stacks[cell_index])


## Returns the rotation for the next box in a cell without reserving it.
func get_slot_rotation(cell_index: int) -> Vector3:
	var base_rot := Vector3.ZERO
	if cell_index >= 0 and cell_index < _cells.size():
		var marker := _cells[cell_index]
		if marker != null:
			base_rot = marker.global_rotation
	return base_rot + Vector3(0, _get_cell_yaw(cell_index, _stacks[cell_index]), 0)


## Returns the closest grid cell to the given world point (using X/Z distance).
func get_closest_cell(point: Vector3) -> int:
	var best := -1
	var best_dist := INF
	for i in range(_cells.size()):
		var marker := _cells[i]
		if marker == null:
			continue
		var dx := marker.global_position.x - point.x
		var dz := marker.global_position.z - point.z
		var dist := dx * dx + dz * dz
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


func _get_cell_offset(cell_index: int, stack_level: int) -> Vector3:
	var key := cell_index * 1000 + stack_level
	if not _cell_offsets.has(key):
		_cell_offsets[key] = Vector3(
			randf_range(-STACK_MAX_OFFSET, STACK_MAX_OFFSET),
			0.0,
			randf_range(-STACK_MAX_OFFSET, STACK_MAX_OFFSET),
		)
	return _cell_offsets[key] as Vector3


func _get_cell_yaw(cell_index: int, stack_level: int) -> float:
	var key := cell_index * 1000 + stack_level
	if not _cell_yaws.has(key):
		_cell_yaws[key] = randf_range(-STACK_MAX_YAW, STACK_MAX_YAW)
	return _cell_yaws[key] as float


## Returns the world position for the next box and reserves that slot.
func get_next_position() -> Vector3:
	return reserve_next_slot().get("position", global_position)


## Releases a slot by its index when a box is removed from the grid.
func release_slot_index(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= _stacks.size():
		return
	_stacks[cell_index] = max(0, _stacks[cell_index] - 1)
	if _stacks[cell_index] == 0:
		for key in _cell_offsets.keys():
			if key / 1000 == cell_index:
				_cell_offsets.erase(key)
		for key in _cell_yaws.keys():
			if key / 1000 == cell_index:
				_cell_yaws.erase(key)


func total_capacity() -> int:
	return _cells.size()


func reset_stacks() -> void:
	for i in range(_stacks.size()):
		_stacks[i] = 0
	_cell_offsets.clear()
	_cell_yaws.clear()

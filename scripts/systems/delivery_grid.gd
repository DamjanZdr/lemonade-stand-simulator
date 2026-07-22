class_name DeliveryGrid
extends Node3D
## Defines a 3x3 grid of delivery drop points using Marker3D children.
## Boxes fill the grid in order, then stack upward on the same cell.

const STACK_MAX_OFFSET: float = 0.04
const STACK_MAX_YAW: float = 0.14

@export var grid_width: int = 3
@export var grid_depth: int = 3
## Offset from marker to box origin. Set to the box's bottom offset so it sits on the marker.

var _cells: Array[Marker3D] = []
var _stacks: Array[int] = []
var _cell_offsets: Dictionary = { }
var _cell_yaws: Dictionary = { }


func _ready() -> void:
	_find_cells()
	add_to_group("delivery_grid")


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
	var height := _stacks[cell_index] * SupplyBox.stack_height + SupplyBox.bottom_offset
	return base + Vector3(0, height, 0) + _get_cell_offset(cell_index)


## Returns the rotation for the next box in a cell without reserving it.
func get_slot_rotation(cell_index: int) -> Vector3:
	var base_rot := Vector3.ZERO
	if cell_index >= 0 and cell_index < _cells.size():
		var marker := _cells[cell_index]
		if marker != null:
			base_rot = marker.global_rotation
	return base_rot + Vector3(0, _get_cell_yaw(cell_index), 0)


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


func _get_cell_offset(cell_index: int) -> Vector3:
	if not _cell_offsets.has(cell_index):
		_cell_offsets[cell_index] = Vector3(
			randf_range(-STACK_MAX_OFFSET, STACK_MAX_OFFSET),
			0.0,
			randf_range(-STACK_MAX_OFFSET, STACK_MAX_OFFSET),
		)
	return _cell_offsets[cell_index] as Vector3


func _get_cell_yaw(cell_index: int) -> float:
	if not _cell_yaws.has(cell_index):
		_cell_yaws[cell_index] = randf_range(-STACK_MAX_YAW, STACK_MAX_YAW)
	return _cell_yaws[cell_index] as float


## Returns the world position for the next box and reserves that slot.
func get_next_position() -> Vector3:
	return reserve_next_slot().get("position", global_position)


## Releases a slot by its index when a box is removed from the grid.
func release_slot_index(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= _stacks.size():
		return
	_stacks[cell_index] = max(0, _stacks[cell_index] - 1)
	if _stacks[cell_index] == 0:
		_cell_offsets.erase(cell_index)
		_cell_yaws.erase(cell_index)


func total_capacity() -> int:
	return _cells.size()

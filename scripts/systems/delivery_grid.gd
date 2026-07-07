class_name DeliveryGrid
extends Node3D
## Defines a 3x3 grid of delivery drop points using Marker3D children.
## Boxes fill the grid in order, then stack upward on the same cell.

const STACK_HEIGHT: float = 0.262

@export var grid_width: int = 3
@export var grid_depth: int = 3

var _cells: Array[Marker3D] = []
var _stacks: Array[int] = []


func _ready() -> void:
	_find_cells()


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


## Reserves the next free slot and returns its index and world position.
func reserve_next_slot() -> Dictionary:
	var best_idx := 0
	var best_height := _stacks[0]
	for i in range(_stacks.size()):
		if _stacks[i] < best_height:
			best_height = _stacks[i]
			best_idx = i
	_stacks[best_idx] += 1

	var marker := _cells[best_idx]
	var pos := global_position
	if marker != null:
		pos = marker.global_position
	pos += Vector3(0, best_height * STACK_HEIGHT, 0)
	return { "index": best_idx, "position": pos }


## Returns the world position for the next box and reserves that slot.
func get_next_position() -> Vector3:
	return reserve_next_slot().get("position", global_position)


## Releases a slot by its index when a box is removed from the grid.
func release_slot_index(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= _stacks.size():
		return
	_stacks[cell_index] = max(0, _stacks[cell_index] - 1)


func total_capacity() -> int:
	return _cells.size()

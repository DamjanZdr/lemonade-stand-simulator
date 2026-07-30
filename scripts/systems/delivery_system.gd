extends Node
## Listens for supply orders. Batches them onto the truck's grid.
## On checkout_completed, the truck drives in and arcs boxes to the delivery grid.

const SUPPLY_BOX_SCENE: PackedScene = preload("res://scenes/objects/supply_box.tscn")

var _grid: DeliveryGrid = null
var _fallback_zone: Vector3 = Vector3(5.0, 0.5, 5.0)
var _truck: DeliveryTruck = null
var _truck_grid: DeliveryGrid = null
var _batched_boxes: Array[SupplyBox] = []


func _ready() -> void:
	EventBus.supply_order_placed.connect(_on_supply_order_placed)
	EventBus.equipment_order_placed.connect(_on_equipment_order_placed)
	EventBus.checkout_completed.connect(_on_checkout_completed)


func set_grid(grid: DeliveryGrid) -> void:
	_grid = grid


func set_delivery_zone(pos: Vector3) -> void:
	_fallback_zone = pos


func _ensure_truck() -> void:
	if _truck != null and is_instance_valid(_truck):
		return
	# Find the truck placed in the world scene
	var world := get_tree().current_scene
	_truck = world.find_child("DeliveryTruck", true, false) as DeliveryTruck
	if _truck == null:
		push_warning("DeliverySystem: no DeliveryTruck found in world")
		return
	_truck_grid = _truck.get_node("DeliveryGrid") as DeliveryGrid
	# Wire the target grid so the truck knows where to deliver
	if _grid != null:
		_truck.set_target_grid(_grid)


func _spawn_box_on_truck(box: SupplyBox) -> void:
	_ensure_truck()

	_truck_grid.add_child(box)
	box.update_metrics()

	var target := _truck_grid.global_position
	var cell_idx := -1
	var rot := Vector3.ZERO
	var slot := _truck_grid.reserve_next_slot()
	cell_idx = slot.get("index", -1)
	target = slot.get("position", _truck_grid.global_position)
	rot = slot.get("rotation", Vector3.ZERO)

	box.global_position = target
	box.global_rotation = rot
	EventBus.supply_box_spawned.emit(box)

	if cell_idx >= 0:
		box.set_meta("truck_cell_idx", cell_idx)

	_batched_boxes.append(box)


func _on_checkout_completed() -> void:
	if _batched_boxes.is_empty():
		return
	if _truck == null or not is_instance_valid(_truck):
		_ensure_truck()

	# Queue boxes on the truck for transfer
	for box in _batched_boxes:
		_truck.queue_box(box, box.get_meta("truck_cell_idx", -1))
	_batched_boxes.clear()

	# Start the delivery sequence (rearrange, drive in, transfer, drive away)
	_truck.start_delivery()


func _on_supply_order_placed(ingredient_type: String, quantity: float, _cost: float) -> void:
	var box: SupplyBox = SUPPLY_BOX_SCENE.instantiate()
	box.ingredient_type = ingredient_type
	box.quantity = quantity
	_spawn_box_on_truck(box)


func _on_equipment_order_placed(container_type: String) -> void:
	var box: SupplyBox = SUPPLY_BOX_SCENE.instantiate()
	box.is_equipment = true
	box.equipment_type = container_type
	_spawn_box_on_truck(box)

extends Node
## Listens for supply orders. Batches them onto the truck's grid.
## On checkout_completed, the truck drives in and arcs boxes to the delivery grid.

const SUPPLY_BOX_SCENE: PackedScene = preload("res://scenes/objects/supply_box.tscn")

var _grid: DeliveryGrid = null
var _fallback_zone: Vector3 = Vector3(5.0, 0.5, 5.0)
var _truck: DeliveryTruck = null
var _truck_grid: DeliveryGrid = null
var _batched_boxes: Array[SupplyBox] = []
## Which truck (by node name, searched under the current scene) this
## DeliverySystem instance should use. Defaults to "DeliveryTruck" for
## backward compatibility with the single-stand setup; a second
## DeliverySystem instance (for a second stand) sets this to
## "DeliveryTruck2" via set_truck_name() before its first delivery.
var _truck_name: String = "DeliveryTruck"
## Which stand this delivery system serves. Set by main.gd during setup.
## Used to assign stand_owner on spawned supply boxes.
var _stand_name: String = ""


func _ready() -> void:
	EventBus.supply_order_placed.connect(_on_supply_order_placed)
	EventBus.equipment_order_placed.connect(_on_equipment_order_placed)
	EventBus.checkout_completed.connect(_on_checkout_completed)
	SupplyBox.pre_render_all()


func set_grid(grid: DeliveryGrid) -> void:
	_grid = grid


func set_delivery_zone(pos: Vector3) -> void:
	_fallback_zone = pos


## Sets which truck (by node name) this DeliverySystem instance targets.
## Call before the first order for a non-default (second, third, ...)
## stand's DeliverySystem instance.
func set_truck_name(truck_name: String) -> void:
	_truck_name = truck_name
	_truck = null # force re-lookup with the new name


## Set which stand this delivery system serves (by StandUnit node name).
## Spawned supply boxes will be assigned to this stand.
func set_stand_name(stand_name: String) -> void:
	_stand_name = stand_name


func _ensure_truck() -> void:
	if _truck != null and is_instance_valid(_truck):
		return
	# Find the truck placed in the world scene
	var world := get_tree().current_scene
	_truck = world.find_child(_truck_name, true, false) as DeliveryTruck
	if _truck == null:
		push_warning("DeliverySystem: no '%s' found in world" % _truck_name)
		return
	_truck_grid = _truck.get_node("DeliveryGrid") as DeliveryGrid
	# Wire the target grid so the truck knows where to deliver
	if _grid != null:
		_truck.set_target_grid(_grid)


func _spawn_box_on_truck(box: SupplyBox) -> void:
	_ensure_truck()
	if _truck_grid == null:
		return

	# Build state dict for replication
	var state: Dictionary = {
		"ingredient_type": box.ingredient_type,
		"quantity": box.quantity,
		"is_equipment": box.is_equipment,
		"equipment_type": box.equipment_type,
	}
	# Assign stand ownership so the box belongs to the stand that ordered it.
	if _stand_name != "":
		state["stand_owner"] = _stand_name

	# Calculate position on truck grid
	var target := _truck_grid.global_position
	var cell_idx := -1
	var rot := Vector3.ZERO
	var slot := _truck_grid.reserve_next_slot()
	cell_idx = slot.get("index", -1)
	target = slot.get("position", _truck_grid.global_position)
	rot = slot.get("rotation", Vector3.ZERO)

	# Use WorldSync to spawn and replicate to clients
	var spawned := WorldSync.spawn_networked(
		"res://scenes/objects/supply_box.tscn",
		_truck_grid,
		target,
		rot,
		state,
	)
	if spawned:
		box = spawned as SupplyBox
		box.update_metrics()
		EventBus.supply_box_spawned.emit(box)
		if cell_idx >= 0:
			box.set_meta("truck_cell_idx", cell_idx)
		_batched_boxes.append(box)


func _on_checkout_completed(stand_name: String) -> void:
	# Only process checkout for our own stand.
	if stand_name != "" and _stand_name != "" and stand_name != _stand_name:
		return
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


func _on_supply_order_placed(
	ingredient_type: String,
	quantity: float,
	_cost: float,
	stand_name: String,
) -> void:
	if not WorldSync.is_host():
		return
	# Only process orders for our own stand.
	if stand_name != "" and _stand_name != "" and stand_name != _stand_name:
		return
	var box: SupplyBox = SUPPLY_BOX_SCENE.instantiate()
	box.ingredient_type = ingredient_type
	box.quantity = quantity
	_spawn_box_on_truck(box)


func _on_equipment_order_placed(container_type: String, stand_name: String) -> void:
	if not WorldSync.is_host():
		return
	# Only process orders for our own stand.
	if stand_name != "" and _stand_name != "" and stand_name != _stand_name:
		return
	var box: SupplyBox = SUPPLY_BOX_SCENE.instantiate()
	box.is_equipment = true
	box.equipment_type = container_type
	_spawn_box_on_truck(box)

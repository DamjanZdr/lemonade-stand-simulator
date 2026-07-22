extends Node
## Listens for supply orders. Spawns a supply box at the next free grid cell, then Tweens it down.

const DeliveryGrid := preload("res://scripts/systems/delivery_grid.gd")
const SUPPLY_BOX_SCENE: PackedScene = preload("res://scenes/objects/supply_box.tscn")

var _grid: DeliveryGrid = null
var _fallback_zone: Vector3 = Vector3(5.0, 0.5, 5.0)


func _ready() -> void:
	EventBus.supply_order_placed.connect(_on_supply_order_placed)
	EventBus.equipment_order_placed.connect(_on_equipment_order_placed)


func set_grid(grid: DeliveryGrid) -> void:
	_grid = grid


func set_delivery_zone(pos: Vector3) -> void:
	_fallback_zone = pos


func _spawn_box(box: SupplyBox) -> void:
	get_parent().add_child(box)

	# Ensure stacking metrics are derived from the current box mesh scale.
	box.update_metrics()

	var target := _fallback_zone
	var cell_idx := -1
	var rot := Vector3.ZERO
	if _grid != null:
		var slot := _grid.reserve_next_slot()
		cell_idx = slot.get("index", -1)
		target = slot.get("position", _fallback_zone)
		rot = slot.get("rotation", Vector3.ZERO)

	var drop_start := target + Vector3(0, Balancing.DELIVERY_DROP_HEIGHT, 0)
	box.global_position = drop_start
	box.global_rotation = rot
	EventBus.supply_box_spawned.emit(box)

	if _grid != null and cell_idx >= 0:
		box.set_meta("delivery_cell_idx", cell_idx)
		box.tree_exited.connect(_grid.release_slot_index.bind(cell_idx))

	var tween := box.create_tween()
	tween.tween_property(box, "global_position", target, 0.7) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _on_supply_order_placed(ingredient_type: String, quantity: float, _cost: float) -> void:
	## Callers (phone menu / shop UI) handle payment before emitting.
	## This system only spawns the physical box.
	var box: SupplyBox = SUPPLY_BOX_SCENE.instantiate()
	box.ingredient_type = ingredient_type
	box.quantity = quantity
	_spawn_box(box)


func _on_equipment_order_placed(container_type: String) -> void:
	var box: SupplyBox = SUPPLY_BOX_SCENE.instantiate()
	box.is_equipment = true
	box.equipment_type = container_type
	_spawn_box(box)

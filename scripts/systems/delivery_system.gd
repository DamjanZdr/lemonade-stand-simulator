extends Node
## Listens for supply orders. Spawns a supply box at the delivery zone, then Tweens it down.

const SUPPLY_BOX_SCENE: PackedScene = preload("res://scenes/objects/supply_box.tscn")

var delivery_zone: Vector3 = Vector3(5.0, 0.5, 5.0) # set by main via set_delivery_zone()


func _ready() -> void:
	EventBus.supply_order_placed.connect(_on_supply_order_placed)


func set_delivery_zone(pos: Vector3) -> void:
	delivery_zone = pos


func _on_supply_order_placed(ingredient_type: String, quantity: float, _cost: float) -> void:
	## Callers (phone menu / shop UI) handle payment before emitting.
	## This system only spawns the physical box.
	var box: SupplyBox = SUPPLY_BOX_SCENE.instantiate()
	box.ingredient_type = ingredient_type
	box.quantity = quantity
	get_parent().add_child(box)

	var drop_start := delivery_zone + Vector3(0, Balancing.DELIVERY_DROP_HEIGHT, 0)
	box.global_position = drop_start
	EventBus.supply_box_spawned.emit(box)

	var tween := box.create_tween()
	tween.tween_property(box, "global_position", delivery_zone, 0.7) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

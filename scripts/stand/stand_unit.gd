class_name StandUnit
extends Node3D
## A single, self-contained lemonade stand: counter, price board, delivery
## grid/marker, thermometer, water dispenser, and customer queue markers.
##
## Multiple StandUnit instances can exist in the world (one per player/AI).
## All the nodes below are children of this node so the whole unit can be
## duplicated and repositioned as a single group. Positions of the children
## were preserved exactly as they were when they were direct children of
## World (this node itself has an identity transform), so nothing visually
## moved when they were grouped here.

@onready var delivery_grid: DeliveryGrid = $DeliveryGrid as DeliveryGrid
@onready var delivery_marker: Marker3D = $DeliveryMarker
@onready var queue_marker_active: Marker3D = $QueueMarkerActive
@onready var queue_marker_1: Marker3D = $QueueMarker1
@onready var queue_marker_2: Marker3D = $QueueMarker2
@onready var price_board: Node3D = $PriceBoard
@onready var thermometer: Node3D = $Thermometer
@onready var water_dispenser: Node3D = $WaterDispenser
@onready var stand_mesh: Node3D = $Stand


## Returns the customer queue spots (active spot + up to 299 waiting spots),
## matching the logic previously inlined in main.gd.
func get_queue_spots() -> Array[Vector3]:
	var active_pos := Vector3(0.0, 0.0, -1.0)
	var start := Vector3(0.0, 0.0, -2.0)
	var step := Vector3(0.0, 0.0, -1.0)
	if queue_marker_active:
		active_pos = queue_marker_active.global_position
	if queue_marker_1:
		start = queue_marker_1.global_position
		if queue_marker_2:
			step = queue_marker_2.global_position - queue_marker_1.global_position
	var spots: Array[Vector3] = []
	spots.append(active_pos)
	for i in range(299):
		spots.append(start + step * float(i))
	return spots


func get_queue_step() -> Vector3:
	if queue_marker_1 and queue_marker_2:
		return queue_marker_2.global_position - queue_marker_1.global_position
	return Vector3(0.0, 0.0, -1.0)


func get_delivery_grid() -> DeliveryGrid:
	return delivery_grid


func get_delivery_marker_position() -> Vector3:
	if delivery_marker:
		return delivery_marker.global_position
	return global_position

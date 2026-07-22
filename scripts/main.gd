extends Node
## Main scene root. Wires everything together at startup.

const CASH_PICKUP_SCENE: PackedScene = preload("res://scenes/objects/cash_pickup.tscn")
const OUTLINE_SCENE: PackedScene = preload("res://scenes/ui/outline_overlay.tscn")
const DAY_SUMMARY_SCENE: PackedScene = preload("res://scenes/ui/day_summary.tscn")
const DeliveryGrid := preload("res://scripts/systems/delivery_grid.gd")

@onready var world: Node3D = $World
@onready var player: CharacterBody3D = $Player
@onready var spawner: Node = $CustomerSpawner
@onready var ped_spawner: Node = $PedestrianSpawner
@onready var delivery: Node = $DeliverySystem

var _cash_drop_pos: Vector3 = Vector3(0, 1.05, -0.4)


func _ready() -> void:
	# QueueMarkerActive is the spot for the customer currently at the stand.
	# QueueMarker1 is the first waiting spot (second customer in line).
	# QueueMarker2 sets the direction and spacing for the rest of the waiting line.
	# Move/rotate these markers in the editor to reorient the whole queue.
	# Up to 20 customer slots are generated automatically from that direction.
	var m_active: Marker3D = world.get_node_or_null("QueueMarkerActive") as Marker3D
	var m1: Marker3D = world.get_node_or_null("QueueMarker1") as Marker3D
	var m2: Marker3D = world.get_node_or_null("QueueMarker2") as Marker3D
	var active_pos := Vector3(0.0, 0.0, -1.0)
	var start := Vector3(0.0, 0.0, -2.0)
	var step := Vector3(0.0, 0.0, -1.0)
	if m_active:
		active_pos = m_active.global_position
	if m1:
		start = m1.global_position
		if m2:
			step = m2.global_position - m1.global_position
	var spots: Array[Vector3] = []
	spots.append(active_pos)
	for i in range(20):
		spots.append(start + step * float(i))
	spawner.set_queue_spots(spots, step)

	# Pedestrian spawner reads its PedestrianPath children automatically.
	# No wiring needed here — add paths in the editor as children of PedestrianSpawner.
	ped_spawner.setup(spawner)

	# Wire delivery grid
	var dgrid := world.get_node_or_null("DeliveryGrid") as DeliveryGrid
	if dgrid == null:
		var dmarker := world.get_node_or_null("DeliveryMarker") as Marker3D
		if dmarker:
			delivery.set_delivery_zone(dmarker.global_position)
	else:
		delivery.set_grid(dgrid)

	# Find the CashPickup placed in the stand scene — use its position, then hide it
	var cash_template: Node3D = world.find_child("CashPickup", true, false) as Node3D
	if cash_template:
		_cash_drop_pos = cash_template.global_position
		cash_template.visible = false
		var phys: StaticBody3D = cash_template.get_node_or_null("Physics") as StaticBody3D
		if phys:
			phys.collision_layer = 0

	# Pitcher is placed in world.tscn — its _ready() captures its own position.
	EventBus.cash_dropped.connect(_on_cash_dropped)

	# Spawn the screen-space outline overlay and hand it the main camera so it
	# can mirror the transform every frame.
	var outline_sys: Node = OUTLINE_SCENE.instantiate()
	add_child(outline_sys)
	outline_sys.setup(player.get_node("Head/Camera3D") as Camera3D)

	# Add the evening summary overlay
	add_child(DAY_SUMMARY_SCENE.instantiate())

	# Start the day cycle — morning setup then immediately begin the day
	DayManager.start_morning()
	DayManager.start_day()
	SaveManager.respawn_placed_containers()


func _on_cash_dropped(drop_pos: Vector3, payment: float, change_due: float) -> void:
	var pickup: CashPickup = CASH_PICKUP_SCENE.instantiate()
	pickup.payment = payment
	pickup.change_due = change_due
	# Use the passed drop_pos (e.g. NPC CashPoint) if valid, otherwise fallback to register.
	var base_pos := drop_pos if drop_pos.length_squared() > 0.001 else _cash_drop_pos
	# Slight random offset so bills don't stack exactly
	pickup.position = base_pos + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1))
	add_child(pickup)

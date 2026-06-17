extends Node
## Main scene root. Wires everything together at startup.

const CASH_PICKUP_SCENE: PackedScene = preload("res://scenes/objects/cash_pickup.tscn")
const OUTLINE_SCENE: PackedScene = preload("res://scenes/ui/outline_overlay.tscn")
const MORNING_HUB_SCENE: PackedScene = preload("res://scenes/ui/morning_hub.tscn")
const DAY_SUMMARY_SCENE: PackedScene = preload("res://scenes/ui/day_summary.tscn")

@onready var world: Node3D = $World
@onready var player: CharacterBody3D = $Player
@onready var spawner: Node = $CustomerSpawner
@onready var ped_spawner: Node = $PedestrianSpawner
@onready var delivery: Node = $DeliverySystem

var _cash_drop_pos: Vector3 = Vector3(0, 1.05, -0.4)


func _ready() -> void:
	# QueueMarker1 sets the start of the line.
	# QueueMarker2 sets the direction and spacing between each customer slot.
	# Move/rotate these two markers in the editor to reorient the whole queue.
	# Up to 20 customer slots are generated automatically from that direction.
	var m1 := world.get_node_or_null("QueueMarker1") as Marker3D
	var m2 := world.get_node_or_null("QueueMarker2") as Marker3D
	var start := Vector3(0.0, 0.0, -2.0)
	var step := Vector3(0.0, 0.0, -1.0)
	if m1:
		start = m1.global_position
		if m2:
			step = m2.global_position - m1.global_position
	var spots: Array[Vector3] = []
	for i in range(20):
		spots.append(start + step * float(i))
	spawner.set_queue_spots(spots, step)

	# Wire delivery zone
	var dmarker := world.get_node("DeliveryMarker") as Marker3D
	if dmarker:
		delivery.set_delivery_zone(dmarker.global_position)

	# Pedestrian spawner reads its PedestrianPath children automatically.
	# No wiring needed here — add paths in the editor as children of PedestrianSpawner.
	ped_spawner.setup(spawner)

	# Find the CashPickup placed in the stand scene — use its position, then hide it
	var cash_template := world.find_child("CashPickup", true, false) as Node3D
	if cash_template:
		_cash_drop_pos = cash_template.global_position
		cash_template.visible = false
		var phys := cash_template.get_node_or_null("Physics") as StaticBody3D
		if phys:
			phys.collision_layer = 0

	# Pitcher is placed in world.tscn — its _ready() captures its own position.
	EventBus.cash_dropped.connect(_on_cash_dropped)

	# Spawn the screen-space outline overlay and hand it the main camera so it
	# can mirror the transform every frame.
	var outline_sys := OUTLINE_SCENE.instantiate()
	add_child(outline_sys)
	outline_sys.setup(player.get_node("Head/Camera3D") as Camera3D)

	# Add MorningHub and DaySummary overlays
	add_child(MORNING_HUB_SCENE.instantiate())
	add_child(DAY_SUMMARY_SCENE.instantiate())

	# Start the day cycle in morning phase
	DayManager.start_morning()


func _on_cash_dropped(drop_pos: Vector3, payment: float, change_due: float) -> void:
	var pickup: CashPickup = CASH_PICKUP_SCENE.instantiate()
	pickup.payment = payment
	pickup.change_due = change_due
	# Use the passed drop_pos (e.g. NPC CashPoint) if valid, otherwise fallback to register.
	var base_pos := drop_pos if drop_pos.length_squared() > 0.001 else _cash_drop_pos
	# Slight random offset so bills don't stack exactly
	pickup.position = base_pos + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1))
	add_child(pickup)

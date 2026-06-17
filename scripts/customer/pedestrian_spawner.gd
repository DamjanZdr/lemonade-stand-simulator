extends Node
## Manages pedestrian spawning.
## Automatically discovers every PedestrianPath node in the scene (they self-register
## via the "pedestrian_paths" group on _ready). No manual wiring needed here —
## just drop PedestrianPath scripts on Marker3Ds anywhere in the world.

const PEDESTRIAN_SCENE: PackedScene = preload("res://scenes/customer/pedestrian.tscn")

@export var max_pedestrians: int = 10
@export var spawn_interval: float = 3.0

var _customer_spawner: Node = null
var _pedestrians: Array = []
var _spawn_timer: Timer


func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.one_shot = false
	_spawn_timer.timeout.connect(_try_spawn)
	add_child(_spawn_timer)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.DAY:
		_spawn_timer.start()
	else:
		_spawn_timer.stop()


func setup(customer_spawner: Node) -> void:
	_customer_spawner = customer_spawner


func _try_spawn() -> void:
	_pedestrians = _pedestrians.filter(func(p): return is_instance_valid(p))
	if _pedestrians.size() >= max_pedestrians:
		return

	# Gather all paths that have at least one waypoint.
	var usable: Array = get_tree().get_nodes_in_group("pedestrian_paths").filter(
		func(p): return not (p as PedestrianPath).waypoints.is_empty()
	)

	if usable.is_empty():
		return

	# Weighted random pick.
	var total: float = 0.0
	for p in usable:
		total += (p as PedestrianPath).spawn_weight
	var roll := randf() * total
	var chosen: PedestrianPath = usable[-1]
	for p in usable:
		roll -= (p as PedestrianPath).spawn_weight
		if roll <= 0.0:
			chosen = p
			break

	var ped: Pedestrian = PEDESTRIAN_SCENE.instantiate()
	get_parent().add_child(ped)
	ped.global_position = chosen.global_position
	ped.setup(chosen.waypoints)
	ped.wants_to_join.connect(_on_wants_to_join)
	_pedestrians.append(ped)


func _on_wants_to_join(ped: Pedestrian) -> void:
	if _customer_spawner == null:
		_resume(ped)
		return

	var slot: int = _customer_spawner.claim_free_slot(ped)
	if slot == -1:
		_resume(ped)
		return

	# Slot is reserved. Have the pedestrian walk to it — same NPC walks visibly
	# to the queue. When it arrives, spawn the customer already in-place (WAITING).
	var slot_pos: Vector3 = _customer_spawner.get_slot_position(slot)
	ped.walk_to_queue(slot_pos, func(): _finalize_conversion(ped))


func _finalize_conversion(ped: Pedestrian) -> void:
	var slot: int = _customer_spawner.get_slot_for_pedestrian(ped)
	if slot == -1:
		_resume(ped)
		return
	_customer_spawner.spawn_converted(slot, ped)
	_pedestrians.erase(ped)
	ped.queue_free()


## Resumes a pedestrian rejected by a full queue — advance past the convertable waypoint.
func _resume(ped: Pedestrian) -> void:
	ped._advance_waypoint()
	if is_instance_valid(ped):
		ped._npc.play_anim("Walk")

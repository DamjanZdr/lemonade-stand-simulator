extends Node
## Manages pedestrian spawning.
## Automatically discovers every PedestrianPath node in the scene (they self-register
## via the "pedestrian_paths" group on _ready). No manual wiring needed here —
## just drop PedestrianPath scripts on Marker3Ds anywhere in the world.

const PEDESTRIAN_SCENE: PackedScene = preload("res://scenes/customer/pedestrian.tscn")

@export var max_pedestrians: int = 10
@export var spawn_interval: float = 3.0

var _customer_spawner: Node = null
var _managed: bool = false
var _pedestrians: Array = []
var _spawn_timer: Timer


func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.one_shot = false
	_spawn_timer.timeout.connect(_try_spawn)
	add_child(_spawn_timer)
	add_to_group("pedestrian_spawner")
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_update_spawner()


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if _managed:
		return
	if phase == DayManager.Phase.DAY:
		_spawn_timer.start()
	else:
		_spawn_timer.stop()


func setup(customer_spawner: Node) -> void:
	_customer_spawner = customer_spawner


func set_managed(enabled: bool) -> void:
	_managed = enabled


func spawn_on_path(path: PedestrianPath) -> void:
	_pedestrians = _pedestrians.filter(func(p):
			return is_instance_valid(p))
	if path == null or path.waypoints.is_empty():
		push_warning("PedestrianSpawner: cannot spawn on null or empty path.")
		return
	_spawn_pedestrian(path)


func _spawn_pedestrian(path: PedestrianPath) -> void:
	var ped: Pedestrian = PEDESTRIAN_SCENE.instantiate()
	get_parent().add_child(ped)
	ped.collision_layer = 16
	ped.collision_mask = 3
	ped.global_position = path.waypoints[0].global_position
	ped.setup(path.waypoints, 1)
	ped.wants_to_join.connect(_on_wants_to_join)
	ped.add_to_group("trash_spawn_candidates")
	_pedestrians.append(ped)
	EventBus.pedestrian_spawned.emit(ped)


func _try_spawn() -> void:
	if _managed:
		return
	_update_spawner()
	_pedestrians = _pedestrians.filter(func(p):
			return is_instance_valid(p))
	if _pedestrians.size() >= max_pedestrians:
		return

	# Gather all paths that have at least one waypoint.
	var usable: Array = get_tree().get_nodes_in_group("pedestrian_paths").filter(
		func(p):
			return not (p as PedestrianPath).waypoints.is_empty()
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

	_spawn_pedestrian(chosen)


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
	ped.walk_to_queue(slot_pos, func():
			_finalize_conversion(ped))


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


func _update_spawner() -> void:
	var traffic: float = UpgradeManager.get_effect_total("foot_traffic")
	max_pedestrians = 10 + int(10.0 * traffic)
	var new_interval: float = spawn_interval / (1.0 + traffic)
	if new_interval < 0.5:
		new_interval = 0.5
	_spawn_timer.wait_time = new_interval

class_name Pedestrian
extends CharacterBody3D
## A neighbourhood pedestrian that follows a PedestrianPath in order.
## At convertable waypoints it rolls a popularity-based chance to join the queue.
## On success it walks directly to the reserved queue slot (same NPC, visually continuous)
## and signals the spawner when it arrives. After the last waypoint it despawns.

const GRAVITY := 9.8

@export var walk_speed: float = 2.2

signal wants_to_join(pedestrian: Pedestrian)

var _waypoints: Array[PedestrianWaypoint] = []
var _waypoint_idx: int = 0

## When true the pedestrian has diverted to a queue slot and ignores waypoints.
var _routing_to_queue: bool = false
var _queue_target: Vector3 = Vector3.ZERO
var _queue_arrived_cb: Callable = Callable() # called once the pedestrian reaches the slot

@onready var _npc: Node3D = $NPCBody


func _ready() -> void:
	floor_snap_length = 0.2
	_npc.randomize_appearance()
	_npc.play_anim("Walk")


## Called by PedestrianSpawner right after instantiation.
func setup(waypoints: Array[PedestrianWaypoint]) -> void:
	_waypoints = waypoints
	_waypoint_idx = 0


## Called by PedestrianSpawner after a slot is reserved.
## The pedestrian stops following waypoints and walks straight to [target].
## [on_arrive] is called once it gets there.
func walk_to_queue(target: Vector3, on_arrive: Callable) -> void:
	_routing_to_queue = true
	_queue_target = target
	_queue_arrived_cb = on_arrive
	_npc.play_anim("Walk")


func update_queue_target(target: Vector3) -> void:
	_queue_target = target


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if _routing_to_queue:
		if global_position.distance_to(_queue_target) < 0.35:
			_routing_to_queue = false
			velocity = Vector3.ZERO
			if _queue_arrived_cb.is_valid():
				_queue_arrived_cb.call()
		else:
			_walk_toward(_queue_target, delta)
		move_and_slide()
		return

	if _waypoints.is_empty() or _waypoint_idx >= _waypoints.size():
		move_and_slide()
		return

	var target := _waypoints[_waypoint_idx].global_position

	if global_position.distance_to(target) < 0.55:
		_arrive()
	else:
		_walk_toward(target, delta)

	move_and_slide()


func _arrive() -> void:
	var wp := _waypoints[_waypoint_idx]

	var convert_chance: float = Balancing.pedestrian_convert_chance(GameState.popularity)
	var marketing_bonus: float = UpgradeManager.get_effect_total("marketing")
	if marketing_bonus > 0.0:
		convert_chance = clampf(convert_chance + marketing_bonus, 0.0, 1.0)
	if wp.convertable and randf() < convert_chance:
		wants_to_join.emit(self)
		return # spawner will call walk_to_queue() or _resume(); don't advance yet

	_advance_waypoint()


func _advance_waypoint() -> void:
	_waypoint_idx += 1
	if _waypoint_idx >= _waypoints.size():
		queue_free()


func _walk_toward(target: Vector3, delta: float) -> void:
	var dir := (target - global_position).normalized()
	dir.y = 0.0
	velocity.x = dir.x * walk_speed
	velocity.z = dir.z * walk_speed
	if dir.length_squared() > 0.01:
		var target_basis := Basis.looking_at(dir, Vector3.UP)
		var t := minf(delta * 10.0, 1.0)
		var q := basis.get_rotation_quaternion().slerp(
			target_basis.get_rotation_quaternion(),
			t,
		)
		basis = Basis(q)

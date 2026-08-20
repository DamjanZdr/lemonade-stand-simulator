extends Node
## Manages pedestrian spawning.
## Automatically discovers every PedestrianPath node in the scene (they self-register
## via the "pedestrian_paths" group on _ready). No manual wiring needed here —
## just drop PedestrianPath scripts on Marker3Ds anywhere in the world.

const PEDESTRIAN_SCENE: PackedScene = preload("res://scenes/customer/pedestrian.tscn")

@export var max_pedestrians: int = 10
@export var spawn_interval: float = 3.0

## Each entry: {"spawner": CustomerSpawner-like Node, "stand": StandUnit or null}.
## When a pedestrian wants to join a queue, one entry is chosen via a
## popularity-weighted random pick (higher popularity = more likely to be
## chosen), so pedestrians naturally distribute across multiple stands
## roughly proportional to how popular each one currently is. If "stand" is
## null (e.g. registered via the legacy setup() call), it's treated as a
## flat weight of 1.0.
var _stand_entries: Array[Dictionary] = []
## Tracks which spawner a given pedestrian was routed to, from the moment
## they're chosen to join until they either finish converting or get
## rejected — needed since _finalize_conversion/_resume happen later and
## can no longer just assume "the" single spawner once there's more than one.
var _ped_spawner_map: Dictionary = { }

var _managed: bool = false
var _pedestrians: Array = []
var _spawn_timer: Timer
var _sync_timer: float = 0.0
const NPC_SYNC_INTERVAL: float = 0.07 # ~14Hz position sync for NPCs


func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.one_shot = false
	_spawn_timer.timeout.connect(_try_spawn)
	add_child(_spawn_timer)
	add_to_group("pedestrian_spawner")
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_update_spawner()


func _process(delta: float) -> void:
	# Host: periodically sync all pedestrian positions to clients.
	# Clients interpolate toward these positions smoothly (server-authoritative,
	# like Schedule 1 / FishNet). Uses unreliable RPCs for bandwidth efficiency.
	if not WorldSync.is_host():
		return
	_sync_timer += delta
	if _sync_timer < NPC_SYNC_INTERVAL:
		return
	_sync_timer = 0.0
	_pedestrians = _pedestrians.filter(
		func(p):
			return is_instance_valid(p),
	)
	for ped in _pedestrians:
		var p := ped as Pedestrian
		if p == null:
			continue
		WorldSync.sync_transform(p, p.global_position, p.global_rotation)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if _managed:
		return
	if phase == DayManager.Phase.DAY:
		_spawn_timer.start()
	else:
		_spawn_timer.stop()


## Legacy single-stand setup. Equivalent to register_stand(spawner, null),
## i.e. a flat weight of 1.0 (fine as long as it's the only stand).
func setup(customer_spawner: Node) -> void:
	register_stand(customer_spawner, null)


## Registers a stand's customer spawner so pedestrians can be routed to it.
## Call once per stand (main.gd/world setup does this for each StandUnit).
func register_stand(customer_spawner: Node, stand: StandUnit) -> void:
	_stand_entries.append({ "spawner": customer_spawner, "stand": stand })


## Popularity-weighted random pick among registered stands. Returns an empty
## Dictionary if no stands are registered yet.
func _pick_stand_entry() -> Dictionary:
	if _stand_entries.is_empty():
		return { }
	if _stand_entries.size() == 1:
		return _stand_entries[0]
	var weights: Array[float] = []
	var total := 0.0
	for entry in _stand_entries:
		var stand: StandUnit = entry.get("stand")
		# Floor the weight so a brand-new/unpopular stand can still get a
		# trickle of customers rather than a hard 0% chance.
		var w: float = maxf(stand.popularity, 0.01) if stand else 1.0
		weights.append(w)
		total += w
	var roll := randf() * total
	for i in range(_stand_entries.size()):
		roll -= weights[i]
		if roll <= 0.0:
			return _stand_entries[i]
	return _stand_entries[-1]


func set_managed(enabled: bool) -> void:
	_managed = enabled


func spawn_on_path(path: PedestrianPath) -> void:
	_pedestrians = _pedestrians.filter(
		func(p):
			return is_instance_valid(p),
	)
	if path == null or path.waypoints.is_empty():
		push_warning("PedestrianSpawner: cannot spawn on null or empty path.")
		return
	_spawn_pedestrian(path)


func _spawn_pedestrian(path: PedestrianPath) -> void:
	if not WorldSync.is_host():
		return
	# Server-authoritative: spawn on host + replicate to clients via WorldSync.
	# Position is synced periodically via WorldSync.sync_transform() in _process.
	# State changes (offered, serving, resume) use RPCs on the NPC itself.
	var spawned := WorldSync.spawn_networked(
		"res://scenes/customer/pedestrian.tscn",
		get_parent(),
		path.waypoints[0].global_position,
		Vector3.ZERO,
		{ },
	) as Pedestrian
	if spawned == null:
		return
	spawned.collision_layer = 16
	spawned.collision_mask = 3
	spawned.setup(path.waypoints, 1)
	spawned.wants_to_join.connect(_on_wants_to_join)
	spawned.add_to_group("trash_spawn_candidates")
	_pedestrians.append(spawned)
	EventBus.pedestrian_spawned.emit(spawned)


func _try_spawn() -> void:
	if _managed:
		return
	_update_spawner()
	_pedestrians = _pedestrians.filter(
		func(p):
			return is_instance_valid(p),
	)
	if _pedestrians.size() >= max_pedestrians:
		return

	# Gather all paths that have at least one waypoint.
	var usable: Array = get_tree().get_nodes_in_group("pedestrian_paths").filter(
		func(p):
			return not (p as PedestrianPath).waypoints.is_empty(),
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
	var entry := _pick_stand_entry()
	var spawner: Node = entry.get("spawner")
	if spawner == null:
		_resume(ped)
		return

	var slot: int = spawner.claim_free_slot(ped)
	if slot == -1:
		_resume(ped)
		return

	# Remember which spawner this pedestrian committed to, so
	# _finalize_conversion/_resume use the same one later.
	_ped_spawner_map[ped] = spawner

	# Slot is reserved. Have the pedestrian walk to it — same NPC walks visibly
	# to the queue. When it arrives, spawn the customer already in-place (WAITING).
	var slot_pos: Vector3 = spawner.get_slot_position(slot)
	ped.walk_to_queue(
		slot_pos,
		func():
			_finalize_conversion(ped),
	)


func _finalize_conversion(ped: Pedestrian) -> void:
	var spawner: Node = _ped_spawner_map.get(ped)
	if spawner == null:
		_resume(ped)
		return
	var slot: int = spawner.get_slot_for_pedestrian(ped)
	if slot == -1:
		_resume(ped)
		return
	spawner.spawn_converted(slot, ped)
	_ped_spawner_map.erase(ped)
	_pedestrians.erase(ped)
	ped.queue_free()


## Resumes a pedestrian rejected by a full queue — advance past the convertable waypoint.
func _resume(ped: Pedestrian) -> void:
	_ped_spawner_map.erase(ped)
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

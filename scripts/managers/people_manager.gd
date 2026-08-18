class_name PeopleManager
extends Node
## Coordinates pedestrian spawning for a workday.
##
## A single total is configured and the manager spreads those pedestrians
## across the active day, picking a random available route for each one.

@export var total_people: int = 100
## Stop scheduling new spawns this many seconds before the day ends.
@export var spawn_margin: float = 1.0
@export var pedestrian_spawner_group: StringName = &"pedestrian_spawner"
@export var convert_chance_at_zero_popularity: float = 0.05
@export var convert_chance_at_max_popularity: float = 1.0

var _spawner: Node = null
var _schedule: Array[float] = []
var _next_index: int = 0
var _day_total_time: float = 0.0
var _active: bool = false


func _ready() -> void:
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.day_timer_updated.connect(_on_day_timer_updated)
	call_deferred("_find_spawner")
	add_to_group("people_manager")


func _find_spawner() -> void:
	_spawner = get_tree().get_first_node_in_group(pedestrian_spawner_group)
	if _spawner == null:
		push_warning(
			"PeopleManager: no PedestrianSpawner found in group '%s'." % pedestrian_spawner_group,
		)
	else:
		_spawner.set_managed(true)


func get_pedestrian_convert_chance(popularity: float) -> float:
	var t := clampf(popularity, 0.0, 1.0)
	return lerpf(convert_chance_at_zero_popularity, convert_chance_at_max_popularity, t)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.DAY:
		_active = true
		_day_total_time = 0.0
		_schedule.clear()
		_next_index = 0
	else:
		_active = false


func _on_day_timer_updated(time_left: float, total_time: float) -> void:
	if not _active or _spawner == null:
		return
	if total_time <= 0.0:
		return
	if _day_total_time <= 0.0:
		_day_total_time = total_time
		_build_schedule(total_time)

	var elapsed := total_time - time_left
	while _next_index < _schedule.size() and _schedule[_next_index] <= elapsed:
		_spawn_one()
		_next_index += 1


func _build_schedule(total_time: float) -> void:
	_schedule.clear()
	if total_people <= 0 or total_time <= 0.0:
		return

	var available := maxf(0.0, total_time - spawn_margin)
	var hour_length := available / 9.0
	if hour_length <= 0.0:
		return

	var block_hours: Array[int] = [2, 4, 3]
	var block_shares: Array[float] = [0.2, 0.6, 0.2]
	var block_counts := _distribute_in_blocks(total_people, block_shares)
	var hour_index := 0
	for b in range(block_hours.size()):
		var per_hour := _distribute_count(block_counts[b], block_hours[b])
		for h in range(block_hours[b]):
			var start := float(hour_index) * hour_length
			var end := start + hour_length
			_fill_hour(start, end, per_hour[h])
			hour_index += 1

	_schedule.sort()


func _distribute_in_blocks(total: int, shares: Array[float]) -> Array[int]:
	var raw: Array[int] = []
	var frac: Array[float] = []
	var allocated := 0
	for share in shares:
		var value := float(total) * share
		var floor_count := int(value)
		raw.append(floor_count)
		frac.append(value - float(floor_count))
		allocated += floor_count

	var result := raw.duplicate()
	var remainder := total - allocated
	var indices: Array[int] = []
	for i in range(shares.size()):
		indices.append(i)
	indices.sort_custom(
		func(a: int, b: int) -> bool:
			return frac[a] > frac[b],
	)
	for i in range(remainder):
		result[indices[i % indices.size()]] += 1
	return result


func _distribute_count(total: int, slots: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(slots)
	if slots <= 0:
		return result
	var base := total / slots
	var rem := total % slots
	for i in range(slots):
		result[i] = base + (1 if i < rem else 0)
	return result


func _fill_hour(start: float, end: float, count: int) -> void:
	if count <= 0:
		return
	var current := start
	var remaining := end - start
	for i in range(count):
		var left := count - i
		var base := remaining / float(left)
		var interval := randf_range(base * 0.5, base * 1.5)
		interval = clampf(interval, base * 0.5, remaining)
		current += interval
		remaining -= interval
		_schedule.append(current)


func _spawn_one() -> void:
	var paths := get_tree().get_nodes_in_group("pedestrian_paths").filter(
		func(p):
			return not (p as PedestrianPath).waypoints.is_empty(),
	)
	if paths.is_empty():
		push_warning("PeopleManager: no usable pedestrian paths found.")
		return

	var index := randi() % paths.size()
	var chosen: PedestrianPath = paths[index]
	_spawner.spawn_on_path(chosen)

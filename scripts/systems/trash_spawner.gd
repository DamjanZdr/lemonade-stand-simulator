extends Node3D
## Drops random litter near pedestrians or customers every 10-20 seconds.
## Spawns are anchored to existing NPCs, so they never appear outside the
## walkable/playable area.

const TRASH_SCENE: PackedScene = preload("res://scenes/objects/trash.tscn")

@export var min_interval: float = 10.0
@export var max_interval: float = 20.0
@export var max_trash_count: int = 20
@export var horizontal_spread: float = 0.8

var _timer: Timer = null
var _playable_area: Area3D = null


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_find_playable_area()
	_schedule_next()


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.DAY:
		_schedule_next()
	else:
		_timer.stop()


func _schedule_next() -> void:
	_timer.start(randf_range(min_interval, max_interval))


func _on_timer_timeout() -> void:
	_spawn_trash()
	_schedule_next()


func _spawn_trash() -> void:
	var candidates := get_tree().get_nodes_in_group("trash_spawn_candidates")
	candidates = candidates.filter(
		func(n):
			return is_instance_valid(n) and n is Node3D and _is_inside_playable_area(n),
	)
	if candidates.is_empty():
		return

	if get_tree().get_nodes_in_group("trash_item").size() >= max_trash_count:
		return

	var npc := candidates[randi() % candidates.size()] as Node3D
	var base_pos := npc.global_position
	var feet_y := _get_feet_y(npc)
	var angle := randf() * TAU
	var radius := randf() * horizontal_spread
	var spawn_x := base_pos.x + cos(angle) * radius
	var spawn_z := base_pos.z + sin(angle) * radius
	var ground_y := _find_ground_y(spawn_x, feet_y + 0.5, spawn_z, feet_y, npc)
	if not WorldSync.is_host():
		return
	var trash_rot := Vector3(0, randf() * TAU, 0)
	# Use WorldSync to spawn and replicate
	WorldSync.spawn_networked(
		"res://scenes/objects/trash.tscn",
		get_tree().current_scene,
		Vector3(spawn_x, ground_y, spawn_z),
		trash_rot,
		{ },
	)


func _get_feet_y(npc: Node3D) -> float:
	var body := npc as CharacterBody3D
	if body == null:
		return npc.global_position.y
	var col := npc.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null or col.shape == null:
		return npc.global_position.y
	if col.shape is CapsuleShape3D:
		var cap: CapsuleShape3D = col.shape as CapsuleShape3D
		return npc.global_position.y + col.position.y - cap.height * 0.5
	if col.shape is CylinderShape3D:
		var cyl: CylinderShape3D = col.shape as CylinderShape3D
		return npc.global_position.y + col.position.y - cyl.height * 0.5
	return npc.global_position.y


func _get_collision_bottom_offset(trash: Node3D) -> float:
	var col := trash.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null or col.shape == null:
		return 0.0
	var half_height: float = 0.0
	if col.shape is BoxShape3D:
		half_height = (col.shape as BoxShape3D).size.y * 0.5
	elif col.shape is CapsuleShape3D:
		half_height = (col.shape as CapsuleShape3D).height * 0.5
	elif col.shape is SphereShape3D:
		half_height = (col.shape as SphereShape3D).radius
	return half_height - col.position.y


func _find_ground_y(
	x: float,
	start_y: float,
	z: float,
	fallback_y: float,
	exclude: CollisionObject3D = null,
) -> float:
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, start_y, z)
	var to := Vector3(x, start_y - 1.0, z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	if exclude != null:
		query.exclude = [exclude.get_rid()]
	var result := space.intersect_ray(query)
	if result:
		return result.position.y
	return fallback_y


func _find_playable_area() -> void:
	var current := get_tree().current_scene
	if current == null:
		return
	_playable_area = current.get_node_or_null("World/PlayableArea") as Area3D
	if _playable_area == null:
		_playable_area = current.get_node_or_null("PlayableArea") as Area3D


func _is_inside_playable_area(npc: Node3D) -> bool:
	if _playable_area == null:
		return true
	var col := _playable_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null or not (col.shape is BoxShape3D):
		return true
	var box: BoxShape3D = col.shape as BoxShape3D
	var local_pos: Vector3 = _playable_area.global_transform.affine_inverse() * npc.global_position
	var half: Vector3 = box.size * 0.5
	return (
		abs(local_pos.x) <= half.x and abs(local_pos.y) <= half.y and abs(local_pos.z) <= half.z
	)

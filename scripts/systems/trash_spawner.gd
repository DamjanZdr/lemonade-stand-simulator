extends Node3D
## Drops random litter near pedestrians or customers every 10-20 seconds.
## Spawns are anchored to existing NPCs, so they never appear outside the
## walkable/playable area.

const _VARIANT_SCENES: Dictionary = {
	"apple": "res://scenes/objects/trash_apple.tscn",
	"banana": "res://scenes/objects/trash_banana.tscn",
	"can": "res://scenes/objects/trash_can.tscn",
	"cigarettes": "res://scenes/objects/trash_cigarettes.tscn",
	"cup": "res://scenes/objects/trash_cup.tscn",
}

# Offset to put the collision shape bottom at ground level.
# Calculated from trash.tscn: CollisionShape3D at Y=-0.104, BoxShape3D height=0.161
# bottom = -0.104 - 0.0805 = -0.1845, so offset = 0.1845
const TRASH_Y_OFFSET: float = 0.185

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
	if not WorldSync.is_host():
		return
	# Pick a variant deterministically so all clients see the same trash type
	var variants: Array[String] = ["apple", "banana", "can", "cigarettes", "cup"]
	var variant := variants[randi() % variants.size()]
	var scene_path: String = _VARIANT_SCENES.get(variant, "res://scenes/objects/trash_apple.tscn")
	# Spawn a temporary RigidBody3D that falls from above, then spawns
	# the real TrashItem when it hits the ground.
	var drop_pos := Vector3(spawn_x, feet_y + 1.5, spawn_z)
	_drop_trash_with_physics(scene_path, variant, drop_pos)


## Drop trash from a position using a temporary RigidBody3D. When it
## hits the ground, the actual TrashItem is spawned at that position.
func _drop_trash_with_physics(scene_path: String, variant: String, drop_pos: Vector3) -> void:
	var trash_scene := load(scene_path) as PackedScene
	if trash_scene == null:
		return
	var body := RigidBody3D.new()
	body.name = "DroppingTrash"
	# Collide with all layers (streets are on layer 2, ground on 1, etc.)
	body.collision_mask = 0xFFFFFFFF
	# Lock rotation so it doesn't spin.
	body.axis_lock_angular_x = true
	body.axis_lock_angular_y = true
	body.axis_lock_angular_z = true
	# Copy model and collision shapes from the scene.
	var instance := trash_scene.instantiate()
	for child in instance.get_children():
		if child is CollisionShape3D:
			var dup := (child as CollisionShape3D).duplicate() as CollisionShape3D
			body.add_child(dup)
		elif child is Node3D:
			var dup := (child as Node3D).duplicate() as Node3D
			dup.visible = true
			body.add_child(dup)
	instance.queue_free()
	# Add to scene, then set position.
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(body)
	body.global_position = drop_pos
	# When it hits the ground, spawn the real TrashItem and remove body.
	var landed := false
	body.body_entered.connect(
		func(_other):
			if landed:
				return
			landed = true
			_finalize_drop(body, scene_path, variant),
	)
	# Fallback: after 3 seconds, finalize wherever it is.
	get_tree().create_timer(3.0).timeout.connect(
		func():
			if not landed and is_instance_valid(body):
				landed = true
				_finalize_drop(body, scene_path, variant),
	)


func _finalize_drop(body: RigidBody3D, scene_path: String, variant: String) -> void:
	if not is_instance_valid(body):
		return
	var land_pos := body.global_position
	body.freeze = true
	WorldSync.spawn_networked(
		scene_path,
		get_tree().current_scene,
		land_pos,
		Vector3.ZERO,
		{ "trash_variant": variant },
	)
	body.queue_free()


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
	var to := Vector3(x, start_y - 2.0, z)
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
	_playable_area = current.find_child("PlayableArea", true, false) as Area3D


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

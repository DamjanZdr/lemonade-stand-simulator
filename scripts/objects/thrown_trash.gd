class_name ThrownTrash
extends RigidBody3D
## Networked physics body for thrown/dropped trash.
## Host runs physics and syncs transform to clients.
## Clients interpolate to received positions (no physics).
## Any player can pick it up mid-air or after landing.

## Trash type (apple, banana, can, cigarettes, cup, empty_box).
var trash_type: String = "empty_box"
## Refund value when disposed of in a trashcan.
var trash_value: float = 0.0
## Initial velocity to apply on the host after spawn.
var _initial_velocity: Vector3 = Vector3.ZERO
## Whether this is an NPC drop (vs player throw). Determines spawn behavior.
var is_npc_drop: bool = false

## The node that threw/dropped this trash. Ignored by collision detection
## so the thrower/dropper doesn't stun themselves.
var source_node: Node = null

## Grace period after spawn during which collisions are ignored (seconds).
## Prevents the trash from stunning the thrower/dropper on spawn overlap.
const _SPAWN_GRACE: float = 0.3
var _spawn_time: float = 0.0

## Whether this trash has already hit someone (stun only applies once).
var _hit_someone: bool = false

const _VARIANT_SCENES: Dictionary = {
	"apple": "res://scenes/objects/trash_apple.tscn",
	"banana": "res://scenes/objects/trash_banana.tscn",
	"can": "res://scenes/objects/trash_can.tscn",
	"cigarettes": "res://scenes/objects/trash_cigarettes.tscn",
	"cup": "res://scenes/objects/trash_cup.tscn",
}

## No-bounce physics material.
static var _no_bounce_mat: PhysicsMaterial = null

## Client-side interpolation target.
var _net_target_pos: Vector3 = Vector3.ZERO
var _has_net_target: bool = false
const _NET_LERP_SPEED: float = 15.0

var _landed: bool = false
var _sync_timer: float = 0.0


func _ready() -> void:
	# Tag with metadata so any player can raycast-detect it for pickup.
	set_meta("is_thrown_trash", true)
	set_meta("trash_type", trash_type)
	set_meta("trash_value", trash_value)

	# Build the visual + collision from the variant scene.
	_build_visuals()

	# Lock all rotation.
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	# Collide with all layers.
	collision_mask = 0xFFFFFFFF
	# No bounce.
	physics_material_override = _get_no_bounce_material()

	if WorldSync.is_host():
		# Host: run physics. Apply initial velocity after spawn.
		freeze = false
		if _initial_velocity != Vector3.ZERO:
			linear_velocity = _initial_velocity
		# Enable contact monitoring so we can detect hits on players/NPCs.
		contact_monitor = true
		max_contacts_reported = 4
		body_entered.connect(_on_body_entered)
		# When the body sleeps (lands), finalize.
		sleeping_state_changed.connect(_on_sleeping)
		# Fallback: finalize after 5 seconds.
		get_tree().create_timer(5.0).timeout.connect(_on_fallback)
	else:
		# Client: no physics, just interpolate to host positions.
		freeze = true
		# Remove collision shapes — clients don't need physics collision,
		# but keep the visual for rendering and an Area3D for raycast pickup.
		_remove_collision_shapes()


func _physics_process(delta: float) -> void:
	if WorldSync.is_host():
		if _landed or not is_instance_valid(self):
			return
		_spawn_time += delta
		# Manual NPC hit detection — body_entered is unreliable for fast
		# objects (tunneling). Check overlap each frame after grace period.
		if _spawn_time >= _SPAWN_GRACE and not _hit_someone:
			_check_npc_overlap()
		# Sync transform to clients periodically (every ~50ms).
		_sync_timer += delta
		if _sync_timer >= 0.05:
			_sync_timer = 0.0
			WorldSync.sync_transform(self, global_position, global_rotation)
	else:
		# Client: interpolate toward received position.
		if _has_net_target:
			var t := clampf(_NET_LERP_SPEED * delta, 0.0, 1.0)
			global_position = global_position.lerp(_net_target_pos, t)


## Called by WorldSync transform sync on clients.
func net_set_target(pos: Vector3, rot: Vector3) -> void:
	_net_target_pos = pos
	_has_net_target = true
	global_rotation = rot


## Build visual model + collision shapes from the variant scene.
func _build_visuals() -> void:
	if trash_type == "empty_box":
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.2, 0.2, 0.2)
		col.shape = shape
		add_child(col)
		return
	var scene_path: String = _VARIANT_SCENES.get(trash_type, "")
	if scene_path == "":
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var instance := scene.instantiate()
	for child in instance.get_children():
		if child is CollisionShape3D:
			var dup := (child as CollisionShape3D).duplicate() as CollisionShape3D
			add_child(dup)
		elif child is Node3D:
			var dup := (child as Node3D).duplicate() as Node3D
			dup.visible = true
			add_child(dup)
	instance.queue_free()


## Remove collision shapes on clients (no physics needed).
func _remove_collision_shapes() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			child.queue_free()


static func _get_no_bounce_material() -> PhysicsMaterial:
	if _no_bounce_mat == null:
		_no_bounce_mat = PhysicsMaterial.new()
		_no_bounce_mat.bounce = 0.0
		_no_bounce_mat.friction = 1.0
	return _no_bounce_mat


## Host: called when the thrown trash collides with another body.
## If it hits a player or pedestrian/customer, stun them for 3 seconds.
## Only applies once per trash, and only after the spawn grace period.
## The source node (thrower/dropper) is ignored.
func _on_body_entered(body: Node) -> void:
	_try_stun(body)


## Host: manual overlap check each physics frame. More reliable than
## body_entered for fast-moving objects that can tunnel through NPCs.
func _check_npc_overlap() -> void:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = global_transform
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var results := space.intersect_shape(params, 32)
	for result in results:
		var collider = result.collider
		if _try_stun(collider):
			return


## Try to stun a body. Returns true if a stun was applied.
## Walks up the tree to find Player/Pedestrian/Customer, skipping source.
func _try_stun(body: Node) -> bool:
	if _landed or _hit_someone or not is_instance_valid(self):
		return false
	# Ignore collisions during spawn grace period (prevents self-stun).
	if _spawn_time < _SPAWN_GRACE:
		return false
	var node: Node = body
	while node != null:
		# Skip the source node (thrower/dropper).
		if source_node != null and is_instance_valid(source_node) and node == source_node:
			return false
		if node is Player:
			var p := node as Player
			_hit_someone = true
			p.stun(2.0)
			GameLog.log("[ThrownTrash] Stunned player %s for 2s" % p.name)
			return true
		if node is Pedestrian:
			var ped := node as Pedestrian
			_hit_someone = true
			ped.stun(2.0)
			GameLog.log("[ThrownTrash] Stunned pedestrian for 2s")
			return true
		if node is Customer:
			var cust := node as Customer
			_hit_someone = true
			cust.stun(2.0)
			GameLog.log("[ThrownTrash] Stunned customer for 2s")
			return true
		node = node.get_parent()
	return false


func _on_sleeping() -> void:
	if _landed or not is_instance_valid(self) or not sleeping:
		return
	_finalize()


func _on_fallback() -> void:
	if _landed or not is_instance_valid(self):
		return
	_finalize()


## Host: freeze, spawn the real TrashItem via WorldSync, then despawn self.
func _finalize() -> void:
	if _landed or not is_instance_valid(self):
		return
	_landed = true
	freeze = true
	var land_pos := global_position
	# If the trash fell through the world (Y way below ground), skip
	# spawning the TrashItem — it would appear underground and be
	# unreachable. Just despawn the ThrownTrash body.
	if land_pos.y < -1.0:
		print(
			"[ThrownTrash] Skipping spawn — fell through world: type=%s y=%.2f"
			% [trash_type, land_pos.y]
		)
		WorldSync.despawn_networked(self)
		return
	# If the trash is floating above the ground (never slept, hit the
	# fallback timer), raycast down to find the actual ground and place
	# the TrashItem there so it doesn't float.
	if land_pos.y > 0.5:
		var ground_y := _raycast_ground_y(land_pos)
		if ground_y < land_pos.y:
			land_pos.y = ground_y
	# Spawn the real trash item at this position via WorldSync.
	if trash_type == "empty_box":
		var state: Dictionary = {
			"is_trash_box": true,
			"ingredient_type": "trash",
			"quantity": 0.0,
			"trash_value": trash_value,
			"trash_type": trash_type,
		}
		var box := WorldSync.request_spawn(
			"res://scenes/objects/supply_box.tscn",
			land_pos,
			Vector3.ZERO,
			state,
		) as SupplyBox
		if box:
			box.update_metrics()
	else:
		var scene_path: String = _VARIANT_SCENES.get(trash_type, "")
		if scene_path != "":
			var state2: Dictionary = {
				"trash_variant": trash_type,
				"trash_type": trash_type,
				"trash_value": trash_value,
			}
			WorldSync.request_spawn(scene_path, land_pos, Vector3.ZERO, state2)
	# Despawn self via WorldSync so clients remove it too.
	WorldSync.despawn_networked(self)


## Raycast straight down from pos to find the ground Y coordinate.
## Used when trash is floating (hit the fallback timer without sleeping).
## Falls back to pos.y if no ground is found.
func _raycast_ground_y(pos: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var from := pos + Vector3.UP * 0.5
	var to := pos + Vector3.DOWN * 3.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	if result and result.has("position"):
		return result.position.y
	return pos.y


## Called by the host when a player picks up this trash mid-air.
## Gives the trash to the player and despawns the body.
func pickup_by(player: Node) -> void:
	if not WorldSync.is_host():
		return
	if _landed or not is_instance_valid(self):
		return
	# Set _landed first to prevent _finalize from racing with us.
	_landed = true
	# Get the visual for the hand mesh.
	var visual: Node3D = null
	for child in get_children():
		if child is Node3D and not child is CollisionShape3D:
			visual = (child as Node3D).duplicate()
			break
	# Give trash to the player.
	var inv := player.get_node_or_null("Inventory") as PlayerInventory
	if inv:
		inv.make_held_trash(trash_value, trash_type, visual)
	# Despawn via WorldSync so all clients remove it.
	WorldSync.despawn_networked(self)

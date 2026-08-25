class_name Player
extends CharacterBody3D

@export var move_speed: float = 5.0
const MOUSE_SENSITIVITY: float = 0.002

## Head/neck yaw limit before the body rotates to catch up.
const NECK_YAW_MAX: float = 0.8
## How quickly the body rotates to match the head when the neck hits its limit.
const NECK_YAW_CATCHUP_SPEED: float = 8.0

const HINT_GROUND := "Aim at ground to place"
const HINT_STAND := "Aim at stand or workstation to place"

## Which stand this player is assigned to (set by whatever assigns players
## to stands ΓÇö the lobby, in real multiplayer). Null in solo/offline play,
## where there's no "your stand vs their stand" concept since only one
## person is playing ΓÇö see StandUnit.can_be_served_by() for how this is
## used to restrict serving another stand's customers in real multiplayer
## without blocking solo testing of every stand.
var assigned_stand: StandUnit = null

var held_item: int = HeldItem.NONE
var held_item_data: Dictionary = { }
var _held_mesh: Node3D = null

@export var gravity: float = 9.8
@export var sprint_multiplier: float = 1.8
@export var jump_velocity: float = 5.0
@export var rapid_fire_interval: float = 0.35

# Last node hit by a raycast during an interact call; used by interactable
# scripts to know which collider the player actually clicked.
var last_interact_hit: Node = null

@onready var head: Node3D = $Head
@onready var hand_slot: Node3D = $Head/Camera3D/HandSlot
@onready var ray: RayCast3D = $Head/RayCast3D
@onready var camera: Camera3D = $Head/Camera3D
@onready var visuals: PlayerVisuals = $Visuals
@onready var inventory: PlayerInventory = $PlayerInventory
@onready var interaction = $PlayerInteraction
@onready var placement: PlayerPlacement = $PlayerPlacement

var _in_priceboard_mode := false
var _sync_pos_timer: float = 0.0
var _last_synced_pos: Vector3 = Vector3.ZERO
var _last_synced_rot: Vector3 = Vector3.ZERO
var _last_synced_pitch: float = 0.0
var _last_synced_yaw: float = 0.0
const SYNC_MIN_INTERVAL: float = 0.05 # Max 20 updates/sec while moving
const SYNC_POS_THRESHOLD: float = 0.1 # Min movement (meters) to trigger sync

# Remote player interpolation target (set by RPC, lerped toward in _process)
var _net_target_pos: Vector3 = Vector3.ZERO
var _net_target_rot: Vector3 = Vector3.ZERO
var _has_net_target: bool = false
var _net_head_pitch: float = 0.0
var _net_head_yaw: float = 0.0

# Camera-relative yaw and pitch. The body rotates to catch up once the head
# yaw exceeds the neck limit; storing them prevents incremental rotations
# from introducing unwanted roll into the head/camera.
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0

const NET_LERP_SPEED: float = 12.0 # How fast remote players snap to target

# Animation state
var _current_anim: String = "Idle"
var _was_moving: bool = false
var _prev_sync_pos: Vector3 = Vector3.ZERO
var _is_sprinting: bool = false
var _time_since_sync: float = 0.0
const SYNC_ROT_THRESHOLD: float = 0.05 # Min rotation (radians) to trigger sync
var _priceboard_tween: Tween = null
var _priceboard_camera_original_local: Transform3D
var _priceboard_camera_original_top_level := false

var _money_mode: bool = false


func set_money_mode(active: bool) -> void:
	_money_mode = active
	if interaction != null:
		interaction.set_money_mode(active)
	if active:
		EventBus.interaction_hint_changed.emit("")


func _enter_tree() -> void:
	# Multiplayer authority: nodes spawned via main.gd's per-peer spawning
	# are named after the owning peer's ID, matching the pattern used by
	# the Phase 1 networking test scene. A statically-placed Player (e.g.
	# in an editor preview scene with a non-numeric name) keeps the
	# default authority (peer 1 / host), which is also correct for solo
	# play using the default OfflineMultiplayerPeer.
	if name.is_valid_int():
		set_multiplayer_authority(int(name))
	GameLog.log(
		"[Player] _enter_tree name=%s authority=%d my_id=%d is_auth=%s"
		% [
			name,
			get_multiplayer_authority(),
			multiplayer.get_unique_id(),
			is_multiplayer_authority(),
		]
	)
	_setup_position_replication()


## So other peers can see where a remote player physically is, even
## though only the authoritative peer drives that player's own movement
## input/physics locally.
func _setup_position_replication() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "PositionSync"
	# Explicitly set the synchronizer's authority to match the player's.
	# Without this, the synchronizer may not know which peer is the
	# authority and won't replicate position/rotation to other peers.
	sync.set_multiplayer_authority(get_multiplayer_authority())
	# Set replication config BEFORE adding to tree ΓÇö otherwise the
	# synchronizer tries to start replication with no config and errors.
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath("../:position"))
	config.add_property(NodePath("../:rotation"))
	sync.replication_config = config
	add_child(sync)
	GameLog.log(
		"[Player] PositionSync set up for %s authority=%d"
		% [name, sync.get_multiplayer_authority()]
	)


func _ready() -> void:
	add_to_group("player")
	GameLog.log(
		"[Player] _ready name=%s authority=%d my_id=%d is_auth=%s"
		% [
			name,
			get_multiplayer_authority(),
			multiplayer.get_unique_id(),
			is_multiplayer_authority(),
		]
	)
	_setup_visuals()
	if is_multiplayer_authority():
		_configure_local_player()
	else:
		# This is another peer's player, replicated here so we can see
		# them ΓÇö not ours to control. Skip capturing input/camera/audio,
		# which would otherwise fight with our own local player for them.
		# Log the initial position so we can see if the synchronizer
		# is updating it over time.
		GameLog.log("[Player] Remote player %s initial pos=%s" % [name, str(global_position)])
		# Set up a one-shot timer to check if position is being updated
		var timer := get_tree().create_timer(3.0)
		timer.timeout.connect(
			func():
				if is_instance_valid(self):
					GameLog.log(
						"[Player] Remote player %s pos after 3s=%s" % [name, str(global_position)]
					),
		)


## Applies local-player-only setup: mouse capture, camera, audio, and physics.
## Called from _ready for the local player, and from main.gd when a late
## joiner's authority is claimed after the spawner replicates the node.
func _configure_local_player() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Layer 2 is used by the screen-space outline system for white fill nodes.
	# The main camera must not render them ΓÇö only the SubViewport OutlineCamera does.
	$Head/Camera3D.cull_mask &= ~2
	$Head/Camera3D.make_current()
	GameLog.log("[Player] Camera made current for local player %s" % name)
	var listener := $Head/Camera3D/AudioListener3D as AudioListener3D
	if listener:
		listener.make_current()

	# Smooth movement over small ledges and slopes (sidewalks, curbs, etc.)
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 0.3
	floor_constant_speed = true
	floor_stop_on_slope = false
	floor_block_on_wall = false

	# Precompute shared box metrics and load the workstation scene for placement.
	placement._configure_local_player()


## Set up the PlayerVisuals: apply customization from the lobby roster,
## scale the head bone, hide the model for the local player (first-person),
## and start the idle animation.
func _setup_visuals() -> void:
	if visuals == null:
		return
	# Mark as player visual so eye look-at targets other players, not "Player"
	visuals.is_player_visual = true
	# Apply customization from the lobby roster
	var peer_id := int(name)
	var entry: Dictionary = LobbyManager.roster.get(peer_id, { })
	var custom: Dictionary = entry.get("customization", { })
	if not custom.is_empty():
		visuals.apply_customization(custom)
	else:
		# No customization data ΓÇö use a deterministic seed based on peer ID
		# so all peers see the same random appearance for this player
		visuals.appearance_seed = peer_id * 2654435761
		visuals.randomize_appearance()
	# Scale the head bone for cartoony proportions (from customization or default)
	var head_size: float = custom.get("head_size", 1.3)
	visuals.scale_head_bone(head_size)
	# Hide visuals for the local player (first-person camera)
	# Remote players see the full character model
	visuals.visible = not is_multiplayer_authority()
	# Start idle animation
	visuals.play_anim("Idle")
	_current_anim = "Idle"


## Update the player's animation based on movement state.
## Walk = 1.7x speed, Sprint = 2.0x speed, Jump = idle for now.
## Animations switch immediately (no waiting for current loop to finish).
func _update_anim() -> void:
	if visuals == null or not visuals.visible:
		return

	# Determine state
	var on_floor: bool
	if is_multiplayer_authority():
		on_floor = is_on_floor()
	else:
		# Remote players don't run move_and_slide, so estimate from velocity.y
		on_floor = absf(velocity.y) < 1.0

	var horizontal_vel := Vector3(velocity.x, 0, velocity.z).length()
	var moving := horizontal_vel > 0.5 and on_floor

	# Determine target animation and speed
	var target_anim: String
	var target_speed: float = 1.0

	if not on_floor:
		# Jumping/falling ΓÇö play idle for now
		target_anim = "Idle"
		target_speed = 1.0
	elif moving:
		target_anim = "Walk"
		# Walk animation is designed for the model's default facing.
		# The player model is rotated 180┬░, so negate speed to match.
		# Walk = -1.7x (reversed), Sprint = -2.0x
		target_speed = -(2.0 if _is_sprinting else 1.7)
	else:
		target_anim = "Idle"
		target_speed = 1.0

	# Always apply ΓÇö even if same anim, speed may have changed (walk<->sprint)
	if _current_anim != target_anim:
		visuals.play_anim_speed(target_anim, target_speed)
		_current_anim = target_anim
	elif target_anim == "Walk":
		# Same anim but speed might have changed (started/stopped sprinting)
		visuals.set_anim_speed(target_speed)


func enter_priceboard_focus(focus_transform: Transform3D) -> void:
	_in_priceboard_mode = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_priceboard_camera_original_local = camera.transform
	_priceboard_camera_original_top_level = camera.top_level
	camera.top_level = true
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(false)
	if _priceboard_tween != null and _priceboard_tween.is_valid():
		_priceboard_tween.kill()
	_priceboard_tween = create_tween()
	_priceboard_tween.set_trans(Tween.TRANS_QUAD)
	_priceboard_tween.set_ease(Tween.EASE_IN_OUT)
	_priceboard_tween.tween_property(camera, "global_transform", focus_transform, 0.4)


func exit_priceboard_focus() -> void:
	if not _in_priceboard_mode:
		return
	var target_global := head.global_transform * _priceboard_camera_original_local
	if _priceboard_tween != null and _priceboard_tween.is_valid():
		_priceboard_tween.kill()
	_priceboard_tween = create_tween()
	_priceboard_tween.set_trans(Tween.TRANS_QUAD)
	_priceboard_tween.set_ease(Tween.EASE_IN_OUT)
	_priceboard_tween.tween_property(camera, "global_transform", target_global, 0.4)
	_priceboard_tween.finished.connect(_on_priceboard_tween_finished)


func _on_priceboard_tween_finished() -> void:
	camera.top_level = _priceboard_camera_original_top_level
	camera.transform = _priceboard_camera_original_local
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_in_priceboard_mode = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(true)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if _in_priceboard_mode:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Update stored yaw/pitch and re-apply the head rotation as a single
		# clean Euler vector. This avoids mixing rotate_x with rotation.y and
		# keeps the camera horizon level.
		_look_yaw = wrap_angle(_look_yaw - event.relative.x * MOUSE_SENSITIVITY)
		_look_pitch = clampf(
			_look_pitch - event.relative.y * MOUSE_SENSITIVITY,
			-PI / 2.1,
			PI / 2.1,
		)
		head.rotation = Vector3(_look_pitch, _look_yaw, 0)

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if interaction != null:
				interaction.set_primary_held(true)
				interaction.primary_interact()
		elif not event.pressed:
			if interaction != null:
				interaction.set_primary_held(false)

	if event.is_action_pressed("secondary_interact") and \
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if interaction != null:
			interaction.secondary_interact()


func _process(delta: float) -> void:
	# Remote players: interpolate toward network target and update animation
	if not is_multiplayer_authority():
		_time_since_sync += delta
		# If no position RPC arrived recently, the authority has stopped
		# moving ΓÇö snap velocity to zero immediately so walk->idle is instant
		if _time_since_sync > 0.15:
			velocity = Vector3.ZERO
		else:
			# Decay velocity for smooth interpolation between RPCs
			velocity = velocity.move_toward(Vector3.ZERO, 30.0 * delta)
		# Smoothly interpolate toward the network target position
		if _has_net_target:
			var t := clampf(NET_LERP_SPEED * delta, 0.0, 1.0)
			global_position = global_position.lerp(_net_target_pos, t)
			global_rotation.y = lerp_angle(global_rotation.y, _net_target_rot.y, t)
		# Update neck/head bones so other players see where this player is looking.
		# Apply immediately for this frame, then deferred after AnimationPlayer
		# has updated so the pose isn't overwritten by the current animation.
		if visuals != null and visuals.visible:
			var neck_yaw := global_rotation.y + _net_head_yaw
			visuals.set_look_target(neck_yaw, _net_head_pitch, global_rotation.y)
		_update_anim()
	else:
		# Local player: update neck/head bones based on camera look direction.
		# PlayerVisuals applies the pose in _physics_process after the
		# AnimationPlayer has updated so the pose isn't overwritten.
		if visuals != null and visuals.visible:
			var cam_yaw := head.global_rotation.y
			var cam_pitch := head.rotation.x
			var body_yaw := global_rotation.y
			visuals.set_look_target(cam_yaw, cam_pitch, body_yaw)
		if interaction != null and not _money_mode:
			interaction.poll_hint()
			interaction.update_rapid_fire(delta)
		placement.update_ghost()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		# Remote players' position/rotation come from RPC sync
		# instead of local physics simulation.
		return
	if _in_priceboard_mode:
		velocity = Vector3.ZERO
		move_and_slide()
		_try_sync_position(delta)
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Movement follows the camera/head direction so looking around still steers.
	var direction := (head.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	_is_sprinting = Input.is_action_pressed("sprint") and direction != Vector3.ZERO
	var speed_bonus := UpgradeManager.get_effect_total("movement_speed")
	var speed := (move_speed + speed_bonus) * (sprint_multiplier if _is_sprinting else 1.0)
	velocity.x = direction.x * speed if direction else move_toward(velocity.x, 0, speed)
	velocity.z = direction.z * speed if direction else move_toward(velocity.z, 0, speed)
	move_and_slide()
	_update_body_yaw(delta)
	_try_sync_position(delta)
	if interaction != null:
		interaction.update_frame_lookups()
	placement.update_ghost()
	_update_anim()


## Only sync position when the player has actually moved, rotated, or
## changed their look direction beyond a threshold. While standing still
## and not looking around, no RPCs are sent at all.
## While moving, syncs are throttled to max 20/sec (0.05s interval).
func _try_sync_position(delta: float) -> void:
	_sync_pos_timer += delta
	if _sync_pos_timer < SYNC_MIN_INTERVAL:
		return
	var pos_delta := global_position.distance_to(_last_synced_pos)
	var rot_delta := absf(global_rotation.y - _last_synced_rot.y)
	var pitch_delta := absf(head.rotation.x - _last_synced_pitch)
	var yaw_delta := absf(head.rotation.y - _last_synced_yaw)
	if (
		pos_delta < SYNC_POS_THRESHOLD and rot_delta < SYNC_ROT_THRESHOLD \
				and pitch_delta < 0.05
		and yaw_delta < 0.05
	):
		return # Haven't moved/looked enough, skip
	_sync_pos_timer = 0.0
	_last_synced_pos = global_position
	_last_synced_rot = global_rotation
	_last_synced_pitch = head.rotation.x
	_last_synced_yaw = head.rotation.y
	_sync_position.rpc(
		global_position,
		global_rotation,
		_is_sprinting,
		head.rotation.x,
		head.rotation.y,
	)


## After the head turns past the neck limit, rotate the body to catch up.
## The camera stays steady because the body turn is subtracted from _look_yaw
## and the head is re-set as a clean Euler vector.
func _update_body_yaw(delta: float) -> void:
	if absf(_look_yaw) <= NECK_YAW_MAX:
		return
	var excess: float = _look_yaw - sign(_look_yaw) * NECK_YAW_MAX
	var max_turn: float = NECK_YAW_CATCHUP_SPEED * delta
	var turn: float = clampf(excess, -max_turn, max_turn)
	rotation.y = wrap_angle(rotation.y + turn)
	_look_yaw = wrap_angle(_look_yaw - turn)
	head.rotation = Vector3(_look_pitch, _look_yaw, 0)


## Wrap an angle to the [-PI, PI] range.
func wrap_angle(angle: float) -> float:
	while angle > PI:
		angle -= TAU
	while angle < -PI:
		angle += TAU
	return angle


## Simple position sync RPC. Only the authority sends; all other peers
## receive and set the interpolation target (smoothed in _process).
@rpc("authority", "call_local", "unreliable")
func _sync_position(
	pos: Vector3,
	rot: Vector3,
	sprinting: bool = false,
	head_pitch: float = 0.0,
	head_yaw: float = 0.0,
) -> void:
	if is_multiplayer_authority():
		return # We're the authority, we already have the right position
	# Compute velocity from position delta so animations work on remote players
	var delta_pos := pos - _prev_sync_pos
	velocity = delta_pos / (get_process_delta_time() if get_process_delta_time() > 0 else 0.016)
	_prev_sync_pos = pos
	_is_sprinting = sprinting
	_time_since_sync = 0.0
	# Set interpolation target instead of snapping directly
	_net_target_pos = pos
	_net_target_rot = rot
	_has_net_target = true
	# Update neck/head bones on the remote player's visual model
	_net_head_pitch = head_pitch
	_net_head_yaw = head_yaw

# ---------------------------------------------------------------------------
#  Placement delegation wrappers
#  PlayerInteraction, PlayerInventory, and object scripts (press, pitcher,
#  fruit_bin, etc.) call these on the Player node directly. They forward to
#  the PlayerPlacement child that now owns the real implementation.
# ---------------------------------------------------------------------------


## Rapid-fire interval adjusted by the nimbleness upgrade. Used by
## PlayerInteraction to throttle held-mouse deposits.
func _get_rapid_fire_interval() -> float:
	var nimble_bonus: float = UpgradeManager.get_effect_total("nimbleness")
	if nimble_bonus > 0.0:
		return rapid_fire_interval * (1.0 - nimble_bonus)
	return rapid_fire_interval


func pickup_container(interactable: Interactable, container_type: String) -> void:
	placement.pickup_container(interactable, container_type)


func _remove_placement_groups(node: Node) -> void:
	placement._remove_placement_groups(node)


func _held_pitcher_has_contents() -> bool:
	return placement._held_pitcher_has_contents()


func _empty_held_pitcher() -> void:
	placement._empty_held_pitcher()


func _is_aiming_at_grid() -> bool:
	return placement._is_aiming_at_grid()


func _is_placement_surface(collider: Object) -> bool:
	return placement._is_placement_surface(collider)


func _is_ground_surface(collider: Object) -> bool:
	return placement._is_ground_surface(collider)


func _find_customer_in_ancestors(node: Node) -> Customer:
	return placement._find_customer_in_ancestors(node)


func _find_pedestrian_in_ancestors(node: Node) -> Pedestrian:
	return placement._find_pedestrian_in_ancestors(node)


func _set_visual_visible(node: Node, on: bool) -> void:
	if node is GeometryInstance3D or node is CanvasItem:
		node.visible = on
	for child in node.get_children():
		_set_visual_visible(child, on)

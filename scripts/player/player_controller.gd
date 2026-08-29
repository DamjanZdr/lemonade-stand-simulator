class_name PlayerController
extends Node
## Handles movement, camera look, input, animation, network position sync,
## and priceboard camera focus for the parent Player.

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	if _player == null:
		push_warning("PlayerController: parent is not a Player")


const MOUSE_SENSITIVITY: float = 0.002
## Head/neck yaw limit before the body rotates to catch up.
const NECK_YAW_MAX: float = 0.8
## How quickly the body rotates to match the _player.head when the neck hits its limit.
const NECK_YAW_CATCHUP_SPEED: float = 8.0
var _in_priceboard_mode := false
var _sync_pos_timer: float = 0.0
var _last_synced_pos: Vector3 = Vector3.ZERO
var _last_synced_rot: Vector3 = Vector3.ZERO
var _last_synced_pitch: float = 0.0
var _last_synced_yaw: float = 0.0
var _last_synced_crouch: bool = false
var _last_synced_sprint: bool = false
const SYNC_MIN_INTERVAL: float = 0.05 # Max 20 updates/sec while moving
const SYNC_POS_THRESHOLD: float = 0.1 # Min movement (meters) to trigger sync
# Remote player interpolation target (set by RPC, lerped toward in _process)
var _net_target_pos: Vector3 = Vector3.ZERO
var _net_target_rot: Vector3 = Vector3.ZERO
var _has_net_target: bool = false
var _net_head_pitch: float = 0.0
var _net_head_yaw: float = 0.0
# Camera-relative yaw and pitch. The body rotates to catch up once the _player.head
# yaw exceeds the neck limit; storing them prevents incremental rotations
# from introducing unwanted roll into the _player.head/_player.camera.
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
const NET_LERP_SPEED: float = 12.0 # How fast remote players snap to target
# Animation state
var _current_anim: String = "Idle"
var _crouch_frozen: bool = false
var _is_airborne: bool = false
var _air_time: float = 0.0
const MIN_AIR_TIME: float = 0.3 # Min seconds airborne before landing check
var _was_moving: bool = false
var _prev_sync_pos: Vector3 = Vector3.ZERO
var _is_sprinting: bool = false
var _time_since_sync: float = 0.0
const SYNC_ROT_THRESHOLD: float = 0.05 # Min _player.rotation (radians) to trigger sync
var _priceboard_tween: Tween = null
var _priceboard_camera_original_local: Transform3D
var _priceboard_camera_original_top_level := false


## Update the player's animation based on movement state.
## Walk = 1.7x speed, Sprint = 2.0x speed, Jump = idle for now.
## Animations switch immediately (no waiting for current loop to finish).
func _update_anim() -> void:
	if _player.visuals == null:
		return

	# Determine state with hysteresis to prevent jump flicker.
	# Once airborne, require a minimum air time before allowing landing,
	# then require strong evidence of being on floor. This prevents the
	# Jump animation from flickering back to Idle/Walk at the jump peak
	# (where velocity.y ≈ 0 momentarily).
	var raw_on_floor: bool
	if _player.is_multiplayer_authority():
		raw_on_floor = _player.is_on_floor()
	else:
		raw_on_floor = absf(_player.velocity.y) < 1.0
	var on_floor: bool = raw_on_floor
	if _is_airborne:
		_air_time += get_process_delta_time()
		# Only allow landing after minimum air time AND clearly on floor
		if _air_time < MIN_AIR_TIME:
			on_floor = false
		else:
			on_floor = raw_on_floor and _player.velocity.y >= -0.5
	else:
		_air_time = 0.0
	if on_floor:
		_is_airborne = false
		_air_time = 0.0
	else:
		_is_airborne = true

	var horizontal_vel := Vector3(_player.velocity.x, 0, _player.velocity.z).length()
	var moving := horizontal_vel > 0.5 and on_floor

	# Determine target animation and speed
	var target_anim: String
	var target_speed: float = 1.0

	if not on_floor:
		target_anim = "Jump"
		target_speed = 1.0
	elif _player.is_crouching:
		if moving:
			# Walking while crouched: play Crouch animation looped
			target_anim = "Crouch"
			# Same reversed speed as Walk (model is rotated 180°)
			target_speed = -1.7
		else:
			# Standing crouched: freeze on first frame of Crouch
			target_anim = "Crouch"
			target_speed = 1.0
	elif moving:
		target_anim = "Walk"
		# Walk animation is designed for the model's default facing.
		# The player model is rotated 180°, so negate speed to match.
		# Walk = -1.7x (reversed), Sprint = -2.0x
		target_speed = -(2.0 if _is_sprinting else 1.7)
	else:
		target_anim = "Idle"
		target_speed = 1.0

	# Apply animation
	var crouch_freeze := _player.is_crouching and not moving and on_floor
	if _current_anim != target_anim or _crouch_frozen != crouch_freeze:
		if crouch_freeze:
			# Standing crouched: freeze on first frame of Crouch (it's a
			# crouch-walk cycle, so frame 0 is already the crouched pose).
			_player.visuals.seek_anim("Crouch", 0.0)
			_crouch_frozen = true
		else:
			_player.visuals.play_anim_speed(target_anim, target_speed)
			_crouch_frozen = false
		_current_anim = target_anim
	elif target_anim == "Walk" or (target_anim == "Crouch" and moving):
		# Same anim but speed might have changed
		_player.visuals.set_anim_speed(target_speed)


## Apply crouch visual: lower the head/camera and update animation.
## The Crouch animation handles the body pose; this just lowers the
## camera for the first-person view.
var _head_base_y: float = 0.0
var _head_base_set: bool = false
const CROUCH_DROP: float = 0.6


func _apply_crouch_visual() -> void:
	if not _head_base_set:
		_head_base_y = _player.head.position.y
		_head_base_set = true
	var target_y: float = _head_base_y - CROUCH_DROP if _player.is_crouching else _head_base_y
	var tween := _player.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_player.head, "position:y", target_y, 0.15)


func enter_priceboard_focus(focus_transform: Transform3D) -> void:
	_in_priceboard_mode = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_priceboard_camera_original_local = _player.camera.transform
	_priceboard_camera_original_top_level = _player.camera.top_level
	_player.camera.top_level = true
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(false)
	if _priceboard_tween != null and _priceboard_tween.is_valid():
		_priceboard_tween.kill()
	_priceboard_tween = _player.create_tween()
	_priceboard_tween.set_trans(Tween.TRANS_QUAD)
	_priceboard_tween.set_ease(Tween.EASE_IN_OUT)
	_priceboard_tween.tween_property(_player.camera, "global_transform", focus_transform, 0.4)


func exit_priceboard_focus() -> void:
	if not _in_priceboard_mode:
		return
	var target_global := _player.head.global_transform * _priceboard_camera_original_local
	if _priceboard_tween != null and _priceboard_tween.is_valid():
		_priceboard_tween.kill()
	_priceboard_tween = _player.create_tween()
	_priceboard_tween.set_trans(Tween.TRANS_QUAD)
	_priceboard_tween.set_ease(Tween.EASE_IN_OUT)
	_priceboard_tween.tween_property(_player.camera, "global_transform", target_global, 0.4)
	_priceboard_tween.finished.connect(_on_priceboard_tween_finished)


func _on_priceboard_tween_finished() -> void:
	_player.camera.top_level = _priceboard_camera_original_top_level
	_player.camera.transform = _priceboard_camera_original_local
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_in_priceboard_mode = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(true)


func _unhandled_input(event: InputEvent) -> void:
	if not _player.is_multiplayer_authority():
		return
	if _in_priceboard_mode:
		return
	# ESC menu open: ignore all gameplay input (except ui_cancel for toggle).
	if EventBus.esc_menu_open and not event.is_action("ui_cancel"):
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Update stored yaw/pitch and re-apply the _player.head _player.rotation as a single
		# clean Euler vector. This avoids mixing rotate_x with _player.rotation.y and
		# keeps the _player.camera horizon level.
		_look_yaw = wrap_angle(_look_yaw - event.relative.x * MOUSE_SENSITIVITY)
		_look_pitch = clampf(
			_look_pitch - event.relative.y * MOUSE_SENSITIVITY,
			-PI / 2.1,
			PI / 2.1,
		)
		_player.head.rotation = Vector3(_look_pitch, _look_yaw, 0)

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if _player.interaction != null:
				_player.interaction.set_primary_held(true)
				_player.interaction.primary_interact()
		elif not event.pressed:
			if _player.interaction != null:
				_player.interaction.set_primary_held(false)

	if event.is_action_pressed("secondary_interact") and \
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _player.interaction != null:
			_player.interaction.secondary_interact()


func _process(delta: float) -> void:
	# Remote players: interpolate toward network target and update animation
	if not _player.is_multiplayer_authority():
		_time_since_sync += delta
		# If no position RPC arrived recently, the authority has stopped
		# moving ΓÇö snap _player.velocity to zero immediately so walk->idle is instant
		if _time_since_sync > 0.15:
			_player.velocity = Vector3.ZERO
		else:
			# Decay _player.velocity for smooth interpolation between RPCs
			_player.velocity = _player.velocity.move_toward(Vector3.ZERO, 10.0 * delta)
		# Smoothly interpolate toward the network target position
		if _has_net_target:
			var t := clampf(NET_LERP_SPEED * delta, 0.0, 1.0)
			_player.global_position = _player.global_position.lerp(_net_target_pos, t)
			_player.global_rotation.y = lerp_angle(_player.global_rotation.y, _net_target_rot.y, t)
		# Update neck/_player.head bones so other players see where this player is looking.
		# Apply immediately for this frame, then deferred after AnimationPlayer
		# has updated so the pose isn't overwritten by the current animation.
		if _player.visuals != null and _player.visuals.visible:
			var neck_yaw := _player.global_rotation.y + _net_head_yaw
			_player.visuals.set_look_target(neck_yaw, _net_head_pitch, _player.global_rotation.y)
		_update_anim()
	else:
		# Local player: update neck/_player.head bones based on _player.camera look direction.
		# PlayerVisuals applies the pose in _physics_process after the
		# AnimationPlayer has updated so the pose isn't overwritten.
		if _player.visuals != null and _player.visuals.visible:
			var cam_yaw := _player.head.global_rotation.y
			var cam_pitch := _player.head.rotation.x
			var body_yaw := _player.global_rotation.y
			_player.visuals.set_look_target(cam_yaw, cam_pitch, body_yaw)
		if _player.interaction != null and not _player._money_mode:
			_player.interaction.poll_hint()
			_player.interaction.update_rapid_fire(delta)
		_player.placement.update_ghost()


func _physics_process(delta: float) -> void:
	if not _player.is_multiplayer_authority():
		# Remote players' position/_player.rotation come from RPC sync
		# instead of local physics simulation.
		return
	# Debug: log once per second to diagnose late-join freeze
	if Engine.get_process_frames() % 60 == 0:
		GameLog.log(
			"[Controller] physics auth=%s pos=%s mouse=%d input=(%.1f,%.1f)"
			% [
				_player.is_multiplayer_authority(),
				str(_player.global_position),
				Input.mouse_mode,
				Input.get_vector("move_left", "move_right", "move_forward", "move_back").x,
				Input.get_vector("move_left", "move_right", "move_forward", "move_back").y,
			]
		)
	if _in_priceboard_mode:
		_player.velocity = Vector3.ZERO
		_player.move_and_slide()
		_try_sync_position(delta)
		return

	# ESC menu open: freeze movement.
	if EventBus.esc_menu_open:
		_player.velocity.x = move_toward(_player.velocity.x, 0, 20.0 * delta)
		_player.velocity.z = move_toward(_player.velocity.z, 0, 20.0 * delta)
		_player.move_and_slide()
		_update_anim()
		return

	# Tick stun timer.
	if _player._stun_timer > 0.0:
		_player._stun_timer = maxf(_player._stun_timer - delta, 0.0)
		# When stun ends, play Fall in reverse to get back up.
		if _player._stun_timer <= 0.0 and _player._stun_recovering:
			_player._stun_recovering = false
			_player._stun_recover_timer = 0.0
			if _player.visuals:
				_player.visuals.play_anim_reverse("Fall", 0.3)
				_player._stun_recover_timer = _player.visuals.get_anim_length("Fall")

	# Tick recovery timer (Fall playing in reverse).
	if _player._stun_recover_timer > 0.0:
		_player._stun_recover_timer = maxf(_player._stun_recover_timer - delta, 0.0)
		_player.velocity.x = move_toward(_player.velocity.x, 0, 20.0 * delta)
		_player.velocity.z = move_toward(_player.velocity.z, 0, 20.0 * delta)
		_player.move_and_slide()
		if _player._stun_recover_timer <= 0.0:
			_update_anim()
		return

	# Crouch toggle (CTRL or C).
	if Input.is_action_just_pressed("crouch"):
		_player.is_crouching = not _player.is_crouching
		_apply_crouch_visual()
		_update_anim()

	if not _player.is_on_floor():
		_player.velocity.y -= _player.gravity * delta
	else:
		if Input.is_action_just_pressed("jump") and not _player.is_crouching:
			_player.velocity.y = _player.jump_velocity

	# Stunned: can't move, play Fall, hold last frame.
	if _player.is_stunned():
		_player.velocity.x = move_toward(_player.velocity.x, 0, 20.0 * delta)
		_player.velocity.z = move_toward(_player.velocity.z, 0, 20.0 * delta)
		_player.move_and_slide()
		# Play Fall once when stun starts.
		if not _player._stun_fall_played:
			_player._stun_fall_played = true
			_player._stun_recovering = true
			if _player.visuals:
				_player.visuals.play_anim_once("Fall", 0.05)
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Movement follows the head's yaw only — zero out Y so pitch
	# (looking up/down) doesn't reduce horizontal speed.
	var direction := (_player.head.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	direction.y = 0
	direction = direction.normalized()
	_is_sprinting = (
		Input.is_action_pressed("sprint") and direction != Vector3.ZERO and not _player.is_crouching
	)
	var speed_bonus := UpgradeManager.get_effect_total("movement_speed")
	var base_speed := _player.move_speed + speed_bonus
	# Crouch halves speed; sprint uses the multiplier (now faster).
	var speed := base_speed * (
		(0.5 if _player.is_crouching else 1.0)
		* (_player.sprint_multiplier if _is_sprinting else 1.0)
	)
	_player.velocity.x = (
		direction.x * speed
		if direction
		else move_toward(_player.velocity.x, 0, speed)
	)
	_player.velocity.z = (
		direction.z * speed
		if direction
		else move_toward(_player.velocity.z, 0, speed)
	)
	_player.move_and_slide()
	_update_body_yaw(delta)
	_try_sync_position(delta)
	if _player.interaction != null:
		_player.interaction.update_frame_lookups()
	_player.placement.update_ghost()
	_update_anim()


## Only sync position when the player has actually moved, rotated, or
## changed their look direction beyond a threshold. While standing still
## and not looking around, no RPCs are sent at all.
## While moving, syncs are throttled to max 20/sec (0.05s interval).
func _try_sync_position(delta: float) -> void:
	_sync_pos_timer += delta
	if _sync_pos_timer < SYNC_MIN_INTERVAL:
		return
	var pos_delta := _player.global_position.distance_to(_last_synced_pos)
	var rot_delta := absf(_player.global_rotation.y - _last_synced_rot.y)
	var pitch_delta := absf(_player.head.rotation.x - _last_synced_pitch)
	var yaw_delta := absf(_player.head.rotation.y - _last_synced_yaw)
	if (
		pos_delta < SYNC_POS_THRESHOLD and rot_delta < SYNC_ROT_THRESHOLD \
				and pitch_delta < 0.05
		and yaw_delta < 0.05 and _player.is_crouching == _last_synced_crouch
		and _is_sprinting == _last_synced_sprint
	):
		return # Haven't moved/looked/changed state enough, skip
	_sync_pos_timer = 0.0
	_last_synced_pos = _player.global_position
	_last_synced_rot = _player.global_rotation
	_last_synced_pitch = _player.head.rotation.x
	_last_synced_yaw = _player.head.rotation.y
	_last_synced_crouch = _player.is_crouching
	_last_synced_sprint = _is_sprinting
	_sync_position.rpc(
		_player.global_position,
		_player.global_rotation,
		_is_sprinting,
		_player.head.rotation.x,
		_player.head.rotation.y,
		_player.is_crouching,
	)


## After the _player.head turns past the neck limit, rotate the body to catch up.
## The _player.camera stays steady because the body turn is subtracted from _look_yaw
## and the _player.head is re-set as a clean Euler vector.
func _update_body_yaw(delta: float) -> void:
	if absf(_look_yaw) <= NECK_YAW_MAX:
		return
	var excess: float = _look_yaw - sign(_look_yaw) * NECK_YAW_MAX
	var max_turn: float = NECK_YAW_CATCHUP_SPEED * delta
	var turn: float = clampf(excess, -max_turn, max_turn)
	_player.rotation.y = wrap_angle(_player.rotation.y + turn)
	_look_yaw = wrap_angle(_look_yaw - turn)
	_player.head.rotation = Vector3(_look_pitch, _look_yaw, 0)


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
	crouching: bool = false,
) -> void:
	if _player.is_multiplayer_authority():
		return # We're the authority, we already have the right position
	# Compute _player.velocity from position delta so animations work on remote players
	var delta_pos := pos - _prev_sync_pos
	_player.velocity = delta_pos / (
		get_process_delta_time() if get_process_delta_time() > 0 else 0.016
	)
	_prev_sync_pos = pos
	_is_sprinting = sprinting
	_player.is_crouching = crouching
	_time_since_sync = 0.0
	# Set interpolation target instead of snapping directly
	_net_target_pos = pos
	_net_target_rot = rot
	_has_net_target = true
	# Update neck/_player.head bones on the remote player's visual model
	_net_head_pitch = head_pitch
	_net_head_yaw = head_yaw

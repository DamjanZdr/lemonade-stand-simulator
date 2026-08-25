class_name PlayerVisuals
extends Node3D
## Visual appearance system for players. Based on the NPC appearance system.
## Picks gender, a hairstyle, hair color, and per-surface clothing color.
## Can be randomized or set explicitly for player customization.

## When true, eye look-at targets the closest OTHER player in the "player"
## group instead of the single "Player" node (NPC behavior).
@export var is_player_visual: bool = false

## When non-null, eye look-at always targets this node instead of searching
## for players. Used by the lobby to make player models look at the camera.
var look_at_target: Node3D = null

# ── Animation speed controls (editable per-instance in the Inspector) ──────────
@export_group("Animation Speeds")
@export var walk_speed: float = 1.0
@export var idle_speed: float = 1.0
@export var idle_alt_speed: float = 1.0 # Idle_001
@export var look_around_speed: float = 1.0
@export var talk_speed: float = 1.0

# ── Eye look-at ─────────────────────────────────────────────────────────────────
@export_group("Eye Look-At")
## How close the player must be (in world units) for NPCs to track them.
@export var eye_look_range: float = 6.0
## Maximum eye rotation in degrees.
@export var eye_look_max_deg: float = 22.0
## How quickly the eyes lerp to their target rotation (higher = snappier).
@export var eye_look_speed: float = 6.0

const HAIR_COLORS: Array[Color] = [
	Color(0.08, 0.04, 0.01), # black
	Color(0.18, 0.09, 0.03), # dark brown
	Color(0.42, 0.25, 0.08), # medium brown
	Color(0.65, 0.45, 0.15), # light brown
	Color(0.88, 0.74, 0.28), # blonde
	Color(0.72, 0.20, 0.05), # auburn / red
	Color(0.55, 0.55, 0.55), # grey
	Color(0.92, 0.92, 0.90), # white / silver
]

const CLOTHING_COLORS: Array[Color] = [
	Color(0.80, 0.20, 0.20), # red
	Color(0.20, 0.40, 0.85), # blue
	Color(0.15, 0.55, 0.20), # green
	Color(0.85, 0.75, 0.10), # yellow
	Color(0.55, 0.10, 0.55), # purple
	Color(0.95, 0.50, 0.05), # orange
	Color(0.20, 0.20, 0.22), # charcoal
	Color(0.88, 0.88, 0.88), # light grey
	Color(0.72, 0.48, 0.28), # tan / khaki
	Color(0.05, 0.32, 0.35), # teal
	Color(0.60, 0.15, 0.10), # maroon
	Color(0.10, 0.22, 0.45), # navy
	Color(0.85, 0.40, 0.55), # pink
	Color(0.25, 0.55, 0.75), # sky blue
	Color(0.40, 0.70, 0.30), # lime green
]

## Mesh surface names that represent individual clothing pieces.
## Each matching surface gets its own independently-picked random color.
const CLOTHING_SURFACES: Array[String] = [
	"pants",
	"shirt",
	"top",
	"dress",
	"skirt",
	"jacket",
	"shorts",
	"blouse",
	"trousers",
	"suit",
	"coat",
	"sweater",
	"pullover",
	"shoes",
]

@onready var _man: Node3D = $man
@onready var _woman: Node3D = $woman
@onready var _man_mesh: MeshInstance3D = $man/Armature/Skeleton3D/MaleMesh
@onready var _woman_mesh: MeshInstance3D = $woman/Armature/Skeleton3D/FemaleMesh
@onready var _man_hairs: Node3D = $man/Armature/Skeleton3D/Head/Hairstyles
@onready var _woman_hairs: Node3D = $woman/Armature/Skeleton3D/Head/Hairstyles
@onready var _man_anim: AnimationPlayer = $man/AnimationPlayer
@onready var _woman_anim: AnimationPlayer = $woman/AnimationPlayer
@onready var _man_left_eye: MeshInstance3D = $man/Armature/Skeleton3D/Head/LeftEyeMale
@onready var _man_right_eye: MeshInstance3D = $man/Armature/Skeleton3D/Head/RightEyeMale
@onready var _man_head: Node3D = $man/Armature/Skeleton3D/Head
@onready var _man_left_marker: Marker3D = $man/Armature/Skeleton3D/Head/LeftEyeMale/Marker3D
@onready var _man_right_marker: Marker3D = $man/Armature/Skeleton3D/Head/RightEyeMale/Marker3D
@onready var _woman_left_eye: MeshInstance3D = $woman/Armature/Skeleton3D/Head/LeftEyeFemale
@onready var _woman_right_eye: MeshInstance3D = $woman/Armature/Skeleton3D/Head/RightEyeFemale
@onready var _woman_head: Node3D = $woman/Armature/Skeleton3D/Head
@onready var _woman_left_marker: Marker3D = $woman/Armature/Skeleton3D/Head/LeftEyeFemale/Marker3D
@onready var _woman_right_marker: Marker3D = $woman/Armature/Skeleton3D/Head/RightEyeFemale/Marker3D


func _ready() -> void:
	_disable_cast_shadows()
	# Run animations in the physics step so we can apply procedural bone
	# poses afterwards in _physics_process, guaranteeing the pose sticks.
	if _man_anim != null:
		_man_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	if _woman_anim != null:
		_woman_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS


func _disable_cast_shadows() -> void:
	## NPCs are small and numerous; shadows from every mesh tank the shadow-map pass.
	for node: Node in find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if gi:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


const _EYE_SCALE := 0.30564013

var _active_anim: AnimationPlayer = null

# Stored look target for procedural head/neck poses. Applied in
# _physics_process after the AnimationPlayer has updated, so the pose isn't
# overwritten by the current animation.
var _look_camera_yaw: float = 0.0
var _look_camera_pitch: float = 0.0
var _look_body_yaw: float = 0.0

var anim_player: AnimationPlayer:
	get:
		return _active_anim
var _left_eye: MeshInstance3D = null
var _right_eye: MeshInstance3D = null
var _left_marker: Marker3D = null
var _right_marker: Marker3D = null
# Marker direction in eye-LOCAL space, captured once — stable regardless of eye rotation.
var _left_rest_dir := Vector3.ZERO
var _right_rest_dir := Vector3.ZERO
var _eye_rot_l := Quaternion.IDENTITY
var _eye_rot_r := Quaternion.IDENTITY
var _player_cache: Node3D = null
var _camera_cache: Camera3D = null
var _is_near_player: bool = true
var _check_timer: float = 0.0
var _closest_player_cache: Node3D = null
var _closest_player_dist: float = INF


func _get_player_camera() -> Camera3D:
	if _camera_cache and is_instance_valid(_camera_cache):
		return _camera_cache
	if _player_cache == null:
		return null
	_camera_cache = _player_cache.find_child("Camera3D", true, false) as Camera3D
	return _camera_cache


func _ensure_player() -> bool:
	if _player_cache and is_instance_valid(_player_cache):
		return true
	if get_tree().current_scene == null:
		return false
	_player_cache = get_tree().current_scene.find_child("Player", true, false) as Node3D
	return _player_cache != null


## For player visuals: find the closest OTHER player in the "player" group.
## Skips self (the parent Player node). Returns null if none within range.
func _find_closest_other_player() -> Node3D:
	var my_root := get_parent()
	var best: Node3D = null
	var best_dist := eye_look_range
	for node in get_tree().get_nodes_in_group("player"):
		if node == my_root:
			continue
		if not is_instance_valid(node):
			continue
		var d := global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	_closest_player_dist = best_dist
	return best


func _is_player_near() -> bool:
	if is_player_visual:
		var closest := _find_closest_other_player()
		_closest_player_cache = closest
		return closest != null
	if not _ensure_player():
		return true
	return global_position.distance_to(_player_cache.global_position) <= 25.0


## When non-zero, randomize_appearance() uses this seed for deterministic
## results across all peers. Set by WorldSync spawn state before _ready().
var appearance_seed: int = 0


func randomize_appearance() -> void:
	# Use a seeded RNG if appearance_seed is set (multiplayer sync).
	# Falls back to the global RNG for single-player.
	var rng := RandomNumberGenerator.new()
	if appearance_seed != 0:
		rng.seed = appearance_seed
	else:
		rng.randomize()
	var male := rng.randi() % 2 == 0
	_man.visible = male
	_woman.visible = not male
	_active_anim = _man_anim if male else _woman_anim
	_left_eye = _man_left_eye if male else _woman_left_eye
	_right_eye = _man_right_eye if male else _woman_right_eye
	_left_marker = _man_left_marker if male else _woman_left_marker
	_right_marker = _man_right_marker if male else _woman_right_marker
	# Capture forward direction in eye-local space from the marker's local position.
	# This is stable — it doesn't change when the eye mesh rotates.
	_left_rest_dir = (
		_left_marker.position.normalized()
		if _left_marker.position.length() > 0.001
		else Vector3(0, 0, 1)
	)
	_right_rest_dir = (
		_right_marker.position.normalized()
		if _right_marker.position.length() > 0.001
		else Vector3(0, 0, 1)
	)
	_eye_rot_l = Quaternion.IDENTITY
	_eye_rot_r = Quaternion.IDENTITY

	var hairs: Node3D = _man_hairs if male else _woman_hairs
	var body: MeshInstance3D = _man_mesh if male else _woman_mesh

	_pick_hair_seeded(hairs, HAIR_COLORS[rng.randi() % HAIR_COLORS.size()], rng)
	_tint_clothing_seeded(body, rng)

# ── Character customization API ──────────────────────────────────────────────
# These methods allow explicit control over appearance instead of random.
# Used by the lobby customization UI.

const EYEBROW_NAMES: Array[String] = ["Neutral", "Angry", "Doubt", "Sad", "Shock"]


func set_gender(male: bool) -> void:
	_man.visible = male
	_woman.visible = not male
	_active_anim = _man_anim if male else _woman_anim
	_left_eye = _man_left_eye if male else _woman_left_eye
	_right_eye = _man_right_eye if male else _woman_right_eye
	_left_marker = _man_left_marker if male else _woman_left_marker
	_right_marker = _man_right_marker if male else _woman_right_marker
	_left_rest_dir = (
		_left_marker.position.normalized()
		if _left_marker.position.length() > 0.001
		else Vector3(0, 0, 1)
	)
	_right_rest_dir = (
		_right_marker.position.normalized()
		if _right_marker.position.length() > 0.001
		else Vector3(0, 0, 1)
	)
	_eye_rot_l = Quaternion.IDENTITY
	_eye_rot_r = Quaternion.IDENTITY


func is_male() -> bool:
	return _man.visible


func get_hair_count() -> int:
	var hairs := _man_hairs if _man.visible else _woman_hairs
	return hairs.get_child_count()


## Returns the name of the hair style at the given index (e.g. "Hair1M").
func get_hair_name(index: int) -> String:
	var hairs: Node3D = _man_hairs if _man.visible else _woman_hairs
	var children := hairs.get_children()
	if children.is_empty():
		return "Hair"
	index = index % children.size()
	return children[index].name


func set_hair(index: int, color: Color) -> void:
	var hairs: Node3D = _man_hairs if _man.visible else _woman_hairs
	var children := hairs.get_children()
	if children.is_empty():
		return
	index = index % children.size()
	for i in children.size():
		var child := children[i] as Node3D
		if child == null:
			continue
		child.visible = i == index
		if i == index:
			_tint_meshes_in(child, color)


func get_eyebrow_count() -> int:
	var eb := _get_eyebrows_node()
	if eb == null:
		return 0
	return eb.get_child_count()


## Returns the name of the eyebrow style at the given index (e.g. "Neutral").
func get_eyebrow_name(index: int) -> String:
	var eb := _get_eyebrows_node()
	if eb == null:
		return "Brows"
	var children := eb.get_children()
	if children.is_empty():
		return "Brows"
	index = index % children.size()
	# Strip gender suffix (e.g. "NeutralEyebrowsM" -> "Neutral")
	var n: String = children[index].name
	n = n.replace("EyebrowsM", "").replace("EyebrowsF", "")
	return n


func set_eyebrow(index: int) -> void:
	var eb := _get_eyebrows_node()
	if eb == null:
		return
	var children := eb.get_children()
	if children.is_empty():
		return
	index = index % children.size()
	for i in children.size():
		var child := children[i] as Node3D
		if child == null:
			continue
		child.visible = i == index


func _get_eyebrows_node() -> Node3D:
	if _man.visible:
		return get_node_or_null("man/Armature/Skeleton3D/Head/Eyebrows")
	return get_node_or_null("woman/Armature/Skeleton3D/Head/Eyebrows")


func set_hair_color(color: Color) -> void:
	var hairs: Node3D = _man_hairs if _man.visible else _woman_hairs
	for child in hairs.get_children():
		var c := child as Node3D
		if c and c.visible:
			_tint_meshes_in(c, color)


func set_clothing_color(surface_name: String, color: Color) -> void:
	var body: MeshInstance3D = _man_mesh if _man.visible else _woman_mesh
	var mesh := body.mesh as ArrayMesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i).to_lower() == surface_name.to_lower():
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			body.set_surface_override_material(i, mat)


## Set the skin color by tinting all non-clothing, non-hair surfaces.
## A slider value of 0.0 = lightest skin, 1.0 = darkest skin.
## Also tints the eye meshes (the skin-colored sclera/eyelid portion)
## so the skin tone matches around the eyes.
func set_skin_color(slider_value: float) -> void:
	var skin_color := _skin_color_from_slider(slider_value)
	var body: MeshInstance3D = _man_mesh if _man.visible else _woman_mesh
	var mesh := body.mesh as ArrayMesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var sname := mesh.surface_get_name(i).to_lower()
		if sname in CLOTHING_SURFACES:
			continue
		if sname in ["hair", "eyebrow", "eyebrows"]:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = skin_color
		body.set_surface_override_material(i, mat)
	# Apply the same skin color to the eye meshes so the skin tone
	# around the eyes matches the rest of the body.
	var left_eye: MeshInstance3D = (
		_left_eye
		if _left_eye
		else (_man_left_eye if _man.visible else _woman_left_eye)
	)
	var right_eye: MeshInstance3D = (
		_right_eye
		if _right_eye
		else (_man_right_eye if _man.visible else _woman_right_eye)
	)
	for eye in [left_eye, right_eye]:
		if eye == null or not is_instance_valid(eye):
			continue
		var eye_mesh := eye.mesh as ArrayMesh
		if eye_mesh == null:
			continue
		for i in eye_mesh.get_surface_count():
			# Only tint the "Skin" surface (eyelid). The other surfaces
			# are the iris/white (unnamed) and pupil ("EyeBlack") —
			# those must keep their original materials.
			var sname := eye_mesh.surface_get_name(i).to_lower()
			if sname != "skin":
				continue
			var eye_mat := StandardMaterial3D.new()
			eye_mat.albedo_color = skin_color
			eye.set_surface_override_material(i, eye_mat)


## Map a 0-1 slider value to a skin color ranging from light to dark.
func _skin_color_from_slider(value: float) -> Color:
	var light := Color(0.98, 0.87, 0.75, 1.0)
	var tan := Color(0.90, 0.72, 0.55, 1.0)
	var medium := Color(0.75, 0.55, 0.40, 1.0)
	var dark := Color(0.45, 0.30, 0.22, 1.0)
	var darkest := Color(0.25, 0.16, 0.12, 1.0)
	if value < 0.25:
		return light.lerp(tan, value / 0.25)
	elif value < 0.5:
		return tan.lerp(medium, (value - 0.25) / 0.25)
	elif value < 0.75:
		return medium.lerp(dark, (value - 0.5) / 0.25)
	else:
		return dark.lerp(darkest, (value - 0.75) / 0.25)


func set_clothing_colors(colors: Dictionary) -> void:
	var body: MeshInstance3D = _man_mesh if _man.visible else _woman_mesh
	var mesh := body.mesh as ArrayMesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var sname := mesh.surface_get_name(i).to_lower()
		if sname in CLOTHING_SURFACES and colors.has(sname):
			var mat := StandardMaterial3D.new()
			mat.albedo_color = colors[sname]
			body.set_surface_override_material(i, mat)


func get_clothing_surface_names() -> Array[String]:
	var body: MeshInstance3D = _man_mesh if _man.visible else _woman_mesh
	var mesh := body.mesh as ArrayMesh
	if mesh == null:
		return []
	var result: Array[String] = []
	for i in mesh.get_surface_count():
		var sname := mesh.surface_get_name(i).to_lower()
		if sname in CLOTHING_SURFACES and not result.has(sname):
			result.append(sname)
	return result


## Apply a customization dictionary (stored in lobby roster) to this visual.
func apply_customization(data: Dictionary) -> void:
	var male: bool = data.get("male", true)
	set_gender(male)
	var hair_idx: int = data.get("hair_index", 0)
	var hair_color: Color = data.get("hair_color", HAIR_COLORS[2])
	set_hair(hair_idx, hair_color)
	var eb_idx: int = data.get("eyebrow_index", 0)
	set_eyebrow(eb_idx)
	var clothing: Dictionary = data.get("clothing_colors", { })
	if clothing.is_empty():
		_tint_clothing(_man_mesh if male else _woman_mesh)
	else:
		set_clothing_colors(clothing)
	# Skin color (0.0 = lightest, 1.0 = darkest)
	var skin_val: float = data.get("skin_color", 0.0)
	if skin_val > 0.0:
		set_skin_color(skin_val)


## Get the current customization as a dictionary (for storing in roster).
func get_customization() -> Dictionary:
	var data: Dictionary = { }
	data["male"] = _man.visible
	# Find visible hair index
	var hairs: Node3D = _man_hairs if _man.visible else _woman_hairs
	var hair_idx := 0
	for i in hairs.get_children().size():
		var c := hairs.get_child(i) as Node3D
		if c and c.visible:
			hair_idx = i
			break
	data["hair_index"] = hair_idx
	# Find visible eyebrow index
	var eb := _get_eyebrows_node()
	var eb_idx := 0
	if eb:
		for i in eb.get_children().size():
			var c := eb.get_child(i) as Node3D
			if c and c.visible:
				eb_idx = i
				break
	data["eyebrow_index"] = eb_idx
	return data


## Scale the head bone to make it bigger (cartoony proportions).
## Uses set_bone_pose_scale so only the scale changes (not position),
## and it's an absolute set so repeated calls don't compound.
func scale_head_bone(scale: float) -> void:
	var skel := get_active_skeleton()
	if skel == null:
		return
	var head_idx := skel.find_bone("Head")
	if head_idx >= 0:
		skel.set_bone_pose_scale(head_idx, Vector3.ONE * scale)


func play_anim(anim_name: String) -> void:
	if _active_anim == null:
		return
	if not _active_anim.has_animation(anim_name):
		return
	var anim := _active_anim.get_animation(anim_name)
	if anim:
		# Talk plays once, everything else loops
		if anim_name == "Talk":
			anim.loop_mode = Animation.LOOP_NONE
		else:
			anim.loop_mode = Animation.LOOP_LINEAR
	# Apply per-animation speed from exported parameters.
	var speed_map := {
		"Walk": walk_speed,
		"Idle": idle_speed,
		"Idle_001": idle_alt_speed,
		"LookAround": look_around_speed,
		"Talk": talk_speed,
	}
	var s: float = speed_map.get(anim_name, 1.0)
	# custom_blend=0.0 = instant switch (no blending), custom_speed=s
	_active_anim.play(anim_name, 0.0, s)


## Play an animation with a custom speed multiplier (overrides the default).
## Passes speed as custom_speed to play() so it actually takes effect
## (play()'s custom_speed defaults to 1.0 and overrides speed_scale).
func play_anim_speed(anim_name: String, speed: float) -> void:
	if _active_anim == null:
		return
	if not _active_anim.has_animation(anim_name):
		return
	var anim := _active_anim.get_animation(anim_name)
	if anim:
		if anim_name == "Talk":
			anim.loop_mode = Animation.LOOP_NONE
		else:
			anim.loop_mode = Animation.LOOP_LINEAR
	# custom_blend=0.0 = instant switch (no blending), custom_speed=speed
	_active_anim.play(anim_name, 0.0, speed)


## Update the speed of the currently playing animation without restarting it.
func set_anim_speed(speed: float) -> void:
	if _active_anim == null:
		return
	_active_anim.speed_scale = speed


func pause_anim() -> void:
	if _active_anim != null:
		_active_anim.playback_active = false


func resume_anim(anim_name: String = "Walk") -> void:
	if _active_anim == null:
		return
	if _active_anim.assigned_animation != anim_name:
		_active_anim.play(anim_name)
	_active_anim.playback_active = true


func get_active_skeleton() -> Skeleton3D:
	if _man.visible:
		return $man/Armature/Skeleton3D as Skeleton3D
	return $woman/Armature/Skeleton3D as Skeleton3D


## Update neck and head bones based on camera look direction.
## Neck rotates on Y (left/right) up to ±0.2 rad before the body turns.
## Head rotates on X (up/down) up to +0.5 (down) / -0.5 (up).
## Called from the player's _process.
var _neck_yaw: float = 0.0
var _head_pitch: float = 0.0
const NECK_YAW_MAX: float = 0.2
const HEAD_PITCH_MAX: float = 0.5


func set_look_target(camera_yaw: float, camera_pitch: float, body_yaw: float) -> void:
	_look_camera_yaw = camera_yaw
	_look_camera_pitch = camera_pitch
	_look_body_yaw = body_yaw


func _physics_process(_delta: float) -> void:
	# Apply the procedural head/neck pose in the physics step. Because the
	# AnimationPlayer is also set to physics callback, this runs before the
	# animation overwrites the pose; the deferred call runs after the animation
	# update so the pose wins for the rendered frame.
	update_look_bones(_look_camera_yaw, _look_camera_pitch, _look_body_yaw)
	call_deferred("update_look_bones", _look_camera_yaw, _look_camera_pitch, _look_body_yaw)


func update_look_bones(camera_yaw: float, camera_pitch: float, body_yaw: float) -> void:
	var skel := get_active_skeleton()
	if skel == null:
		return
	# Neck yaw: difference between camera yaw and body yaw, clamped
	var yaw_diff := wrap_angle(camera_yaw - body_yaw)
	_neck_yaw = clampf(yaw_diff, -NECK_YAW_MAX, NECK_YAW_MAX)
	# Head pitch: camera pitch inverted because the model's local X axis
	# points the opposite way to the camera's pitch direction.
	_head_pitch = clampf(-camera_pitch, -HEAD_PITCH_MAX, HEAD_PITCH_MAX)
	# Apply to neck bone (Y rotation) as a local rotation on top of the bone's
	# rest pose, so it turns around the bone's own axis instead of world space.
	var neck_idx := skel.find_bone("Neck")
	if neck_idx >= 0:
		var rest := skel.get_bone_rest(neck_idx)
		var local_yaw := Quaternion.from_euler(Vector3(0, _neck_yaw, 0))
		var neck_rot := rest.basis.get_rotation_quaternion() * local_yaw
		skel.set_bone_pose_rotation(neck_idx, neck_rot)
	# Apply to head bone (X rotation for pitch)
	var head_idx := skel.find_bone("Head")
	if head_idx >= 0:
		var rest := skel.get_bone_rest(head_idx)
		var local_pitch := Quaternion.from_euler(Vector3(_head_pitch, 0, 0))
		var head_rot := rest.basis.get_rotation_quaternion() * local_pitch
		skel.set_bone_pose_rotation(head_idx, head_rot)


## Wrap an angle to the [-PI, PI] range.
func wrap_angle(angle: float) -> float:
	while angle > PI:
		angle -= TAU
	while angle < -PI:
		angle += TAU
	return angle


func get_cash_point_name() -> String:
	return "CashPoint" if _man.visible else "CashPoint2"


func get_hand_global_pos(hand_name: String = "Hand.L") -> Vector3:
	var skel := get_active_skeleton()
	if skel == null:
		return global_position
	var idx := skel.find_bone(hand_name)
	if idx < 0:
		return global_position
	return skel.to_global(skel.get_bone_global_pose(idx).origin)


func start_payment_pose(_target_world_pos: Vector3) -> void:
	var skel := get_active_skeleton()
	if skel == null:
		return
	# Stop animation so bone poses aren't overwritten every frame.
	if _active_anim != null:
		_active_anim.stop()
	# Exact left-arm pose values from the editor.
	var upper := skel.find_bone("UpperArm.L")
	var forearm := skel.find_bone("Forearm.L")
	var hand := skel.find_bone("Hand.L")
	if upper >= 0:
		skel.set_bone_pose_rotation(upper, Quaternion(0.079505, -0.500881, -0.996835, -0.073285))
	if forearm >= 0:
		skel.set_bone_pose_rotation(forearm, Quaternion(0.268259, -0.000267, -0.266304, 2.115031))
	if hand >= 0:
		skel.set_bone_pose_rotation(hand, Quaternion(-0.119877, -1.080266, 0.089036, 1.313535))
		skel.set_bone_pose_position(hand, Vector3(0, 2.771, 0.29))


func stop_payment_pose() -> void:
	var skel := get_active_skeleton()
	if skel == null:
		return
	# Reset the 3 posed bones back to their REST pose so animation takes over cleanly.
	for bone_name in ["UpperArm.L", "Forearm.L", "Hand.L"]:
		var idx := skel.find_bone(bone_name)
		if idx >= 0:
			var rest := skel.get_bone_rest(idx)
			skel.set_bone_pose_rotation(idx, rest.basis.get_rotation_quaternion())
			skel.set_bone_pose_position(idx, rest.origin)


func _process(delta: float) -> void:
	# If a look_at_target is set (e.g. lobby camera), always track it
	if look_at_target != null and is_instance_valid(look_at_target):
		_update_eye_look(delta)
		return
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 0.2
		_is_near_player = _is_player_near()

	if _is_near_player:
		_update_eye_look(delta)


func _update_eye_look(delta: float) -> void:
	if _left_eye == null or _left_rest_dir == Vector3.ZERO:
		return

	# If a look_at_target override is set, use it directly
	if look_at_target != null and is_instance_valid(look_at_target):
		var aim := look_at_target.global_position
		var dist_l := _left_eye.global_position.distance_to(aim)
		var dist_r := _right_eye.global_position.distance_to(aim)
		var t := clampf(eye_look_speed * delta, 0.0, 1.0)
		var target_l := _target_eye_rot(_left_eye, _left_rest_dir, aim, dist_l)
		var target_r := _target_eye_rot(_right_eye, _right_rest_dir, aim, dist_r)
		_eye_rot_l = _eye_rot_l.slerp(target_l, t)
		_eye_rot_r = _eye_rot_r.slerp(target_r, t)
		_apply_eye(_left_eye, _eye_rot_l)
		_apply_eye(_right_eye, _eye_rot_r)
		return

	# Determine the look target: for player visuals, use the closest other
	# player; for NPC visuals, use the single "Player" node.
	var target: Node3D = null
	var dist: float = INF

	if is_player_visual:
		target = _closest_player_cache
		if target == null or not is_instance_valid(target):
			# Try a fresh search in case the cache is stale
			target = _find_closest_other_player()
		if target == null:
			# No other player nearby — ease eyes back to neutral
			var t := clampf(eye_look_speed * delta, 0.0, 1.0)
			_eye_rot_l = _eye_rot_l.slerp(Quaternion.IDENTITY, t)
			_eye_rot_r = _eye_rot_r.slerp(Quaternion.IDENTITY, t)
			_apply_eye(_left_eye, _eye_rot_l)
			_apply_eye(_right_eye, _eye_rot_r)
			return
		dist = _closest_player_dist
	else:
		if not is_instance_valid(_player_cache):
			_player_cache = get_tree().current_scene.find_child("Player", true, false) as Node3D
		if _player_cache == null:
			return
		target = _player_cache
		dist = _left_eye.global_position.distance_to(target.global_position)

	# Far-away NPCs only keep rotating back to neutral; skip math once they're there.
	if dist > eye_look_range:
		var left_neutral := absf(_eye_rot_l.dot(Quaternion.IDENTITY)) > 0.9999
		var right_neutral := absf(_eye_rot_r.dot(Quaternion.IDENTITY)) > 0.9999
		if left_neutral and right_neutral:
			return

	# For player visuals, aim at the other player's head/chest height.
	# For NPC visuals, use the player's camera if available.
	var aim: Vector3
	if is_player_visual:
		aim = target.global_position + Vector3(0, 1.5, 0)
	else:
		var cam := _get_player_camera()
		aim = cam.global_position if cam else target.global_position + Vector3(0, 1.7, 0)

	var t := clampf(eye_look_speed * delta, 0.0, 1.0)
	var target_l := Quaternion.IDENTITY
	var target_r := Quaternion.IDENTITY
	if dist <= eye_look_range:
		target_l = _target_eye_rot(_left_eye, _left_rest_dir, aim, dist)
		target_r = _target_eye_rot(_right_eye, _right_rest_dir, aim, dist)

	_eye_rot_l = _eye_rot_l.slerp(target_l, t)
	_eye_rot_r = _eye_rot_r.slerp(target_r, t)
	_apply_eye(_left_eye, _eye_rot_l)
	_apply_eye(_right_eye, _eye_rot_r)


## Computes the world-space rotation that swings the eye's rest-forward toward aim.
## Uses parent basis + local rest direction so it's stable under eye rotation.
func _target_eye_rot(
	eye: MeshInstance3D,
	rest_local: Vector3,
	aim: Vector3,
	dist: float,
) -> Quaternion:
	if dist > eye_look_range:
		return Quaternion.IDENTITY
	var par := eye.get_parent() as Node3D
	if par == null:
		return Quaternion.IDENTITY
	# Reconstruct world-space rest-forward from the parent's (Head bone) basis.
	# Does NOT use the eye's own basis so it stays stable as we rotate it.
	var rest_fwd := (par.global_transform.basis * rest_local).normalized()
	var want_fwd := (aim - eye.global_position).normalized()
	var ang := rest_fwd.angle_to(want_fwd)
	if ang < 0.001:
		return Quaternion.IDENTITY
	var clamped_fwd := rest_fwd.slerp(want_fwd, minf(deg_to_rad(eye_look_max_deg) / ang, 1.0)).normalized()
	var clamped_ang := rest_fwd.angle_to(clamped_fwd)
	if clamped_ang < 0.001:
		return Quaternion.IDENTITY
	var axis := rest_fwd.cross(clamped_fwd)
	if axis.length_squared() < 0.0001:
		return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), clamped_ang)


## Applies a world-space rotation on top of the eye's rest pose (scale-only basis).
func _apply_eye(eye: MeshInstance3D, world_rot: Quaternion) -> void:
	var par := eye.get_parent() as Node3D
	if par == null:
		return
	var P := par.global_transform.basis
	# Convert world-space rotation to parent-local: L = P⁻¹ · Rw · P
	var local_rot := P.inverse() * Basis(world_rot) * P
	eye.transform = Transform3D(
		local_rot * Basis.from_scale(Vector3.ONE * _EYE_SCALE),
		eye.transform.origin,
	)


func _pick_hair(hairs: Node3D, color: Color) -> void:
	var children := hairs.get_children()
	if children.is_empty():
		return
	var chosen: int = randi() % children.size()
	for i in children.size():
		var child := children[i] as Node3D
		if child == null:
			continue
		child.visible = i == chosen
		if i == chosen:
			_tint_meshes_in(child, color)


## Seeded version of _pick_hair for deterministic multiplayer sync.
func _pick_hair_seeded(hairs: Node3D, color: Color, rng: RandomNumberGenerator) -> void:
	var children := hairs.get_children()
	if children.is_empty():
		return
	var chosen: int = rng.randi() % children.size()
	for i in children.size():
		var child := children[i] as Node3D
		if child == null:
			continue
		child.visible = i == chosen
		if i == chosen:
			_tint_meshes_in(child, color)


## Each clothing surface picks its own independent random color.
func _tint_clothing(body: MeshInstance3D) -> void:
	var mesh := body.mesh as ArrayMesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i).to_lower() in CLOTHING_SURFACES:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = CLOTHING_COLORS[randi() % CLOTHING_COLORS.size()]
			body.set_surface_override_material(i, mat)


## Seeded version of _tint_clothing for deterministic multiplayer sync.
func _tint_clothing_seeded(body: MeshInstance3D, rng: RandomNumberGenerator) -> void:
	var mesh := body.mesh as ArrayMesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i).to_lower() in CLOTHING_SURFACES:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = CLOTHING_COLORS[rng.randi() % CLOTHING_COLORS.size()]
			body.set_surface_override_material(i, mat)


## Applies a uniform color to all MeshInstance3D nodes inside a GLB-instanced hair node.
func _tint_meshes_in(root: Node3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = mat

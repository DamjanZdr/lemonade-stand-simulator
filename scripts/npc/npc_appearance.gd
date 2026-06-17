extends Node3D
## Randomizes the visual appearance of an NPC each time randomize_appearance() is called.
## Picks gender, a random hairstyle, hair color, and per-surface clothing color — giving
## virtually unlimited unique customer looks from the same base mesh + attribute GLBs.

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

const _EYE_SCALE := 0.30564013

var _active_anim: AnimationPlayer = null
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


func randomize_appearance() -> void:
	var male := randi() % 2 == 0
	_man.visible = male
	_woman.visible = not male
	_active_anim = _man_anim if male else _woman_anim
	_left_eye = _man_left_eye if male else _woman_left_eye
	_right_eye = _man_right_eye if male else _woman_right_eye
	_left_marker = _man_left_marker if male else _woman_left_marker
	_right_marker = _man_right_marker if male else _woman_right_marker
	# Capture forward direction in eye-local space from the marker's local position.
	# This is stable — it doesn't change when the eye mesh rotates.
	_left_rest_dir = _left_marker.position.normalized() if _left_marker.position.length() > 0.001 else Vector3(0, 0, 1)
	_right_rest_dir = _right_marker.position.normalized() if _right_marker.position.length() > 0.001 else Vector3(0, 0, 1)
	_eye_rot_l = Quaternion.IDENTITY
	_eye_rot_r = Quaternion.IDENTITY

	var hairs: Node3D = _man_hairs if male else _woman_hairs
	var body: MeshInstance3D = _man_mesh if male else _woman_mesh

	_pick_hair(hairs, HAIR_COLORS[randi() % HAIR_COLORS.size()])
	_tint_clothing(body)


func play_anim(anim_name: String) -> void:
	if _active_anim == null:
		return
	if not _active_anim.has_animation(anim_name):
		return
	# Force loop mode on the animation resource so Walk/Idle repeat continuously.
	var anim := _active_anim.get_animation(anim_name)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR
	# Apply per-animation speed from exported parameters.
	var speed_map := {
		"Walk": walk_speed,
		"Idle": idle_speed,
		"Idle_001": idle_alt_speed,
		"LookAround": look_around_speed,
		"Talk": talk_speed,
	}
	_active_anim.speed_scale = speed_map.get(anim_name, 1.0)
	_active_anim.play(anim_name)


func get_active_skeleton() -> Skeleton3D:
	if _man.visible:
		return $man/Armature/Skeleton3D as Skeleton3D
	return $woman/Armature/Skeleton3D as Skeleton3D


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
	_update_eye_look(delta)


func _update_eye_look(delta: float) -> void:
	if _left_eye == null or _left_rest_dir == Vector3.ZERO:
		return

	if not is_instance_valid(_player_cache):
		_player_cache = get_tree().current_scene.find_child("Player", true, false) as Node3D
	if _player_cache == null:
		return

	var aim := _player_cache.global_position + Vector3(0, 1.2, 0)
	var dist := _left_eye.global_position.distance_to(_player_cache.global_position)
	var t := clampf(eye_look_speed * delta, 0.0, 1.0)

	_eye_rot_l = _eye_rot_l.slerp(_target_eye_rot(_left_eye, _left_rest_dir, aim, dist), t)
	_eye_rot_r = _eye_rot_r.slerp(_target_eye_rot(_right_eye, _right_rest_dir, aim, dist), t)

	_apply_eye(_left_eye, _eye_rot_l)
	_apply_eye(_right_eye, _eye_rot_r)


## Computes the world-space rotation that swings the eye's rest-forward toward aim.
## Uses parent basis + local rest direction so it's stable under eye rotation.
func _target_eye_rot(eye: MeshInstance3D, rest_local: Vector3, aim: Vector3, dist: float) -> Quaternion:
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
	eye.transform = Transform3D(local_rot * Basis.from_scale(Vector3.ONE * _EYE_SCALE), eye.transform.origin)


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


## Applies a uniform color to all MeshInstance3D nodes inside a GLB-instanced hair node.
func _tint_meshes_in(root: Node3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = mat

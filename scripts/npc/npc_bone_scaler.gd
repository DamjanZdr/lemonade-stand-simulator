class_name NpcBoneScaler
extends SkeletonModifier3D
## Multiplies bone pose scales every frame AFTER the AnimationPlayer has
## written them. Needed because the NPC animations carry scale_3d tracks
## on every bone, so a one-shot set_bone_pose_scale() is stomped on the
## next frame.
##
## When a bone's animation has no scale track, the pose still contains
## last frame's multiplied value — we detect that case and divide our
## own previous multiplier back out so it never compounds.

## bone_idx -> Vector3 multiplier to apply on top of the animated scale.
var _scales: Dictionary = { }
## bone_idx -> the final value we wrote last frame.
var _applied: Dictionary = { }
## bone_idx -> the pre-multiplier value from last frame (used when the
## animation didn't rewrite the bone this frame).
var _bases: Dictionary = { }


func _ready() -> void:
	influence = 1.0
	active = true


func set_bone_scale(bone_name: String, mul: Vector3) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	var idx := skel.find_bone(bone_name)
	if idx >= 0:
		_scales[idx] = mul


func clear() -> void:
	_scales.clear()
	_applied.clear()
	_bases.clear()


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _scales.is_empty():
		return
	for idx: int in _scales:
		var mul: Vector3 = _scales[idx]
		var base := skel.get_bone_pose_scale(idx)
		var prev: Vector3 = _applied.get(idx, Vector3.ZERO)
		if prev != Vector3.ZERO and base.is_equal_approx(prev):
			# Animation left our value untouched — recover the
			# pre-multiplier base so we don't compound.
			base = _bases.get(idx, Vector3.ONE)
		var out := base * mul
		skel.set_bone_pose_scale(idx, out)
		_bases[idx] = base
		_applied[idx] = out

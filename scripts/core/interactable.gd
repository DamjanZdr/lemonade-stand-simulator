class_name Interactable
extends Node3D
## Base class for all clickable objects in the world.
## Subclasses override interact() and get_hint().
##
## Highlighting uses a screen-space edge-detection outline (no object tint).
## Each MeshInstance3D child gets an "_Outline" child placed on render layer 2
## only.  The main Camera3D has layer 2 masked out, so the fill is invisible in
## normal play.  The SubViewport OutlineCamera (cull_mask=2) renders only the
## fills → the canvas shader (outline_overlay) draws just the border pixels.

## Shared flat-white fill material (lazy-created, truly one instance per game).
static var _fill_mat: StandardMaterial3D = null


func interact(player: Node) -> void:
	pass


func interact_secondary(player: Node) -> void:
	pass


func get_hint(_player: Node) -> String:
	return "Interact"


func set_highlight(on: bool) -> void:
	_apply_outline(self, on)


func _get_fill_mat() -> StandardMaterial3D:
	if _fill_mat == null:
		_fill_mat = StandardMaterial3D.new()
		_fill_mat.albedo_color = Color.WHITE
		_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	return _fill_mat


func _apply_outline(node: Node, on: bool) -> void:
	if node is MeshInstance3D and node.name != "_Outline":
		var mi := node as MeshInstance3D
		var existing := mi.get_node_or_null("_Outline") as MeshInstance3D
		if on and existing == null and mi.mesh != null:
			var ol := MeshInstance3D.new()
			ol.name = "_Outline"
			ol.mesh = mi.mesh
			ol.layers = 2 # invisible to main camera; seen only by OutlineCamera
			ol.material_override = _get_fill_mat()
			ol.add_to_group("outline_fill")
			ol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ol.skin = mi.skin
			mi.add_child(ol)
			ol.transform = Transform3D.IDENTITY
			var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
			if skel != null:
				ol.skeleton = ol.get_path_to(skel)
		elif not on and existing != null:
			existing.queue_free()
	for child in node.get_children():
		if child.name == "_Outline":
			continue # never recurse into outline nodes themselves
		_apply_outline(child, on)


## Returns the player's held mesh center for throw-arc animations.
func _get_hand_pos(player: Node) -> Vector3:
	var held_mesh: Node3D = player.get("_held_mesh")
	if held_mesh != null and is_instance_valid(held_mesh):
		return held_mesh.global_position
	var hand: Node3D = player.get("hand_slot")
	if hand != null:
		return hand.global_position
	return player.global_position + Vector3(0, 1.0, 0)


## Animates a node from start_global to its target_local slot along a
## cubic-bezier arc, mimicking the delivery truck's throwing motion.
## Returns the Tween so callers can chain finished callbacks.
func _animate_throw_arc(
	node: Node3D, start_global: Vector3, target_local: Vector3,
	duration: float = 0.35,
) -> Tween:
	var parent := node.get_parent()
	if parent == null:
		return null
	var target_global: Vector3 = parent.to_global(target_local)
	var dist := start_global.distance_to(target_global)
	var arc_h := clampf(dist * 0.4, 0.3, 2.0)
	var cp1 := start_global + Vector3(0, arc_h, 0)
	var cp2: Vector3 = target_global + Vector3(0, arc_h, 0)
	node.global_position = start_global
	AudioManager.play_sfx("swoosh", start_global)
	var tween := node.create_tween()
	tween.tween_method(
		func(t: float):
			var p: Vector3 = start_global * (1.0 - t) ** 3 \
				+ cp1 * 3.0 * ((1.0 - t) ** 2) * t \
				+ cp2 * 3.0 * (1.0 - t) * (t ** 2) \
				+ target_global * (t ** 3)
			node.global_position = p,
		0.0, 1.0, duration,
	).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(func(): node.position = target_local)
	return tween

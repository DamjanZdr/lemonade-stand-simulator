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
		_fill_mat.albedo_color            = Color.WHITE
		_fill_mat.shading_mode            = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fill_mat.transparency            = BaseMaterial3D.TRANSPARENCY_DISABLED
	return _fill_mat


func _apply_outline(node: Node, on: bool) -> void:
	if node is MeshInstance3D and node.name != "_Outline":
		var mi       := node as MeshInstance3D
		var existing := mi.get_node_or_null("_Outline") as MeshInstance3D
		if on and existing == null and mi.mesh != null:
			var ol := MeshInstance3D.new()
			ol.name              = "_Outline"
			ol.mesh              = mi.mesh
			ol.layers            = 2        # invisible to main camera; seen only by OutlineCamera
			ol.material_override = _get_fill_mat()
			mi.add_child(ol)
		elif not on and existing != null:
			existing.queue_free()
	for child in node.get_children():
		if child.name == "_Outline":
			continue  # never recurse into outline nodes themselves
		_apply_outline(child, on)

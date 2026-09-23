@tool
extends EditorScript

const BakePrep := preload("res://scripts/tools/lightmap_bake_prep.gd")


func _run() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		push_error("PrepareCoopLightmap: open scenes/world/world.tscn first.")
		return
	BakePrep.prepare(root, false)

@tool
extends EditorScript


func _run() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		push_error("PrepareCoopLightmap: open scenes/world/world.tscn first.")
		return
	var prep := LightmapBakePrep.new()
	prep.prepare(root, false)

@tool
extends EditorScript
## Run this from the editor: File → Run File (or Ctrl+Shift+X in the script editor).
## Sets gi_mode on all MeshInstance3D nodes based on distance from the stand.
## Meshes within BAKE_RADIUS get GI_MODE_STATIC (baked into lightmaps).
## Meshes outside get GI_MODE_DYNAMIC (lit by SDFGI/VoxelGI at runtime, not baked).

const STAND_POS := Vector3(2.0, 0.0, -2.0)
const BAKE_RADIUS := 60.0


func _run() -> void:
	var edited := get_editor_interface().get_edited_scene_root()
	if edited == null:
		print("SetLightmapGI: No scene open in editor!")
		return
	var counts := { "static": 0, "dynamic": 0 }
	_set_gi_by_distance(edited, counts)
	print(
		"SetLightmapGI: %d STATIC (within %.0f units), %d DYNAMIC (far)"
		% [counts.static, BAKE_RADIUS, counts.dynamic]
	)


func _set_gi_by_distance(node: Node, counts: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var dist := mi.global_position.distance_to(STAND_POS)
		if dist <= BAKE_RADIUS:
			mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			counts.static += 1
		else:
			mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
			counts.dynamic += 1
	for child in node.get_children():
		_set_gi_by_distance(child, counts)

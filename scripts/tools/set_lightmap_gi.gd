@tool
extends EditorScript
## Run this from the editor: File → Run File (or Ctrl+Shift+X in the script editor).
## Sets gi_mode on all MeshInstance3D nodes based on distance from the stands.
## Meshes within BAKE_RADIUS of EITHER stand get GI_MODE_STATIC (baked into lightmaps).
## Meshes outside get GI_MODE_DYNAMIC (lit by VoxelGI at runtime, not baked).
## This prevents the bake from processing the entire 2000+ node neighborhood
## and crashing — only nearby geometry gets baked.

const BAKE_RADIUS := 100.0
const STAND_POSITIONS := [
	Vector3(2.0, 0.0, -2.0), # StandUnit (at origin)
	Vector3(-8.1, 0.0, -24.0), # StandUnit2
]


func _run() -> void:
	var edited := get_editor_interface().get_edited_scene_root()
	if edited == null:
		print("SetLightmapGI: No scene open in editor!")
		return
	var counts := { "static": 0, "dynamic": 0 }
	_set_gi_by_distance(edited, counts)
	print(
		"SetLightmapGI: %d STATIC (within %.0f units of a stand), %d DYNAMIC (far)"
		% [counts.static, BAKE_RADIUS, counts.dynamic]
	)


func _set_gi_by_distance(node: Node, counts: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var min_dist := INF
		for pos in STAND_POSITIONS:
			var d := mi.global_position.distance_to(pos)
			if d < min_dist:
				min_dist = d
		if min_dist <= BAKE_RADIUS:
			mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			counts.static += 1
		else:
			mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
			counts.dynamic += 1
	for child in node.get_children():
		_set_gi_by_distance(child, counts)

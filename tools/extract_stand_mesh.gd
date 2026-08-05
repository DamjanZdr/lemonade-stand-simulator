extends SceneTree

func _init() -> void:
	var ps := load("res://assets/models/props/stand.glb") as PackedScene
	if ps == null:
		push_error("Failed to load res://assets/models/props/stand.glb")
		quit()
		return

	var root := ps.instantiate()
	var mi := _find_mesh_instance(root)
	if mi == null:
		push_error("No MeshInstance3D found in stand.glb")
		quit()
		return

	var mesh := mi.mesh.duplicate(true) as ArrayMesh
	if mesh == null:
		push_error("MeshInstance3D has no ArrayMesh")
		quit()
		return

	var plank_mat := StandardMaterial3D.new()
	plank_mat.albedo_texture = load("res://assets/textures/props/stand_StandTexture.png")

	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.052, 0.052, 0.052)

	for i in range(mesh.get_surface_count()):
		# Surface 0 is Plank1 (textured), surface 1 is Metal (dark).
		mesh.surface_set_material(i, plank_mat if i == 0 else metal_mat)

	var err := ResourceSaver.save(
		mesh,
		"res://scenes/stand/stand_Cube_024.res",
		ResourceSaver.FLAG_COMPRESS,
	)
	if err != OK:
		push_error("Failed to save stand mesh: " + str(err))
	else:
		print("Saved updated stand mesh to res://scenes/stand/stand_Cube_024.res")

	quit()


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null

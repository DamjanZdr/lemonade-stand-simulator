extends SceneTree

func _init():
	var scene_source := load("res://assets/models/grassblades.glb") as PackedScene
	if scene_source == null:
		push_error("Failed to load grassblades.glb")
		quit()
		return
	var scene := scene_source.instantiate()
	var mesh := _extract_first_mesh(scene)
	scene.queue_free()
	if mesh == null:
		push_error("No mesh found in grassblades.glb")
		quit()
		return
	var err := ResourceSaver.save(mesh, "res://assets/models/environment/Grass/grassblade.res")
	if err != OK:
		push_error("Failed to save grassblade.res: %d" % err)
	else:
		print("Saved grassblade.res")
	quit()


func _extract_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found := _extract_first_mesh(child)
		if found != null:
			return found
	return null

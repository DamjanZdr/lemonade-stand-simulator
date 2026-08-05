class_name GrassScatterer
extends Node3D
## Procedurally scatters grass instances across grass patch surfaces.
## Culls blades that sit under blocker geometry (roads, sidewalks, houses).

@export var grass_mesh: Mesh
@export var grass_material: Material
@export var grass_mesh_scene: PackedScene
@export var grass_density: float = 20.0 # Blades per square unit on each patch
@export var random_seed: int = 0
@export var base_scale: float = 0.1
@export var scale_variance: float = 0.05
@export var max_draw_distance: float = 80.0
@export var grass_surfaces_path: NodePath
@export var surface_group: StringName = &"grass_surface"
@export var blocker_group: StringName = &"grass_blocker"
@export var blocker_margin: float = 0.05

var _multimesh: MultiMeshInstance3D
var _blockers: Array[Dictionary] = []
var _surfaces: Array[Node] = []


func _ready() -> void:
	if random_seed != 0:
		seed(random_seed)
	# Wait one frame so all transforms are committed before sampling AABBs.
	await get_tree().process_frame
	_generate_grass()


func _generate_grass() -> void:
	var mesh := _get_grass_mesh()
	if mesh == null:
		push_error("GrassScatterer: No grass mesh assigned!")
		return

	_surfaces = _get_grass_surfaces()
	if _surfaces.is_empty():
		push_error("GrassScatterer: No grass surfaces found!")
		return

	_build_blockers()

	_multimesh = MultiMeshInstance3D.new()
	_multimesh.name = "GrassMultiMesh"
	_multimesh.multimesh = MultiMesh.new()
	_multimesh.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.multimesh.mesh = mesh

	var material := _get_grass_material()
	if material != null:
		_multimesh.material_override = material

	var instances: Array[Transform3D] = []

	for surface in _surfaces:
		if not surface is GeometryInstance3D:
			continue
		var geom := surface as GeometryInstance3D
		var aabb: AABB = geom.get_aabb()
		if aabb.size.length_squared() <= 0.0:
			continue
		var patch_size := Vector2(aabb.size.x, aabb.size.z)
		var patch_instances := int(patch_size.x * patch_size.y * grass_density)
		for i in range(patch_instances):
			var local_x := randf_range(aabb.position.x, aabb.position.x + aabb.size.x)
			var local_z := randf_range(aabb.position.z, aabb.position.z + aabb.size.z)
			var top_y := aabb.position.y + aabb.size.y
			var pos := geom.global_transform * Vector3(local_x, top_y, local_z)

			if _is_blocked(pos):
				continue

			var rotation_y := randf() * TAU
			var tilt_x := randf_range(-0.2, 0.2)
			var tilt_z := randf_range(-0.2, 0.2)
			var scale_var := base_scale + randf_range(-scale_variance, scale_variance)

			var grass_transform := Transform3D()
			grass_transform = grass_transform.scaled(Vector3(scale_var, scale_var, scale_var))
			grass_transform = grass_transform.rotated(Vector3.RIGHT, tilt_x)
			grass_transform = grass_transform.rotated(Vector3.FORWARD, tilt_z)
			grass_transform = grass_transform.rotated(Vector3.UP, rotation_y)
			grass_transform.origin = pos

			instances.append(grass_transform)

	_multimesh.multimesh.instance_count = instances.size()

	for i in range(instances.size()):
		_multimesh.multimesh.set_instance_transform(i, instances[i])

	add_child(_multimesh)
	_multimesh.top_level = true
	_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_multimesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if max_draw_distance > 0.0:
		_multimesh.visibility_range_end = max_draw_distance
		_multimesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	print("GrassScatterer: Generated %d grass instances" % instances.size())


func _get_grass_mesh() -> Mesh:
	if grass_mesh != null:
		return grass_mesh
	var scene_source := grass_mesh_scene
	if scene_source == null:
		scene_source = load("res://assets/models/environment/grass/grass.glb") as PackedScene
	if scene_source != null:
		var scene := scene_source.instantiate()
		var found: Mesh = _extract_first_mesh(scene)
		scene.queue_free()
		return found
	return null


func _extract_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found := _extract_first_mesh(child)
		if found != null:
			return found
	return null


func _get_grass_material() -> Material:
	if grass_material != null:
		return grass_material
	# Billboard wind shader so the grass blade always faces the camera.
	var shader := load("res://assets/shaders/grass.gdshader") as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		return mat
	return null


func _get_grass_surfaces() -> Array[Node]:
	if not surface_group.is_empty():
		return get_tree().get_nodes_in_group(surface_group)
	if not grass_surfaces_path.is_empty():
		var node := get_node_or_null(grass_surfaces_path)
		if node != null:
			return [node]
	var surfaces := get_node_or_null("GrassSurfaces")
	if surfaces == null and get_parent() != null:
		surfaces = get_parent().get_node_or_null("GrassSurfaces")
	if surfaces != null:
		return [surfaces]
	return []


func _has_surface_children(node: Node) -> bool:
	for child in node.get_children():
		if child is MeshInstance3D:
			return true
	return false


func _build_blockers() -> void:
	_blockers.clear()
	if blocker_group.is_empty():
		return
	for node in get_tree().get_nodes_in_group(blocker_group):
		if not surface_group.is_empty() and node.is_in_group(surface_group):
			continue
		_collect_blockers(node)


func _collect_blockers(node: Node) -> void:
	if not surface_group.is_empty() and node.is_in_group(surface_group):
		return
	if node == _multimesh:
		return
	if node is GeometryInstance3D:
		var geom := node as GeometryInstance3D
		var local_aabb := geom.get_aabb()
		if local_aabb.size.length_squared() > 0.0:
			_blockers.append({ "transform": geom.global_transform, "aabb": local_aabb })
		return
	for child in node.get_children():
		_collect_blockers(child)


func _is_blocked(pos: Vector3) -> bool:
	if _blockers.is_empty():
		return false
	for blocker in _blockers:
		var trans: Transform3D = blocker["transform"]
		var aabb: AABB = blocker["aabb"]
		var local_pos := trans.affine_inverse() * pos
		var expanded := aabb.grow(blocker_margin)
		if expanded.has_point(local_pos):
			return true
	return false

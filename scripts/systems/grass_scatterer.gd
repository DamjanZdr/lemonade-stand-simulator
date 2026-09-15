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
## If > 0, grass is only spawned within this radius of spawn_center.
## Use this to avoid generating millions of blades when the floor surface is huge.
@export var spawn_radius: float = 0.0
## World-space center of the spawn circle. Default is the scene origin.
@export var spawn_center: Vector3 = Vector3.ZERO
## Hard cap on instances per surface so a huge floor doesn't iterate forever.
@export var max_instances_per_surface: int = 10000
## Hard cap on total instances across all surfaces.
@export var max_total_instances: int = 100000

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
	var mesh_aabb: AABB = mesh.get_aabb()
	print("[GrassScatterer] mesh=%s aabb=%s" % [mesh.resource_name, str(mesh_aabb)])
	# With +90° X rotation local +Z becomes world -Y. The blade's bottom end in
	# world Y is at local z = aabb_end_z, so offset the origin onto the surface.
	var local_bottom_offset := Vector3(0.0, 0.0, mesh_aabb.position.z + mesh_aabb.size.z)

	_surfaces = _get_grass_surfaces()
	if _surfaces.is_empty():
		push_error("GrassScatterer: No grass surfaces found!")
		return
	print("[GrassScatterer] surfaces=%d" % _surfaces.size())
	for s in _surfaces:
		print("[GrassScatterer] surface=%s transform=%s" % [s.name, str(s.global_transform)])

	_build_blockers()

	var material := _get_grass_material()

	var instances: Array[Transform3D] = []
	var spawn_r2 := spawn_radius * spawn_radius
	var yield_counter := 0
	const YIELD_EVERY := 2048

	for surface in _surfaces:
		if instances.size() >= max_total_instances:
			break
		if not surface is GeometryInstance3D:
			continue
		var geom := surface as GeometryInstance3D
		var aabb: AABB = geom.get_aabb()
		if aabb.size.length_squared() <= 0.0:
			continue

		var local_min_x := aabb.position.x
		var local_max_x := aabb.position.x + aabb.size.x
		var local_min_z := aabb.position.z
		var local_max_z := aabb.position.z + aabb.size.z

		# If a spawn radius is set, restrict sampling to the intersection of
		# the surface and the spawn circle's bounding box (in local space).
		# This prevents iterating over a huge floor when grass is only wanted
		# around a small area.
		if spawn_radius > 0.0:
			var circle_aabb := AABB(
				spawn_center - Vector3(spawn_radius, 0.0, spawn_radius),
				Vector3(spawn_radius * 2.0, 0.0, spawn_radius * 2.0),
			)
			var circle_local := geom.global_transform.affine_inverse() * circle_aabb
			local_min_x = maxf(local_min_x, circle_local.position.x)
			local_max_x = minf(local_max_x, circle_local.position.x + circle_local.size.x)
			local_min_z = maxf(local_min_z, circle_local.position.z)
			local_max_z = minf(local_max_z, circle_local.position.z + circle_local.size.z)
			if local_max_x <= local_min_x or local_max_z <= local_min_z:
				continue

		var sample_area := (local_max_x - local_min_x) * (local_max_z - local_min_z)
		var raw_count := int(sample_area * grass_density)
		var patch_instances := clampi(raw_count, 0, max_instances_per_surface)

		for i in range(patch_instances):
			if instances.size() >= max_total_instances:
				break
			var local_x := randf_range(local_min_x, local_max_x)
			var local_z := randf_range(local_min_z, local_max_z)
			var top_y := aabb.position.y + aabb.size.y
			var pos := geom.global_transform * Vector3(local_x, top_y, local_z)

			if _is_blocked(pos):
				continue
			if spawn_radius > 0.0 and pos.distance_squared_to(spawn_center) > spawn_r2:
				continue

			var rotation_y := randf() * TAU
			var tilt_x := randf_range(-0.03, 0.03)
			var tilt_z := randf_range(-0.03, 0.03)
			var scale_var := base_scale + randf_range(-scale_variance, scale_variance)

			var grass_transform := Transform3D()
			grass_transform = grass_transform.scaled(Vector3(scale_var, scale_var, scale_var))
			# Imported grassblade mesh is Z-up (Blender); stand upright in Y-up.
			grass_transform = grass_transform.rotated(Vector3.RIGHT, PI / 2.0)
			grass_transform = grass_transform.rotated(Vector3.RIGHT, tilt_x)
			grass_transform = grass_transform.rotated(Vector3.FORWARD, tilt_z)
			grass_transform = grass_transform.rotated(Vector3.UP, rotation_y)
			# Place the blade's bottom end on the surface, not the mesh origin,
			# then convert the world-space origin into this node's local space.
			grass_transform.origin = global_transform.affine_inverse() * (
				pos - grass_transform.basis * local_bottom_offset
			)

			instances.append(grass_transform)
			yield_counter += 1
			if yield_counter % YIELD_EVERY == 0:
				await get_tree().process_frame

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = instances.size()
	for i in range(instances.size()):
		mm.set_instance_transform(i, instances[i])

	_multimesh = MultiMeshInstance3D.new()
	_multimesh.name = "GrassMultiMesh"
	add_child(_multimesh, true)
	_multimesh.multimesh = mm
	if material != null:
		_multimesh.material_override = material

	_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_multimesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	print("GrassScatterer: Generated %d grass instances" % instances.size())
	for j in range(min(instances.size(), 3)):
		print("[GrassScatterer] instance %d pos=%s" % [j, str(instances[j].origin)])
	print(
		"[GrassScatterer] multimesh visible=%s material_override=%s"
		% [_multimesh.visible, _multimesh.material_override]
	)


func _get_grass_mesh() -> Mesh:
	if grass_mesh != null:
		return grass_mesh
	var scene_source := grass_mesh_scene
	if scene_source != null:
		var scene := scene_source.instantiate()
		var found: Mesh = _extract_first_mesh(scene)
		scene.queue_free()
		return found
	# Fallback: load the converted grassblade mesh resource.
	var saved_mesh := load("res://assets/models/environment/Grass/grassblade.res") as Mesh
	if saved_mesh != null:
		return saved_mesh
	# Last resort: a simple low-poly blade.
	return _create_default_blade_mesh()


func _create_default_blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A simple blade: bottom-left, bottom-right, tip.
	# Width 0.1, height 1.0, centered on X/Z, origin at bottom.
	var p0 := Vector3(-0.05, 0.0, 0.0)
	var p1 := Vector3(0.05, 0.0, 0.0)
	var p2 := Vector3(0.0, 1.0, 0.0)
	var normal := ((p1 - p0).cross(p2 - p0)).normalized()
	st.set_normal(normal)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(p0)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(p1)
	st.set_uv(Vector2(0.5, 1.0))
	st.add_vertex(p2)
	st.index()
	return st.commit()


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
		# Treat each blocker as an infinite vertical column using its X/Z
		# footprint. This catches houses whose imported AABB doesn't reach
		# all the way down to the ground plane.
		var min_x := aabb.position.x - blocker_margin
		var max_x := aabb.position.x + aabb.size.x + blocker_margin
		var min_z := aabb.position.z - blocker_margin
		var max_z := aabb.position.z + aabb.size.z + blocker_margin
		if (
			local_pos.x >= min_x and local_pos.x <= max_x
			and local_pos.z >= min_z and local_pos.z <= max_z
		):
			return true
	return false

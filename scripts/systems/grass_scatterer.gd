class_name GrassScatterer
extends Node3D
## Procedurally scatters grass instances across grass patch surfaces.
## Culls blades that sit under blocker geometry (roads, sidewalks, houses).
## Streams chunks in a radius around the player so only nearby grass exists.

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
## If true, grass is generated in chunks around the player instead of a fixed
## radius around spawn_center.
@export var follow_player := false
## World-space size of each grass chunk.
@export var chunk_size: float = 20.0
## Radius in chunks around the player to keep alive (0 = only the player's
## chunk, 1 = 3x3, 2 = 5x5, ...).
@export var chunk_radius: int = 3
## Maximum instances allowed inside a single chunk.
@export var max_instances_per_chunk: int = 8000

var _multimesh: MultiMeshInstance3D
var _blockers: Array[Dictionary] = []
var _surfaces: Array[Node] = []
var _blocked_cells: Dictionary = { }
var _blocker_cell_size := 0.5
var _mesh: Mesh
var _material: Material
var _local_bottom_offset := Vector3.ZERO
var _active_chunks: Dictionary = { } # Vector2i -> MultiMeshInstance3D
var _player: Node3D
var _initialized := false


func _ready() -> void:
	if random_seed != 0:
		seed(random_seed)
	# Wait one frame so all transforms are committed before sampling AABBs.
	await get_tree().process_frame
	_mesh = _get_grass_mesh()
	if _mesh == null:
		push_error("GrassScatterer: No grass mesh assigned!")
		return
	var mesh_aabb: AABB = _mesh.get_aabb()
	print("[GrassScatterer] mesh=%s aabb=%s" % [_mesh.resource_name, str(mesh_aabb)])
	# With +90° X rotation local +Z becomes world -Y. The blade's bottom end in
	# world Y is at local z = aabb_end_z, so offset the origin onto the surface.
	_local_bottom_offset = Vector3(0.0, 0.0, mesh_aabb.position.z + mesh_aabb.size.z)

	_surfaces = _get_grass_surfaces()
	if _surfaces.is_empty():
		push_error("GrassScatterer: No grass surfaces found!")
		return
	print("[GrassScatterer] surfaces=%d" % _surfaces.size())
	for s in _surfaces:
		print("[GrassScatterer] surface=%s transform=%s" % [s.name, str(s.global_transform)])

	_build_blockers()
	_material = _get_grass_material()
	_initialized = true


func _process(_delta: float) -> void:
	if not _initialized:
		return
	if _player == null:
		_player = _find_player()
		if _player == null:
			return
	_update_chunks()


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as Node3D
	return get_tree().root.find_child("Player", true, false) as Node3D


func _update_chunks() -> void:
	var player_pos := _player.global_position
	var center_chunk := Vector2i(
		int(floor(player_pos.x / chunk_size)),
		int(floor(player_pos.z / chunk_size)),
	)
	var needed := { }
	for dx in range(-chunk_radius, chunk_radius + 1):
		for dz in range(-chunk_radius, chunk_radius + 1):
			needed[Vector2i(center_chunk.x + dx, center_chunk.y + dz)] = true
	var to_remove: Array[Vector2i] = []
	for key in _active_chunks.keys():
		if not needed.has(key):
			to_remove.append(key)
	for key in to_remove:
		var mi: MultiMeshInstance3D = _active_chunks[key]
		if is_instance_valid(mi):
			mi.queue_free()
		_active_chunks.erase(key)
	for key in needed.keys():
		if not _active_chunks.has(key):
			var chunk := _generate_chunk(key)
			if chunk != null:
				_active_chunks[key] = chunk


func _generate_chunk(chunk_coord: Vector2i) -> MultiMeshInstance3D:
	var chunk_origin := Vector3(chunk_coord.x * chunk_size, 0.0, chunk_coord.y * chunk_size)
	var chunk_aabb := AABB(chunk_origin, Vector3(chunk_size, 0.0, chunk_size))
	var instances: Array[Transform3D] = []

	for surface in _surfaces:
		if not surface is GeometryInstance3D:
			continue
		var geom := surface as GeometryInstance3D
		var aabb: AABB = geom.get_aabb()
		if aabb.size.length_squared() <= 0.0:
			continue
		var chunk_local := geom.global_transform.affine_inverse() * chunk_aabb
		var local_min_x := maxf(aabb.position.x, chunk_local.position.x)
		var local_max_x := minf(
			aabb.position.x + aabb.size.x,
			chunk_local.position.x + chunk_local.size.x,
		)
		var local_min_z := maxf(aabb.position.z, chunk_local.position.z)
		var local_max_z := minf(
			aabb.position.z + aabb.size.z,
			chunk_local.position.z + chunk_local.size.z,
		)
		if local_max_x <= local_min_x or local_max_z <= local_min_z:
			continue
		var sample_area := (local_max_x - local_min_x) * (local_max_z - local_min_z)
		var raw_count := int(sample_area * grass_density)
		var target := clampi(raw_count, 0, max_instances_per_chunk)
		var top_y := aabb.position.y + aabb.size.y
		for i in range(target):
			var local_x := randf_range(local_min_x, local_max_x)
			var local_z := randf_range(local_min_z, local_max_z)
			var pos := geom.global_transform * Vector3(local_x, top_y, local_z)
			if _is_blocked(pos):
				continue
			instances.append(_make_blade_transform(pos))
			if instances.size() >= max_instances_per_chunk:
				break

	if instances.is_empty():
		return null

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh
	mm.instance_count = instances.size()
	for i in range(instances.size()):
		mm.set_instance_transform(i, instances[i])

	var mi := MultiMeshInstance3D.new()
	mi.name = "GrassChunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	mi.multimesh = mm
	if _material != null:
		mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi, true)
	return mi


func _make_blade_transform(pos: Vector3) -> Transform3D:
	var rotation_y := randf() * TAU
	var tilt_x := randf_range(-0.03, 0.03)
	var tilt_z := randf_range(-0.03, 0.03)
	var scale_var := base_scale + randf_range(-scale_variance, scale_variance)

	var grass_transform := Transform3D()
	grass_transform = grass_transform.scaled(Vector3(scale_var, scale_var, scale_var))
	grass_transform = grass_transform.rotated(Vector3.RIGHT, PI / 2.0)
	grass_transform = grass_transform.rotated(Vector3.RIGHT, tilt_x)
	grass_transform = grass_transform.rotated(Vector3.FORWARD, tilt_z)
	grass_transform = grass_transform.rotated(Vector3.UP, rotation_y)
	var bottom_end_world := pos - grass_transform.basis * _local_bottom_offset
	grass_transform.origin = global_transform.affine_inverse() * bottom_end_world
	return grass_transform


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
	_blocked_cells.clear()
	if blocker_group.is_empty():
		return
	for node in get_tree().get_nodes_in_group(blocker_group):
		if not surface_group.is_empty() and node.is_in_group(surface_group):
			continue
		_collect_blockers(node)
	if _blockers.size() > 0:
		print("[GrassScatterer] blockers=%d" % _blockers.size())
		_rasterize_blockers()
		print("[GrassScatterer] blocked cells=%d" % _blocked_cells.size())


func _collect_blockers(node: Node) -> void:
	if not surface_group.is_empty() and node.is_in_group(surface_group):
		return
	if node == _multimesh:
		return
	if node is Node3D and not (node as Node3D).visible:
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var footprint := _compute_mesh_footprint(mi.mesh)
		if footprint.size.length_squared() > 0.0:
			_blockers.append({ "transform": mi.global_transform, "aabb": footprint, "node": mi })
		return
	for child in node.get_children():
		_collect_blockers(child)


func _compute_mesh_footprint(mesh: Mesh) -> AABB:
	if mesh == null:
		return AABB()
	var min_y := 0.0
	var first_y := true
	var surface_count := mesh.get_surface_count()
	for s in range(surface_count):
		var arr := mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		for v in verts:
			if first_y:
				min_y = v.y
				first_y = false
			else:
				min_y = minf(min_y, v.y)
	if first_y:
		return AABB()

	var height_limit := 0.5
	var first := true
	var min_x := 0.0
	var max_x := 0.0
	var min_z := 0.0
	var max_z := 0.0
	for s in range(surface_count):
		var arr := mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		for v in verts:
			if v.y > min_y + height_limit:
				continue
			if first:
				min_x = v.x
				max_x = v.x
				min_z = v.z
				max_z = v.z
				first = false
			else:
				min_x = minf(min_x, v.x)
				max_x = maxf(max_x, v.x)
				min_z = minf(min_z, v.z)
				max_z = maxf(max_z, v.z)
	if first:
		return AABB()
	return AABB(Vector3(min_x, 0.0, min_z), Vector3(max_x - min_x, 1.0, max_z - min_z))


func _is_blocked(pos: Vector3) -> bool:
	if _blocked_cells.is_empty():
		return false
	var cell := Vector2i(
		int(floor(pos.x / _blocker_cell_size)),
		int(floor(pos.z / _blocker_cell_size)),
	)
	return _blocked_cells.has(cell)


func _rasterize_blockers() -> void:
	var y_limit := 1.0
	for blocker in _blockers:
		var mi: MeshInstance3D = blocker.get("node")
		if mi == null:
			continue
		var trans: Transform3D = blocker["transform"]
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var mesh_min_y := 0.0
		var first := true
		for s in range(mesh.get_surface_count()):
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts:
				var wv := trans * v
				if first:
					mesh_min_y = wv.y
					first = false
				else:
					mesh_min_y = minf(mesh_min_y, wv.y)
		if first:
			continue
		var ground_limit := mesh_min_y + y_limit
		for s in range(mesh.get_surface_count()):
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var tri_count := verts.size() / 3 if indices.is_empty() else indices.size() / 3
			for t in range(tri_count):
				var i0 := t * 3
				var v0 := verts[i0] if indices.is_empty() else verts[indices[i0]]
				var v1 := verts[i0 + 1] if indices.is_empty() else verts[indices[i0 + 1]]
				var v2 := verts[i0 + 2] if indices.is_empty() else verts[indices[i0 + 2]]
				var w0 := trans * v0
				var w1 := trans * v1
				var w2 := trans * v2
				if minf(w0.y, minf(w1.y, w2.y)) > ground_limit:
					continue
				var min_x := minf(w0.x, minf(w1.x, w2.x)) - blocker_margin
				var max_x := maxf(w0.x, maxf(w1.x, w2.x)) + blocker_margin
				var min_z := minf(w0.z, minf(w1.z, w2.z)) - blocker_margin
				var max_z := maxf(w0.z, maxf(w1.z, w2.z)) + blocker_margin
				var cx0 := int(floor(min_x / _blocker_cell_size))
				var cx1 := int(floor(max_x / _blocker_cell_size))
				var cz0 := int(floor(min_z / _blocker_cell_size))
				var cz1 := int(floor(max_z / _blocker_cell_size))
				for cx in range(cx0, cx1 + 1):
					for cz in range(cz0, cz1 + 1):
						var cell_center := Vector2(
							(float(cx) + 0.5) * _blocker_cell_size,
							(float(cz) + 0.5) * _blocker_cell_size,
						)
						if _point_in_triangle_2d(
							cell_center,
							Vector2(w0.x, w0.z),
							Vector2(w1.x, w1.z),
							Vector2(w2.x, w2.z),
						):
							_blocked_cells[Vector2i(cx, cz)] = true


func _point_in_triangle_2d(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d2 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var d3 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var has_neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_neg and has_pos)

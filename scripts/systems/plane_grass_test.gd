extends MultiMeshInstance3D

@export var blade_mesh: Mesh = preload("res://assets/models/environment/Grass/grass.res")
@export var blade_material: Material = preload("res://assets/materials/grass_blade.tres")
@export var blade_count: int = 25600
@export var plane_size: Vector2 = Vector2(10, 10)
@export var base_scale: float = 0.0792
@export var plane_node_path: NodePath = "../Plane"
@export var grass_bottom_color: Color = Color(0.05, 0.3, 0.05)
@export var grass_top_color: Color = Color(0.45, 0.9, 0.25)


func _ready() -> void:
	if blade_mesh == null:
		push_error("PlaneGrassTest: no blade mesh")
		return

	var plane := get_node_or_null(plane_node_path) as Node3D
	var plane_origin := global_position if plane == null else plane.global_position
	var plane_basis := global_basis if plane == null else plane.global_basis
	var blade_aabb: AABB = blade_mesh.get_aabb()
	# grass.res is already Y-up; its bottom is at y = aabb.position.y.
	var local_bottom_offset := Vector3(0.0, blade_aabb.position.y, 0.0)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade_mesh
	mm.instance_count = blade_count

	for i in range(blade_count):
		var local_pos := Vector3(
			randf_range(-plane_size.x / 2.0, plane_size.x / 2.0),
			0.0,
			randf_range(-plane_size.y / 2.0, plane_size.y / 2.0),
		)
		var rotation_y := randf() * TAU
		var scale_var := base_scale + randf_range(-0.02, 0.02)

		var target_world := plane_origin + plane_basis * local_pos
		var t := Transform3D()
		t = t.scaled(Vector3(scale_var, scale_var, scale_var))
		t = t.rotated(Vector3.UP, rotation_y)
		# Place the blade's bottom on the plane, not the mesh origin.
		var bottom_end_world := target_world - t.basis * local_bottom_offset
		t.origin = global_transform.affine_inverse() * bottom_end_world
		mm.set_instance_transform(i, t)

	multimesh = mm
	material_override = blade_material
	if blade_material is ShaderMaterial:
		(blade_material as ShaderMaterial).set_shader_parameter("bottom_color", grass_bottom_color)
		(blade_material as ShaderMaterial).set_shader_parameter("top_color", grass_top_color)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("PlaneGrassTest: spawned %d blades on %s" % [blade_count, name])

extends MultiMeshInstance3D
## Scatters grass blades across the grass_surface CSGBox3D inside a radius.

@export var blade_mesh: Mesh = preload("res://assets/models/environment/Grass/grass.res")
@export var blade_material: Material = preload("res://assets/materials/grass_blade.tres")
@export var blade_count: int = 25600
@export var spawn_center: Vector3 = Vector3.ZERO
@export var spawn_radius: float = 60.0
@export var base_scale: float = 0.2
@export var grass_bottom_color: Color = Color(0.05, 0.3, 0.05)
@export var grass_top_color: Color = Color(0.45, 0.9, 0.25)
@export var surface_group: StringName = &"grass_surface"


func _ready() -> void:
	if blade_mesh == null:
		push_error("PlaneGrassTest: no blade mesh")
		return

	var surface := _find_grass_surface()
	if surface == null:
		push_error("PlaneGrassTest: no grass surface found")
		return
	var geom := surface as GeometryInstance3D
	var aabb: AABB = geom.get_aabb()
	var top_y := aabb.position.y + aabb.size.y
	var blade_aabb: AABB = blade_mesh.get_aabb()
	var local_bottom_offset := Vector3(0.0, blade_aabb.position.y, 0.0)

	var instances: Array[Transform3D] = []
	var spawn_r2 := spawn_radius * spawn_radius
	for i in range(blade_count):
		var local_x := randf_range(aabb.position.x, aabb.position.x + aabb.size.x)
		var local_z := randf_range(aabb.position.z, aabb.position.z + aabb.size.z)
		var pos := geom.global_transform * Vector3(local_x, top_y, local_z)
		if spawn_radius > 0.0 and pos.distance_squared_to(spawn_center) > spawn_r2:
			continue
		var rotation_y := randf() * TAU
		var scale_var := base_scale + randf_range(-0.05, 0.05)

		var t := Transform3D()
		t = t.scaled(Vector3(scale_var, scale_var, scale_var))
		t = t.rotated(Vector3.UP, rotation_y)
		var bottom_end_world := pos - t.basis * local_bottom_offset
		t.origin = global_transform.affine_inverse() * bottom_end_world
		instances.append(t)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade_mesh
	mm.instance_count = instances.size()
	for i in range(instances.size()):
		mm.set_instance_transform(i, instances[i])
	multimesh = mm
	material_override = blade_material
	if blade_material is ShaderMaterial:
		(blade_material as ShaderMaterial).set_shader_parameter("bottom_color", grass_bottom_color)
		(blade_material as ShaderMaterial).set_shader_parameter("top_color", grass_top_color)
		(blade_material as ShaderMaterial).set_shader_parameter("player_pos", spawn_center)
		(blade_material as ShaderMaterial).set_shader_parameter("fade_radius", spawn_radius)
		(blade_material as ShaderMaterial).set_shader_parameter("fade_width", spawn_radius * 0.2)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("PlaneGrassTest: spawned %d blades on %s" % [blade_count, name])


func _find_grass_surface() -> Node:
	var nodes := get_tree().get_nodes_in_group(surface_group)
	if not nodes.is_empty():
		return nodes[0]
	return get_parent().get_node_or_null("../CSGBox3D")

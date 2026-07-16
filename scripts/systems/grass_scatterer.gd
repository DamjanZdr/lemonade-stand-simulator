class_name GrassScatterer
extends Node3D
## Procedurally scatters grass instances across grass patch surfaces.

@export var grass_mesh: ArrayMesh
@export var grass_material: Material
@export var grass_density: float = 20.0 # Blades per square unit on each patch
@export var random_seed: int = 0
@export var base_scale: float = 0.1
@export var scale_variance: float = 0.05

var _multimesh: MultiMeshInstance3D


func _ready() -> void:
	if random_seed != 0:
		seed(random_seed)
	_generate_grass()


func _generate_grass() -> void:
	if grass_mesh == null:
		push_error("GrassScatterer: No grass mesh assigned!")
		return

	_multimesh = MultiMeshInstance3D.new()
	_multimesh.multimesh = MultiMesh.new()
	_multimesh.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.multimesh.mesh = grass_mesh
	if grass_material != null:
		_multimesh.material_override = grass_material

	var instances: Array[Transform3D] = []

	# Find all grass patch surfaces (GrassSurfaces is a sibling node)
	var grass_surfaces_node = get_parent().get_node_or_null("GrassSurfaces")
	if grass_surfaces_node == null:
		push_error("GrassScatterer: No GrassSurfaces node found!")
		return

	print(
		"GrassScatterer: Found GrassSurfaces node with ",
		grass_surfaces_node.get_child_count(),
		" children",
	)
	print("GrassScatterer: GrassSurfaces global position: ", grass_surfaces_node.global_position)
	print("GrassScatterer: GrassSurfaces global rotation: ", grass_surfaces_node.global_rotation)
	print("GrassScatterer: GrassSurfaces global scale: ", grass_surfaces_node.global_scale)
	var _patch_count = 0

	for child in grass_surfaces_node.get_children():
		if child is MeshInstance3D:
			_patch_count += 1
			var patch: MeshInstance3D = child
			# Use the patch's global transform (already accounts for parent rotation)
			var patch_origin = patch.global_transform.origin
			var patch_basis = patch.global_transform.basis
			var patch_size = Vector2(5, 5) # Each patch is 5x5 units

			# Calculate instances for this patch
			var patch_instances = int(patch_size.x * patch_size.y * grass_density)
			print(
				"GrassScatterer: Patch ",
				patch.name,
				" at ",
				patch_origin,
				" generating ",
				patch_instances,
				" instances",
			)

			for i in range(patch_instances):
				# Random position within patch bounds
				var local_x = randf_range(-patch_size.x / 2.0, patch_size.x / 2.0)
				var local_z = randf_range(-patch_size.y / 2.0, patch_size.y / 2.0)
				# Apply patch rotation to local offset
				var local_offset = patch_basis * Vector3(local_x, 0, local_z)
				# Use the patch's y position + offset to lift grass above surface
				var pos = Vector3(
					patch_origin.x + local_offset.x,
					patch_origin.y + 0.1,
					patch_origin.z + local_offset.z,
				)

				# Rotation with tilt
				var rotation_y = randf() * TAU
				var tilt_x = randf_range(-0.2, 0.2) # Slight tilt on X
				var tilt_z = randf_range(-0.2, 0.2) # Slight tilt on Z

				# Scale with variance
				var scale_var = base_scale + randf_range(-scale_variance, scale_variance)

				var grass_transform = Transform3D()
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
	print("GrassScatterer: Generated %d grass instances" % instances.size())
	if instances.size() > 0:
		print("GrassScatterer: First instance position: ", instances[0].origin)

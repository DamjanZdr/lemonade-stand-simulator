class_name PlayerMirror
extends Node3D
## Placeable debug mirror. Drag `scenes/props/player_mirror.tscn` into a
## level, position and rotate it, and it will show the local player from a
## third-person angle. Useful for testing head/neck/animation poses without
## needing a second player in multiplayer.

@export var mirror_size: Vector2 = Vector2(1.2, 1.8)
@export var viewport_resolution: Vector2i = Vector2i(256, 320)

var _viewport: SubViewport = null
var _camera: Camera3D = null

@onready var _mesh: MeshInstance3D = $MirrorMesh


func _ready() -> void:
	_setup_viewport()
	_setup_mesh()
	# Viewport textures are not always ready in _ready; assign the material
	# after one frame to make sure the texture exists.
	call_deferred("_assign_viewport_texture")


func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = viewport_resolution
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_camera = Camera3D.new()
	# Render everything except the mirror surface itself.
	_camera.cull_mask = 1
	_viewport.add_child(_camera)


func _setup_mesh() -> void:
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "MirrorMesh"
		add_child(_mesh)

	if _mesh.mesh == null:
		var quad := QuadMesh.new()
		quad.size = mirror_size
		_mesh.mesh = quad

	# QuadMesh faces +Z by default; flip vertically so the viewport texture
	# appears right-side-up.
	_mesh.scale.y = -1.0
	# Put the mirror surface on its own cull layer so the reflection camera
	# can see through it and capture the player behind it.
	_mesh.layers = 2

	var mat := _mesh.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		_mesh.material_override = mat
	mat.roughness = 0.1
	mat.metallic = 0.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Double-sided so it can be seen from either side.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _assign_viewport_texture() -> void:
	if _viewport == null or _mesh == null:
		return
	var mat := _mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_texture = _viewport.get_texture()


func _process(_delta: float) -> void:
	var player := _find_local_player()
	if player == null or _camera == null:
		return
	var player_pos: Vector3 = player.global_position
	# Mirror's +Z points toward the player. Place the reflection camera
	# slightly behind the mirror plane, looking through it at the player.
	var forward: Vector3 = (player_pos - global_position).normalized()
	if forward.length_squared() < 0.001:
		forward = -global_transform.basis.z
	_camera.global_position = global_position - forward * 0.5
	_camera.look_at(player_pos + Vector3(0.0, 1.0, 0.0), Vector3.UP)


func _find_local_player() -> Node3D:
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Player
		if p != null and p.is_multiplayer_authority():
			return p
	return null

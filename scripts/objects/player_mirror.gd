class_name PlayerMirror
extends Node3D
## Placeable debug mirror. Drag `scenes/props/player_mirror.tscn` into a
## level, position and rotate it, and it will show the local player from a
## third-person angle. Useful for testing head/neck/animation poses without
## needing a second player in multiplayer.

@export var mirror_size: Vector2 = Vector2(1.2, 1.8)
@export var viewport_resolution: Vector2i = Vector2i(256, 320)

# Cull layer used only for the local player's visual model so the main
# camera doesn't see it but the mirror reflection camera can.
const PLAYER_VISUAL_LAYER: int = 3

var _viewport: SubViewport = null
var _camera: Camera3D = null

@onready var _mesh: MeshInstance3D = $MirrorMesh


func _ready() -> void:
	_setup_viewport()
	_setup_mesh()
	# Viewport textures are not always ready in _ready; assign the material
	# after one frame to make sure the texture exists.
	call_deferred("_assign_viewport_texture")
	_configure_local_player_visual()


func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = viewport_resolution
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_camera = Camera3D.new()
	# Render world (layer 1) and the local player visual clone (layer 3),
	# but not the mirror surface itself (layer 2).
	_camera.cull_mask = 1 | (1 << (PLAYER_VISUAL_LAYER - 1))
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


func _configure_local_player_visual() -> void:
	var player := _find_local_player()
	if player == null or player.visuals == null:
		return
	# The local player's visual model is normally hidden in first-person.
	# Make it visible but move it to a separate cull layer so the main
	# camera still doesn't see it while the mirror camera can.
	player.visuals.visible = true
	_set_visual_layers_recursive(player.visuals, PLAYER_VISUAL_LAYER)
	if player.camera != null:
		player.camera.cull_mask &= ~(1 << (PLAYER_VISUAL_LAYER - 1))


func _set_visual_layers_recursive(node: Node, layer: int) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null:
		mesh.layers = 1 << (layer - 1)
	for child in node.get_children():
		_set_visual_layers_recursive(child, layer)


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

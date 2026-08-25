class_name PlayerMirror
extends Node3D
## Simple debug mirror showing the local player from a third-person angle.
## Useful for checking head/neck/animation poses without needing a second
## player in multiplayer.

@export var mirror_size: Vector2 = Vector2(1.2, 1.8)
@export var viewport_resolution: Vector2i = Vector2i(256, 320)

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _mesh: MeshInstance3D = null


func _ready() -> void:
	_setup_viewport()
	_setup_mesh()


func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = viewport_resolution
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.cull_mask = 1
	_viewport.add_child(_camera)


func _setup_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = mirror_size
	_mesh.mesh = plane
	# PlaneMesh is horizontal by default; rotate it vertical and flip it
	# so the viewport texture appears right-side-up.
	_mesh.rotation = Vector3(-PI / 2.0, 0.0, PI)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.roughness = 0.1
	mat.metallic = 0.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material_override = mat
	add_child(_mesh)


func _process(_delta: float) -> void:
	var player := _find_local_player()
	if player == null or _camera == null:
		return
	var player_pos: Vector3 = player.global_position
	# Face the mesh toward the player.
	look_at(player_pos + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	# Place the camera behind and above the player, looking at them.
	_camera.global_position = player_pos + Vector3(0.0, 1.6, 2.2)
	_camera.look_at(player_pos + Vector3(0.0, 1.0, 0.0), Vector3.UP)


func _find_local_player() -> Node3D:
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Player
		if p != null and p.is_multiplayer_authority():
			return p
	return null

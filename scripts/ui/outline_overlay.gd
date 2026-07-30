extends Node
## Screen-space silhouette outline system.
##
## Architecture:
##   1. Highlighted interactables get "_Outline" child MeshInstance3D nodes
##      placed on render layer 2 with a flat white unshaded material.
##   2. The SubViewport's OutlineCamera (cull_mask=2) renders ONLY those fills
##      against a transparent background → solid white silhouette texture.
##   3. A canvas edge-detect shader on DisplayRect reads that texture and
##      draws only the border pixels as yellow.
##
## The main Camera3D has bit 2 excluded from its cull_mask, so the fill
## nodes are completely invisible in the main view.

@onready var _subvp: SubViewport = $SubViewport
@onready var _cam: Camera3D = $SubViewport/OutlineCamera
@onready var _display: TextureRect = $OverlayLayer/DisplayRect

var _main_cam: Camera3D = null
var _target_width: float = 2.5


func _get_base_viewport_size() -> Vector2i:
	return Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
	)


func _ready() -> void:
	# Render the outline mask at the project base size so it stretches with the
	# 3D viewport instead of being treated as an independent UI element.
	_subvp.size = _get_base_viewport_size()
	_subvp.world_3d = get_viewport().world_3d
	_subvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_viewport().size_changed.connect(_update_shader_width)

	# Make sure the outline camera is the active camera in the SubViewport.
	if _cam != null:
		_cam.current = true

	# The edge-detect material uses the SubViewport texture as a shader
	# parameter. Assign it in code as well so it survives project reloads.
	if _display != null and _display.material != null:
		_display.texture = _subvp.get_texture()
		(_display.material as ShaderMaterial).set_shader_parameter(
			"outline_texture",
			_subvp.get_texture(),
		)

	# Dev panel live controls.
	EventBus.debug_set_outline_width.connect(_on_set_width)
	EventBus.debug_set_outline_color.connect(_on_set_color)

	# Sync outline camera right before every render to avoid one-frame lag.
	RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)

	_update_shader_width()


func _on_set_width(width: float) -> void:
	_target_width = width
	_update_shader_width()


func _update_shader_width() -> void:
	if _display == null or _display.material == null:
		return
	var base_size := Vector2(_get_base_viewport_size())
	var win_size := Vector2(get_window().size)
	var scale_factor: float = (
		0.5 * (win_size.x / max(1.0, base_size.x) + win_size.y / max(1.0, base_size.y))
	)
	(_display.material as ShaderMaterial).set_shader_parameter(
		"outline_width",
		_target_width / scale_factor,
	)


func _on_set_color(color: Color) -> void:
	(_display.material as ShaderMaterial).set_shader_parameter("outline_color", color)


func setup(main_cam: Camera3D) -> void:
	_main_cam = main_cam


func _process(_delta: float) -> void:
	if _main_cam == null or _cam == null:
		return
	# Sync early so the SubViewport renders with a camera position close to
	# what the main viewport will use, reducing the one-frame texture lag.
	_sync_outline_camera()


func _on_frame_pre_draw() -> void:
	if _display == null or get_tree() == null or _main_cam == null:
		return
	# Only show the outline overlay when at least one object is highlighted.
	var active := get_tree().get_first_node_in_group("outline_fill") != null
	_display.visible = active
	_subvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Final sync right before rendering as a last-chance correction.
	_sync_outline_camera()


func _sync_outline_camera() -> void:
	if _main_cam == null or _cam == null:
		return
	_cam.global_transform = _main_cam.global_transform
	_cam.fov = _main_cam.fov
	_cam.near = _main_cam.near
	_cam.far = _main_cam.far

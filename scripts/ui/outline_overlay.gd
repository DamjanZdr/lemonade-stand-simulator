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


func _get_actual_viewport_size() -> Vector2i:
	# Use the main camera's viewport if available — that's the actual
	# game viewport the player sees. This is more reliable than
	# get_viewport() which might return a different viewport in some
	# contexts (e.g. editor SubViewports).
	if _main_cam != null and is_instance_valid(_main_cam):
		var vp := _main_cam.get_viewport()
		if vp:
			return vp.size
	var vp := get_viewport()
	if vp:
		return vp.size
	return _get_base_viewport_size()


func _ready() -> void:
	# Render the outline mask at the actual viewport size so it matches
	# the main view exactly. Using the project base size causes offsets
	# when the window is a different size (e.g. running outside editor).
	_subvp.size = _get_actual_viewport_size()
	_subvp.world_3d = get_viewport().world_3d
	_subvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_viewport().size_changed.connect(_on_viewport_size_changed)

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


func _on_viewport_size_changed() -> void:
	# Update SubViewport size to match the actual viewport
	_subvp.size = _get_actual_viewport_size()
	_update_shader_width()


func _update_shader_width() -> void:
	if _display == null or _display.material == null:
		return
	# Scale outline width based on the ratio of actual viewport size to
	# the project base size. This keeps the outline width consistent
	# regardless of resolution.
	var vp_size := Vector2(_get_actual_viewport_size())
	var base_size := Vector2(_get_base_viewport_size())
	var scale_factor: float = (
		0.5 * (vp_size.x / max(1.0, base_size.x) + vp_size.y / max(1.0, base_size.y))
	)
	(_display.material as ShaderMaterial).set_shader_parameter(
		"outline_width",
		_target_width / max(0.01, scale_factor),
	)


func _on_set_color(color: Color) -> void:
	(_display.material as ShaderMaterial).set_shader_parameter("outline_color", color)


func setup(main_cam: Camera3D) -> void:
	_main_cam = main_cam


func _process(_delta: float) -> void:
	if _main_cam == null or _cam == null:
		return
	# Update SubViewport size to match the actual viewport every frame.
	# This catches size changes from window resize, editor startup,
	# fullscreen toggles, etc. that the size_changed signal might miss.
	var vp_size := _get_actual_viewport_size()
	if _subvp.size != vp_size:
		_subvp.size = vp_size
		_update_shader_width()
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
	# Update SubViewport size right before rendering so the outline
	# camera's projection matches the main camera's projection exactly.
	var vp_size := _get_actual_viewport_size()
	if _subvp.size != vp_size:
		_subvp.size = vp_size
		_update_shader_width()
	# Final sync right before rendering as a last-chance correction.
	_sync_outline_camera()


func _sync_outline_camera() -> void:
	if _main_cam == null or _cam == null:
		return
	_cam.global_transform = _main_cam.global_transform
	_cam.fov = _main_cam.fov
	_cam.near = _main_cam.near
	_cam.far = _main_cam.far
	_cam.keep_aspect = _main_cam.keep_aspect
	_cam.projection = _main_cam.projection
	_cam.size = _main_cam.size # for orthographic projection
	_cam.h_offset = _main_cam.h_offset
	_cam.v_offset = _main_cam.v_offset

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
var _target_width: float = 1.5


func _get_base_viewport_size() -> Vector2i:
	return Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
	)


func _get_actual_viewport_size() -> Vector2i:
	# Use the main viewport's actual rendering rect, not the window size.
	# With canvas_items stretch mode, the viewport size can differ from
	# the window size, causing the outline silhouette to be scaled wrong.
	var vp := get_viewport()
	if vp != null:
		var rect := vp.get_visible_rect()
		if rect.size.x > 0 and rect.size.y > 0:
			return rect.size
	var win := get_window()
	if win != null:
		var sz := win.get_size()
		if sz.x > 0 and sz.y > 0:
			return sz
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
	# Use a fixed outline width in pixels — don't scale with resolution.
	# The shader divides this by the texture size to get UV-space step,
	# so a constant pixel width looks the same on any screen size.
	(_display.material as ShaderMaterial).set_shader_parameter("outline_width", _target_width)


func _on_set_color(color: Color) -> void:
	(_display.material as ShaderMaterial).set_shader_parameter("outline_color", color)


func setup(main_cam: Camera3D) -> void:
	_main_cam = main_cam
	# Sync immediately so the outline camera matches the main camera
	# from the very first frame — otherwise the default FOV (75) makes
	# objects appear larger than they are in the main view (FOV 90).
	_sync_outline_camera()
	# Also update the SubViewport size now that we have the main camera
	var vp_size := _get_actual_viewport_size()
	if _subvp.size != vp_size:
		_subvp.size = vp_size
		_update_shader_width()


func _process(_delta: float) -> void:
	if _main_cam == null or not is_instance_valid(_main_cam) or _cam == null:
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
	if _display == null or get_tree() == null or _main_cam == null \
			or not is_instance_valid(_main_cam):
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
	if _main_cam == null or not is_instance_valid(_main_cam) or _cam == null:
		return
	if not is_inside_tree() or not _cam.is_inside_tree() or not _main_cam.is_inside_tree():
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
	# Debug: log sizes once per second to diagnose outline scale mismatch
	if false and Engine.get_process_frames() % 60 == 0:
		var win := get_window()
		var win_size := win.size if win != null else Vector2i.ZERO
		var main_vp_size := _main_cam.get_viewport().get_visible_rect().size
		GameLog.log(
			"[Outline] subvp=%s win=%s main_vp=%s base=%s fov=%.1f aspect=%.3f"
			% [
				_subvp.size,
				win_size,
				main_vp_size,
				_get_base_viewport_size(),
				_cam.fov,
				float(_subvp.size.x) / float(_subvp.size.y),
			]
		)

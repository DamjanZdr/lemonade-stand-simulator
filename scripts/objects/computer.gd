class_name Computer
extends Interactable

@onready var _screen_ui: SubViewport = $ScreenUI
@onready var _screen_camera: Camera3D = $ScreenCamera
@onready var _screen_mesh: MeshInstance3D = $ScreenMesh
@onready var _ui_root: CanvasLayer = $ScreenUI/MorningHub
@onready var _screen_camera_target: Transform3D = _screen_camera.global_transform
@onready var _screen_camera_fov: float = _screen_camera.fov

var _active: bool = false
var _transitioning: bool = false
var _player: Node = null
var _player_camera: Camera3D = null
var _zoom_tween: Tween = null


func _ready() -> void:
	if _ui_root == null:
		push_warning("Computer: MorningHub not found in ScreenUI.")
		return

	# Make sure the off-screen SubViewport clears to dark so the screen can
	# never show white/placeholder pixels, even if the UI background fails.
	RenderingServer.set_default_clear_color(Color(0.02, 0.022, 0.028, 1.0))

	# Layer 2 is used by the screen-space outline system for white fill nodes
	# (see Interactable._apply_outline). The main player camera excludes this
	# layer, but ScreenCamera didn't, so leftover outline fills (left behind
	# because player input/processing is disabled while the hub is open,
	# preventing set_highlight(false) from ever firing) rendered as solid
	# white over the computer model once ScreenCamera became active.
	_screen_camera.cull_mask &= ~2

	# Render one frame so the ViewportTexture is allocated before we bind it.
	_screen_ui.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Smooths jagged panel/text edges in the off-screen UI; without this the
	# screen looks noticeably worse than plain on-screen UI since it's being
	# resampled onto a 3D quad at a different pixel density.
	_screen_ui.msaa_2d = Viewport.MSAA_4X
	_setup_screen_material.call_deferred()


func _setup_screen_material() -> void:
	# Give the SubViewport a chance to allocate its render target.
	await get_tree().process_frame

	var vp_tex := _screen_ui.get_texture()

	# StandardMaterial3D + ViewportTexture is fragile in Godot 4; use a tiny
	# shader so the texture is sampled every frame and always stays valid.
	var shader := Shader.new()
	shader.code = (
		"shader_type spatial;\n"
		+ "render_mode unshaded, cull_disabled;\n"
		# filter_linear_mipmap (instead of plain filter_linear) lets the
		# renderer use mipmaps when the UI is minified onto the quad,
		# avoiding shimmering/aliasing on small text.
		+ "uniform sampler2D screen_texture : filter_linear_mipmap;\n"
		+ "void fragment() {\n"
		+ "\tvec4 col = texture(screen_texture, UV);\n"
		# The SubViewport's 2D content is already gamma-encoded (sRGB)
		# final pixel color. Godot's 3D pipeline treats ALBEDO as linear
		# and applies a linear->sRGB conversion on output, so writing
		# the sRGB value directly double-encodes it, washing everything
		# out. Converting back to linear here cancels that out.
		+ "\tALBEDO = pow(col.rgb, vec3(2.2));\n"
		+ "\tALPHA = 1.0;\n"
		+ "}\n"
	)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("screen_texture", vp_tex)
	_screen_mesh.set_surface_override_material(0, mat)


func interact(player: Node) -> void:
	if _transitioning:
		return
	if _active:
		_exit()
	else:
		_enter(player)


func get_hint(_hint_player: Node) -> String:
	if _transitioning:
		return ""
	return "Computer | E: close" if _active else "Computer | LMB: use"


func _enter(player: Node) -> void:
	_player = player
	_player_camera = _find_player_camera(player)
	if _player_camera == null:
		push_warning("Computer: could not find player camera.")
		_player = null
		return

	# Remove the hover outline; player processing is about to stop, so it
	# won't get a chance to call set_highlight(false) itself.
	set_highlight(false)

	_player.set_process(false)
	_player.set_physics_process(false)
	_player.set_process_input(false)
	_player.set_process_unhandled_input(false)

	_player_camera.current = false
	_screen_camera.current = true
	_screen_camera.global_transform = _player_camera.global_transform
	_screen_camera.fov = _player_camera.fov

	_screen_ui.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_transitioning = true
	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_QUAD)
	_zoom_tween.set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_property(_screen_camera, "global_transform", _screen_camera_target, 0.5)
	_zoom_tween.parallel().tween_property(_screen_camera, "fov", _screen_camera_fov, 0.5)
	_zoom_tween.tween_callback(_on_zoom_finished)


func _on_zoom_finished() -> void:
	_transitioning = false
	_active = true
	if _ui_root.has_method("_show_morning_hub"):
		_ui_root._show_morning_hub()
	if _player != null and is_instance_valid(_player):
		EventBus.interaction_hint_changed.emit(get_hint(_player))


func _exit() -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
		_zoom_tween = null

	_transitioning = false
	_active = false

	if _ui_root != null and _ui_root.has_method("_hide_morning_hub"):
		_ui_root._hide_morning_hub()
	# Keep rendering always so the texture doesn't fall back to a white placeholder
	# while the computer is off-screen.
	_screen_ui.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	if _player_camera != null and is_instance_valid(_player_camera):
		_screen_camera.current = false
		_player_camera.current = true
		_player_camera = null

	if _player != null and is_instance_valid(_player):
		_player.set_process(true)
		_player.set_physics_process(true)
		_player.set_process_input(true)
		_player.set_process_unhandled_input(true)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if _player != null and is_instance_valid(_player):
		EventBus.interaction_hint_changed.emit(get_hint(_player))
		_player = null


func _process(_delta: float) -> void:
	if _active and _ui_root != null and not _ui_root.panel.visible:
		_exit()


func _input(event: InputEvent) -> void:
	if not _active and not _transitioning:
		return

	var exit_action := (
		event.is_action_pressed("ui_cancel")
		or event.is_action_pressed("secondary_interact") or _is_right_click(event)
	)
	if exit_action:
		_exit()
		get_viewport().set_input_as_handled()
		return

	if not _active:
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_forward_mouse_event(event)
		get_viewport().set_input_as_handled()


func _forward_mouse_event(event: InputEvent) -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _screen_camera.project_ray_origin(mouse_pos)
	var ray_dir := _screen_camera.project_ray_normal(mouse_pos)

	var screen_pos := _screen_mesh.global_position
	var screen_normal := _screen_mesh.global_transform.basis.z
	var plane := Plane(screen_normal, screen_pos)
	var hit: Variant = plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return

	var hit_pos: Vector3 = hit as Vector3
	var local := _screen_mesh.to_local(hit_pos)
	var quad_mesh := _screen_mesh.mesh as QuadMesh
	if quad_mesh == null:
		return
	var size := quad_mesh.size

	var uv := Vector2((local.x / size.x) + 0.5, -(local.y / size.y) + 0.5)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return

	var viewport_event: InputEvent = event.duplicate() as InputEvent
	var viewport_pos := uv * Vector2(_screen_ui.size)
	viewport_event.position = viewport_pos
	viewport_event.global_position = viewport_pos
	_screen_ui.push_input(viewport_event)


func _find_player_camera(player: Node) -> Camera3D:
	return player.find_child("Camera3D", true, false) as Camera3D


func _is_right_click(event: InputEvent) -> bool:
	return (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed
	)

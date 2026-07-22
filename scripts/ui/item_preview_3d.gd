class_name ItemPreview3D
extends SubViewportContainer
## Renders a regular 3D preview scene into a UI card.

@export var preview_scene: PackedScene
@export var auto_rotate: bool = true
@export var rotation_speed: float = 1.0

@onready var _viewport: SubViewport = $SubViewport

var _preview_instance: Node3D = null
var _model_root: Node3D = null
var _camera: Camera3D = null
var _preview_angle: float = 0.0


func _ready() -> void:
	# SubViewportContainer with stretch enabled controls the viewport size,
	# so just keep the default size and let the container scale it.
	# Nested SubViewports inside another SubViewport don't get reliable
	# UPDATE_WHEN_VISIBLE notifications, so render always to avoid white placeholder.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	# Smooth scaling when the viewport texture is drawn at UI size.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	_setup_environment()

	if preview_scene != null:
		_load_preview_scene(preview_scene)


func _setup_environment() -> void:
	## Each preview viewport has its own World3D. Use a procedural sky so
	# transparent/metallic objects (like the pitcher glass) get reflections
	# and small surface details (like strawberry seeds) keep natural contrast.
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.3
	# Without a filmic tonemap, Environment.TONEMAP_MODE_LINEAR (the default)
	# hard-clips any channel over 1.0 straight to white. Combined with sky
	# ambient + direct light, bright/saturated albedos (lemon yellow, peach
	# skin, etc.) were blowing out to solid white while only very dark
	# colors stayed visible. tonemap_white must also be raised above its
	# default of 1.0 (matches world.tscn's Environment_main) - at 1.0 the
	# Filmic curve has no headroom and still clips almost like Linear.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.1

	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)


func set_preview_scene(scene: PackedScene) -> void:
	preview_scene = scene
	if _viewport == null:
		return
	if _preview_instance != null and is_instance_valid(_preview_instance):
		_preview_instance.queue_free()
		_preview_instance = null
	if scene != null:
		_load_preview_scene(scene)


func _load_preview_scene(scene: PackedScene) -> void:
	_preview_instance = scene.instantiate() as Node3D
	if _preview_instance == null:
		push_error("ItemPreview3D: preview scene root is not a Node3D")
		return
	_viewport.add_child(_preview_instance)

	_camera = _find_camera(_preview_instance)
	if _camera != null:
		_camera.current = true
		# Layer 2 is used by the screen-space outline system for white fill
		# nodes (see Interactable._apply_outline). Without excluding it here
		# (same fix as Computer.ScreenCamera), whatever is currently
		# highlighted in the main game bleeds through as solid white.
		_camera.cull_mask &= ~2

	_configure_lights(_preview_instance)

	_model_root = _find_model_root(_preview_instance)


func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null


func _configure_lights(node: Node) -> void:
	## NOTE: shadow_enabled was previously forced on here to add contrast for
	## small surface details, but shadow mapping on a DirectionalLight3D in a
	## tiny isolated preview World3D was causing the whole model to render
	## solid white (misbehaving shadow distance/bias at this tiny scale).
	## Leave shadows off for these preview scenes.
	for child in node.get_children():
		_configure_lights(child)


func _find_model_root(node: Node) -> Node3D:
	## Try to find a node named "Model" or "ModelRoot" first, otherwise use the scene root.
	var named := node.get_node_or_null("Model")
	if named != null:
		return named as Node3D
	named = node.get_node_or_null("ModelRoot")
	if named != null:
		return named as Node3D
	return node as Node3D


func _process(delta: float) -> void:
	if not auto_rotate or _model_root == null:
		return
	_preview_angle += rotation_speed * delta
	_model_root.rotation.y = _preview_angle

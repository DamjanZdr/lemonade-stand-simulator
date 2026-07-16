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
	# Render at 2x the UI display size so the preview is crisp without
	# excessive downscaling that blurs small details (e.g. strawberry seeds).
	var w := maxi(160, int(custom_minimum_size.x * 2.0))
	var h := maxi(100, int(custom_minimum_size.y * 2.0))
	_viewport.size = Vector2i(w, h)
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
	## Enable shadows on any DirectionalLight3D in the preview scene so small
	## surface details (like strawberry seeds) get visible contrast.
	if node is DirectionalLight3D:
		var light := node as DirectionalLight3D
		light.shadow_enabled = true
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

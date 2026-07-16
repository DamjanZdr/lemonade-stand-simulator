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
	# Higher render resolution so the preview looks crisp in the UI card.
	_viewport.size = Vector2i(400, 240)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	# Smooth scaling when the viewport texture is drawn at UI size.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	_setup_environment()

	if preview_scene != null:
		_load_preview_scene(preview_scene)


func _setup_environment() -> void:
	## Each preview viewport has its own World3D, so it needs its own
	## environment. Add a soft ambient fill so shadows are not pitch black.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.45, 0.45, 1.0)
	env.ambient_light_energy = 0.6

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

	_model_root = _find_model_root(_preview_instance)


func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null


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

extends CharacterBody3D
## Minimal player for multiplayer testing.
##
## Third-person capsule with WASD movement + mouse look.
## Only the authority peer controls the player; others see it replicated.

@export var move_speed: float = 5.0
@export var sprint_multiplier: float = 1.8
@export var mouse_sensitivity: float = 0.002
@export var gravity: float = 9.8

var _camera: Camera3D = null


func _enter_tree() -> void:
	# Set authority based on node name (peer ID).
	set_multiplayer_authority(int(name))


func _ready() -> void:
	# Set up replication config in code (avoids complex .tscn resource).
	var sync = $MultiplayerSynchronizer as MultiplayerSynchronizer
	if sync:
		var config = SceneReplicationConfig.new()
		config.add_property("position")
		config.add_property("rotation")
		sync.replication_config = config

	_camera = $Camera3D as Camera3D

	if is_multiplayer_authority():
		# Local player: blue, activate camera, capture mouse.
		_set_color(Color(0.3, 0.5, 0.9))
		if _camera:
			_camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		# Remote player: red.
		_set_color(Color(0.9, 0.3, 0.3))


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if _camera:
			_camera.rotate_x(-event.relative.y * mouse_sensitivity)
			_camera.rotation.x = clampf(_camera.rotation.x, -PI / 2.1, PI / 2.1)
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed = move_speed * (sprint_multiplier if Input.is_action_pressed("sprint") else 1.0)
	velocity.x = direction.x * speed if direction else move_toward(velocity.x, 0, speed)
	velocity.z = direction.z * speed if direction else move_toward(velocity.z, 0, speed)
	move_and_slide()


func _set_color(color: Color) -> void:
	var mesh = $MeshInstance3D as MeshInstance3D
	if mesh:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mesh.material_override = mat

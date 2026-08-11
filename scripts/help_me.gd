extends Node3D
## HelpMe test scene: press G to drop an object at the marker,
## click the object to show "GIVE ME LEMONADE" for 5 seconds.

@onready var _marker: Marker3D = $Marker3D

const _MESSAGE_TEXT := "GIVE ME LEMONADE"
const _MESSAGE_DURATION := 5.0
const _SPAWN_HEIGHT_OFFSET := 0.5 # spawn slightly above marker origin


func _ready() -> void:
	# Make sure we receive input events
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		_spawn_object()


func _spawn_object() -> void:
	var body := RigidBody3D.new()

	# Visual mesh
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.85, 0.2, 1) # lemon yellow
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	# Collision
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.5, 0.5)
	col.shape = shape
	body.add_child(col)

	# Position at marker, slightly offset up so it drops
	body.global_position = _marker.global_position + Vector3(0, _SPAWN_HEIGHT_OFFSET, 0)

	# Click detection
	body.input_ray_pickable = true
	body.connect("input_event", _on_object_clicked)

	add_child(body)


func _on_object_clicked(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_message(_camera if _camera is Node3D else null)


func _show_message(_anchor: Node3D) -> void:
	# Avoid stacking multiple labels — remove any existing one
	var existing := get_node_or_null("MessageLabel")
	if existing:
		existing.queue_free()

	var label := Label3D.new()
	label.name = "MessageLabel"
	label.text = _MESSAGE_TEXT
	label.font_size = 48
	label.modulate = Color(1, 0.9, 0.2, 1)
	label.outline_modulate = Color.BLACK
	label.outline_size = 8
	label.pixel_size = 0.01
	label.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 2, 0)
	add_child(label)

	# Auto-remove after duration
	get_tree().create_timer(_MESSAGE_DURATION).timeout.connect(label.queue_free)

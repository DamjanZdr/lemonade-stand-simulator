extends Node3D
## HelpMe test scene: press G to spawn the Bean at StartPoint,
## it falls to the floor, walks to EndPoint, then disappears.
## Click the Bean to show "GIVE ME LEMONADE" for 5 seconds.
##
## Set auto_spawn_count in the inspector to auto-spawn that many beans
## every 0.5 seconds. Set it to 0 to disable auto-spawning.

@export var auto_spawn_count: int = 0

@onready var _start_point: Marker3D = $StartPoint
@onready var _end_point: Marker3D = $EndPoint
@onready var _bean_template: Node3D = $Bean

var _beans: Array[CharacterBody3D] = []
var _auto_spawn_remaining: int = 0
var _auto_spawn_timer: float = 0.0

const _MESSAGE_TEXT := "GIVE ME LEMONADE"
const _MESSAGE_DURATION := 5.0
const _MOVE_SPEED: float = 3.0
const _GRAVITY: float = 9.8
const _AUTO_SPAWN_INTERVAL: float = 0.5


func _ready() -> void:
	set_process_input(true)
	_bean_template.visible = true
	_auto_spawn_remaining = auto_spawn_count


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		_spawn_bean()


func _process(delta: float) -> void:
	if _auto_spawn_remaining > 0:
		_auto_spawn_timer += delta
		if _auto_spawn_timer >= _AUTO_SPAWN_INTERVAL:
			_auto_spawn_timer = 0.0
			_spawn_bean()
			_auto_spawn_remaining -= 1


func _spawn_bean() -> void:
	var bean_copy := _bean_template.duplicate() as Node3D
	bean_copy.visible = true

	var body := CharacterBody3D.new()
	body.name = "BeanWalker_%d" % _beans.size()
	add_child(body)
	body.global_position = _start_point.global_position

	# Beans on layer 2, collide with everything except layer 2
	body.collision_layer = 2
	body.collision_mask = 0xFFFFFFFD

	body.look_at(_end_point.global_position)

	# Reparent children from the StaticBody3D copy into the CharacterBody3D
	for child in bean_copy.get_children():
		bean_copy.remove_child(child)
		body.add_child(child)
	bean_copy.queue_free()

	# Move CollisionShape3D to be a direct child of the body
	var inner_bean := body.get_node_or_null("Bean")
	if inner_bean:
		var col := inner_bean.get_node_or_null("CollisionShape3D")
		if col:
			var world_pos: Vector3 = col.global_position
			inner_bean.remove_child(col)
			body.add_child(col)
			col.global_position = world_pos

	body.set_meta("destination", _end_point.global_position)
	body.set_meta("was_grounded", false)

	body.input_ray_pickable = true
	body.connect("input_event", _on_bean_clicked)

	_beans.append(body)
	print(
		"[Bean] spawned #%d at %s, children=%d"
		% [_beans.size(), body.global_position, body.get_child_count()]
	)


func _physics_process(delta: float) -> void:
	var alive: Array[CharacterBody3D] = []
	for body in _beans:
		if not is_instance_valid(body):
			continue

		var dest: Vector3 = body.get_meta("destination", Vector3.ZERO)
		var to_dest: Vector3 = dest - body.global_position
		to_dest.y = 0
		var dist: float = to_dest.length()

		if dist < 0.5:
			print("[Bean] reached destination, freeing %s" % body.name)
			body.queue_free()
			continue

		var on_floor: bool = body.is_on_floor()
		if on_floor:
			body.set_meta("was_grounded", true)
		var grounded: bool = on_floor or body.get_meta("was_grounded", false)

		var vel: Vector3 = Vector3.ZERO
		if grounded:
			var dir: Vector3 = to_dest.normalized()
			vel = dir * _MOVE_SPEED
		vel.y = body.velocity.y - _GRAVITY * delta
		body.velocity = vel
		body.move_and_slide()

		alive.append(body)

	_beans = alive


func _on_bean_clicked(
	_camera: Node,
	event: InputEvent,
	_pos: Vector3,
	_normal: Vector3,
	_shape_idx: int,
) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_message()


func _show_message() -> void:
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

	get_tree().create_timer(_MESSAGE_DURATION).timeout.connect(label.queue_free)

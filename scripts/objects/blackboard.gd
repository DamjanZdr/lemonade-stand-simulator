extends Interactable
## Interactive recipe blackboard. Each fruit has a visual fruit and sugar amount.

const FRUIT_LABELS: Dictionary = {
	"lemon": "Lemon",
	"strawberry": "Strawberry",
	"blueberry": "Blueberry",
	"peach": "Peach",
	"watermelon": "Watermelon",
}

const FRUIT_AMOUNT_LABEL := "fruit .... "
const SUGAR_AMOUNT_LABEL := "sugar .... "
const EMPTY_VALUE := "?"
const CURSOR_BLINK := 0.5

@export var font: FontFile = preload("res://AmaticSC-Bold.ttf")
@export var font_size: int = 110
@export var label_pixel_size: float = 0.003
@export var label_width: float = 0.9
@export var label_height: float = 1.1
@export var spacing_x: float = 1.05
@export var start_offset: Vector3 = Vector3(-2.1, 0.55, 0.08)

@onready var board_camera: Camera3D = $Camera3D

var _labels: Dictionary = { }
var _colliders: Dictionary = { }
var _visual_values: Dictionary = { }

var _editing_fruit := ""
var _editing_field := "" # "fruit" or "sugar"
var _edit_buffer := ""
var _cursor_visible := true
var _cursor_timer := 0.0


func _ready() -> void:
	_setup_labels()
	_refresh_all_labels()


func get_hint(_player: Node) -> String:
	if _editing_fruit != "":
		return "Enter: next / Esc: cancel"
	return "LMB: Edit recipes"


func interact(_player: Node) -> void:
	if _editing_fruit != "":
		return
	var p := _player as Player
	if p != null and board_camera != null:
		p.enter_priceboard_focus(board_camera.global_transform)
	_start_edit(GameState.FRUIT_TYPES[0], "fruit")


func _input(event: InputEvent) -> void:
	if _editing_fruit == "":
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	var key: int = event.keycode
	var handled := true

	match key:
		KEY_ENTER, KEY_KP_ENTER:
			_confirm_and_next()
		KEY_ESCAPE:
			_cancel_edit()
		KEY_BACKSPACE:
			_edit_buffer = ""
			_cursor_visible = true
			_cursor_timer = 0.0
			_refresh_label(_editing_fruit)
		KEY_0, KEY_KP_0:
			_append_char("0")
		KEY_1, KEY_KP_1:
			_append_char("1")
		KEY_2, KEY_KP_2:
			_append_char("2")
		KEY_3, KEY_KP_3:
			_append_char("3")
		KEY_4, KEY_KP_4:
			_append_char("4")
		KEY_5, KEY_KP_5:
			_append_char("5")
		KEY_6, KEY_KP_6:
			_append_char("6")
		KEY_7, KEY_KP_7:
			_append_char("7")
		KEY_8, KEY_KP_8:
			_append_char("8")
		KEY_9, KEY_KP_9:
			_append_char("9")
		KEY_LEFT:
			_move_horizontal(-1)
		KEY_RIGHT:
			_move_horizontal(1)
		KEY_UP:
			_move_vertical(-1)
		KEY_DOWN:
			_move_vertical(1)
		_:
			handled = false

	if handled:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _editing_fruit == "":
		return
	_cursor_timer += delta
	if _cursor_timer >= CURSOR_BLINK:
		_cursor_timer -= CURSOR_BLINK
		_cursor_visible = not _cursor_visible
		_refresh_label(_editing_fruit)


func _setup_labels() -> void:
	for i in range(GameState.FRUIT_TYPES.size()):
		var ft: String = GameState.FRUIT_TYPES[i]
		var pos := start_offset + Vector3(i * spacing_x, 0.0, 0.0)
		var label := Label3D.new()
		label.name = ft.capitalize() + "Label"
		label.text = _format_label_text(ft, EMPTY_VALUE, EMPTY_VALUE)
		label.font = font
		label.font_size = font_size
		label.pixel_size = label_pixel_size
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.alpha_cut = Label3D.ALPHA_CUT_HASH
		label.double_sided = false
		add_child(label)
		label.transform.origin = pos
		_labels[ft] = label

		_visual_values[ft] = { "fruit": "", "sugar": "" }

		var area := Area3D.new()
		area.name = ft.capitalize() + "Area"
		area.input_ray_pickable = true
		var center_offset := Vector3(label_width * 0.5, -label_height * 0.5, 0.0)
		area.position = pos + center_offset
		add_child(area)
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(label_width, label_height, 0.05)
		shape.shape = box
		area.add_child(shape)
		area.input_event.connect(_on_label_clicked.bind(ft))
		_colliders[ft] = area


func _format_label_text(fruit: String, fruit_value: String, sugar_value: String) -> String:
	var name_label: String = FRUIT_LABELS.get(fruit, fruit.capitalize())
	return "%s\n%s%s\n%s%s" % [
		name_label,
		FRUIT_AMOUNT_LABEL,
		fruit_value,
		SUGAR_AMOUNT_LABEL,
		sugar_value,
	]


func _refresh_all_labels() -> void:
	for ft in GameState.FRUIT_TYPES:
		_refresh_label(ft)


func _refresh_label(fruit: String) -> String:
	var label: Label3D = _labels[fruit]
	var values: Dictionary = _visual_values[fruit]
	var fruit_value: String = values.get("fruit", "")
	var sugar_value: String = values.get("sugar", "")
	var fruit_display := fruit_value if fruit_value != "" else EMPTY_VALUE
	var sugar_display := sugar_value if sugar_value != "" else EMPTY_VALUE

	if fruit == _editing_fruit:
		if _editing_field == "fruit":
			fruit_display = _get_active_display(_edit_buffer)
		else:
			sugar_display = _get_active_display(_edit_buffer)

	label.text = _format_label_text(fruit, fruit_display, sugar_display)
	return label.text


func _get_active_display(buffer: String) -> String:
	var value := buffer if buffer != "" else EMPTY_VALUE
	var cursor := "_" if _cursor_visible else " "
	return value + cursor


func _start_edit(fruit: String, field: String) -> void:
	_editing_fruit = fruit
	_editing_field = field
	_edit_buffer = _visual_values[fruit].get(field, "")
	_cursor_visible = true
	_cursor_timer = 0.0
	_refresh_all_labels()


func _confirm_and_next() -> void:
	if _editing_fruit == "":
		return
	_visual_values[_editing_fruit][_editing_field] = _edit_buffer

	var idx := GameState.FRUIT_TYPES.find(_editing_fruit)
	if _editing_field == "fruit":
		_start_edit(_editing_fruit, "sugar")
	else:
		idx += 1
		if idx >= GameState.FRUIT_TYPES.size():
			_finish_edit()
		else:
			_start_edit(GameState.FRUIT_TYPES[idx], "fruit")


func _move_horizontal(direction: int) -> void:
	if _editing_fruit == "":
		return
	var idx := GameState.FRUIT_TYPES.find(_editing_fruit)
	idx = wrapi(idx + direction, 0, GameState.FRUIT_TYPES.size())
	_visual_values[_editing_fruit][_editing_field] = _edit_buffer
	_start_edit(GameState.FRUIT_TYPES[idx], _editing_field)


func _move_vertical(direction: int) -> void:
	if _editing_fruit == "":
		return
	_visual_values[_editing_fruit][_editing_field] = _edit_buffer
	if _editing_field == "fruit":
		if direction < 0:
			# From fruit, up goes to the sugar of the previous fruit.
			var prev_idx := GameState.FRUIT_TYPES.find(_editing_fruit) - 1
			var idx := wrapi(prev_idx, 0, GameState.FRUIT_TYPES.size())
			_start_edit(GameState.FRUIT_TYPES[idx], "sugar")
		else:
			# From fruit, down goes to the sugar of the same fruit.
			_start_edit(_editing_fruit, "sugar")
	else:
		if direction > 0:
			# From sugar, down goes to the fruit of the next fruit.
			var next_idx := GameState.FRUIT_TYPES.find(_editing_fruit) + 1
			var idx := wrapi(next_idx, 0, GameState.FRUIT_TYPES.size())
			_start_edit(GameState.FRUIT_TYPES[idx], "fruit")
		else:
			# From sugar, up goes to the fruit of the same fruit.
			_start_edit(_editing_fruit, "fruit")


func _append_char(c: String) -> void:
	if _edit_buffer.length() >= 1:
		return
	_edit_buffer = c
	_cursor_visible = true
	_cursor_timer = 0.0
	_refresh_label(_editing_fruit)


func _on_label_clicked(
		_camera: Node,
		event: InputEvent,
		_pos: Vector3,
		_normal: Vector3,
		_shape: int,
		fruit: String,
) -> void:
	if _editing_fruit == "":
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_visual_values[_editing_fruit][_editing_field] = _edit_buffer
		_start_edit(fruit, "fruit")


func _cancel_edit() -> void:
	_finish_edit()


func _finish_edit() -> void:
	_editing_fruit = ""
	_editing_field = ""
	_edit_buffer = ""
	_cursor_visible = true
	_cursor_timer = 0.0
	_refresh_all_labels()
	var p := get_tree().get_first_node_in_group("player") as Player
	if p != null:
		p.exit_priceboard_focus()

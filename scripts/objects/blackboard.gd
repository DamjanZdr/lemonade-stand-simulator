extends Interactable
## Interactive recipe blackboard. Uses scene-placed Label3D nodes.

const EMPTY_VALUE := "?"
const CURSOR_BLINK := 0.5

@export var columns: int = 3
@export var click_collider_size: Vector3 = Vector3(0.9, 0.45, 0.05)

@onready var board_camera: Camera3D = $Camera3D

var _label_nodes: Array[Label3D] = []
var _label_data: Array[Dictionary] = []
var _label_index := -1
var _field_index := 0  # 0 = primary, 1 = sugar
var _edit_buffer := ""
var _cursor_visible := true
var _cursor_timer := 0.0


func _ready() -> void:
	_scan_labels()
	_refresh_all_labels()


func get_hint(_player: Node) -> String:
	if _label_index >= 0:
		return "Enter: next / Esc: cancel"
	return "LMB: Edit recipes"


func interact(_player: Node) -> void:
	if _label_index >= 0:
		return
	var p := _player as Player
	if p != null and board_camera != null:
		p.enter_priceboard_focus(board_camera.global_transform)
	_start_edit(0, 0)


func _input(event: InputEvent) -> void:
	if _label_index < 0:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	var key: int = event.keycode
	var handled := true

	match key:
		KEY_ENTER, KEY_KP_ENTER:
			_confirm_and_next()
		KEY_ESCAPE:
			_finish_edit()
		KEY_BACKSPACE:
			_edit_buffer = ""
			_cursor_visible = true
			_cursor_timer = 0.0
			_refresh_label(_label_index)
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
	if _label_index < 0:
		return
	_cursor_timer += delta
	if _cursor_timer >= CURSOR_BLINK:
		_cursor_timer -= CURSOR_BLINK
		_cursor_visible = not _cursor_visible
		_refresh_label(_label_index)


func _scan_labels() -> void:
	_label_nodes.clear()
	_label_data.clear()
	for child in get_children():
		if child is Label3D:
			var label := child as Label3D
			_label_nodes.append(label)
			var lines := label.text.split("\n")
			var prefix1 := _extract_prefix(lines[0] if lines.size() > 0 else "")
			var prefix2 := _extract_prefix(lines[1] if lines.size() > 1 else "")
			_label_data.append({
				"name": label.name,
				"prefix1": prefix1,
				"prefix2": prefix2,
				"value1": "",
				"value2": "",
			})
			_add_click_area(label, _label_nodes.size() - 1)


func _extract_prefix(line: String) -> String:
	var idx := line.find(EMPTY_VALUE)
	if idx < 0:
		return line
	return line.substr(0, idx)


func _add_click_area(label: Label3D, index: int) -> void:
	var area := Area3D.new()
	area.name = label.name + "Area"
	area.input_ray_pickable = true
	area.position = label.position
	add_child(area)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = click_collider_size
	shape.shape = box
	area.add_child(shape)
	area.input_event.connect(_on_label_clicked.bind(index))


func _refresh_all_labels() -> void:
	for i in range(_label_nodes.size()):
		_refresh_label(i)


func _refresh_label(index: int) -> void:
	var label: Label3D = _label_nodes[index]
	var data: Dictionary = _label_data[index]
	var line1 := _build_line(data["prefix1"], data["value1"], 0, index)
	var line2 := _build_line(data["prefix2"], data["value2"], 1, index)
	label.text = line1 + "\n" + line2


func _build_line(prefix: String, value: String, field: int, index: int) -> String:
	var is_active := index == _label_index and field == _field_index
	var display := value if value != "" else EMPTY_VALUE
	if is_active:
		var cursor := "_" if _cursor_visible else " "
		return prefix + display + cursor
	return prefix + display


func _start_edit(label_idx: int, field_idx: int) -> void:
	_label_index = label_idx
	_field_index = field_idx
	_edit_buffer = _label_data[label_idx]["value%d" % (field_idx + 1)]
	_cursor_visible = true
	_cursor_timer = 0.0
	_refresh_all_labels()


func _confirm_and_next() -> void:
	_store_buffer()
	if _field_index == 0:
		_start_edit(_label_index, 1)
	else:
		var next_idx := _label_index + 1
		if next_idx >= _label_nodes.size():
			_finish_edit()
		else:
			_start_edit(next_idx, 0)


func _move_horizontal(direction: int) -> void:
	_store_buffer()
	var row := _label_index / columns
	var col := _label_index % columns
	col = wrapi(col + direction, 0, columns)
	var new_index := row * columns + col
	_start_edit(new_index, _field_index)


func _move_vertical(direction: int) -> void:
	_store_buffer()
	var rows := _label_nodes.size() / columns
	if _field_index == 0:
		if direction < 0:
			# From primary, up goes to sugar of label above.
			var row := _label_index / columns
			var col := _label_index % columns
			row = wrapi(row - 1, 0, rows)
			_start_edit(row * columns + col, 1)
		else:
			# From primary, down goes to sugar of same label.
			_start_edit(_label_index, 1)
	else:
		if direction > 0:
			# From sugar, down goes to primary of label below.
			var row := _label_index / columns
			var col := _label_index % columns
			row = wrapi(row + 1, 0, rows)
			_start_edit(row * columns + col, 0)
		else:
			# From sugar, up goes to primary of same label.
			_start_edit(_label_index, 0)


func _store_buffer() -> void:
	if _label_index < 0:
		return
	_label_data[_label_index]["value%d" % (_field_index + 1)] = _edit_buffer


func _append_char(c: String) -> void:
	if _edit_buffer.length() >= 1:
		return
	_edit_buffer = c
	_cursor_visible = true
	_cursor_timer = 0.0
	_refresh_label(_label_index)


func _on_label_clicked(
		_camera: Node,
		event: InputEvent,
		_pos: Vector3,
		_normal: Vector3,
		_shape: int,
		index: int,
) -> void:
	if _label_index < 0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_store_buffer()
		_start_edit(index, 0)


func _finish_edit() -> void:
	_store_buffer()
	_label_index = -1
	_field_index = 0
	_edit_buffer = ""
	_cursor_visible = true
	_cursor_timer = 0.0
	_refresh_all_labels()
	var p := get_tree().get_first_node_in_group("player") as Player
	if p != null:
		p.exit_priceboard_focus()

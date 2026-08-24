extends Interactable
## Interactive recipe blackboard. Uses scene-placed Label3D nodes.

const EMPTY_VALUE := "?"
const CURSOR_BLINK := 0.5

@export var columns: int = 2
@export var click_collider_size: Vector3 = Vector3(0.9, 0.45, 0.05)

@onready var board_camera: Camera3D = $Camera3D

var _label_nodes: Array[Label3D] = []
var _label_data: Array[Dictionary] = []
var _label_index := -1
var _field_index := 0 # 0 = primary, 1 = sugar
var _edit_buffer := ""
var _cursor_visible := true
var _cursor_timer := 0.0
## The player currently editing recipes on this board. Stored so we
## can release THEM from focus when editing ends — not just whichever
## player happens to be first in the "player" group (which in MP
## would often be the wrong one).
var _editing_player: Player = null


func _ready() -> void:
	_scan_labels()
	_refresh_all_labels()
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	# Listen to global recipe changes so the blackboard labels stay in
	# sync when another player edits the same recipes.
	EventBus.recipe_changed.connect(_on_recipe_changed)


func get_hint(_player: Node) -> String:
	if _label_index >= 0:
		return "Blackboard | Enter: next / Esc: cancel"
	return "Blackboard | LMB: edit recipes"


func interact(_player: Node) -> void:
	if _label_index >= 0:
		return
	var p := _player as Player
	if p != null and board_camera != null:
		_editing_player = p
		p.enter_priceboard_focus(board_camera.global_transform)
	_start_edit(0, 0)
	# Clear any stale edited values from a previous session so ESC
	# truly cancels instead of re-applying old values.
	for i in range(_label_data.size()):
		_label_data[i]["value1"] = ""
		_label_data[i]["value2"] = ""


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
		KEY_LEFT, KEY_A:
			_move_horizontal(-1)
		KEY_RIGHT, KEY_D:
			_move_horizontal(1)
		KEY_UP, KEY_W:
			_move_vertical(-1)
		KEY_DOWN, KEY_S:
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
	for child in find_children("*", "Label3D"):
		var label := child as Label3D
		if label.name.ends_with("Locked"):
			continue
		if label.text.find(EMPTY_VALUE) < 0:
			continue
		var fruit_id := label.name.to_lower()
		var is_locked := (
			fruit_id in StandUnit.FRUIT_TYPES and not UpgradeManager.is_fruit_unlocked(fruit_id)
		)
		_label_nodes.append(label)
		var lines := label.text.split("\n")
		var prefix1 := _extract_prefix(lines[0] if lines.size() > 0 else "")
		var prefix2 := _extract_prefix(lines[1] if lines.size() > 1 else "")
		_label_data.append(
			{
				"name": label.name,
				"prefix1": prefix1,
				"prefix2": prefix2,
				"value1": "",
				"value2": "",
				"locked": is_locked,
			}
		)
		if fruit_id in StandUnit.FRUIT_TYPES:
			var parent_title := label.get_parent() as Label3D
			if parent_title != null:
				var locked_lbl := parent_title.get_node_or_null(label.name + "Locked") as Label3D
				if locked_lbl != null:
					locked_lbl.visible = is_locked
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
	add_child(area)
	area.global_position = label.global_position
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
	if data.get("locked", false):
		label.text = ""
		return
	var line1 := _build_line(data["prefix1"], data["value1"], 0, index)
	var line2 := _build_line(data["prefix2"], data["value2"], 1, index)
	label.text = line1 + "\n" + line2


func _build_line(prefix: String, value: String, field: int, index: int) -> String:
	var data: Dictionary = _label_data[index]
	if data.get("locked", false):
		return prefix + "Locked"
	var is_active := index == _label_index and field == _field_index
	if is_active:
		if _edit_buffer == "":
			var cursor := "_" if _cursor_visible else " "
			return prefix + cursor
		return prefix + _edit_buffer
	var display := value if value != "" else EMPTY_VALUE
	return prefix + display


func _start_edit(label_idx: int, field_idx: int) -> void:
	if _label_data[label_idx].get("locked", false):
		var next := _next_editable_index(label_idx, 1)
		if next < 0:
			_apply_and_finish_edit()
			return
		label_idx = next
	_label_index = label_idx
	_field_index = field_idx
	_edit_buffer = ""
	_cursor_visible = true
	_cursor_timer = 0.0
	_refresh_all_labels()


func _confirm_and_next() -> void:
	_store_buffer()
	if _field_index == 0:
		_start_edit(_label_index, 1)
	else:
		var next_idx := _next_editable_index(_label_index, 1)
		if next_idx < 0:
			_apply_and_finish_edit()
		else:
			_start_edit(next_idx, 0)


func _move_horizontal(direction: int) -> void:
	_store_buffer()
	var row := int(_label_index / columns)
	var col := int(_label_index % columns)
	col = wrapi(col + direction, 0, columns)
	var new_index := row * columns + col
	if new_index < _label_nodes.size():
		_start_edit(new_index, _field_index)


func _move_vertical(direction: int) -> void:
	_store_buffer()
	var rows := int(_label_nodes.size() / columns)
	if _field_index == 0:
		if direction < 0:
			var row := int(_label_index / columns)
			var col := int(_label_index % columns)
			row = wrapi(row - 1, 0, rows)
			var new_index := row * columns + col
			if new_index < _label_nodes.size():
				_start_edit(new_index, 1)
		else:
			_start_edit(_label_index, 1)
	else:
		if direction > 0:
			var row := int(_label_index / columns)
			var col := int(_label_index % columns)
			row = wrapi(row + 1, 0, rows)
			var new_index := row * columns + col
			if new_index < _label_nodes.size():
				_start_edit(new_index, 0)
		else:
			_start_edit(_label_index, 0)


func _store_buffer() -> void:
	if _label_index < 0:
		return
	if _edit_buffer == "":
		return
	_label_data[_label_index]["value%d" % (_field_index + 1)] = _edit_buffer


func _append_char(c: String) -> void:
	_edit_buffer = c
	_store_buffer()
	_confirm_and_next()


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
	_label_index = -1
	_field_index = 0
	_edit_buffer = ""
	_cursor_visible = true
	_cursor_timer = 0.0
	_refresh_all_labels()
	if _editing_player != null and is_instance_valid(_editing_player):
		_editing_player.exit_priceboard_focus()
	_editing_player = null


## Finish editing and apply the entered recipe values to the stand.
func _apply_and_finish_edit() -> void:
	_store_buffer()
	_apply_recipes_to_stand()
	_finish_edit()


## Send all edited recipe values to the nearest stand via RPC so
## the host and all clients see the same recipes.
func _apply_recipes_to_stand() -> void:
	var stand := _find_nearest_stand()
	if stand == null:
		return
	for i in range(_label_data.size()):
		var data: Dictionary = _label_data[i]
		if data.get("locked", false):
			continue
		var fruit_id: String = data.get("name", "").to_lower()
		if fruit_id == "" or not fruit_id in StandUnit.FRUIT_TYPES:
			continue
		var v1: String = data.get("value1", "")
		var v2: String = data.get("value2", "")
		if v1 == "" and v2 == "":
			continue
		# Build recipe from current GameState values, then override
		# with the edited fields.
		var recipe := GameState.get_recipe(fruit_id).duplicate()
		if v1 != "" and v1.is_valid_float():
			recipe["fruit_count"] = float(v1)
		if v2 != "" and v2.is_valid_float():
			recipe["sugar"] = float(v2)
		stand.request_set_recipe(fruit_id, recipe)
		# Also update local GameState immediately for responsiveness
		GameState.set_recipe(fruit_id, recipe)


## Find the closest StandUnit in the scene to this blackboard.
func _find_nearest_stand() -> StandUnit:
	var best: StandUnit = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("stand"):
		var s := node as StandUnit
		if s == null or not is_instance_valid(s):
			continue
		var d := global_position.distance_squared_to(s.global_position)
		if d < best_dist:
			best_dist = d
			best = s
	return best


func _next_editable_index(from: int, direction: int) -> int:
	var count := _label_nodes.size()
	var idx := from
	for _i in range(count):
		idx = wrapi(idx + direction, 0, count)
		if not _label_data[idx].get("locked", false):
			return idx
	return -1


func _on_upgrade_purchased(_upgrade: int, _cost: float) -> void:
	for i in range(_label_data.size()):
		var data: Dictionary = _label_data[i]
		var fruit_id: String = data.get("name", "").to_lower()
		if fruit_id in StandUnit.FRUIT_TYPES:
			var was_locked: bool = data.get("locked", false)
			var now_locked := not UpgradeManager.is_fruit_unlocked(fruit_id)
			data["locked"] = now_locked
			if was_locked != now_locked:
				var label: Label3D = _label_nodes[i]
				var parent_title := label.get_parent() as Label3D
				if parent_title != null:
					var locked_lbl := parent_title.get_node_or_null(label.name + "Locked") as Label3D
					if locked_lbl != null:
						locked_lbl.visible = now_locked
	_refresh_all_labels()


func _on_recipe_changed(fruit_type: String, recipe: Dictionary) -> void:
	if recipe.is_empty():
		return
	for i in range(_label_data.size()):
		var data: Dictionary = _label_data[i]
		var fruit_id: String = data.get("name", "").to_lower()
		if fruit_id != fruit_type:
			continue
		# Update both recipe fields on the blackboard labels so all
		# players see the same values.
		if recipe.has("fruit_count"):
			data["value1"] = str(int(recipe["fruit_count"]))
		if recipe.has("sugar"):
			data["value2"] = str(int(recipe["sugar"]))
		break
	_refresh_all_labels()

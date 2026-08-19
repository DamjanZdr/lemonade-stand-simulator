extends Interactable
## Interactive price board. LMB opens a screen UI where each fruit price can be edited.

const FRUIT_LABELS: Dictionary = {
	"lemon": "Lemon",
	"strawberry": "Strawberry",
	"blueberry": "Blueberry",
	"peach": "Peach",
	"watermelon": "Watermelon",
}

@onready var label_3d: Label3D = $Label3D
@onready var board_camera: Camera3D = $Camera3D
## PriceBoard is a direct child of its StandUnit in the scene, so this is
## the stand whose prices this board displays/edits — no extra wiring
## needed from main.gd.
@onready var _stand: StandUnit = get_parent() as StandUnit

var _editing_index := -1
var _edit_buffer := ""
var _cursor_visible := true
var _cursor_timer := 0.0
var _price_prefix: Dictionary = { }
## The player who is currently editing prices on this board. Stored so we
## can release THEM from priceboard focus when editing ends — not just
## whichever player happens to be first in the "player" group (which in
## multiplayer would often be the wrong one).
var _editing_player: Player = null
const CURSOR_BLINK := 0.5


func _ready() -> void:
	_setup_prices_label()
	_load_price_prefixes()
	if _stand:
		_stand.price_changed.connect(_on_price_changed)
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	_refresh_label()


func get_hint(_player: Node) -> String:
	if _editing_index >= 0:
		return "Price Board | Enter: next / Esc: cancel"
	return "Price Board | LMB: edit prices"


func interact(_player: Node) -> void:
	if _editing_index < 0:
		var p := _player as Player
		if p != null and board_camera != null:
			_editing_player = p
			p.enter_priceboard_focus(board_camera.global_transform)
		_start_edit()


func _input(event: InputEvent) -> void:
	if _editing_index < 0:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	var key: int = event.keycode
	var handled := true

	if key == KEY_ENTER or key == KEY_KP_ENTER:
		_confirm_and_next()
	elif key == KEY_ESCAPE:
		_cancel_edit()
	elif key == KEY_BACKSPACE:
		if _edit_buffer.length() > 1:
			_edit_buffer = _edit_buffer.substr(0, _edit_buffer.length() - 1)
		else:
			_edit_buffer = ""
		_cursor_visible = true
		_cursor_timer = 0.0
		_refresh_label()
	elif key == KEY_0 or key == KEY_KP_0:
		_append_char("0")
	elif key == KEY_1 or key == KEY_KP_1:
		_append_char("1")
	elif key == KEY_2 or key == KEY_KP_2:
		_append_char("2")
	elif key == KEY_3 or key == KEY_KP_3:
		_append_char("3")
	elif key == KEY_4 or key == KEY_KP_4:
		_append_char("4")
	elif key == KEY_5 or key == KEY_KP_5:
		_append_char("5")
	elif key == KEY_6 or key == KEY_KP_6:
		_append_char("6")
	elif key == KEY_7 or key == KEY_KP_7:
		_append_char("7")
	elif key == KEY_8 or key == KEY_KP_8:
		_append_char("8")
	elif key == KEY_9 or key == KEY_KP_9:
		_append_char("9")
	elif key == KEY_PERIOD or key == KEY_KP_PERIOD:
		_append_char(".")
	elif key == KEY_UP or key == KEY_W:
		_move_vertical(-1)
	elif key == KEY_DOWN or key == KEY_S:
		_move_vertical(1)
	else:
		handled = false

	if handled:
		get_viewport().set_input_as_handled()


func _setup_prices_label() -> void:
	label_3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label_3d.vertical_alignment = VERTICAL_ALIGNMENT_TOP


func _load_price_prefixes() -> void:
	_price_prefix.clear()
	for line in label_3d.text.split("\n"):
		if line == "":
			continue
		var prefix := ""
		for c in line:
			if c.is_valid_int():
				break
			prefix += c
		if prefix == "":
			continue
		for ft in StandUnit.FRUIT_TYPES:
			var label: String = FRUIT_LABELS.get(ft, ft.capitalize())
			if prefix.begins_with(label):
				_price_prefix[ft] = prefix
				break


func _process(delta: float) -> void:
	if _editing_index < 0:
		return
	_cursor_timer += delta
	if _cursor_timer >= CURSOR_BLINK:
		_cursor_timer -= CURSOR_BLINK
		_cursor_visible = not _cursor_visible
		_refresh_label()


func _start_edit() -> void:
	_editing_index = _next_editable_index(-1, 1)
	_edit_buffer = ""
	_cursor_visible = true
	_cursor_timer = 0.0
	_refresh_label()


func _commit_current_price() -> void:
	if _editing_index < 0 or _editing_index >= StandUnit.FRUIT_TYPES.size():
		return
	var raw := _edit_buffer
	if raw != "" and raw.is_valid_float():
		_stand.request_set_price(StandUnit.FRUIT_TYPES[_editing_index], float(raw))


func _confirm_and_next() -> void:
	_commit_current_price()
	var next := _next_editable_index(_editing_index, 1)
	if next < 0:
		_editing_index = -1
		if _editing_player != null and is_instance_valid(_editing_player):
			_editing_player.exit_priceboard_focus()
		_editing_player = null
	else:
		_editing_index = next
		_edit_buffer = ""
		_cursor_visible = true
		_cursor_timer = 0.0
		_refresh_label()


func _move_vertical(direction: int) -> void:
	if _editing_index < 0 or _editing_index >= StandUnit.FRUIT_TYPES.size():
		return
	_commit_current_price()
	var next := _next_editable_index(_editing_index, direction)
	if next >= 0:
		_editing_index = next
	_edit_buffer = ""
	_cursor_visible = true
	_cursor_timer = 0.0
	_refresh_label()


func _cancel_edit() -> void:
	_editing_index = -1
	_edit_buffer = ""
	_cursor_visible = true
	_cursor_timer = 0.0
	if _editing_player != null and is_instance_valid(_editing_player):
		_editing_player.exit_priceboard_focus()
	_editing_player = null
	_refresh_label()


func _append_char(c: String) -> void:
	var candidate := _edit_buffer + c
	var sanitized := _sanitize_price(candidate)
	if sanitized != candidate:
		return
	_edit_buffer = sanitized
	_cursor_visible = true
	_cursor_timer = 0.0
	_refresh_label()


func _refresh_label() -> void:
	var txt := ""
	for i in range(StandUnit.FRUIT_TYPES.size()):
		var ft: String = StandUnit.FRUIT_TYPES[i]
		if not UpgradeManager.is_fruit_unlocked(ft):
			continue
		var label: String = FRUIT_LABELS.get(ft, ft.capitalize())
		var prefix: String = _price_prefix.get(ft, label + ".....")
		if i == _editing_index:
			var cursor := "_" if _cursor_visible else " "
			txt += "%s%s%s\n" % [prefix, _edit_buffer, cursor]
		else:
			txt += "%s%.2f\n" % [prefix, _stand.get_price(ft)]
	label_3d.text = txt


func _on_price_changed(_fruit: String, _new_price: float) -> void:
	_refresh_label()


func _on_upgrade_purchased(_upgrade: int, _cost: float) -> void:
	_refresh_label()


func _next_editable_index(from: int, direction: int) -> int:
	var count := StandUnit.FRUIT_TYPES.size()
	var idx := from
	for _i in range(count):
		idx = wrapi(idx + direction, 0, count)
		var ft: String = StandUnit.FRUIT_TYPES[idx]
		if UpgradeManager.is_fruit_unlocked(ft):
			return idx
	return -1


func _sanitize_price(text: String) -> String:
	var out := ""
	var dot_count := 0
	var digit_count := 0
	for c in text:
		if c.is_valid_int():
			if digit_count >= 3:
				continue
			out += c
			digit_count += 1
		elif c == "." and dot_count == 0:
			out += c
			dot_count += 1
	return out

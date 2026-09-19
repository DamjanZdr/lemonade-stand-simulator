class_name Duck
extends Interactable
## Easter egg: click the duck to cycle its lines, one per click.
## After the last line, the next click ends it; the click after that
## restarts the cycle from the first line.

const _LINES: Array[String] = ["Hey", "pam pam pam", "got any grapes?"]

var _line_idx: int = -1 ## -1 = not talking; 0.._LINES.size()-1 = showing that line.
var _label: Label3D = null


func _ready() -> void:
	_label = Label3D.new()
	_label.name = "SpeechLabel"
	_label.font_size = 48
	_label.modulate = Color(1.0, 0.95, 0.4)
	_label.outline_size = 8
	_label.outline_modulate = Color.BLACK
	_label.pixel_size = 0.01
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0.0, 0.9, 0.0)
	_label.visible = false
	add_child(_label)


func interact(_player: Node) -> void:
	_line_idx += 1
	if _line_idx >= _LINES.size():
		# Bit's over — hide the line. The next click restarts the cycle.
		_line_idx = -1
		_label.visible = false
		return
	_label.text = _LINES[_line_idx]
	_label.visible = true


func get_hint(_player: Node) -> String:
	return "Duck | LMB: talk"

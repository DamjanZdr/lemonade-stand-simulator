class_name Duck
extends Interactable
## Easter egg: click the duck to cycle its lines, one per click.
## After the last line, the next click ends it; the click after that
## restarts the cycle from the first line.
## Speech uses the same screen-space bubble style as Customer.

const _LINES: Array[String] = ["Hey", "pam pam pam", "got any grapes?"]

var _line_idx: int = -1 ## -1 = not talking; 0.._LINES.size()-1 = showing that line.
var _ui_layer: CanvasLayer = null
var _ui_panel: Panel = null
var _ui_label: Label = null


func _ready() -> void:
	# CanvasLayer-based bubble (layer 101) so the text renders above the
	# outline overlay — same approach as Customer._build_order_bubble().
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "SpeechBubbleLayer"
	_ui_layer.layer = 101
	add_child(_ui_layer)

	_ui_panel = Panel.new()
	_ui_panel.name = "SpeechPanel"
	_ui_panel.visible = false
	_ui_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 0.8)
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	_ui_panel.add_theme_stylebox_override("panel", sb)
	_ui_layer.add_child(_ui_panel)

	_ui_label = Label.new()
	_ui_label.name = "SpeechLabel"
	_ui_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui_label.add_theme_font_size_override("font_size", 12)
	_ui_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_ui_label.add_theme_constant_override("outline_size", 2)
	_ui_label.visible = false
	_ui_panel.add_child(_ui_label)


func _process(_delta: float) -> void:
	# Track the line state, not panel.visible — the position update itself
	# hides the panel while the bubble is behind the camera, and gating on
	# visible would freeze it hidden once the player looks back.
	if _line_idx >= 0:
		_update_bubble_screen_pos()


func interact(_player: Node) -> void:
	_line_idx += 1
	if _line_idx >= _LINES.size():
		# Bit's over — hide the bubble. The next click restarts the cycle.
		_line_idx = -1
		_ui_panel.visible = false
		_ui_label.visible = false
		return
	_set_speech_text(_LINES[_line_idx])


func get_hint(_player: Node) -> String:
	return "Duck | LMB: talk"


func _set_speech_text(text: String) -> void:
	_ui_label.text = text
	_ui_label.visible = true
	# Size the panel to the label synchronously — _update_bubble_screen_pos
	# reads the panel size the same frame to center it.
	var label_size := _ui_label.get_combined_minimum_size()
	var pad := Vector2(8, 4)
	_ui_panel.size = label_size + pad * 2
	_ui_label.position = pad
	_ui_label.size = label_size
	_ui_panel.visible = true


func _update_bubble_screen_pos() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Float the bubble just above the duck.
	var bubble_pos := global_position + Vector3(0, 0.9, 0)
	if cam.is_position_behind(bubble_pos):
		_ui_panel.visible = false
		return
	_ui_panel.visible = true
	var screen_pos := cam.unproject_position(bubble_pos)
	# Scale the screen-space bubble with distance so it doesn't look
	# huge when the duck is far away.
	var dist := cam.global_position.distance_to(bubble_pos)
	var ui_scale := clampf(4.0 / dist, 0.25, 1.3)
	_ui_panel.scale = Vector2(ui_scale, ui_scale)
	var panel_size := _ui_panel.size * ui_scale
	_ui_panel.position = screen_pos - panel_size * 0.5

extends CanvasLayer
## Simple FPS counter shown in the bottom-left corner.
## Toggle with the F key.

var _label: Label
var _refresh_timer: float = 0.0


func _enter_tree() -> void:
	# Hide as early as possible so it never flashes on screen
	visible = false


func _ready() -> void:
	visible = false
	# Build the label programmatically since this is a CanvasLayer
	_label = Label.new()
	_label.anchors_preset = Control.PRESET_BOTTOM_LEFT
	_label.offset_left = 8
	_label.offset_top = -30
	_label.offset_right = 120
	_label.offset_bottom = -4
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1, 1, 0.4, 0.9))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	_label.text = "FPS: --"
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F:
			visible = not visible


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer += delta
	if _refresh_timer < 0.25:
		return
	_refresh_timer = 0.0
	var fps := Engine.get_frames_per_second()
	_label.text = "FPS: %d" % fps

extends Label
## Simple FPS counter shown in the bottom-left corner.
## Toggle with the F key.

var _refresh_timer: float = 0.0


func _enter_tree() -> void:
	# Hide as early as possible so it never flashes on screen
	visible = false


func _ready() -> void:
	visible = false
	# Position in the bottom-left corner
	anchors_preset = PRESET_BOTTOM_LEFT
	offset_left = 8
	offset_top = -30
	offset_right = 120
	offset_bottom = -4
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color", Color(1, 1, 0.4, 0.9))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 3)
	text = "FPS: --"


func _input(event: InputEvent) -> void:
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
	text = "FPS: %d" % fps

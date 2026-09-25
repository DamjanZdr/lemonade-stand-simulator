extends Control
## In-game debug console panel. Shows live log output from GameLog.
## Toggle with F12. Has a Copy button to copy all logs to clipboard.
## Has a Clear button to clear the buffer.

@onready var _panel: Panel = $Panel
@onready var _rich_label: RichTextLabel = $Panel/Margin/VBox/Scroll/RichLabel
@onready var _copy_button: Button = $Panel/Margin/Buttons/CopyButton
@onready var _clear_button: Button = $Panel/Margin/Buttons/ClearButton
@onready var _close_button: Button = $Panel/Margin/Buttons/CloseButton
@onready var _reset_achievements_button: Button = $Panel/Margin/Buttons/ResetAchievementsButton

var _visible: bool = false
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func _enter_tree() -> void:
	# Hide as early as possible so the panel never flashes on screen
	visible = false


func _ready() -> void:
	visible = false
	_panel.visible = false
	_copy_button.pressed.connect(_on_copy)
	_clear_button.pressed.connect(_on_clear)
	_close_button.pressed.connect(_on_close)
	_reset_achievements_button.pressed.connect(_on_reset_achievements)
	GameLog.log_added.connect(_on_log_added)
	# Pre-fill with existing buffer
	_rich_label.text = GameLog.get_buffer_text()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			if event.shift_pressed:
				AchievementManager.reset_all_achievements()
				return
			_toggle()


func _toggle() -> void:
	_visible = not _visible
	visible = _visible
	_panel.visible = _visible
	if _visible:
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# Scroll to bottom
		await get_tree().process_frame
		_rich_label.scroll_to_line(_rich_label.get_line_count() - 1)
	else:
		Input.mouse_mode = _previous_mouse_mode


func _on_log_added(_msg: String) -> void:
	_rich_label.text = GameLog.get_buffer_text()
	if _visible:
		_rich_label.scroll_to_line(_rich_label.get_line_count() - 1)


func _on_copy() -> void:
	GameLog.copy_to_clipboard()
	_copy_button.text = "Copied!"
	await get_tree().create_timer(1.0).timeout
	_copy_button.text = "Copy"


func _on_clear() -> void:
	GameLog.clear()
	_rich_label.text = ""


func _on_close() -> void:
	_visible = false
	visible = false
	_panel.visible = false
	Input.mouse_mode = _previous_mouse_mode


func _on_reset_achievements() -> void:
	AchievementManager.reset_all_achievements()

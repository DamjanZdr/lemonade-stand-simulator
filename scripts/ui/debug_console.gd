extends Control
## In-game debug console panel. Shows live log output from GameLog.
## Toggle with F12. Has a Copy button to copy all logs to clipboard.
## Has a Clear button to clear the buffer.

@onready var _panel: Panel = $Panel
@onready var _rich_label: RichTextLabel = $Panel/Margin/VBox/Scroll/RichLabel
@onready var _copy_button: Button = $Panel/Margin/Buttons/CopyButton
@onready var _clear_button: Button = $Panel/Margin/Buttons/ClearButton
@onready var _close_button: Button = $Panel/Margin/Buttons/CloseButton

var _visible: bool = false


func _ready() -> void:
	_panel.visible = false
	_copy_button.pressed.connect(_on_copy)
	_clear_button.pressed.connect(_on_clear)
	_close_button.pressed.connect(_on_close)
	GameLog.log_added.connect(_on_log_added)
	# Pre-fill with existing buffer
	_rich_label.text = GameLog.get_buffer_text()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			_visible = not _visible
			_panel.visible = _visible
			if _visible:
				# Scroll to bottom
				await get_tree().process_frame
				_rich_label.scroll_to_line(_rich_label.get_line_count() - 1)


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
	_panel.visible = false

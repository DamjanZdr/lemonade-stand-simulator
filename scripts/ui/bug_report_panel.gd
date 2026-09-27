extends Control
## Bug report popup. Collects severity + description + steps to reproduce and
## POSTs them to the project's Discord webhook. No account needed.

const WEBHOOK_URL := (
	"https://discord.com/api/webhooks/1553811409102438430/"
	+ "9YF81WnSIjmnt-nnli3AQ9GZxgt4lwMB-9io_c7-0dra6OtVtyuuSzdkD0w04MVSWBPp"
)
const MENU_THEME := preload("res://assets/themes/menu_theme.tres")
const FONT_GRANDSTANDER := preload("res://assets/fonts/Grandstander-clean.ttf")

const SEVERITIES: Array[String] = ["Cosmetic", "Minor", "Annoying", "Game Breaking"]
const SEVERITY_COLORS: Array[int] = [0x9AA0A6, 0x4A90D9, 0xE8862E, 0xD93636]
const FIELD_LIMIT := 950

var _severity_option: OptionButton
var _desc_edit: TextEdit
var _steps_edit: TextEdit
var _status_label: Label
var _submit_btn: Button
var _http: HTTPRequest
var _sending := false


func _ready() -> void:
	_build()
	if _desc_edit:
		_desc_edit.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = MENU_THEME

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.10, 0.14, 0.97)
	card_style.set_corner_radius_all(10)
	card_style.set_border_width_all(1)
	card_style.border_color = Color(1, 1, 1, 0.15)
	card_style.content_margin_left = 20
	card_style.content_margin_right = 20
	card_style.content_margin_top = 14
	card_style.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# Header row: title + close X.
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Report a Bug"
	title.add_theme_font_override("font", FONT_GRANDSTANDER)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 30)
	close_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	close_btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# Severity row.
	var sev_row := HBoxContainer.new()
	sev_row.add_theme_constant_override("separation", 12)
	vbox.add_child(sev_row)
	sev_row.add_child(_make_small_label("Severity"))
	_severity_option = OptionButton.new()
	_severity_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in SEVERITIES:
		_severity_option.add_item(s)
	_severity_option.selected = 1 # "Minor" default
	_style_option(_severity_option)
	sev_row.add_child(_severity_option)

	vbox.add_child(_make_small_label("What happened?"))
	_desc_edit = _make_text_edit(110, "Describe the bug…")
	vbox.add_child(_desc_edit)

	vbox.add_child(_make_small_label("Steps to reproduce (optional)"))
	_steps_edit = _make_text_edit(80, "1. Go to…\n2. Click…")
	vbox.add_child(_steps_edit)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(1, 0.6, 0.5, 0.9))
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	# Buttons row (right aligned).
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.flat = true
	cancel_btn.add_theme_font_size_override("font_size", 20)
	cancel_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	cancel_btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	cancel_btn.pressed.connect(close)
	btn_row.add_child(cancel_btn)

	_submit_btn = Button.new()
	_submit_btn.text = "Submit"
	_submit_btn.flat = true
	_submit_btn.add_theme_font_size_override("font_size", 20)
	_submit_btn.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1))
	_submit_btn.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.6, 1))
	_submit_btn.pressed.connect(_submit)
	btn_row.add_child(_submit_btn)

	_http = HTTPRequest.new()
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


func _make_small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	return l


func _make_text_edit(height: float, placeholder: String) -> TextEdit:
	var e := TextEdit.new()
	e.custom_minimum_size = Vector2(0, height)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	e.scroll_fit_content_height = false
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", FONT_GRANDSTANDER)
	e.add_theme_font_size_override("font_size", 16)
	e.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	e.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.35))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	e.add_theme_stylebox_override("normal", sb)
	var focus_sb := sb.duplicate() as StyleBoxFlat
	focus_sb.border_color = Color(1, 0.9, 0.3, 0.8)
	e.add_theme_stylebox_override("focus", focus_sb)
	return e


func _style_option(ob: OptionButton) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	ob.add_theme_stylebox_override("normal", sb)
	ob.add_theme_stylebox_override("hover", sb)
	ob.add_theme_stylebox_override("pressed", sb)
	ob.add_theme_font_override("font", FONT_GRANDSTANDER)
	ob.add_theme_font_size_override("font_size", 16)
	ob.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))


func close() -> void:
	queue_free()


func _submit() -> void:
	if _sending:
		return
	var desc := _desc_edit.text.strip_edges()
	if desc.length() < 5:
		_status_label.text = "Please describe the bug first."
		return
	_sending = true
	_submit_btn.disabled = true
	_status_label.text = "Sending…"
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))

	var severity := SEVERITIES[_severity_option.selected]
	var steps := _steps_edit.text.strip_edges()
	var fields: Array = [
		{ "name": "Description", "value": desc.left(FIELD_LIMIT) },
		{ "name": "Steps to Reproduce", "value": steps.left(FIELD_LIMIT) if steps != "" else "—" },
		{ "name": "Severity", "value": severity, "inline": true },
		{ "name": "Version", "value": _game_version(), "inline": true },
		{ "name": "Mode", "value": _game_mode(), "inline": true },
		{ "name": "Day", "value": str(DayManager.day_number), "inline": true },
		{ "name": "Platform", "value": _platform_info(), "inline": false },
	]
	var log_tail := _log_tail()
	if log_tail != "":
		fields.append({ "name": "Recent Log", "value": "```\n%s\n```" % log_tail })

	var payload := {
		"username": "Bug Reports",
		"embeds": [
			{
				"title": "Bug Report — %s" % severity,
				"color": SEVERITY_COLORS[_severity_option.selected],
				"fields": fields,
				"timestamp": Time.get_datetime_string_from_system(true, true),
			},
		],
	}
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _http.request(WEBHOOK_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_on_request_completed(
			HTTPRequest.RESULT_CANT_CONNECT,
			0,
			PackedStringArray(),
			PackedByteArray(),
		)


func _game_version() -> String:
	return "v" + String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func _game_mode() -> String:
	var keys := GameState.GameMode.keys()
	return keys[GameState.game_mode] if GameState.game_mode < keys.size() else "?"


func _platform_info() -> String:
	return "%s | %s" % [OS.get_name(), RenderingServer.get_video_adapter_name()]


func _log_tail() -> String:
	var buf := GameLog.get_buffer_text()
	if buf.is_empty():
		return ""
	return buf.right(900)


func _on_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray,
) -> void:
	_sending = false
	_submit_btn.disabled = false
	if response_code >= 200 and response_code < 300:
		_status_label.text = "Thanks! Report sent."
		_status_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6, 0.95))
		var tw := create_tween()
		tw.tween_interval(1.0)
		tw.tween_callback(queue_free)
	else:
		_status_label.text = (
			"Failed to send (HTTP %d). Try again or ping us on Discord." % response_code
		)
		_status_label.add_theme_color_override("font_color", Color(1, 0.6, 0.5, 0.9))

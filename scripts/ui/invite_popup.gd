extends CanvasLayer
## Steam lobby invite popup — appears when a friend invites you while the
## game is running (menu or in-game). One-line panel, top-right next to
## where onboarding sits. Yellow Accept, plain Decline, and a timer line
## that auto-dismisses after INVITE_TIMEOUT seconds.

const INVITE_TIMEOUT := 15.0

signal accepted(lobby_id: int)
signal declined

var _lobby_id: int = 0
var _time_left: float = INVITE_TIMEOUT
var _timer_bar: ColorRect = null
var _timer_track: Control = null


func _ready() -> void:
	layer = 200
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_time_left -= delta
	if _timer_bar and _timer_track:
		_timer_bar.size.x = _timer_track.size.x * (
			maxf(_time_left, 0.0) / INVITE_TIMEOUT
		)
	if _time_left <= 0.0:
		declined.emit()
		hide_popup()


func show_invite(lobby_id: int, friend_name: String) -> void:
	for c in get_children():
		c.queue_free()
	_lobby_id = lobby_id
	_time_left = INVITE_TIMEOUT

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(0, 24)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.15)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# One line: "Name invited you [Accept] [Decline]"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	vbox.add_child(row)

	var name_label := Label.new()
	name_label.text = "%s invited you to play" % friend_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var accept := Button.new()
	accept.text = "Accept"
	accept.add_theme_font_size_override("font_size", 18)
	accept.custom_minimum_size = Vector2(88, 34)
	var accept_style := StyleBoxFlat.new()
	accept_style.bg_color = Color(0.90, 0.78, 0.22, 1.0)
	accept_style.corner_radius_top_left = 6
	accept_style.corner_radius_top_right = 6
	accept_style.corner_radius_bottom_left = 6
	accept_style.corner_radius_bottom_right = 6
	accept_style.content_margin_left = 12
	accept_style.content_margin_right = 12
	accept.add_theme_stylebox_override("normal", accept_style)
	var accept_hover := accept_style.duplicate() as StyleBoxFlat
	accept_hover.bg_color = Color(1.0, 0.88, 0.35, 1.0)
	accept.add_theme_stylebox_override("hover", accept_hover)
	accept.add_theme_color_override("font_color", Color(0.12, 0.10, 0.05))
	accept.pressed.connect(_on_accept)
	row.add_child(accept)

	var decline := Button.new()
	decline.text = "Decline"
	decline.add_theme_font_size_override("font_size", 18)
	decline.custom_minimum_size = Vector2(88, 34)
	decline.pressed.connect(_on_decline)
	row.add_child(decline)

	# Timer line under the row.
	_timer_track = Control.new()
	_timer_track.custom_minimum_size = Vector2(0, 3)
	vbox.add_child(_timer_track)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.1)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	_timer_track.add_child(track)
	_timer_bar = ColorRect.new()
	_timer_bar.color = Color(0.90, 0.78, 0.22, 0.9)
	_timer_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_timer_bar.size = Vector2(0, 3)
	_timer_track.add_child(_timer_bar)

	visible = true


func hide_popup() -> void:
	visible = false


func _on_accept() -> void:
	accepted.emit(_lobby_id)
	hide_popup()


func _on_decline() -> void:
	declined.emit()
	hide_popup()

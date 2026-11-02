extends CanvasLayer
## Steam lobby invite popup — appears when a friend invites you while the
## game is running (menu or in-game). Yellow Accept, plain Decline, and a
## shrinking timer line that auto-dismisses after INVITE_TIMEOUT seconds.

const INVITE_TIMEOUT := 15.0

signal accepted(lobby_id: int)
signal declined

var _lobby_id: int = 0
var _time_left: float = INVITE_TIMEOUT
var _timer_bar: ColorRect = null


func _ready() -> void:
	layer = 200
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_time_left -= delta
	if _timer_bar:
		_timer_bar.size.x = _timer_bar.get_parent().size.x * (
			_time_left / INVITE_TIMEOUT
		)
	if _time_left <= 0.0:
		declined.emit()
		hide_popup()


## Show the invite for `lobby_id` from `friend_name`.
func show_invite(lobby_id: int, friend_name: String) -> void:
	# Clear any previous invite
	for c in get_children():
		c.queue_free()
	_lobby_id = lobby_id
	_time_left = INVITE_TIMEOUT

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(24, -24)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
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
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Game invite"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	box.add_child(title)

	var name_label := Label.new()
	name_label.text = "%s invited you to play" % friend_name
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	box.add_child(name_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	var accept := Button.new()
	accept.text = "Accept"
	accept.add_theme_font_size_override("font_size", 22)
	var accept_style := StyleBoxFlat.new()
	accept_style.bg_color = Color(0.90, 0.78, 0.22, 1.0)
	accept_style.corner_radius_top_left = 6
	accept_style.corner_radius_top_right = 6
	accept_style.corner_radius_bottom_left = 6
	accept_style.corner_radius_bottom_right = 6
	accept.add_theme_stylebox_override("normal", accept_style)
	var accept_hover := accept_style.duplicate() as StyleBoxFlat
	accept_hover.bg_color = Color(1.0, 0.88, 0.35, 1.0)
	accept.add_theme_stylebox_override("hover", accept_hover)
	accept.add_theme_color_override("font_color", Color(0.12, 0.10, 0.05))
	accept.pressed.connect(_on_accept)
	buttons.add_child(accept)

	var decline := Button.new()
	decline.text = "Decline"
	decline.add_theme_font_size_override("font_size", 22)
	decline.pressed.connect(_on_decline)
	buttons.add_child(decline)

	# Timer line — shrinks left-to-right over INVITE_TIMEOUT seconds.
	var timer_track := PanelContainer.new()
	timer_track.custom_minimum_size = Vector2(0, 4)
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color(1, 1, 1, 0.1)
	timer_track.add_theme_stylebox_override("panel", track_style)
	box.add_child(timer_track)
	_timer_bar = ColorRect.new()
	_timer_bar.color = Color(0.90, 0.78, 0.22, 0.9)
	_timer_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_timer_bar.size = Vector2(0, 4)
	timer_track.add_child(_timer_bar)

	visible = true


func hide_popup() -> void:
	visible = false


func _on_accept() -> void:
	accepted.emit(_lobby_id)
	hide_popup()


func _on_decline() -> void:
	declined.emit()
	hide_popup()

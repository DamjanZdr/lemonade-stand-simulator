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
	# The InviteTemplate mockup is an editor-positioning aid only.
	var tpl := (
		get_tree().current_scene.find_child("InviteTemplate", true, false)
		if get_tree().current_scene
		else null
	)
	if tpl:
		tpl.visible = false


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
	# Position comes from an "InviteAnchor" Control placed in the scene —
	# drag it in the editor to move the popup. Falls back to top-right.
	var anchor := (
		get_tree().current_scene.find_child("InviteAnchor", true, false)
		if get_tree().current_scene
		else null
	)
	if anchor is Control:
		# Anchor's top-left = the popup's top-left, in resolved screen px.
		# Read the global rect AFTER the panel is in the tree — before that
		# the anchor's own anchors may not have laid out yet.
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	else:
		panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		panel.position = Vector2(-24, 60)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var target_x := panel.position.x
	panel.position.x = target_x + 80
	panel.modulate = Color(1, 1, 1, 0)
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
	if anchor is Control:
		await get_tree().process_frame  # let anchors lay out
		var r := (anchor as Control).get_global_rect()
		panel.position = r.position
	target_x = panel.position.x
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "position:x", target_x, 0.25)
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)


func hide_popup() -> void:
	var panel: Control = get_children()[0] if get_child_count() > 0 else null
	if panel != null:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(panel, "position:x", panel.position.x + 80, 0.2)
		tw.tween_property(panel, "modulate:a", 0.0, 0.2)
		await tw.finished
	visible = false


func _on_accept() -> void:
	accepted.emit(_lobby_id)
	hide_popup()


func _on_decline() -> void:
	declined.emit()
	hide_popup()

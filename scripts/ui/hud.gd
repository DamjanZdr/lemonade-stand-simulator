extends CanvasLayer
## Shop-manager style HUD: money, day, time, popularity, and customers.

const AMATIC_FONT := preload("res://assets/fonts/AmaticSC-Bold.ttf")
const MOUSE_ICON := preload("res://assets/textures/ui/upgrades/mouse indicator.png")

const CIRCLE_SIZE := 120
const BAR_HEIGHT := 64
const MONEY_GAP := 12.0
const RIGHT_PAD := 12.0
const MONEY_MIN_WIDTH := 80.0
const ICON_SIZE := 24

@onready var _hint_label: Label = $HintLabel

var _hint_box: HBoxContainer
var _hint_container: VBoxContainer
var _contents_label: Label
var _mouse_icon_flipped: Texture2D

var _money_label: Label
var _day_label: Label
var _time_label: Label
var _temp_label: Label
var _day_progress: TextureProgressBar

var _main_style: StyleBoxFlat
var _circle_style: StyleBoxFlat
var _time_ring_under: ImageTexture
var _time_ring_progress: ImageTexture

var _main_panel: Control
var _bar: Panel
var _hbox: HBoxContainer
var _info_col: VBoxContainer
var _prev_money: float = 0.0
var _gain_label: Label = null

## Which stand's economy this HUD displays. Assigned by whatever wires up
## the player-to-stand relationship (main.gd in Stage A; later, whichever
## system assigns a local player to their controlled StandUnit). Money
## signals are connected here rather than to the global EventBus, so this
## HUD only ever reacts to its own stand's money — never another stand's.
var _stand: StandUnit = null


func _ready() -> void:
	add_to_group("hud")
	_create_flipped_icon()
	_build_hint_box()
	_build_styles()
	_build_ui()
	_build_version_label()
	_remove_legacy()
	_connect_signals()
	_refresh()


func _build_version_label() -> void:
	var label := Label.new()
	label.name = "VersionLabel"
	label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.0.0")
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left = -90.0
	label.offset_top = -24.0
	label.offset_right = -8.0
	label.offset_bottom = -6.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(label)


func _on_money(value: float) -> void:
	if value > _prev_money:
		EventBus.interaction_hint_changed.emit("")
		_show_money_gain(value - _prev_money, value)
	else:
		_money_label.text = "$%.2f" % value
		_update_hud_size()
	_prev_money = value


func _update_hud_size() -> void:
	if _money_label == null or _hbox == null:
		return
	var money_w := _money_label.get_combined_minimum_size().x
	if money_w <= 0.0:
		money_w = AMATIC_FONT.get_string_size(_money_label.text, HORIZONTAL_ALIGNMENT_LEFT, 32).x
	var info_w := maxf(MONEY_MIN_WIDTH, money_w + 4.0)
	_info_col.custom_minimum_size = Vector2(info_w, 0)
	var hbox_w := CIRCLE_SIZE + MONEY_GAP + info_w + RIGHT_PAD
	var hbox_h := float(CIRCLE_SIZE)
	_hbox.offset_right = hbox_w
	_hbox.offset_bottom = hbox_h
	_bar.offset_left = float(CIRCLE_SIZE) / 2.0
	_bar.offset_top = (hbox_h - float(BAR_HEIGHT)) * 0.5
	_bar.offset_right = hbox_w
	_bar.offset_bottom = _bar.offset_top + float(BAR_HEIGHT)
	_main_panel.offset_right = 10.0 + hbox_w
	_main_panel.offset_bottom = 10.0 + hbox_h


func _on_weather(temp: float) -> void:
	_temp_label.text = "%.0f°C" % temp


func _on_hint(hint: String) -> void:
	_hint_label.text = ""
	_contents_label.text = ""
	for child in _hint_box.get_children():
		child.queue_free()
	if hint == "":
		return
	# Split off contents line (before \n) if present
	var hint_line := hint
	var newline_idx := hint.find("\n")
	if newline_idx >= 0:
		_contents_label.text = hint.substr(0, newline_idx)
		hint_line = hint.substr(newline_idx + 1)
	var parts := hint_line.split("|", true)
	for i in range(parts.size()):
		var part := parts[i].strip_edges()
		if i > 0:
			_add_hint_text("  |  ")
		if part.begins_with("LMB:"):
			_add_mouse_icon(false)
			_add_hint_text(part.substr(4).strip_edges())
		elif part.begins_with("RMB:"):
			_add_mouse_icon(true)
			_add_hint_text(part.substr(4).strip_edges())
		else:
			_add_hint_text(part)


func _on_day_phase_changed(_phase: int, day: int) -> void:
	_day_label.text = "Day %d" % day


func _on_day_timer_updated(time_left: float, total_time: float) -> void:
	if total_time <= 0.0:
		return
	var t := clampf(1.0 - (time_left / total_time), 0.0, 1.0)
	_day_progress.value = t
	# Map 0→1 to 9:00 → 18:00 (9-hour workday)
	var total_minutes: float = 9.0 * 60.0 + t * 9.0 * 60.0
	var hour: int = int(total_minutes / 60.0)
	var minute: int = int(total_minutes) % 60
	var ampm := "AM" if hour < 12 else "PM"
	var display_hour: int = hour if hour <= 12 else hour - 12
	if display_hour == 0:
		display_hour = 12
	_time_label.text = "%d:%02d %s" % [display_hour, minute, ampm]


func _build_styles() -> void:
	_main_style = StyleBoxFlat.new()
	_main_style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	_main_style.corner_radius_top_left = 0
	_main_style.corner_radius_top_right = 10
	_main_style.corner_radius_bottom_left = 0
	_main_style.corner_radius_bottom_right = 10

	_circle_style = StyleBoxFlat.new()
	_circle_style.bg_color = Color(0.08, 0.08, 0.12, 1.0)
	_circle_style.corner_radius_top_left = 60
	_circle_style.corner_radius_top_right = 60
	_circle_style.corner_radius_bottom_left = 60
	_circle_style.corner_radius_bottom_right = 60

	_time_ring_under = _create_ring_texture(120, 8.0, Color(0.25, 0.25, 0.25, 0.85))
	_time_ring_progress = _create_ring_texture(120, 8.0, Color(0.95, 0.75, 0.15, 0.95))


func _build_ui() -> void:
	var font: Font = AMATIC_FONT

	# Top-left control: circular clock with a bar emerging from behind it
	_main_panel = Control.new()
	_main_panel.name = "MainPanel"
	_main_panel.anchors_preset = Control.PRESET_TOP_LEFT
	_main_panel.anchor_left = 0.0
	_main_panel.anchor_top = 0.0
	_main_panel.anchor_right = 0.0
	_main_panel.anchor_bottom = 0.0
	_main_panel.offset_left = 10.0
	_main_panel.offset_top = 10.0
	_main_panel.offset_right = 10.0
	_main_panel.offset_bottom = 10.0
	_main_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_main_panel.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_main_panel)

	# Shorter bar behind the circle, centered vertically
	_bar = Panel.new()
	_bar.name = "Bar"
	_bar.add_theme_stylebox_override("panel", _main_style)
	_main_panel.add_child(_bar)

	# Content row: circle on the left, money on the right
	_hbox = HBoxContainer.new()
	_hbox.add_theme_constant_override("separation", 0)
	_main_panel.add_child(_hbox)

	# Circular clock face
	var time_circle := Panel.new()
	time_circle.name = "TimeCircle"
	time_circle.custom_minimum_size = Vector2(CIRCLE_SIZE, CIRCLE_SIZE)
	time_circle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	time_circle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_circle.add_theme_stylebox_override("panel", _circle_style)
	_hbox.add_child(time_circle)

	_day_progress = TextureProgressBar.new()
	_day_progress.anchors_preset = Control.PRESET_FULL_RECT
	_day_progress.min_value = 0.0
	_day_progress.max_value = 1.0
	_day_progress.step = 0.001
	_day_progress.value = 0.0
	_day_progress.texture_under = _time_ring_under
	_day_progress.texture_progress = _time_ring_progress
	_day_progress.radial_initial_angle = 270.0
	_day_progress.radial_fill_degrees = 360.0
	_day_progress.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	time_circle.add_child(_day_progress)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)
	time_circle.add_child(center)

	var time_vbox := VBoxContainer.new()
	time_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	time_vbox.add_theme_constant_override("separation", 0)
	center.add_child(time_vbox)

	_day_label = _make_label("Day 1", 14, font)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	time_vbox.add_child(_day_label)

	_time_label = _make_label("9:00 AM", 26, font, Color(1.0, 0.95, 0.7))
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	time_vbox.add_child(_time_label)

	_temp_label = _make_label("25°C", 14, font, Color(0.65, 0.85, 1.0))
	_temp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_temp_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	time_vbox.add_child(_temp_label)

	# Spacer between the circle and the money
	var left_spacer := Control.new()
	left_spacer.custom_minimum_size = Vector2(MONEY_GAP, 0)
	left_spacer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hbox.add_child(left_spacer)

	# Money to the right of the circle
	_info_col = VBoxContainer.new()
	_info_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	_info_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_info_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_info_col.custom_minimum_size = Vector2(MONEY_MIN_WIDTH, 0)
	_hbox.add_child(_info_col)

	# Placeholder until set_stand() assigns a real stand and refreshes this.
	_money_label = _make_label("$%.2f" % 0.0, 32, font, Color(0.25, 0.95, 0.35))
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_info_col.add_child(_money_label)

	# Small right padding that stays fixed while the money area grows
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(RIGHT_PAD, 0)
	tail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hbox.add_child(tail)

	_update_hud_size()


func _make_label(text: String, size: int, font: Font, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _create_ring_texture(size: int, thickness: float, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var center := Vector2(size * 0.5, size * 0.5)
	var outer := float(size) * 0.5
	var inner := outer - thickness
	var edge := 0.8
	for y in range(size):
		for x in range(size):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var a: float
			if d < inner - edge:
				a = 0.0
			elif d < inner + edge:
				a = (d - (inner - edge)) / (2.0 * edge)
			elif d < outer - edge:
				a = 1.0
			elif d < outer + edge:
				a = 1.0 - (d - (outer - edge)) / (2.0 * edge)
			else:
				a = 0.0
			img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _remove_legacy() -> void:
	var legacy := $VBox
	if legacy:
		legacy.queue_free()
	var legacy_time := $TimeLabel
	if legacy_time:
		legacy_time.queue_free()


func _create_flipped_icon() -> void:
	var img := MOUSE_ICON.get_image()
	var flipped := img.duplicate()
	flipped.flip_x()
	_mouse_icon_flipped = ImageTexture.create_from_image(flipped)


func _build_hint_box() -> void:
	_hint_container = VBoxContainer.new()
	_hint_container.name = "HintContainer"
	_hint_container.anchor_left = 0.0
	_hint_container.anchor_top = 1.0
	_hint_container.anchor_right = 1.0
	_hint_container.anchor_bottom = 1.0
	_hint_container.offset_left = 20.0
	_hint_container.offset_top = -70.0
	_hint_container.offset_right = -20.0
	_hint_container.offset_bottom = -30.0
	_hint_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_container)

	_contents_label = Label.new()
	_contents_label.name = "ContentsLabel"
	_contents_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_contents_label.add_theme_font_override("font", AMATIC_FONT)
	_contents_label.add_theme_font_size_override("font_size", 22)
	_contents_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.85))
	_contents_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_contents_label.add_theme_constant_override("shadow_offset_x", 1)
	_contents_label.add_theme_constant_override("shadow_offset_y", 1)
	_contents_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_container.add_child(_contents_label)

	_hint_box = HBoxContainer.new()
	_hint_box.name = "HintBox"
	_hint_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_container.add_child(_hint_box)
	_hint_label.visible = false


func _add_mouse_icon(flipped: bool) -> void:
	var icon_h := 22
	var icon_w := int(
		float(icon_h) * float(MOUSE_ICON.get_width()) / float(MOUSE_ICON.get_height())
	)
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(icon_w, icon_h)
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow := TextureRect.new()
	shadow.texture = _mouse_icon_flipped if flipped else MOUSE_ICON
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.position = Vector2(1, 1)
	shadow.size = Vector2(icon_w, icon_h)
	shadow.modulate = Color(0, 0, 0, 0.7)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(shadow)
	var tex := TextureRect.new()
	tex.texture = _mouse_icon_flipped if flipped else MOUSE_ICON
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.size = Vector2(icon_w, icon_h)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(tex)
	_hint_box.add_child(wrapper)


func _add_hint_text(text: String) -> void:
	if text == "":
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", AMATIC_FONT)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	_hint_box.add_child(lbl)


func _connect_signals() -> void:
	# Shared/global — the same for every stand (one day cycle, one weather).
	EventBus.day_timer_updated.connect(_on_day_timer_updated)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.weather_changed.connect(_on_weather)
	EventBus.interaction_hint_changed.connect(_on_hint)


## Assigns which stand this HUD displays and hooks up its per-stand money
## signal. Call this once the local player's controlled stand is known
## (main.gd does this right after finding/creating the StandUnit).
func set_stand(stand: StandUnit) -> void:
	if _stand and _stand.money_changed.is_connected(_on_money):
		_stand.money_changed.disconnect(_on_money)
	_stand = stand
	if _stand == null:
		return
	_stand.money_changed.connect(_on_money)
	_prev_money = _stand.money
	_on_money(_stand.money)


func _show_money_gain(amount: float, new_total: float) -> void:
	if _main_panel == null:
		return
	# Replace existing gain label if a new income event comes in.
	if _gain_label != null and is_instance_valid(_gain_label):
		_gain_label.queue_free()
	# +$X.XX pops in to the right of the money, holds, then fades.
	# Matches the money label's font size and style.
	_gain_label = _make_label("+$%.2f" % amount, 32, AMATIC_FONT, Color(0.3, 1.0, 0.4))
	_gain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_gain_label.modulate.a = 0.0
	_gain_label.scale = Vector2.ZERO
	# Position right after the money panel edge, same vertical position.
	var money_pos := _money_label.global_position - _main_panel.global_position
	_gain_label.position = Vector2(_main_panel.size.x + 12.0, money_pos.y)
	_main_panel.add_child(_gain_label)
	var gt := create_tween()
	gt.set_parallel(true)
	gt.tween_property(_gain_label, "modulate:a", 1.0, 0.1)
	gt.tween_property(_gain_label, "scale", Vector2(1.3, 1.3), 0.15).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	gt \
			.chain() \
			.tween_property(_gain_label, "scale", Vector2.ONE, 0.1) \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)
	gt.chain().tween_interval(0.3)
	gt.chain().tween_property(_gain_label, "modulate:a", 0.0, 0.4)
	gt.chain().tween_callback(_gain_label.queue_free)
	# Money label: count up after +x fades, no zoom.
	var old_val := _prev_money
	_money_label.text = "$%.2f" % old_val
	var mt := create_tween()
	mt.tween_interval(0.5)
	mt.tween_method(
		func(t: float) -> void:
			_money_label.text = "$%.2f" % lerpf(old_val, new_total, t),
		0.0,
		1.0,
		0.4,
	)
	mt.tween_callback(
		func() -> void:
			_money_label.text = "$%.2f" % new_total
			_update_hud_size(),
	)


func _refresh() -> void:
	# Money is refreshed separately in set_stand() once a stand is assigned.
	_on_weather(GameState.temperature)
	_on_day_phase_changed(DayManager.current_phase, DayManager.day_number)


func set_hud_visible(vis: bool) -> void:
	if _main_panel:
		_main_panel.visible = vis
	if _hint_box:
		_hint_box.visible = vis

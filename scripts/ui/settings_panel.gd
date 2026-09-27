extends Control
## Left-area settings page matching the main/ESC menu design.

const MENU_THEME := preload("res://assets/themes/menu_theme.tres")

signal back_pressed
signal fullscreen_toggled(enabled: bool)
signal vsync_toggled(enabled: bool)
signal enhanced_lighting_toggled(enabled: bool)
signal fps_toggled(enabled: bool)

const _TAB_NAMES: Array[String] = ["Gameplay", "Graphics", "Audio"]

var _tab_buttons: Array[Button] = []
var _tab_contents: Array[Control] = []
var _active_tab: int = 0

var _master_slider: HSlider
var _master_value: Label
var _sfx_slider: HSlider
var _sfx_value: Label
var _music_slider: HSlider
var _music_value: Label

var _quality_option: OptionButton
var _fs_check: CheckBox
var _vsync_check: CheckBox
var _lighting_check: CheckBox
var _fps_check: CheckBox

var _autosave_slider: HSlider
var _autosave_value: Label
var _sens_slider: HSlider
var _sens_value: Label
var _fov_slider: HSlider
var _fov_value: Label


func _ready() -> void:
	_build_ui()
	sync_state()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var list := VBoxContainer.new()
	list.name = "SettingsList"
	list.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	list.offset_left = 60.0
	list.offset_top = 80.0
	list.offset_right = 400.0
	list.offset_bottom = -80.0
	list.grow_vertical = Control.GROW_DIRECTION_BOTH
	list.theme = MENU_THEME
	list.add_theme_constant_override("separation", 8)
	add_child(list)

	var title := Label.new()
	title.name = "Title"
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	list.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	list.add_child(spacer)

	# Tabs row like the lobby (Gameplay | Graphics | Audio).
	var tabs_row := HBoxContainer.new()
	tabs_row.name = "TabsRow"
	tabs_row.add_theme_constant_override("separation", 8)
	list.add_child(tabs_row)

	for i in range(_TAB_NAMES.size()):
		var tab := Button.new()
		tab.name = _TAB_NAMES[i] + "Tab"
		tab.text = _TAB_NAMES[i]
		tab.flat = true
		tab.add_theme_font_size_override("font_size", 26)
		tab.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		tab.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
		tab.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_make_flat_button(tab)
		_setup_hover_effect(tab)
		_tab_buttons.append(tab)
		tabs_row.add_child(tab)
		tab.pressed.connect(
			func():
				AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
				_set_tab(i),
		)

		if i < _TAB_NAMES.size() - 1:
			var divider := ColorRect.new()
			divider.custom_minimum_size = Vector2(2, 20)
			divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			divider.color = Color(1, 1, 1, 0.25)
			tabs_row.add_child(divider)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 4)
	list.add_child(spacer2)

	# Content container that holds the three category panels.
	var content := Control.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(content)

	var gameplay_tab := _build_gameplay_tab()
	content.add_child(gameplay_tab)
	_tab_contents.append(gameplay_tab)

	var graphics_tab := _build_graphics_tab()
	content.add_child(graphics_tab)
	_tab_contents.append(graphics_tab)

	var audio_tab := _build_audio_tab()
	content.add_child(audio_tab)
	_tab_contents.append(audio_tab)

	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 48)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.add_theme_font_size_override("font_size", 38)
	back.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	back.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.pressed.connect(
		func():
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
			back_pressed.emit(),
	)
	list.add_child(back)
	_make_flat_button(back)
	_setup_hover_effect(back)

	_set_tab(0)


func _set_tab(index: int) -> void:
	_active_tab = index
	for i in range(_tab_buttons.size()):
		var active := i == index
		_tab_buttons[i].add_theme_color_override(
			"font_color",
			Color(1, 0.9, 0.3, 1.0) if active else Color(1, 1, 1, 0.7),
		)
		_tab_contents[i].visible = active


func _build_audio_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Audio"
	tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.add_theme_constant_override("separation", 10)

	var master := _add_slider_row(tab, "Master")
	_master_slider = master[0] as HSlider
	_master_value = master[1] as Label
	_master_slider.value_changed.connect(
		func(v: float):
			AudioServer.set_bus_volume_db(0, linear_to_db(v))
			_master_value.text = "%d" % int(round(v * 100)),
	)
	_master_slider.drag_ended.connect(_save_audio)

	var sfx := _add_slider_row(tab, "SFX")
	_sfx_slider = sfx[0] as HSlider
	_sfx_value = sfx[1] as Label
	_sfx_slider.value_changed.connect(
		func(v: float):
			if AudioServer.get_bus_count() > 1:
				AudioServer.set_bus_volume_db(1, linear_to_db(v))
			_sfx_value.text = "%d" % int(round(v * 100)),
	)
	_sfx_slider.drag_ended.connect(
		func(_changed: bool):
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
			_save_audio(),
	)

	var music := _add_slider_row(tab, "Music")
	_music_slider = music[0] as HSlider
	_music_value = music[1] as Label
	_music_slider.value_changed.connect(
		func(v: float):
			if AudioServer.get_bus_count() > 2:
				AudioServer.set_bus_volume_db(2, linear_to_db(v))
			_music_value.text = "%d" % int(round(v * 100)),
	)
	_music_slider.drag_ended.connect(
		func(_changed: bool):
			AudioManager.play_sfx_ui("blip_select", 1.0, 0.0)
			_save_audio(),
	)

	return tab


func _build_graphics_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Graphics"
	tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.add_theme_constant_override("separation", 10)

	var q_row := HBoxContainer.new()
	q_row.add_theme_constant_override("separation", 12)
	tab.add_child(q_row)

	var q_label := Label.new()
	q_label.custom_minimum_size = Vector2(120, 0)
	q_label.add_theme_font_size_override("font_size", 18)
	q_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	q_label.text = "Quality"
	q_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	q_row.add_child(q_label)

	_quality_option = OptionButton.new()
	_quality_option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_quality_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_quality_option.custom_minimum_size = Vector2(120, 0)
	for q in ["Epic", "High", "Medium", "Low"]:
		_quality_option.add_item(q)
	_style_option_button(_quality_option)
	_quality_option.item_selected.connect(
		func(_idx: int):
			var q := _quality_option.get_item_text(_idx).to_lower()
			SettingsManager.set_graphics_quality(q)
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03),
	)
	q_row.add_child(_quality_option)

	_fs_check = _add_checkbox_row(tab, "Fullscreen")
	_fs_check.toggled.connect(
		func(on: bool):
			fullscreen_toggled.emit(on)
			SettingsManager.save_settings(),
	)

	_vsync_check = _add_checkbox_row(tab, "VSync")
	_vsync_check.toggled.connect(
		func(on: bool):
			vsync_toggled.emit(on)
			SettingsManager.save_settings(),
	)

	_lighting_check = _add_checkbox_row(tab, "Enhanced Lighting")
	_lighting_check.toggled.connect(
		func(on: bool):
			enhanced_lighting_toggled.emit(on)
			SettingsManager.save_graphics_bool("enhanced_lighting", on),
	)

	_fps_check = _add_checkbox_row(tab, "Show FPS")
	_fps_check.toggled.connect(
		func(on: bool):
			fps_toggled.emit(on)
			SettingsManager.save_graphics_bool("fps_counter", on),
	)

	return tab


func _build_gameplay_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Gameplay"
	tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.add_theme_constant_override("separation", 10)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab.add_child(row)

	var label := Label.new()
	label.custom_minimum_size = Vector2(120, 0)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	label.text = "Autosave"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	_autosave_slider = HSlider.new()
	_autosave_slider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_autosave_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_autosave_slider.custom_minimum_size = Vector2(140, 24)
	_autosave_slider.min_value = SettingsManager.AUTOSAVE_MIN_MINUTES
	_autosave_slider.max_value = SettingsManager.AUTOSAVE_MAX_MINUTES
	_autosave_slider.step = 1.0
	_autosave_slider.value = SettingsManager.get_autosave_minutes()
	_style_slider(_autosave_slider)
	row.add_child(_autosave_slider)

	_autosave_value = Label.new()
	_autosave_value.custom_minimum_size = Vector2(60, 0)
	_autosave_value.add_theme_font_size_override("font_size", 16)
	_autosave_value.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_autosave_value.text = "%d min" % int(_autosave_slider.value)
	_autosave_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_autosave_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_autosave_value)

	_autosave_slider.value_changed.connect(
		func(v: float):
			_autosave_value.text = "%d min" % int(v),
	)
	_autosave_slider.drag_ended.connect(
		func(_changed: bool):
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
			SettingsManager.set_autosave_minutes(_autosave_slider.value)
			SaveManager.set_autosave_interval(_autosave_slider.value),
	)

	var sens := _add_slider_row(tab, "Sensitivity")
	_sens_slider = sens[0] as HSlider
	_sens_value = sens[1] as Label
	_sens_slider.min_value = SettingsManager.MOUSE_SENSITIVITY_MIN
	_sens_slider.max_value = SettingsManager.MOUSE_SENSITIVITY_MAX
	_sens_slider.step = 0.05
	_sens_slider.value = SettingsManager.get_mouse_sensitivity()
	_sens_value.text = "%.2f" % _sens_slider.value
	_sens_slider.value_changed.connect(
		func(v: float):
			_sens_value.text = "%.2f" % v
			SettingsManager.set_mouse_sensitivity(v, false),
	)
	_sens_slider.drag_ended.connect(
		func(_changed: bool):
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
			SettingsManager.set_mouse_sensitivity(_sens_slider.value),
	)

	var fov := _add_slider_row(tab, "FOV")
	_fov_slider = fov[0] as HSlider
	_fov_value = fov[1] as Label
	_fov_slider.min_value = SettingsManager.FOV_MIN
	_fov_slider.max_value = SettingsManager.FOV_MAX
	_fov_slider.step = 1.0
	_fov_slider.value = SettingsManager.get_fov()
	_fov_value.text = "%d" % int(_fov_slider.value)
	_fov_slider.value_changed.connect(
		func(v: float):
			_fov_value.text = "%d" % int(v)
			SettingsManager.set_fov(v, false),
	)
	_fov_slider.drag_ended.connect(
		func(_changed: bool):
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
			SettingsManager.set_fov(_fov_slider.value),
	)

	return tab


func sync_state() -> void:
	var master_val := db_to_linear(AudioServer.get_bus_volume_db(0))
	_master_slider.value = master_val
	_master_value.text = "%d" % int(round(master_val * 100))

	var sfx_val := 1.0
	if AudioServer.get_bus_count() > 1:
		sfx_val = db_to_linear(AudioServer.get_bus_volume_db(1))
	_sfx_slider.value = sfx_val
	_sfx_value.text = "%d" % int(round(sfx_val * 100))

	var music_val := 1.0
	if AudioServer.get_bus_count() > 2:
		music_val = db_to_linear(AudioServer.get_bus_volume_db(2))
	_music_slider.value = music_val
	_music_value.text = "%d" % int(round(music_val * 100))

	_fs_check.button_pressed = (
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	)
	_vsync_check.button_pressed = (
		DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	)
	_lighting_check.button_pressed = SettingsManager.get_graphics_bool(
		"enhanced_lighting",
		SettingsManager.DEFAULT_ENHANCED_LIGHTING,
	)
	_fps_check.button_pressed = SettingsManager.get_graphics_bool(
		"fps_counter",
		SettingsManager.DEFAULT_FPS_COUNTER,
	)
	_autosave_slider.value = SettingsManager.get_autosave_minutes()
	_autosave_value.text = "%d min" % int(_autosave_slider.value)
	_sens_slider.value = SettingsManager.get_mouse_sensitivity()
	_sens_value.text = "%.2f" % _sens_slider.value
	_fov_slider.value = SettingsManager.get_fov()
	_fov_value.text = "%d" % int(_fov_slider.value)

	var quality := SettingsManager.get_graphics_quality()
	for i in range(_quality_option.item_count):
		if _quality_option.get_item_text(i).to_lower() == quality:
			_quality_option.select(i)
			break


func _add_slider_row(parent: Node, label_text: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)

	var label := Label.new()
	label.custom_minimum_size = Vector2(120, 0)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(140, 24)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.5
	_style_slider(slider)
	row.add_child(slider)

	var value := Label.new()
	value.custom_minimum_size = Vector2(40, 0)
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	value.text = "%d" % int(round(slider.value * 100))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)

	return [slider, value]


func _add_checkbox_row(parent: Node, label_text: String) -> CheckBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.custom_minimum_size = Vector2(120, 0)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	var cb := CheckBox.new()
	cb.custom_minimum_size = Vector2(24, 24)
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_checkbox(cb)
	row.add_child(cb)
	return cb


func _style_slider(slider: HSlider) -> void:
	slider.add_theme_constant_override("center_grabber", 1)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.set_corner_radius_all(3)
	track.content_margin_top = 6.0
	track.content_margin_bottom = 6.0
	slider.add_theme_stylebox_override("slider", track)

	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 0.85, 0.2, 0.9)
	grab.set_corner_radius_all(6)
	grab.content_margin_top = 6.0
	grab.content_margin_bottom = 6.0
	slider.add_theme_stylebox_override("grabber_area", grab)
	slider.add_theme_stylebox_override("grabber_area_highlight", grab)


func _style_checkbox(cb: CheckBox) -> void:
	cb.theme = Theme.new()
	var make_sb := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(1)
		s.content_margin_left = 6
		s.content_margin_right = 6
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		s.set_corner_radius_all(2)
		return s
	cb.add_theme_stylebox_override("normal", make_sb.call(Color(0, 0, 0, 0), Color(1, 1, 1, 0.4)))
	cb.add_theme_stylebox_override("hover", make_sb.call(Color(0, 0, 0, 0), Color(1, 1, 1, 0.8)))
	cb.add_theme_stylebox_override(
		"pressed",
		make_sb.call(Color(1, 1, 1, 0.1), Color(1, 1, 1, 1.0)),
	)
	cb.add_theme_stylebox_override(
		"checked",
		make_sb.call(Color(1, 0.95, 0.7, 0.15), Color(1, 0.95, 0.7, 1.0)),
	)
	cb.add_theme_stylebox_override(
		"hover_pressed",
		make_sb.call(Color(1, 0.95, 0.7, 0.15), Color(1, 0.95, 0.7, 1.0)),
	)
	cb.add_theme_stylebox_override(
		"hover_checked",
		make_sb.call(Color(1, 0.95, 0.7, 0.2), Color(1, 0.95, 0.7, 1.0)),
	)
	cb.add_theme_stylebox_override(
		"pressed_checked",
		make_sb.call(Color(1, 0.95, 0.7, 0.1), Color(1, 0.95, 0.7, 1.0)),
	)
	cb.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	cb.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))


func _style_option_button(ob: OptionButton) -> void:
	ob.theme = Theme.new()
	var make_sb := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(1)
		s.content_margin_left = 8
		s.content_margin_right = 8
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		s.set_corner_radius_all(3)
		return s
	ob.add_theme_stylebox_override("normal", make_sb.call(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.4)))
	ob.add_theme_stylebox_override(
		"hover",
		make_sb.call(Color(0, 0, 0, 0.4), Color(1, 0.95, 0.7, 0.8)),
	)
	ob.add_theme_stylebox_override(
		"pressed",
		make_sb.call(Color(0, 0, 0, 0.5), Color(1, 0.95, 0.7, 1.0)),
	)
	ob.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	ob.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	ob.add_theme_font_size_override("font_size", 18)


func _make_flat_button(btn: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, empty)


func _setup_hover_effect(btn: Button) -> void:
	btn.pivot_offset = btn.size * 0.5
	btn.mouse_entered.connect(
		func():
			var tw := create_tween()
			tw.tween_property(btn, "scale", Vector2(1.12, 1.12), 0.18)
			tw.parallel().tween_property(btn, "modulate", Color(1.15, 1.15, 1.15, 1.0), 0.18),
	)
	btn.mouse_exited.connect(
		func():
			var tw := create_tween()
			tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.18)
			tw.parallel().tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.18),
	)


func _save_audio() -> void:
	SettingsManager.save_settings()

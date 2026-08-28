extends CanvasLayer
## In-game ESC menu overlay. Same blur + darken style as the main menu.
## Buttons: Back to Game, Settings, Invite, Back to Menu, Quit Game.
## Lobby code row with eye toggle + copy button.

signal back_to_game
signal back_to_menu
signal quit_game
signal settings_pressed
signal settings_back
signal fullscreen_toggled(enabled: bool)
signal vsync_toggled(enabled: bool)
signal enhanced_lighting_toggled(enabled: bool)
signal fps_toggled(enabled: bool)

const HOVER_POP: float = 1.12
const HOVER_DURATION: float = 0.18

var _blur_panel: ColorRect
var _dim_layer: ColorRect
var _menu_box: VBoxContainer
var _back_button: Button
var _settings_button: Button
var _invite_button: Button
var _back_to_menu_button: Button
var _quit_button: Button
var _settings_panel: Control
var _settings_back: Button
var _room_row: HBoxContainer
var _eye_button: Button
var _room_code_label: Label
var _copy_button: Button
var _menu_buttons: Array[Button] = []
var _room_visible: bool = false


func _ready() -> void:
	layer = 60
	visible = false
	_build_ui()


func _build_ui() -> void:
	# BackBufferCopy needed for the blur shader to read the screen.
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)

	# Blur panel (left side, same as main menu).
	var blur_shader := load("res://shaders/ui_blur.gdshader") as Shader
	_blur_panel = ColorRect.new()
	_blur_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blur_mat := ShaderMaterial.new()
	blur_mat.shader = blur_shader
	blur_mat.set_shader_parameter("blur_radius", 12.0)
	blur_mat.set_shader_parameter("fade_start", 0.35)
	_blur_panel.material = blur_mat
	_blur_panel.color = Color(0, 0, 0, 0)
	add_child(_blur_panel)

	# Dim layer (left side, same as main menu).
	var dim_shader := load("res://shaders/ui_dim_fade.gdshader") as Shader
	_dim_layer = ColorRect.new()
	_dim_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim_mat := ShaderMaterial.new()
	dim_mat.shader = dim_shader
	dim_mat.set_shader_parameter("dim_color", Color(0, 0, 0, 0.35))
	dim_mat.set_shader_parameter("fade_start", 0.35)
	_dim_layer.material = dim_mat
	_dim_layer.color = Color(0, 0, 0, 0)
	add_child(_dim_layer)

	# Menu box (left-aligned, same layout as main menu).
	_menu_box = VBoxContainer.new()
	_menu_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_box.offset_left = 60.0
	_menu_box.offset_top = 80.0
	_menu_box.offset_right = 400.0
	_menu_box.offset_bottom = -80.0
	_menu_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var theme := load("res://assets/themes/menu_theme.tres") as Theme
	_menu_box.theme = theme
	_menu_box.add_theme_constant_override("separation", 4)
	add_child(_menu_box)

	# Title.
	var title := Label.new()
	title.text = "Menu"
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.add_theme_color_override("shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 6)
	_menu_box.add_child(title)

	# Spacer.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	_menu_box.add_child(spacer)

	# Buttons.
	_back_button = _make_menu_button("Resume")
	_menu_box.add_child(_back_button)

	_settings_button = _make_menu_button("Settings")
	_menu_box.add_child(_settings_button)

	_back_to_menu_button = _make_menu_button("Main Menu")
	_menu_box.add_child(_back_to_menu_button)

	_quit_button = _make_menu_button("Quit Game")
	_menu_box.add_child(_quit_button)

	# Spacer before room code.
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 16)
	_menu_box.add_child(spacer2)

	# Separator.
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sep.color = Color(0.35, 0.6, 0.9, 0.25)
	_menu_box.add_child(sep)

	# Spacer.
	var spacer3 := Control.new()
	spacer3.custom_minimum_size = Vector2(0, 8)
	_menu_box.add_child(spacer3)

	# Room code row (below the menu buttons).
	_room_row = HBoxContainer.new()
	_room_row.add_theme_constant_override("separation", 6)
	_menu_box.add_child(_room_row)

	_eye_button = Button.new()
	_eye_button.custom_minimum_size = Vector2(24, 24)
	_eye_button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	_eye_button.add_theme_font_size_override("font_size", 18)
	_eye_button.text = "◎"
	_room_row.add_child(_eye_button)

	_room_code_label = Label.new()
	_room_code_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_room_code_label.add_theme_font_size_override("font_size", 18)
	_room_code_label.text = "Room: ************"
	_room_row.add_child(_room_code_label)

	_copy_button = Button.new()
	_copy_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_copy_button.add_theme_font_size_override("font_size", 14)
	_copy_button.text = "Copy"
	_room_row.add_child(_copy_button)

	_invite_button = Button.new()
	_invite_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_invite_button.add_theme_font_size_override("font_size", 14)
	_invite_button.text = "Invite"
	_room_row.add_child(_invite_button)

	_menu_buttons = [_back_button, _settings_button, _back_to_menu_button, _quit_button]
	for btn in _menu_buttons:
		_make_flat_button(btn)
		_add_drop_shadow(btn)
		_setup_hover_effect(btn)

	# Settings panel (reuses the same structure as world_menu).
	_settings_panel = _build_settings_panel()
	add_child(_settings_panel)

	# Wire up buttons.
	_back_button.pressed.connect(
		func():
			_on_button_click(_back_button, _on_back_to_game),
	)
	_settings_button.pressed.connect(
		func():
			_on_button_click(_settings_button, _on_settings_pressed),
	)
	_invite_button.pressed.connect(
		func():
			_on_button_click(_invite_button, _on_invite),
	)
	_back_to_menu_button.pressed.connect(
		func():
			_on_button_click(_back_to_menu_button, _on_back_to_menu),
	)
	_quit_button.pressed.connect(
		func():
			_on_button_click(_quit_button, _on_quit),
	)
	_eye_button.pressed.connect(_on_eye_pressed)
	_copy_button.pressed.connect(_on_copy_pressed)
	_settings_back.pressed.connect(
		func():
			_on_button_click(_settings_back, _on_settings_back),
	)
	_make_flat_button(_settings_back)
	_add_drop_shadow(_settings_back)
	_setup_hover_effect(_settings_back)

	# Make the eye/copy/invite buttons flat with same hover color as menu buttons.
	for btn in [_eye_button, _copy_button, _invite_button]:
		_make_flat_button(btn)
		btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
		_setup_hover_effect(btn)


func _make_menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 48)
	btn.add_theme_font_size_override("font_size", 38)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = text
	return btn


func _build_settings_panel() -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false

	var list := VBoxContainer.new()
	list.set_anchors_preset(Control.PRESET_FULL_RECT)
	list.offset_left = 60.0
	list.offset_top = 80.0
	list.offset_right = 500.0
	list.offset_bottom = -70.0
	list.grow_vertical = Control.GROW_DIRECTION_BOTH
	var theme := load("res://assets/themes/menu_theme.tres") as Theme
	list.theme = theme
	list.add_theme_constant_override("separation", 8)
	panel.add_child(list)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.text = "Settings"
	list.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	list.add_child(spacer)

	# Audio header.
	var audio_header := Label.new()
	audio_header.add_theme_font_size_override("font_size", 22)
	audio_header.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 0.9))
	audio_header.text = "Audio"
	list.add_child(audio_header)

	# Master volume.
	var master_row := HBoxContainer.new()
	master_row.add_theme_constant_override("separation", 12)
	list.add_child(master_row)
	var master_label := Label.new()
	master_label.custom_minimum_size = Vector2(120, 0)
	master_label.add_theme_font_size_override("font_size", 18)
	master_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	master_label.text = "Master"
	master_row.add_child(master_label)
	var master_slider := HSlider.new()
	master_slider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	master_slider.custom_minimum_size = Vector2(100, 20)
	master_slider.min_value = 0.0
	master_slider.max_value = 0.5
	master_slider.step = 0.01
	master_slider.value = 0.5
	master_row.add_child(master_slider)
	var master_value := Label.new()
	master_value.custom_minimum_size = Vector2(40, 0)
	master_value.add_theme_font_size_override("font_size", 16)
	master_value.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	master_value.text = "50"
	master_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	master_row.add_child(master_value)

	# SFX volume.
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 12)
	list.add_child(sfx_row)
	var sfx_label := Label.new()
	sfx_label.custom_minimum_size = Vector2(120, 0)
	sfx_label.add_theme_font_size_override("font_size", 18)
	sfx_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	sfx_label.text = "SFX"
	sfx_row.add_child(sfx_label)
	var sfx_slider := HSlider.new()
	sfx_slider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sfx_slider.custom_minimum_size = Vector2(100, 20)
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 0.5
	sfx_slider.step = 0.01
	sfx_slider.value = 0.5
	sfx_row.add_child(sfx_slider)
	var sfx_value := Label.new()
	sfx_value.custom_minimum_size = Vector2(40, 0)
	sfx_value.add_theme_font_size_override("font_size", 16)
	sfx_value.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	sfx_value.text = "50"
	sfx_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sfx_row.add_child(sfx_value)

	# Music volume.
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 12)
	list.add_child(music_row)
	var music_label := Label.new()
	music_label.custom_minimum_size = Vector2(120, 0)
	music_label.add_theme_font_size_override("font_size", 18)
	music_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	music_label.text = "Music"
	music_row.add_child(music_label)
	var music_slider := HSlider.new()
	music_slider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	music_slider.custom_minimum_size = Vector2(100, 20)
	music_slider.min_value = 0.0
	music_slider.max_value = 0.5
	music_slider.step = 0.01
	music_slider.value = 0.5
	music_row.add_child(music_slider)
	var music_value := Label.new()
	music_value.custom_minimum_size = Vector2(40, 0)
	music_value.add_theme_font_size_override("font_size", 16)
	music_value.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	music_value.text = "50"
	music_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	music_row.add_child(music_value)

	# Spacer.
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 12)
	list.add_child(spacer2)

	# Graphics header.
	var gfx_header := Label.new()
	gfx_header.add_theme_font_size_override("font_size", 22)
	gfx_header.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 0.9))
	gfx_header.text = "Graphics"
	list.add_child(gfx_header)

	# Fullscreen.
	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 12)
	list.add_child(fs_row)
	var fs_label := Label.new()
	fs_label.custom_minimum_size = Vector2(200, 0)
	fs_label.add_theme_font_size_override("font_size", 18)
	fs_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	fs_label.text = "Fullscreen"
	fs_row.add_child(fs_label)
	var fs_check := CheckBox.new()
	fs_check.custom_minimum_size = Vector2(24, 24)
	fs_row.add_child(fs_check)

	# VSync.
	var vsync_row := HBoxContainer.new()
	vsync_row.add_theme_constant_override("separation", 12)
	list.add_child(vsync_row)
	var vsync_label := Label.new()
	vsync_label.custom_minimum_size = Vector2(200, 0)
	vsync_label.add_theme_font_size_override("font_size", 18)
	vsync_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	vsync_label.text = "VSync"
	vsync_row.add_child(vsync_label)
	var vsync_check := CheckBox.new()
	vsync_check.custom_minimum_size = Vector2(24, 24)
	vsync_row.add_child(vsync_check)

	# Enhanced Lighting.
	var lighting_row := HBoxContainer.new()
	lighting_row.add_theme_constant_override("separation", 12)
	list.add_child(lighting_row)
	var lighting_label := Label.new()
	lighting_label.custom_minimum_size = Vector2(200, 0)
	lighting_label.add_theme_font_size_override("font_size", 18)
	lighting_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	lighting_label.text = "Enhanced Lighting"
	lighting_row.add_child(lighting_label)
	var lighting_check := CheckBox.new()
	lighting_check.custom_minimum_size = Vector2(24, 24)
	lighting_row.add_child(lighting_check)

	# Show FPS.
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 12)
	list.add_child(fps_row)
	var fps_label := Label.new()
	fps_label.custom_minimum_size = Vector2(200, 0)
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	fps_label.text = "Show FPS"
	fps_row.add_child(fps_label)
	var fps_check := CheckBox.new()
	fps_check.custom_minimum_size = Vector2(24, 24)
	fps_row.add_child(fps_check)

	# Back button (anchored to bottom-left, same as main menu).
	_settings_back = Button.new()
	_settings_back.theme = theme
	_settings_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_settings_back.offset_left = 60.0
	_settings_back.offset_top = -70.0
	_settings_back.offset_right = 500.0
	_settings_back.offset_bottom = -16.0
	_settings_back.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_settings_back.custom_minimum_size = Vector2(0, 48)
	_settings_back.add_theme_font_size_override("font_size", 38)
	_settings_back.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_settings_back.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	_settings_back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_settings_back.text = "Back"
	panel.add_child(_settings_back)

	# Wire up sliders with drag sounds (same as main menu).
	master_slider.value_changed.connect(
		func(v: float):
			AudioServer.set_bus_volume_db(0, linear_to_db(v))
			master_value.text = "%d" % int(round(v * 100)),
	)
	master_slider.drag_ended.connect(
		func(_changed: bool):
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03),
	)
	sfx_slider.value_changed.connect(
		func(v: float):
			if AudioServer.get_bus_count() > 1:
				AudioServer.set_bus_volume_db(1, linear_to_db(v))
			sfx_value.text = "%d" % int(round(v * 100)),
	)
	sfx_slider.drag_ended.connect(
		func(_changed: bool):
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03),
	)
	music_slider.value_changed.connect(
		func(v: float):
			if AudioServer.get_bus_count() > 2:
				AudioServer.set_bus_volume_db(2, linear_to_db(v))
			music_value.text = "%d" % int(round(v * 100)),
	)
	music_slider.drag_ended.connect(
		func(_changed: bool):
			AudioManager.play_sfx_ui("blip_select", 1.0, 0.0),
	)
	# Graphics toggles — emit signals so main.gd handles them.
	fs_check.toggled.connect(
		func(on: bool):
			fullscreen_toggled.emit(on),
	)
	vsync_check.toggled.connect(
		func(on: bool):
			vsync_toggled.emit(on),
	)
	lighting_check.toggled.connect(
		func(on: bool):
			enhanced_lighting_toggled.emit(on),
	)
	fps_check.toggled.connect(
		func(on: bool):
			fps_toggled.emit(on),
	)

	# Store references for syncing.
	panel.set_meta("master_slider", master_slider)
	panel.set_meta("master_value", master_value)
	panel.set_meta("sfx_slider", sfx_slider)
	panel.set_meta("sfx_value", sfx_value)
	panel.set_meta("music_slider", music_slider)
	panel.set_meta("music_value", music_value)
	panel.set_meta("fs_check", fs_check)
	panel.set_meta("vsync_check", vsync_check)
	panel.set_meta("lighting_check", lighting_check)
	panel.set_meta("fps_check", fps_check)

	return panel


## Show the ESC menu.
func show_menu() -> void:
	visible = true
	_settings_panel.visible = false
	_menu_box.visible = true
	_menu_box.modulate = Color(1, 1, 1, 0)
	# Fade in.
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(_menu_box, "modulate:a", 1.0, 0.2)
	_update_room_display()


## Hide the ESC menu.
func hide_menu() -> void:
	if _menu_box.modulate.a > 0:
		_menu_box.modulate = Color(1, 1, 1, 1)
		var tw := create_tween()
		tw.set_ease(Tween.EASE_IN)
		tw.tween_property(_menu_box, "modulate:a", 0.0, 0.15)
		tw.tween_callback(
			func():
				visible = false,
		)
	else:
		visible = false


## Sync settings controls to current state (call before showing settings).
func _sync_settings() -> void:
	var master_slider := _settings_panel.get_meta("master_slider") as HSlider
	var master_value := _settings_panel.get_meta("master_value") as Label
	var sfx_slider := _settings_panel.get_meta("sfx_slider") as HSlider
	var sfx_value := _settings_panel.get_meta("sfx_value") as Label
	var music_slider := _settings_panel.get_meta("music_slider") as HSlider
	var music_value := _settings_panel.get_meta("music_value") as Label
	var fs_check := _settings_panel.get_meta("fs_check") as CheckBox
	var vsync_check := _settings_panel.get_meta("vsync_check") as CheckBox
	var lighting_check := _settings_panel.get_meta("lighting_check") as CheckBox
	var fps_check := _settings_panel.get_meta("fps_check") as CheckBox
	var master_val := db_to_linear(AudioServer.get_bus_volume_db(0))
	master_slider.value = master_val
	master_value.text = "%d" % int(round(master_val * 100))
	var sfx_val := 1.0
	if AudioServer.get_bus_count() > 1:
		sfx_val = db_to_linear(AudioServer.get_bus_volume_db(1))
	sfx_slider.value = sfx_val
	sfx_value.text = "%d" % int(round(sfx_val * 100))
	var music_val := 1.0
	if AudioServer.get_bus_count() > 2:
		music_val = db_to_linear(AudioServer.get_bus_volume_db(2))
	music_slider.value = music_val
	music_value.text = "%d" % int(round(music_val * 100))
	fs_check.button_pressed = (
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	)
	vsync_check.button_pressed = (
		DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	)
	lighting_check.button_pressed = true
	fps_check.button_pressed = false

# --- Button handlers ---


func _on_back_to_game() -> void:
	hide_menu()
	back_to_game.emit()


func _on_settings_pressed() -> void:
	_sync_settings()
	_settings_panel.visible = true
	_menu_box.visible = false
	settings_pressed.emit()


func _on_settings_back() -> void:
	_settings_panel.visible = false
	_menu_box.visible = true
	settings_back.emit()


func _on_invite() -> void:
	NetworkManager.invite_friend()


func _on_back_to_menu() -> void:
	hide_menu()
	back_to_menu.emit()


func _on_quit() -> void:
	quit_game.emit()


func _on_eye_pressed() -> void:
	_room_visible = not _room_visible
	_update_room_display()


func _update_room_display() -> void:
	if _room_visible:
		_room_code_label.text = "Room: %d" % NetworkManager.lobby_id
		_eye_button.text = "◉"
	else:
		_room_code_label.text = "Room: ************"
		_eye_button.text = "◎"


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(str(NetworkManager.lobby_id))
	_copy_button.text = "Copied!"
	get_tree().create_timer(1.5).timeout.connect(
		func():
			_copy_button.text = "Copy",
	)

# --- Button styling helpers (copied from world_menu.gd) ---


func _on_button_click(btn: Button, callback: Callable) -> void:
	AudioManager.play_sfx_ui("button_click", 1.0, 0.0, 0.0, 0.0)
	# Pop effect on press.
	if btn.has_meta("_base_scale"):
		btn.scale = btn.get_meta("_base_scale")
	var press_tween := create_tween()
	press_tween.set_ease(Tween.EASE_OUT)
	press_tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.06)
	press_tween.tween_property(btn, "scale", Vector2.ONE, 0.12)
	btn.set_meta("_press_tween", press_tween)
	callback.call()


func _make_flat_button(btn: Button) -> void:
	var stylebox_empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", stylebox_empty)
	btn.add_theme_stylebox_override("hover", stylebox_empty)
	btn.add_theme_stylebox_override("pressed", stylebox_empty)
	btn.add_theme_stylebox_override("focus", stylebox_empty)


func _add_drop_shadow(btn: Button) -> void:
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	btn.add_theme_constant_override("shadow_offset_x", 3)
	btn.add_theme_constant_override("shadow_offset_y", 3)
	btn.add_theme_constant_override("shadow_outline_size", 6)


func _setup_hover_effect(btn: Button) -> void:
	var base_scale := btn.scale
	btn.set_meta("_base_scale", base_scale)
	btn.mouse_entered.connect(
		func():
			if btn.disabled:
				return
			if btn.has_meta("_hover_tween") and btn.get_meta("_hover_tween") is Tween:
				(btn.get_meta("_hover_tween") as Tween).kill()
			var hover_tween := create_tween()
			hover_tween.set_ease(Tween.EASE_OUT)
			hover_tween.tween_property(btn, "scale", base_scale * HOVER_POP, HOVER_DURATION)
			btn.set_meta("_hover_tween", hover_tween),
	)
	btn.mouse_exited.connect(
		func():
			if btn.has_meta("_hover_tween") and btn.get_meta("_hover_tween") is Tween:
				(btn.get_meta("_hover_tween") as Tween).kill()
			var exit_tween := create_tween()
			exit_tween.set_ease(Tween.EASE_OUT)
			exit_tween.tween_property(btn, "scale", base_scale, HOVER_DURATION)
			btn.set_meta("_hover_tween", exit_tween),
	)

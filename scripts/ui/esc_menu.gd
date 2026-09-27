extends CanvasLayer
## In-game ESC menu overlay. Same blur + darken style as the main menu.
## Buttons: Back to Game, Settings, Invite, Back to Menu, Quit Game.
## Lobby code row with eye toggle + copy button.

const MENU_THEME := preload("res://assets/themes/menu_theme.tres")
const SETTINGS_PANEL_SCENE := preload("res://scenes/ui/settings_panel.tscn")
const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")
const PromoWidget := preload("res://scripts/ui/promo_widget.gd")

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
var _save_button: Button
var _invite_button: Button
var _back_to_menu_button: Button
var _quit_button: Button
var _settings_panel: SettingsPanel
var _room_row: HBoxContainer
var _eye_button: Button
var _room_code_label: Label
var _copy_button: Button
var _menu_buttons: Array[Button] = []
var _room_visible: bool = false
var _version_label: Label
var _music_widget: PanelContainer
var _music_vinyl: Control
var _music_label: Label
var _music_prev_btn: Button
var _music_next_btn: Button
var _music_progress: ProgressBar
var _music_time_current: Label
var _music_time_total: Label
var _promo_widget: Control

const MUSIC_WIDGET_W: float = 280.0
const MUSIC_WIDGET_H: float = 88.0


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
	var theme := MENU_THEME as Theme
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

	_save_button = _make_menu_button("Save Game")
	_menu_box.add_child(_save_button)

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

	_menu_buttons = [
		_back_button,
		_save_button,
		_settings_button,
		_back_to_menu_button,
		_quit_button,
	]
	for btn in _menu_buttons:
		_make_flat_button(btn)
		_add_drop_shadow(btn)
		_setup_hover_effect(btn)

	# Settings panel (tabbed categories, shared with main menu).
	_settings_panel = SETTINGS_PANEL_SCENE.instantiate() as SettingsPanel
	_settings_panel.fullscreen_toggled.connect(
		func(on: bool):
			fullscreen_toggled.emit(on),
	)
	_settings_panel.vsync_toggled.connect(
		func(on: bool):
			vsync_toggled.emit(on),
	)
	_settings_panel.enhanced_lighting_toggled.connect(
		func(on: bool):
			enhanced_lighting_toggled.emit(on),
	)
	_settings_panel.fps_toggled.connect(
		func(on: bool):
			fps_toggled.emit(on),
	)
	_settings_panel.back_pressed.connect(_on_settings_back)
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
	_save_button.pressed.connect(
		func():
			_on_button_click(_save_button, _on_save_game),
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

	# Make the eye/copy/invite buttons flat with same hover color as menu buttons.
	for btn in [_eye_button, _copy_button, _invite_button]:
		_make_flat_button(btn)
		btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
		_setup_hover_effect(btn)

	# Version label (bottom-left, same as main menu).
	_version_label = Label.new()
	_version_label.anchor_left = 0.0
	_version_label.anchor_top = 1.0
	_version_label.anchor_right = 0.0
	_version_label.anchor_bottom = 1.0
	_version_label.offset_left = 12.0
	_version_label.offset_top = -28.0
	_version_label.offset_right = 100.0
	_version_label.offset_bottom = -8.0
	_version_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_version_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_version_label.add_theme_font_size_override("font_size", 14)
	_version_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	_version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.0.0")
	add_child(_version_label)

	# Music player widget (bottom-right, same as main menu).
	_build_music_player()

	# Promo slideshow above the music player (same as main menu).
	_promo_widget = PromoWidget.new()
	add_child(_promo_widget)


func _make_menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 48)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.add_theme_font_size_override("font_size", 38)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = text
	return btn


## Show the ESC menu.
func show_menu() -> void:
	visible = true
	_settings_panel.visible = false
	_menu_box.visible = true
	_menu_box.modulate = Color(1, 1, 1, 0)
	if _version_label:
		_version_label.visible = true
	if _music_widget:
		_music_widget.visible = true
	if _promo_widget:
		_promo_widget.visible = true
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

# --- Button handlers ---


func _on_back_to_game() -> void:
	hide_menu()
	back_to_game.emit()


func _on_settings_pressed() -> void:
	_settings_panel.sync_state()
	_settings_panel.visible = true
	_menu_box.visible = false
	settings_pressed.emit()


func _on_save_game() -> void:
	# Only the host can save (clients don't have full game state).
	if WorldSync.is_host():
		# Flush the active stand's research before saving.
		UpgradeManager.flush_active_stand()
		SaveManager.save_game(true)
		GameLog.log("[ESCMenu] Game saved to slot: %s" % SaveManager.current_slot)
		# Show a brief confirmation.
		_show_save_confirmation()
	else:
		GameLog.log("[ESCMenu] Save requested by non-host — ignored")


## Show a brief "Game Saved" confirmation text that fades out.
func _show_save_confirmation() -> void:
	var label := Label.new()
	label.text = "Game Saved!"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1))
	label.add_theme_color_override("shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("shadow_outline_size", 4)
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position.y = 100
	label.z_index = 100
	add_child(label)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.tween_interval(1.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func _on_settings_back() -> void:
	_settings_panel.visible = false
	_menu_box.visible = true
	settings_back.emit()


func _on_invite() -> void:
	NetworkManager.invite_friend()


func _on_back_to_menu() -> void:
	# Hide just the menu box + settings, but keep blur/dim visible
	# so the screen stays covered during the fade-to-black transition.
	_menu_box.visible = false
	_settings_panel.visible = false
	if _version_label:
		_version_label.visible = false
	if _music_widget:
		_music_widget.visible = false
	if _promo_widget:
		_promo_widget.visible = false
	back_to_menu.emit()


## Fully hide the ESC menu (blur, dim, everything).
func hide_full() -> void:
	visible = false


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

# ─── Music Player Widget (copied from world_menu.gd) ───


func _build_music_player() -> void:
	# Panel container anchored to bottom-right.
	_music_widget = PanelContainer.new()
	_music_widget.name = "MusicPlayer"
	_music_widget.anchor_left = 1.0
	_music_widget.anchor_top = 1.0
	_music_widget.anchor_right = 1.0
	_music_widget.anchor_bottom = 1.0
	_music_widget.offset_left = -(MUSIC_WIDGET_W + 12.0)
	_music_widget.offset_top = -(MUSIC_WIDGET_H + 12.0)
	_music_widget.offset_right = -12.0
	_music_widget.offset_bottom = -12.0
	_music_widget.custom_minimum_size = Vector2(MUSIC_WIDGET_W, MUSIC_WIDGET_H)
	_music_widget.mouse_filter = Control.MOUSE_FILTER_STOP
	# Semi-transparent background with subtle border.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.22, 0.32, 0.92)
	bg.border_color = Color(1, 1, 1, 0.12)
	bg.set_border_width_all(1)
	bg.set_content_margin_all(10)
	bg.set_corner_radius_all(6)
	_music_widget.add_theme_stylebox_override("panel", bg)
	add_child(_music_widget)

	# Inner VBox: top row (controls + disc + title), progress bar, time row.
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_music_widget.add_child(vbox)

	# Top row: prev | disc + now playing | next
	var top_row := HBoxContainer.new()
	top_row.name = "TopRow"
	top_row.add_theme_constant_override("separation", 8)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	# Prev button.
	_music_prev_btn = Button.new()
	_music_prev_btn.name = "Prev"
	_music_prev_btn.text = "<"
	_music_prev_btn.custom_minimum_size = Vector2(24, 24)
	_music_prev_btn.add_theme_font_size_override("font_size", 16)
	_music_prev_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	_music_prev_btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	_music_prev_btn.add_theme_color_override("font_pressed_color", Color(1, 0.95, 0.7, 0.6))
	_make_flat_button(_music_prev_btn)
	top_row.add_child(_music_prev_btn)
	_music_prev_btn.pressed.connect(
		func():
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
			AudioManager.prev_track(),
	)

	# Disc + text column (disc on left, text stacked on right).
	var disc_row := HBoxContainer.new()
	disc_row.name = "DiscRow"
	disc_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disc_row.add_theme_constant_override("separation", 8)
	disc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	disc_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(disc_row)

	# Vinyl disc — taller so it spans both text lines.
	var disc := Control.new()
	disc.name = "Vinyl"
	disc.custom_minimum_size = Vector2(44, 44)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.set_script(load("res://scripts/ui/vinyl_disc.gd"))
	disc_row.add_child(disc)
	_music_vinyl = disc

	# Text column: NOW PLAYING header + track name.
	var text_col := VBoxContainer.new()
	text_col.name = "TextCol"
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 1)
	text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc_row.add_child(text_col)

	# "NOW PLAYING" small header.
	var np_label := Label.new()
	np_label.name = "NowPlaying"
	np_label.add_theme_font_size_override("font_size", 9)
	np_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 0.5))
	np_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	np_label.text = "♪ NOW PLAYING"
	np_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(np_label)

	# Track name label.
	_music_label = Label.new()
	_music_label.name = "TrackName"
	_music_label.add_theme_font_size_override("font_size", 13)
	_music_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_music_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_music_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_music_label.text = "—"
	_music_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_music_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_child(_music_label)

	# Next button.
	_music_next_btn = Button.new()
	_music_next_btn.name = "Next"
	_music_next_btn.text = ">"
	_music_next_btn.custom_minimum_size = Vector2(24, 24)
	_music_next_btn.add_theme_font_size_override("font_size", 16)
	_music_next_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	_music_next_btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	_music_next_btn.add_theme_color_override("font_pressed_color", Color(1, 0.95, 0.7, 0.6))
	_make_flat_button(_music_next_btn)
	top_row.add_child(_music_next_btn)
	_music_next_btn.pressed.connect(
		func():
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
			AudioManager.next_track(),
	)

	# Progress bar (read-only).
	_music_progress = ProgressBar.new()
	_music_progress.name = "Progress"
	_music_progress.min_value = 0.0
	_music_progress.max_value = 1.0
	_music_progress.value = 0.0
	_music_progress.custom_minimum_size = Vector2(0, 4)
	_music_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_music_progress.show_percentage = false
	# Style the progress bar — minimal.
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(1, 1, 1, 0.08)
	pb_bg.set_corner_radius_all(2)
	_music_progress.add_theme_stylebox_override("background", pb_bg)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = Color(1, 0.85, 0.4, 0.7)
	pb_fill.set_corner_radius_all(2)
	_music_progress.add_theme_stylebox_override("fill", pb_fill)
	vbox.add_child(_music_progress)

	# Time row: current | total.
	var time_row := HBoxContainer.new()
	time_row.name = "TimeRow"
	time_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(time_row)

	_music_time_current = Label.new()
	_music_time_current.name = "TimeCurrent"
	_music_time_current.add_theme_font_size_override("font_size", 10)
	_music_time_current.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	_music_time_current.text = "0:00"
	_music_time_current.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_row.add_child(_music_time_current)

	var spacer := Control.new()
	spacer.name = "TimeSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_row.add_child(spacer)

	_music_time_total = Label.new()
	_music_time_total.name = "TimeTotal"
	_music_time_total.add_theme_font_size_override("font_size", 10)
	_music_time_total.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	_music_time_total.text = "0:00"
	_music_time_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_music_time_total.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_row.add_child(_music_time_total)

	# Connect progress signal.
	AudioManager.music_progress.connect(_update_music_progress)
	# Connect track change signal.
	AudioManager.music_track_changed.connect(_update_music_display)
	# Sync current track display.
	_update_music_display(AudioManager.get_current_track())


func _update_music_display(track_name: String) -> void:
	if _music_label:
		_music_label.text = track_name if track_name != "" else "—"
	if _music_vinyl and _music_vinyl.has_method("set_spinning"):
		_music_vinyl.set_spinning(track_name != "")


func _update_music_progress(current: float, total: float) -> void:
	if _music_progress and total > 0:
		_music_progress.value = current / total
	if _music_time_current:
		_music_time_current.text = _format_time(current)
	if _music_time_total:
		_music_time_total.text = _format_time(total)


func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%d:%02d" % [mins, secs]


func _on_button_click(btn: Button, callback: Callable) -> void:
	AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
	if btn != null and is_instance_valid(btn):
		if not btn.has_meta("_base_scale"):
			btn.set_meta("_base_scale", btn.scale)
		var base_scale: Vector2 = btn.get_meta("_base_scale")
		btn.pivot_offset = Vector2(0, btn.size.y / 2.0)
		if btn.has_meta("_press_tween") and btn.get_meta("_press_tween") is Tween:
			(btn.get_meta("_press_tween") as Tween).kill()
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(btn, "scale", base_scale, 0.12) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "modulate", Color(1.0, 0.95, 0.7), 0.12) \
				.set_ease(Tween.EASE_OUT)
	callback.call()


## Style an HSlider with a custom flat look: thin track + circular grabber.
func _style_slider(slider: HSlider) -> void:
	slider.add_theme_constant_override("center_grabber", 1)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.set_corner_radius_all(3)
	track.content_margin_top = 6.0
	track.content_margin_bottom = 6.0
	slider.add_theme_stylebox_override("slider", track)
	var grab_area := StyleBoxFlat.new()
	grab_area.bg_color = Color(1, 0.85, 0.2, 0.7)
	grab_area.set_corner_radius_all(3)
	grab_area.content_margin_top = 6.0
	grab_area.content_margin_bottom = 6.0
	slider.add_theme_stylebox_override("grabber_area", grab_area)
	var grab_area_hl := StyleBoxFlat.new()
	grab_area_hl.bg_color = Color(1, 0.85, 0.2, 0.9)
	grab_area_hl.set_corner_radius_all(3)
	grab_area_hl.content_margin_top = 6.0
	grab_area_hl.content_margin_bottom = 6.0
	slider.add_theme_stylebox_override("grabber_area_highlight", grab_area_hl)
	_set_slider_emoji_icons(slider)


## Create a circular icon texture at runtime for slider grabbers.
func _make_circle_icon(size: int, fill: Color, border: Color, border_width: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(size / 2.0, size / 2.0)
	var radius: float = size / 2.0 - border_width
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(center)
			if d <= radius:
				img.set_pixel(x, y, fill)
			elif d <= radius + border_width:
				img.set_pixel(x, y, border)
	return ImageTexture.create_from_image(img)


## Set lemon emoji icons on a slider, rendered via SubViewport (async).
func _set_slider_emoji_icons(slider: HSlider) -> void:
	var grabber := await _render_emoji_texture("🍋", 16)
	var grabber_hl := await _render_emoji_texture("🍋", 20)
	if not is_instance_valid(slider):
		return
	if grabber != null:
		slider.add_theme_icon_override("grabber", grabber)
	if grabber_hl != null:
		slider.add_theme_icon_override("grabber_highlight", grabber_hl)
	slider.add_theme_icon_override(
		"grabber_disabled",
		_make_circle_icon(12, Color(0.5, 0.5, 0.5, 0.5), Color(0, 0, 0, 0), 0),
	)


## Render an emoji to a texture via a SubViewport Label (supports emoji fallback).
## Renders at high resolution, removes dark outline pixels, then uses GPU scaling.
func _render_emoji_texture(emoji: String, font_size: int) -> Texture2D:
	var sz := 128
	var vp := SubViewport.new()
	vp.size = Vector2(sz, sz)
	vp.transparent_bg = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var lbl := Label.new()
	lbl.text = emoji
	lbl.add_theme_font_size_override("font_size", 96)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(sz, sz)
	vp.add_child(lbl)
	add_child(vp)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null:
		return null
	_remove_dark_outline(img)
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2(font_size + 8, font_size + 8))
	return tex


## Remove dark outline pixels from an emoji render by making them transparent.
func _remove_dark_outline(img: Image) -> void:
	if img == null:
		return
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var brightness := (c.r + c.g + c.b) / 3.0
			if brightness < 0.25 and c.a > 0.0:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, brightness * c.a * 2.0))


func _make_flat_button(btn: Button) -> void:
	var stylebox_empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", stylebox_empty)
	btn.add_theme_stylebox_override("hover", stylebox_empty)
	btn.add_theme_stylebox_override("pressed", stylebox_empty)
	btn.add_theme_stylebox_override("focus", stylebox_empty)


## Style a CheckBox to be a transparent box with white outline (same as main menu).
func _style_checkbox(cb: CheckBox) -> void:
	# Block the parent menu theme from applying Button green styles.
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


func _add_drop_shadow(btn: Button) -> void:
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	btn.add_theme_constant_override("shadow_offset_x", 3)
	btn.add_theme_constant_override("shadow_offset_y", 3)
	btn.add_theme_constant_override("shadow_outline_size", 6)


func _setup_hover_effect(btn: Button, pop_left: bool = false) -> void:
	if btn == null:
		return
	btn.set_meta("_pop_left", pop_left)
	btn.mouse_entered.connect(
		func():
			AudioManager.play_sfx_ui("blip_select", 1.0, 0.0)
			if not btn.disabled:
				_animate_hover(btn, true),
	)
	btn.mouse_exited.connect(
		func():
			_animate_hover(btn, false),
	)
	# Press animation on mouse down.
	btn.button_down.connect(
		func():
			if not btn.disabled:
				_animate_press(btn),
	)


## Responsive scale pop on hover. Pivot at left-center so it grows
## to the right, staying vertically centered.
func _animate_hover(btn: Button, hover: bool) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	if btn.has_meta("_hover_tween") and btn.get_meta("_hover_tween") is Tween:
		(btn.get_meta("_hover_tween") as Tween).kill()
	if not btn.has_meta("_base_scale"):
		btn.set_meta("_base_scale", btn.scale)
	var pop_left: bool = btn.has_meta("_pop_left") and btn.get_meta("_pop_left")
	if pop_left:
		btn.pivot_offset = Vector2(btn.size.x, btn.size.y / 2.0)
	else:
		btn.pivot_offset = Vector2(0, btn.size.y / 2.0)
	var base_scale: Vector2 = btn.get_meta("_base_scale")
	var tw := create_tween()
	btn.set_meta("_hover_tween", tw)
	tw.set_parallel(true)
	if hover:
		tw.tween_property(btn, "scale", base_scale * HOVER_POP, 0.06) \
				.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "modulate", Color(1.0, 0.95, 0.7), 0.06) \
				.set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(btn, "scale", base_scale, 0.08) \
				.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "modulate", Color.WHITE, 0.08) \
				.set_ease(Tween.EASE_OUT)


## Press animation: squash down + darken on mouse down.
func _animate_press(btn: Button) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	if btn.has_meta("_press_tween") and btn.get_meta("_press_tween") is Tween:
		(btn.get_meta("_press_tween") as Tween).kill()
	if not btn.has_meta("_base_scale"):
		btn.set_meta("_base_scale", btn.scale)
	var base_scale: Vector2 = btn.get_meta("_base_scale")
	btn.pivot_offset = Vector2(0, btn.size.y / 2.0)
	var tw := create_tween()
	btn.set_meta("_press_tween", tw)
	tw.set_parallel(true)
	tw.tween_property(btn, "scale", base_scale * 0.92, 0.05) \
			.set_ease(Tween.EASE_IN)
	tw.tween_property(btn, "modulate", Color(0.7, 0.7, 0.75), 0.05)

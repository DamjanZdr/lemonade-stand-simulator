extends CanvasLayer
## In-world main menu overlay. Professional left-aligned text buttons
## with hover animations and click sounds.

signal play_pressed
signal saves_pressed
signal join_pressed(lobby_id: int)
signal host_pressed
signal settings_pressed
signal fullscreen_toggled(enabled: bool)
signal vsync_toggled(enabled: bool)
signal enhanced_lighting_toggled(enabled: bool)
signal fps_toggled(enabled: bool)
signal new_stand_requested(stand_name: String, game_mode: int)
signal load_stand_requested(slot_name: String)

const HOVER_POP: float = 1.12
const HOVER_DURATION: float = 0.18
const NAME_MAX_WEIGHT: float = 15.0 # Capitals count as 1.5, lowercase as 1.

@onready var _play_button: Button = $MenuBox/PlayButton
@onready var _title_label: Label = $MenuBox/TitleBox/TitleLabel
@onready var _subtitle_label: Label = $MenuBox/TitleBox/SubtitleLabel
@onready var _saves_button: Button = $MenuBox/SavesButton
@onready var _join_button: Button = $MenuBox/JoinButton
@onready var _join_panel: Control = $JoinPanel
@onready var _join_field: LineEdit = $JoinPanel/JoinList/JoinField
@onready var _join_submit: Button = $JoinPanel/JoinList/JoinSubmit
@onready var _join_back: Button = $JoinPanel/JoinBack
var _join_paste_btn: Button = null
var _join_clear_btn: Button = null
var _join_error_label: Label = null
@onready var _quit_button: Button = $MenuBox/QuitButton
@onready var _settings_button: Button = $MenuBox/SettingsButton
@onready var _settings_panel: Control = $SettingsPanel
@onready var _settings_back: Button = $SettingsPanel/SettingsBack
@onready var _master_slider: HSlider = $SettingsPanel/SettingsList/MasterRow/MasterSlider
@onready var _master_value: Label = $SettingsPanel/SettingsList/MasterRow/MasterValue
@onready var _sfx_slider: HSlider = $SettingsPanel/SettingsList/SFXRow/SFXSlider
@onready var _sfx_value: Label = $SettingsPanel/SettingsList/SFXRow/SFXValue
@onready var _music_slider: HSlider = $SettingsPanel/SettingsList/MusicRow/MusicSlider
@onready var _music_value: Label = $SettingsPanel/SettingsList/MusicRow/MusicValue
@onready var _fullscreen_check: CheckBox = $SettingsPanel/SettingsList/FullscreenRow/FullscreenCheck
@onready var _vsync_check: CheckBox = $SettingsPanel/SettingsList/VSyncRow/VSyncCheck
@onready var _lighting_check: CheckBox = $SettingsPanel/SettingsList/LightingRow/LightingCheck
@onready var _fps_check: CheckBox = $SettingsPanel/SettingsList/FPSRow/FPSCheck
@onready var _status_label: Label = $MenuBox/StatusLabel
@onready var _version_label: Label = $VersionLabel

# Music player widget
var _music_vinyl: Control = null
var _music_label: Label = null
var _music_widget: Control = null
var _music_spin_tween: Tween = null
var _music_prev_btn: Button = null
var _music_next_btn: Button = null
var _music_progress: ProgressBar = null
var _music_time_current: Label = null
var _music_time_total: Label = null

# Saves panel
@onready var _saves_panel: Control = $SavesPanel
@onready var _saves_list: VBoxContainer = $SavesPanel/SavesList
@onready var _save_scroll: ScrollContainer = $SavesPanel/SavesList/SaveScroll
@onready var _slots_container: VBoxContainer = $SavesPanel/SavesList/SaveScroll/SlotsContainer
@onready var _new_stand_button: Button = $SavesPanel/SavesList/NewStandButton
@onready var _saves_back: Button = $SavesPanel/SavesList/BackButton

var _saves_data: Array = []
var _menu_buttons: Array[Button] = []


func _ready() -> void:
	_menu_buttons = [_play_button, _saves_button, _join_button, _settings_button, _quit_button]
	_play_button.pressed.connect(
		func():
			_on_button_click(
				_play_button,
				func():
					play_pressed.emit(),
			),
	)
	_saves_button.pressed.connect(
		func():
			_on_button_click(_saves_button, _on_saves_pressed),
	)
	_join_button.pressed.connect(
		func():
			_on_button_click(_join_button, _toggle_join_row),
	)
	_join_submit.pressed.connect(
		func():
			_on_button_click(_join_submit, _on_join_submit),
	)
	_join_back.pressed.connect(
		func():
			_on_button_click(_join_back, _on_join_back),
	)
	_join_field.text_submitted.connect(
		func(_text):
			_on_join_submit(),
	)
	# Inline Paste/Clear button inside the field, at the right edge.
	# Paste shows when empty, Clear shows when not empty.
	_join_paste_btn = Button.new()
	_join_paste_btn.text = "Paste"
	_join_paste_btn.add_theme_font_size_override("font_size", 16)
	_join_paste_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_join_paste_btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	_make_flat_button(_join_paste_btn)
	_setup_hover_effect(_join_paste_btn)
	_join_paste_btn.visible = false
	_join_field.add_child(_join_paste_btn)
	_join_clear_btn = Button.new()
	_join_clear_btn.text = "Clear"
	_join_clear_btn.add_theme_font_size_override("font_size", 16)
	_join_clear_btn.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 0.5))
	_join_clear_btn.add_theme_color_override("font_hover_color", Color(1, 0.3, 0.3, 1))
	_make_flat_button(_join_clear_btn)
	_setup_hover_effect(_join_clear_btn)
	_join_clear_btn.visible = false
	_join_field.add_child(_join_clear_btn)
	# Update button visibility based on field content.
	var update_btns := func():
		var empty := _join_field.text.strip_edges() == ""
		_join_paste_btn.visible = empty
		_join_clear_btn.visible = not empty
		_position_join_inline_btns()
	_join_paste_btn.pressed.connect(
		func():
			_on_button_click(
				_join_paste_btn,
				func():
					_join_field.text = DisplayServer.clipboard_get()
					_join_field.caret_column = _join_field.text.length()
					update_btns.call(),
			),
	)
	_join_clear_btn.pressed.connect(
		func():
			_on_button_click(
				_join_clear_btn,
				func():
					_join_field.text = ""
					_join_field.grab_focus()
					update_btns.call(),
			),
	)
	_join_field.text_changed.connect(
		func(_new_text):
			update_btns.call(),
	)
	# Error label for invalid ID.
	_join_error_label = Label.new()
	_join_error_label.add_theme_font_size_override("font_size", 16)
	_join_error_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4, 0.9))
	_join_error_label.visible = false
	_join_field.add_sibling(_join_error_label)
	_quit_button.pressed.connect(
		func():
			_on_button_click(
				_quit_button,
				func():
					get_tree().quit(),
			),
	)
	_settings_button.pressed.connect(
		func():
			_on_button_click(_settings_button, _on_settings_pressed),
	)
	_settings_back.pressed.connect(
		func():
			_on_button_click(_settings_back, _on_settings_back),
	)
	# Audio sliders — control bus volumes, show value, play sound on release.
	_style_slider(_master_slider)
	_style_slider(_sfx_slider)
	_style_slider(_music_slider)
	# Style the saves list scroll container to match the game's palette.
	# Use the cached _save_scroll reference. SHRINK_BEGIN prevents the
	# VBoxContainer from expanding it beyond its minimum size.
	_save_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_save_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# Add right padding so the scrollbar doesn't overlap the Yes/No
	# delete confirmation buttons on each save row.
	_slots_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Defer styling — the scrollbar child may not exist yet at _ready.
	call_deferred("_style_scroll_container", _save_scroll)
	_master_slider.value_changed.connect(
		func(v: float):
			AudioServer.set_bus_volume_db(0, linear_to_db(v))
			_master_value.text = "%d" % int(round(v * 100)),
	)
	_master_slider.drag_ended.connect(
		func(_changed: bool):
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
			SettingsManager.save_settings(),
	)
	_sfx_slider.value_changed.connect(
		func(v: float):
			if AudioServer.get_bus_count() > 1:
				AudioServer.set_bus_volume_db(1, linear_to_db(v))
			_sfx_value.text = "%d" % int(round(v * 100)),
	)
	_sfx_slider.drag_ended.connect(
		func(_changed: bool):
			AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
			SettingsManager.save_settings(),
	)
	_music_slider.value_changed.connect(
		func(v: float):
			if AudioServer.get_bus_count() > 2:
				AudioServer.set_bus_volume_db(2, linear_to_db(v))
			_music_value.text = "%d" % int(round(v * 100)),
	)
	_music_slider.drag_ended.connect(
		func(_changed: bool):
			AudioManager.play_sfx_ui("blip_select", 1.0, 0.0)
			SettingsManager.save_settings(),
	)
	# Graphics toggles.
	_fullscreen_check.toggled.connect(
		func(on: bool):
			fullscreen_toggled.emit(on)
			SettingsManager.save_settings(),
	)
	_vsync_check.toggled.connect(
		func(on: bool):
			vsync_toggled.emit(on)
			SettingsManager.save_settings(),
	)
	_lighting_check.toggled.connect(
		func(on: bool):
			enhanced_lighting_toggled.emit(on)
			SettingsManager.save_graphics_bool("enhanced_lighting", on),
	)
	_fps_check.toggled.connect(
		func(on: bool):
			fps_toggled.emit(on)
			SettingsManager.save_graphics_bool("fps_counter", on),
	)
	_saves_back.pressed.connect(
		func():
			_on_button_click(_saves_back, _on_saves_back),
	)
	_new_stand_button.pressed.connect(
		func():
			_on_button_click(_new_stand_button, _on_new_stand_pressed),
	)
	_version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.0.0")
	# Remove button backgrounds so they look like plain text, then wire hover.
	for btn in _menu_buttons:
		_make_flat_button(btn)
		_add_drop_shadow(btn)
		_setup_hover_effect(btn)
	_make_flat_button(_join_submit)
	_add_drop_shadow(_join_submit)
	_setup_hover_effect(_join_submit)
	_make_flat_button(_join_back)
	_add_drop_shadow(_join_back)
	_setup_hover_effect(_join_back)
	_make_flat_button(_settings_back)
	_add_drop_shadow(_settings_back)
	_setup_hover_effect(_settings_back)
	# Style checkboxes: transparent bg, white outline, square, minimalist.
	for cb in [_fullscreen_check, _vsync_check, _lighting_check, _fps_check]:
		# Use a helper to make square styleboxes with equal content margins.
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
		cb.add_theme_stylebox_override(
			"normal",
			make_sb.call(Color(0, 0, 0, 0), Color(1, 1, 1, 0.4)),
		)
		cb.add_theme_stylebox_override(
			"hover",
			make_sb.call(Color(0, 0, 0, 0), Color(1, 1, 1, 0.8)),
		)
		cb.add_theme_stylebox_override(
			"pressed",
			make_sb.call(Color(1, 1, 1, 0.1), Color(1, 1, 1, 1.0)),
		)
		cb.add_theme_stylebox_override(
			"checked",
			make_sb.call(Color(1, 0.95, 0.7, 0.15), Color(1, 0.95, 0.7, 1.0)),
		)
		# Hover while checked — keep the checked style, don't go invisible.
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
	# Style join field same as stand box outline.
	var jf_style := StyleBoxFlat.new()
	jf_style.bg_color = Color(0, 0, 0, 0)
	jf_style.border_color = Color(1, 1, 1, 0.4)
	jf_style.set_border_width_all(1)
	jf_style.set_content_margin_all(10)
	jf_style.set_corner_radius_all(4)
	_join_field.add_theme_stylebox_override("normal", jf_style)
	var jf_focus := StyleBoxFlat.new()
	jf_focus.bg_color = Color(0, 0, 0, 0)
	jf_focus.border_color = Color(1, 1, 1, 1.0)
	jf_focus.set_border_width_all(1)
	jf_focus.set_content_margin_all(10)
	jf_focus.set_corner_radius_all(4)
	_join_field.add_theme_stylebox_override("focus", jf_focus)
	_make_flat_button(_saves_back)
	_add_drop_shadow(_saves_back)
	_setup_hover_effect(_saves_back)
	_make_flat_button(_new_stand_button)
	_add_drop_shadow(_new_stand_button)
	_setup_hover_effect(_new_stand_button)
	# Size "Simulator" to match the width of "Lemonade Stand".
	_fit_subtitle_width()
	# Build the music player widget (bottom-right corner).
	_build_music_player()
	# Sync to current track.
	_update_music_display(AudioManager.get_current_track())
	AudioManager.music_track_changed.connect(_update_music_display)


func show_menu() -> void:
	visible = true
	_saves_panel.visible = false
	_join_panel.visible = false
	_settings_panel.visible = false
	_status_label.text = ""
	$MenuBox.visible = true
	$MenuBox.modulate = Color(1, 1, 1, 1)
	print("[ShowMenu] MenuBox.visible=%s modulate=%s" % [$MenuBox.visible, $MenuBox.modulate])
	# Reset all buttons: kill stale tweens, reset modulate + scale,
	# and re-apply flat style + drop shadow + hover effects.
	for btn in _menu_buttons:
		if btn == null or not is_instance_valid(btn):
			print("[ShowMenu] SKIP null/invalid button")
			continue
		# Kill any stale hover/press tweens.
		if btn.has_meta("_hover_tween") and btn.get_meta("_hover_tween") is Tween:
			(btn.get_meta("_hover_tween") as Tween).kill()
		if btn.has_meta("_press_tween") and btn.get_meta("_press_tween") is Tween:
			(btn.get_meta("_press_tween") as Tween).kill()
		btn.modulate = Color(1, 1, 1, 1)
		if btn.has_meta("_base_scale"):
			btn.scale = btn.get_meta("_base_scale")
		else:
			btn.scale = Vector2.ONE
		_make_flat_button(btn)
		_add_drop_shadow(btn)
	# Re-enable all buttons (set_busy may have disabled them).
	set_enabled(true)
	# Animate buttons in
	_animate_buttons_in()


## Show the menu without the stagger animation (used after transitions).
## Fades in over `duration` seconds.
func show_menu_immediate(duration: float = 0.4) -> void:
	visible = true
	_saves_panel.visible = false
	_join_panel.visible = false
	_settings_panel.visible = false
	_status_label.text = ""
	# MenuBox may have been hidden by _on_saves_pressed().
	$MenuBox.visible = true
	# Make sure all buttons are fully visible immediately.
	for btn in _menu_buttons:
		if btn != null and is_instance_valid(btn):
			btn.modulate = Color(1, 1, 1, 1)
	# Fade in the MenuBox.
	$MenuBox.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property($MenuBox, "modulate:a", 1.0, duration)


func hide_menu() -> void:
	# Fade out the MenuBox before hiding.
	if $MenuBox.modulate.a > 0:
		$MenuBox.modulate = Color(1, 1, 1, 1)
		var tw := create_tween()
		tw.set_ease(Tween.EASE_IN)
		tw.tween_property($MenuBox, "modulate:a", 0.0, 0.2)
		tw.tween_callback(
			func():
				visible = false,
		)
	else:
		visible = false


func set_status(text: String) -> void:
	_status_label.text = text
	_status_label.visible = text != ""


func set_busy(text: String) -> void:
	set_status(text)
	for btn in _menu_buttons:
		btn.disabled = true


func set_enabled(enabled: bool) -> void:
	for btn in _menu_buttons:
		btn.disabled = not enabled


## Show the inline name entry (used by Play button when no saves exist).
## Opens the saves panel and triggers the new-stand creation flow,
## since the creation UI lives inside the saves list.
func show_name_entry() -> void:
	# Show the saves panel so the creation UI is visible.
	_saves_panel.visible = true
	$MenuBox.visible = false
	_on_new_stand_pressed()


## Size the "Simulator" subtitle so its rendered width matches the
## "Lemonade Stand" title width.
func _fit_subtitle_width() -> void:
	if _title_label == null or _subtitle_label == null:
		return
	var title_font := _title_label.get_theme_font("font")
	var title_size := _title_label.get_theme_font_size("font_size")
	var title_width := title_font \
			.get_string_size(_title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size) \
			.x
	if title_width <= 0:
		return
	var sub_font := _subtitle_label.get_theme_font("font")
	# Start from the title font size and increase until we match width.
	var sub_size := title_size
	var sub_width := sub_font \
			.get_string_size(_subtitle_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size) \
			.x
	if sub_width <= 0:
		return
	# Scale proportionally to match.
	sub_size = int(round(title_size * title_width / sub_width))
	_subtitle_label.add_theme_font_size_override("font_size", sub_size)


## Add a drop shadow to a button's text.
func _add_drop_shadow(btn: Button) -> void:
	if btn == null:
		return
	btn.add_theme_color_override("shadow_color", Color(0, 0, 0, 0.6))
	btn.add_theme_constant_override("shadow_offset_x", 2)
	btn.add_theme_constant_override("shadow_offset_y", 2)
	btn.add_theme_constant_override("shadow_outline_size", 4)


## Style a ScrollContainer's scrollbar to match the game's lemonade palette:
## semi-transparent rounded track, lemon-yellow grabber with hover highlight.
func _style_scroll_container(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar() as VScrollBar
	if bar == null:
		return
	# Make the scrollbar itself wider (default is ~8px, way too thin).
	bar.custom_minimum_size = Vector2(14, 0)
	# Make the scrollbar wider so it's clearly visible.
	bar.add_theme_constant_override("minimum_grab_thickness", 14)
	# Track: subtle warm brown background.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.62, 0.49, 0.12, 0.2)
	track.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("scroll", track)
	var track_hl := StyleBoxFlat.new()
	track_hl.bg_color = Color(0.62, 0.49, 0.12, 0.3)
	track_hl.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("scroll_focus", track_hl)
	# Grabber: lemon yellow, rounded, with padding so it's narrower than the track.
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(1, 0.85, 0.2, 0.7)
	grabber.set_corner_radius_all(4)
	grabber.content_margin_left = 3.0
	grabber.content_margin_right = 3.0
	grabber.content_margin_top = 4.0
	grabber.content_margin_bottom = 4.0
	bar.add_theme_stylebox_override("grabber", grabber)
	var grabber_hl := StyleBoxFlat.new()
	grabber_hl.bg_color = Color(1, 0.85, 0.2, 1.0)
	grabber_hl.set_corner_radius_all(4)
	grabber_hl.content_margin_left = 3.0
	grabber_hl.content_margin_right = 3.0
	grabber_hl.content_margin_top = 4.0
	grabber_hl.content_margin_bottom = 4.0
	bar.add_theme_stylebox_override("grabber_highlight", grabber_hl)
	var grabber_pressed := StyleBoxFlat.new()
	grabber_pressed.bg_color = Color(1, 0.85, 0.2, 1.0)
	grabber_pressed.set_corner_radius_all(4)
	grabber_pressed.content_margin_left = 3.0
	grabber_pressed.content_margin_right = 3.0
	grabber_pressed.content_margin_top = 4.0
	grabber_pressed.content_margin_bottom = 4.0
	bar.add_theme_stylebox_override("grabber_pressed", grabber_pressed)


## Style an HSlider with a custom flat look: thin track + lemon grabber.
func _style_slider(slider: HSlider) -> void:
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


## Create a circular icon texture at runtime.
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


## Remove all stylebox backgrounds so the button looks like plain text.
func _make_flat_button(btn: Button) -> void:
	if btn == null:
		return
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.add_theme_stylebox_override("disabled", empty)


## Wire hover sound + pop animation + press animation for a button.
## pop_left: if true, the button grows to the left on hover (pivot at right).
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


## Responsive scale pop on hover. Pivot at right-center so it grows
## to the right, staying vertically centered. No bounce — just a
## quick, snappy scale up and back.
func _animate_hover(btn: Button, hover: bool) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	# Kill any existing tween on this button to avoid drift.
	if btn.has_meta("_hover_tween") and btn.get_meta("_hover_tween") is Tween:
		(btn.get_meta("_hover_tween") as Tween).kill()
	# Store the original scale on first hover.
	if not btn.has_meta("_base_scale"):
		btn.set_meta("_base_scale", btn.scale)
	# Pivot at left-center (grows right) or right-center (grows left).
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


## Play click sound and run the callback. Release animation happens here.
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


## Stagger buttons sliding in from the left on menu show.
func _animate_buttons_in() -> void:
	var delay: float = 0.0
	for btn in _menu_buttons:
		if btn == null:
			continue
		btn.modulate = Color(1, 1, 1, 0)
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT)
		tw.set_trans(Tween.TRANS_CUBIC)
		tw.tween_interval(delay)
		tw.tween_property(btn, "modulate:a", 1.0, 0.3)
		delay += 0.06


## Position the inline Paste/Clear buttons at the right edge inside the field.
func _position_join_inline_btns() -> void:
	for btn: Button in [_join_paste_btn, _join_clear_btn]:
		if btn and is_instance_valid(btn) and btn.visible:
			btn.position = Vector2(
				_join_field.size.x - btn.size.x - 8,
				(_join_field.size.y - btn.size.y) / 2.0,
			)


func _toggle_join_row() -> void:
	_join_panel.visible = true
	$MenuBox.visible = false
	_join_field.text = ""
	_join_error_label.visible = false
	_join_paste_btn.visible = true
	_join_clear_btn.visible = false
	# Position buttons after the field has its size computed.
	await get_tree().process_frame
	_position_join_inline_btns()
	_join_field.grab_focus()


func _on_join_back() -> void:
	_join_panel.visible = false
	$MenuBox.visible = true


func _on_settings_pressed() -> void:
	_settings_panel.visible = true
	$MenuBox.visible = false
	# Sync current state into the controls.
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
	_fullscreen_check.button_pressed = (
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	)
	_vsync_check.button_pressed = (
		DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	)
	_lighting_check.button_pressed = true
	_fps_check.button_pressed = false


func _on_settings_back() -> void:
	_settings_panel.visible = false
	$MenuBox.visible = true


func _on_join_submit() -> void:
	var text := _join_field.text.strip_edges()
	if not text.is_valid_int():
		_join_error_label.text = "Invalid lobby ID — must be a number"
		_join_error_label.visible = true
		_join_field.text = ""
		_join_paste_btn.visible = true
		return
	_join_error_label.visible = false
	set_busy("Joining lobby...")
	join_pressed.emit(int(text))


func _on_saves_pressed() -> void:
	_refresh_saves()
	_saves_panel.visible = true
	# Hide the main menu buttons while browsing saves.
	$MenuBox.visible = false
	# Re-style the scrollbar after saves are populated — the scrollbar
	# child may not exist until the ScrollContainer has content.
	call_deferred("_style_scroll_container", _save_scroll)


func _on_saves_back() -> void:
	_saves_panel.visible = false
	$MenuBox.visible = true


func _on_new_stand_pressed() -> void:
	# Remove any existing creation panel (prevent stacking from
	# repeated Play clicks).
	var existing := _saves_list.get_node_or_null("InlineModeSelect")
	if existing:
		existing.queue_free()
	# Hide the save list, new stand button, and back button — creation
	# is a separate overlay view.
	_slots_container.visible = false
	_save_scroll.visible = false
	_new_stand_button.visible = false
	_saves_back.visible = false
	# Also hide the saves title + spacers.
	var saves_title := _saves_list.get_node_or_null("SavesTitle")
	if saves_title:
		saves_title.visible = false
	var spacer1 := _saves_list.get_node_or_null("Spacer")
	if spacer1:
		spacer1.visible = false
	var spacer2 := _saves_list.get_node_or_null("Spacer2")
	if spacer2:
		spacer2.visible = false
	_show_mode_select()


## Restore the saves list visibility after cancelling/confirming creation.
## If there are no saves (entered from Play button), go back to the
## main menu instead of showing an empty saves list.
func _restore_saves_list() -> void:
	# If there are no saves, we came from the Play button — go back
	# to the main menu instead of showing an empty saves panel.
	if _saves_data.is_empty():
		_saves_panel.visible = false
		$MenuBox.visible = true
		# Re-show everything in case it was hidden.
		_slots_container.visible = true
		_save_scroll.visible = true
		_new_stand_button.visible = true
		_saves_back.visible = true
		var saves_title := _saves_list.get_node_or_null("SavesTitle")
		if saves_title:
			saves_title.visible = true
		var spacer1 := _saves_list.get_node_or_null("Spacer")
		if spacer1:
			spacer1.visible = true
		var spacer2 := _saves_list.get_node_or_null("Spacer2")
		if spacer2:
			spacer2.visible = true
		return
	_slots_container.visible = true
	_save_scroll.visible = true
	_new_stand_button.visible = true
	_saves_back.visible = true
	var saves_title := _saves_list.get_node_or_null("SavesTitle")
	if saves_title:
		saves_title.visible = true
	var spacer1 := _saves_list.get_node_or_null("Spacer")
	if spacer1:
		spacer1.visible = true
	var spacer2 := _saves_list.get_node_or_null("Spacer2")
	if spacer2:
		spacer2.visible = true


## Step 1: Show mode selection with silhouette icons.
## Cards have icon + name only. A single description label below the
## cards shows the description for the currently selected mode.
func _show_mode_select() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "InlineModeSelect"
	vbox.add_theme_constant_override("separation", 14)

	# Title.
	var title := Label.new()
	title.text = "Game Mode"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	vbox.add_child(title)

	# Spacer matching the saves list layout.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var selected_mode: int = GameState.GameMode.SOLO
	var mode_cards: Dictionary = { } # mode -> PanelContainer
	var mode_styles: Dictionary = { } # mode -> StyleBoxFlat (for border tweening)
	var mode_descs: Dictionary = {
		GameState.GameMode.SOLO: "One player runs their own lemonade stand.",
		GameState.GameMode.COOP: "Up to 4 players share a stand and work together.",
		GameState.GameMode.VERSUS: "Run 2 stands against each other with up to 4 friends.",
	}
	var mode_names: Dictionary = {
		GameState.GameMode.SOLO: "Solo",
		GameState.GameMode.COOP: "Co-op",
		GameState.GameMode.VERSUS: "Versus",
	}

	# Mode cards row.
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 10)
	cards_row.alignment = BoxContainer.ALIGNMENT_BEGIN

	# Description label (declared before the loop so card click lambdas can reference it).
	var desc_label := Label.new()
	desc_label.add_theme_font_size_override("font_size", 18)
	desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.text = mode_descs[GameState.GameMode.SOLO]

	for mode_info in [
		{ "mode": GameState.GameMode.SOLO, "count": 1, "vs": false },
		{ "mode": GameState.GameMode.COOP, "count": 4, "vs": false },
		{ "mode": GameState.GameMode.VERSUS, "count": 2, "vs": true },
	]:
		var mode_val: int = mode_info["mode"]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(100, 0)
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0, 0, 0, 0.2)
		card_style.border_color = Color(1, 1, 1, 0.25)
		card_style.set_border_width_all(2)
		card_style.set_content_margin_all(10)
		card_style.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", card_style)
		mode_styles[mode_val] = card_style

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 6)
		card_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(card_vbox)

		# Silhouette icon (centered).
		var icon := _build_silhouette_icon(mode_info["count"], mode_info["vs"])
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_vbox.add_child(icon)

		# Mode name.
		var name_lbl := Label.new()
		name_lbl.text = mode_names[mode_val]
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_vbox.add_child(name_lbl)

		# Click handling — pop down then back up + select.
		card.gui_input.connect(
			func(event):
				if (
					event is InputEventMouseButton and event.pressed
					and event.button_index == MOUSE_BUTTON_LEFT
				):
					AudioManager.play_sfx_ui("blip_select", 1.0, 0.0)
					if card.has_meta("_ht") and card.get_meta("_ht") is Tween:
						(card.get_meta("_ht") as Tween).kill()
					card.pivot_offset = card.size / 2.0
					# Squash down, then pop back up.
					var tw := create_tween()
					card.set_meta("_ht", tw)
					tw.tween_property(card, "scale", Vector2.ONE * 0.92, 0.06) \
							.set_ease(Tween.EASE_IN)
					tw.tween_property(card, "scale", Vector2.ONE * HOVER_POP, 0.12) \
							.set_ease(Tween.EASE_OUT) \
							.set_trans(Tween.TRANS_BACK)
					# Update selection after the pop starts.
					selected_mode = mode_val
					desc_label.text = mode_descs[mode_val]
					_update_mode_card_selection(mode_cards, mode_styles, mode_val),
		)
		# Hover effect on the card — pop the whole card panel.
		card.mouse_entered.connect(
			func():
				AudioManager.play_sfx_ui("blip_select", 1.0, 0.0)
				if card.has_meta("_ht") and card.get_meta("_ht") is Tween:
					(card.get_meta("_ht") as Tween).kill()
				card.pivot_offset = card.size / 2.0
				var tw := create_tween()
				card.set_meta("_ht", tw)
				tw.set_parallel(true)
				if mode_val != selected_mode:
					tw.tween_property(card_style, "border_color", Color(1, 1, 1, 0.6), 0.08)
				tw.tween_property(card, "scale", Vector2.ONE * HOVER_POP, 0.06) \
						.set_ease(Tween.EASE_OUT),
		)
		card.mouse_exited.connect(
			func():
				if card.has_meta("_ht") and card.get_meta("_ht") is Tween:
					(card.get_meta("_ht") as Tween).kill()
				card.pivot_offset = card.size / 2.0
				var tw := create_tween()
				card.set_meta("_ht", tw)
				tw.set_parallel(true)
				if mode_val != selected_mode:
					tw.tween_property(card_style, "border_color", Color(1, 1, 1, 0.25), 0.12)
				tw.tween_property(card, "scale", Vector2.ONE, 0.08) \
						.set_ease(Tween.EASE_OUT),
		)

		mode_cards[mode_val] = card
		cards_row.add_child(card)

	# Wrap cards + description + name field in a shrink-to-content VBox so
	# the description and field match the cards' combined width.
	var cards_wrap := VBoxContainer.new()
	cards_wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cards_wrap.add_theme_constant_override("separation", 10)
	cards_wrap.add_child(cards_row)
	cards_wrap.add_child(desc_label)
	vbox.add_child(cards_wrap)

	# Name field (inside cards_wrap so it matches the cards' width).
	var field := LineEdit.new()
	field.name = "NameField"
	field.custom_minimum_size = Vector2(0, 40)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_font_size_override("font_size", 20)
	field.placeholder_text = "Enter stand name..."
	field.text_changed.connect(
		func(new_text: String):
			if _name_weight(new_text) > NAME_MAX_WEIGHT:
				field.text = new_text.substr(0, new_text.length() - 1)
				field.caret_column = field.text.length(),
	)
	var field_style := StyleBoxFlat.new()
	field_style.bg_color = Color(0, 0, 0, 0.3)
	field_style.border_color = Color(1, 1, 1, 1.0)
	field_style.set_border_width_all(2)
	field_style.set_content_margin_all(10)
	field_style.set_corner_radius_all(4)
	field.add_theme_stylebox_override("normal", field_style)
	var field_focus := StyleBoxFlat.new()
	field_focus.bg_color = Color(0, 0, 0, 0.3)
	field_focus.border_color = Color(1, 1, 1, 1.0)
	field_focus.set_border_width_all(2)
	field_focus.set_content_margin_all(10)
	field_focus.set_corner_radius_all(4)
	field.add_theme_stylebox_override("focus", field_focus)
	var field_readonly := StyleBoxFlat.new()
	field_readonly.bg_color = Color(0, 0, 0, 0.3)
	field_readonly.border_color = Color(1, 1, 1, 1.0)
	field_readonly.set_border_width_all(2)
	field_readonly.set_content_margin_all(10)
	field_readonly.set_corner_radius_all(4)
	field.add_theme_stylebox_override("read_only", field_readonly)
	field.add_theme_color_override("font_color", Color(1, 1, 1, 1.0))
	field.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.5))
	field.add_theme_color_override("caret_color", Color(1, 1, 1, 1.0))
	field.text_submitted.connect(
		func(text):
			_confirm_inline_name(vbox, field, selected_mode),
	)
	cards_wrap.add_child(field)

	# Buttons: Back (left) + Create (right), inside cards_wrap so they
	# span the same width as the name field.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 48)
	back_btn.add_theme_font_size_override("font_size", 38)
	back_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	back_btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	_make_flat_button(back_btn)
	_add_drop_shadow(back_btn)
	_setup_hover_effect(back_btn)
	back_btn.pressed.connect(
		func():
			vbox.queue_free()
			_restore_saves_list(),
	)
	# Spacer pushes Create to the right edge.
	var btn_spacer := Control.new()
	btn_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var create_btn := Button.new()
	create_btn.name = "CreateBtn"
	create_btn.text = "Create"
	create_btn.custom_minimum_size = Vector2(0, 48)
	create_btn.add_theme_font_size_override("font_size", 38)
	create_btn.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 0.9))
	create_btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
	_make_flat_button(create_btn)
	_add_drop_shadow(create_btn)
	_setup_hover_effect(create_btn)
	create_btn.pressed.connect(
		func():
			_confirm_inline_name(vbox, field, selected_mode),
	)
	btn_row.add_child(back_btn)
	btn_row.add_child(btn_spacer)
	btn_row.add_child(create_btn)
	cards_wrap.add_child(btn_row)

	# Default: Solo selected.
	_update_mode_card_selection(mode_cards, mode_styles, GameState.GameMode.SOLO)

	var idx := _new_stand_button.get_index()
	_saves_list.add_child(vbox)
	_saves_list.move_child(vbox, idx)
	field.grab_focus()


## Update mode card borders: selected = bright yellow, others = dim.
func _update_mode_card_selection(cards: Dictionary, styles: Dictionary, selected: int) -> void:
	for key in cards:
		var style: StyleBoxFlat = styles[key]
		var card: PanelContainer = cards[key]
		if key == selected:
			style.border_color = Color(1, 0.9, 0.3, 1.0)
			style.bg_color = Color(0.15, 0.12, 0.05, 0.3)
		else:
			style.border_color = Color(1, 1, 1, 0.25)
			style.bg_color = Color(0, 0, 0, 0.2)
		card.add_theme_stylebox_override("panel", style)


func _confirm_inline_name(panel: VBoxContainer, field: LineEdit, mode: int) -> void:
	var name := field.text.strip_edges()
	if name == "":
		return
	panel.queue_free()
	_restore_saves_list()
	set_busy("Creating '%s'..." % name)
	new_stand_requested.emit(name, mode)


## Weighted character count: capitals count as 1.5, everything else as 1.
func _name_weight(s: String) -> float:
	var weight: float = 0.0
	for ch in s:
		if ch >= "A" and ch <= "Z":
			weight += 1.5
		else:
			weight += 1.0
	return weight


## Build a compact silhouette icon for a save row (smaller than the button version).
func _build_save_mode_icon(mode: int) -> Control:
	var count := 1
	var vs := false
	match mode:
		GameState.GameMode.COOP:
			count = 4
		GameState.GameMode.VERSUS:
			count = 2
			vs = true
	return _build_silhouette_icon(count, vs)


## Build a person silhouette icon for the mode selection buttons.
## count = number of people per side. vs = show two groups separated by "VS".
## Each person is a simple head circle + body shape drawn with a custom Control.
func _build_silhouette_icon(count: int, vs: bool) -> Control:
	var container := HBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_theme_constant_override("separation", 4)
	container.alignment = BoxContainer.ALIGNMENT_CENTER

	if vs:
		# Left group (count people).
		var left := HBoxContainer.new()
		left.add_theme_constant_override("separation", 2)
		for i in count:
			left.add_child(_PersonSilhouette.new())
		container.add_child(left)
		# VS label.
		var vs_label := Label.new()
		vs_label.text = "VS"
		vs_label.add_theme_font_size_override("font_size", 14)
		vs_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 0.8))
		vs_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(vs_label)
		# Right group (count people).
		var right := HBoxContainer.new()
		right.add_theme_constant_override("separation", 2)
		for i in count:
			right.add_child(_PersonSilhouette.new())
		container.add_child(right)
	else:
		for i in count:
			container.add_child(_PersonSilhouette.new())
	return container


## Custom Control that draws a simple person silhouette (head + body).
class _PersonSilhouette:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(10, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE


	func _draw() -> void:
		var c := Color(1, 1, 1, 0.85)
		# Head: circle.
		draw_circle(Vector2(5, 4), 3.5, c)
		# Body: rounded rectangle (shoulders + torso).
		var body := Rect2(1.5, 8, 7, 12)
		draw_rect(body, c, true)
		# Round the shoulders slightly by drawing circles at top corners.
		draw_circle(Vector2(2.5, 9), 1.5, c)
		draw_circle(Vector2(7.5, 9), 1.5, c)


## Build the saves list dynamically from SaveManager.list_saves().
func _refresh_saves() -> void:
	_saves_data = SaveManager.list_saves()
	# Clear old slot rows.
	for child in _slots_container.get_children():
		child.queue_free()
	# Build a row for each save. The first (most recently saved) is "active".
	var save_idx := 0
	for save in _saves_data:
		var slot_name: String = save.get("slot", "")
		var stand_name: String = save.get("stand_name", slot_name)
		var game_mode: int = save.get("game_mode", GameState.GameMode.SOLO)
		var day: int = save.get("day", 1)
		var money: float = save.get("money", 0.0)
		var saved_at: float = save.get("saved_at", 0.0)
		var date_text := ""
		if saved_at > 0:
			var dict := Time.get_datetime_dict_from_unix_time(int(saved_at))
			date_text = "%02d/%02d %02d:%02d" % [
				dict["month"],
				dict["day"],
				dict["hour"],
				dict["minute"],
			]
		var is_active := save_idx == 0
		var row := _build_save_row(
			slot_name,
			stand_name,
			game_mode,
			day,
			money,
			date_text,
			is_active,
		)
		_slots_container.add_child(row)
		save_idx += 1
	# Dynamically size the scroll container so the New Stand button sits
	# right below the stands when there are few, and only scrolls when
	# there are enough to exceed the max height.
	_resize_save_scroll()


## Resize the SaveScroll to fit its content, up to a maximum height.
## This keeps the New Stand button close to the stands when there are
# few/no saves, instead of leaving a large empty gap.
const SAVE_SCROLL_MAX_HEIGHT: float = 340.0
const SAVE_ROW_ESTIMATE: float = 90.0 # Approximate height per row + separation


func _resize_save_scroll() -> void:
	var count := _saves_data.size()
	if count == 0:
		# No stands: shrink the scroll area to a minimal height so the
		# New Stand button is right near the top.
		_save_scroll.custom_minimum_size = Vector2(0, 10)
		return
	# Estimate the content height and cap at the max.
	var estimated_height: float = count * SAVE_ROW_ESTIMATE
	var scroll_height: float = minf(estimated_height, SAVE_SCROLL_MAX_HEIGHT)
	_save_scroll.custom_minimum_size = Vector2(0, scroll_height)


## Build a single save row: [Button(colored text) | Delete].
const SAVE_BOX_WIDTH: float = 340.0


func _build_save_row(
	slot_name: String,
	stand_name: String,
	game_mode: int,
	day: int,
	money: float,
	date_text: String,
	is_active: bool = false,
) -> HBoxContainer:
	# Outer row: [Panel(box) | Delete/Yes/No]
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	# Panel with subtle outline that pops as a whole on hover.
	# Active save gets a yellow border; others get white.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SAVE_BOX_WIDTH, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0)
	if is_active:
		panel_style.border_color = Color(1, 0.9, 0.3, 1.0)
		panel_style.set_border_width_all(2)
	else:
		panel_style.border_color = Color(1, 1, 1, 0.4)
		panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(10)
	panel_style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", panel_style)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	# Stand name label — yellow if active, white otherwise.
	var btn := Label.new()
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_font_size_override("font_size", 26)
	if is_active:
		btn.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1.0))
	else:
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1.0))
	btn.add_theme_color_override("shadow_color", Color(0, 0, 0, 0.6))
	btn.add_theme_constant_override("shadow_offset_x", 2)
	btn.add_theme_constant_override("shadow_offset_y", 2)
	btn.add_theme_constant_override("shadow_outline_size", 4)
	btn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = stand_name
	row.add_child(btn)
	# Info line: silhouette mode icon + small dim text.
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 6)
	info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Build the silhouette icon for this save's mode.
	var mode_icon := _build_save_mode_icon(game_mode)
	mode_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_row.add_child(mode_icon)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.text = "Day %d  |  $%.2f  |  %s" % [day, money, date_text]
	info_row.add_child(info)
	row.add_child(info_row)
	# Hover: pop the inner content (row) + brighten border. Panel outline stays put.
	panel.mouse_entered.connect(
		func():
			AudioManager.play_sfx_ui("blip_select", 1.0, 0.0)
			if panel.has_meta("_hover_tween") and panel.get_meta("_hover_tween") is Tween:
				(panel.get_meta("_hover_tween") as Tween).kill()
			row.pivot_offset = Vector2(0, row.size.y / 2.0)
			var tw := create_tween()
			panel.set_meta("_hover_tween", tw)
			tw.set_parallel(true)
			tw.tween_property(row, "scale", Vector2.ONE * HOVER_POP, 0.06) \
					.set_ease(Tween.EASE_OUT)
			tw.tween_property(panel_style, "border_color", Color(1, 1, 1, 1.0), 0.08) \
					.set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "modulate", Color(1.0, 0.95, 0.7), 0.06) \
					.set_ease(Tween.EASE_OUT)
			tw.tween_property(info_row, "modulate", Color(1, 1, 1, 1.0), 0.06) \
					.set_ease(Tween.EASE_OUT),
	)
	panel.mouse_exited.connect(
		func():
			if panel.has_meta("_hover_tween") and panel.get_meta("_hover_tween") is Tween:
				(panel.get_meta("_hover_tween") as Tween).kill()
			var tw := create_tween()
			panel.set_meta("_hover_tween", tw)
			tw.set_parallel(true)
			tw.tween_property(row, "scale", Vector2.ONE, 0.08) \
					.set_ease(Tween.EASE_OUT)
			var restore_color := Color(1, 1, 1, 0.4) if not is_active else Color(1, 0.9, 0.3, 1.0)
			tw.tween_property(panel_style, "border_color", restore_color, 0.12) \
					.set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "modulate", Color.WHITE, 0.08) \
					.set_ease(Tween.EASE_OUT)
			tw.tween_property(info_row, "modulate", Color(1, 1, 1, 0.7), 0.08) \
					.set_ease(Tween.EASE_OUT),
	)
	# Click anywhere on the panel loads the save.
	panel.gui_input.connect(
		func(event):
			if (
				event is InputEventMouseButton and event.pressed
				and event.button_index == MOUSE_BUTTON_LEFT
			):
				AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
				_on_load_save(slot_name, stand_name),
	)
	outer.add_child(panel)
	# Delete button — replaced by Yes/No inline when clicked.
	var del_btn := Button.new()
	del_btn.add_theme_font_size_override("font_size", 20)
	del_btn.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 0.7))
	del_btn.add_theme_color_override("font_hover_color", Color(1, 0.3, 0.3, 1))
	del_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	del_btn.text = "Delete"
	_make_flat_button(del_btn)
	_setup_hover_effect(del_btn)
	# Yes/No container (hidden until Delete is pressed).
	var confirm_row := HBoxContainer.new()
	confirm_row.add_theme_constant_override("separation", 12)
	confirm_row.visible = false
	var yes_btn := Button.new()
	yes_btn.add_theme_font_size_override("font_size", 20)
	yes_btn.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 0.9))
	yes_btn.add_theme_color_override("font_hover_color", Color(1, 0.2, 0.2, 1))
	yes_btn.text = "Yes"
	_make_flat_button(yes_btn)
	_setup_hover_effect(yes_btn)
	yes_btn.pressed.connect(
		func():
			_on_button_click(
				yes_btn,
				func():
					SaveManager.delete_slot(slot_name)
					_refresh_saves(),
			),
	)
	# Divider between Yes and No.
	var divider := VSeparator.new()
	divider.add_theme_constant_override("separation", 0)
	divider.custom_minimum_size = Vector2(1, 20)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var div_style := StyleBoxFlat.new()
	div_style.bg_color = Color(1, 1, 1, 0.3)
	div_style.content_margin_left = 0.5
	div_style.content_margin_right = 0.5
	divider.add_theme_stylebox_override("separator", div_style)
	var no_btn := Button.new()
	no_btn.add_theme_font_size_override("font_size", 20)
	no_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	no_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.8))
	no_btn.text = "No"
	_make_flat_button(no_btn)
	_setup_hover_effect(no_btn, true) # pop_left = true
	no_btn.pressed.connect(
		func():
			_on_button_click(
				no_btn,
				func():
					confirm_row.visible = false
					del_btn.visible = true,
			),
	)
	confirm_row.add_child(yes_btn)
	confirm_row.add_child(divider)
	confirm_row.add_child(no_btn)
	del_btn.pressed.connect(
		func():
			_on_button_click(
				del_btn,
				func():
					del_btn.visible = false
					confirm_row.visible = true,
			),
	)
	outer.add_child(del_btn)
	outer.add_child(confirm_row)
	return outer


func _on_load_save(slot_name: String, stand_name: String) -> void:
	set_busy("Loading %s..." % stand_name)
	load_stand_requested.emit(slot_name)

# ─── Music Player Widget ───

const MUSIC_WIDGET_W: float = 280.0
const MUSIC_WIDGET_H: float = 88.0


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
	bg.bg_color = Color(0.05, 0.05, 0.08, 0.55)
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

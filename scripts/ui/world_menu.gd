extends CanvasLayer
## In-world main menu overlay. Professional left-aligned text buttons
## with hover animations and click sounds.

signal play_pressed
signal saves_pressed
signal join_pressed(lobby_id: int)
signal host_pressed
signal new_stand_requested(stand_name: String)
signal load_stand_requested(slot_name: String)

const HOVER_POP: float = 1.12
const HOVER_DURATION: float = 0.18
const NAME_MAX_WEIGHT: float = 15.0 # Capitals count as 1.5, lowercase as 1.

@onready var _play_button: Button = $MenuBox/PlayButton
@onready var _title_label: Label = $MenuBox/TitleBox/TitleLabel
@onready var _subtitle_label: Label = $MenuBox/TitleBox/SubtitleLabel
@onready var _saves_button: Button = $MenuBox/SavesButton
@onready var _join_button: Button = $MenuBox/JoinButton
@onready var _join_row: HBoxContainer = $MenuBox/JoinRow
@onready var _join_field: LineEdit = $MenuBox/JoinRow/JoinField
@onready var _join_submit: Button = $MenuBox/JoinRow/JoinSubmit
@onready var _quit_button: Button = $MenuBox/QuitButton
@onready var _status_label: Label = $MenuBox/StatusLabel
@onready var _version_label: Label = $VersionLabel

# Saves panel
@onready var _saves_panel: Control = $SavesPanel
@onready var _saves_list: VBoxContainer = $SavesPanel/SavesList
@onready var _slots_container: VBoxContainer = $SavesPanel/SavesList/SlotsContainer
@onready var _new_stand_button: Button = $SavesPanel/SavesList/NewStandButton
@onready var _saves_back: Button = $SavesPanel/BackButton

var _saves_data: Array = []
var _menu_buttons: Array[Button] = []


func _ready() -> void:
	_menu_buttons = [_play_button, _saves_button, _join_button, _quit_button]
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
	_quit_button.pressed.connect(
		func():
			_on_button_click(
				_quit_button,
				func():
					get_tree().quit(),
			),
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
	_make_flat_button(_saves_back)
	_add_drop_shadow(_saves_back)
	_setup_hover_effect(_saves_back)
	_make_flat_button(_new_stand_button)
	_add_drop_shadow(_new_stand_button)
	_setup_hover_effect(_new_stand_button)
	# Size "Simulator" to match the width of "Lemonade Stand".
	_fit_subtitle_width()


func show_menu() -> void:
	visible = true
	_saves_panel.visible = false
	_join_row.visible = false
	_status_label.text = ""
	# Animate buttons in
	_animate_buttons_in()


## Show the menu without the stagger animation (used after transitions).
## Fades in over `duration` seconds.
func show_menu_immediate(duration: float = 0.4) -> void:
	visible = true
	_saves_panel.visible = false
	_join_row.visible = false
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
	visible = false


func set_status(text: String) -> void:
	_status_label.text = text


func set_busy(text: String) -> void:
	set_status(text)
	for btn in _menu_buttons:
		btn.disabled = true


func set_enabled(enabled: bool) -> void:
	for btn in _menu_buttons:
		btn.disabled = not enabled


## Show the inline name entry (used by Play button when no saves exist).
func show_name_entry() -> void:
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


func _toggle_join_row() -> void:
	_join_row.visible = not _join_row.visible
	if _join_row.visible:
		_join_field.grab_focus()


func _on_join_submit() -> void:
	var text := _join_field.text.strip_edges()
	if not text.is_valid_int():
		_status_label.text = "Enter a valid lobby ID"
		return
	set_busy("Joining lobby...")
	join_pressed.emit(int(text))


func _on_saves_pressed() -> void:
	_refresh_saves()
	_saves_panel.visible = true
	# Hide the main menu buttons while browsing saves.
	$MenuBox.visible = false


func _on_saves_back() -> void:
	_saves_panel.visible = false
	$MenuBox.visible = true


func _on_new_stand_pressed() -> void:
	# Inline name entry: hide the New Stand button, show a LineEdit +
	# Create button in its place.
	_new_stand_button.visible = false
	var row := HBoxContainer.new()
	row.name = "InlineNameEntry"
	row.add_theme_constant_override("separation", 12)
	var field := LineEdit.new()
	field.name = "NameField"
	field.size_flags_horizontal = 3
	field.add_theme_font_size_override("font_size", 20)
	field.placeholder_text = "Stand name..."
	# Limit by weighted char count: capitals = 1.5, others = 1.0.
	# Reject typed/deleted text that would exceed NAME_MAX_WEIGHT.
	field.text_changed.connect(
		func(new_text: String):
			if _name_weight(new_text) > NAME_MAX_WEIGHT:
				# Revert to the previous text by trimming the last char.
				field.text = new_text.substr(0, new_text.length() - 1)
				field.caret_column = field.text.length(),
	)
	# Transparent background, white outline border.
	var field_style := StyleBoxFlat.new()
	field_style.bg_color = Color(0, 0, 0, 0)
	field_style.border_color = Color(1, 1, 1, 0.6)
	field_style.set_border_width_all(2)
	field_style.set_content_margin_all(6)
	field.add_theme_stylebox_override("normal", field_style)
	var field_focus := StyleBoxFlat.new()
	field_focus.bg_color = Color(0, 0, 0, 0)
	field_focus.border_color = Color(1, 1, 1, 0.9)
	field_focus.set_border_width_all(2)
	field_focus.set_content_margin_all(6)
	field.add_theme_stylebox_override("focus", field_focus)
	var field_readonly := StyleBoxFlat.new()
	field_readonly.bg_color = Color(0, 0, 0, 0)
	field_readonly.border_color = Color(1, 1, 1, 0.6)
	field_readonly.set_border_width_all(2)
	field_readonly.set_content_margin_all(6)
	field.add_theme_stylebox_override("read_only", field_readonly)
	field.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	field.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.4))
	field.add_theme_color_override("caret_color", Color(1, 1, 1, 0.9))
	field.text_submitted.connect(
		func(text):
			_confirm_inline_name(row, field),
	)
	field.focus_exited.connect(
		func():
			# Cancel if focus lost and field is empty; otherwise keep it
			# so the Create button can still be clicked.
			if field.text.strip_edges() == "":
				_cancel_inline_name(row),
	)
	var create_btn := Button.new()
	create_btn.name = "CreateBtn"
	create_btn.text = "Create"
	create_btn.add_theme_font_size_override("font_size", 20)
	create_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	create_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	_make_flat_button(create_btn)
	_add_drop_shadow(create_btn)
	create_btn.pressed.connect(
		func():
			_confirm_inline_name(row, field),
	)
	row.add_child(field)
	row.add_child(create_btn)
	# Insert the inline row where the New Stand button was (before Spacer2).
	var idx := _new_stand_button.get_index()
	_saves_list.add_child(row)
	_saves_list.move_child(row, idx)
	field.grab_focus()


func _confirm_inline_name(row: HBoxContainer, field: LineEdit) -> void:
	var name := field.text.strip_edges()
	if name == "":
		_cancel_inline_name(row)
		return
	row.queue_free()
	_new_stand_button.visible = true
	set_busy("Creating '%s'..." % name)
	new_stand_requested.emit(name)


func _cancel_inline_name(row: HBoxContainer) -> void:
	row.queue_free()
	_new_stand_button.visible = true


## Weighted character count: capitals count as 1.5, everything else as 1.
func _name_weight(s: String) -> float:
	var weight: float = 0.0
	for ch in s:
		if ch >= "A" and ch <= "Z":
			weight += 1.5
		else:
			weight += 1.0
	return weight


## Build the saves list dynamically from SaveManager.list_saves().
func _refresh_saves() -> void:
	_saves_data = SaveManager.list_saves()
	# Clear old slot rows.
	for child in _slots_container.get_children():
		child.queue_free()
	# Build a row for each save.
	for save in _saves_data:
		var slot_name: String = save.get("slot", "")
		var stand_name: String = save.get("stand_name", slot_name)
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
		var row := _build_save_row(slot_name, stand_name, day, money, date_text)
		_slots_container.add_child(row)


## Build a single save row: [Button(colored text) | Delete].
const SAVE_BOX_WIDTH: float = 360.0


func _build_save_row(
	slot_name: String,
	stand_name: String,
	day: int,
	money: float,
	date_text: String,
) -> HBoxContainer:
	# Outer row: [Panel(box) | Delete/Yes/No]
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	# Panel with subtle outline that pops as a whole on hover.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SAVE_BOX_WIDTH, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0)
	panel_style.border_color = Color(1, 1, 1, 0.15)
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(10)
	panel_style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", panel_style)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	# Stand name label (large, yellow) — no mouse interaction, panel handles everything.
	var btn := Label.new()
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 0.9))
	btn.add_theme_color_override("shadow_color", Color(0, 0, 0, 0.6))
	btn.add_theme_constant_override("shadow_offset_x", 2)
	btn.add_theme_constant_override("shadow_offset_y", 2)
	btn.add_theme_constant_override("shadow_outline_size", 4)
	btn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = stand_name
	row.add_child(btn)
	# Info line: small, dim text under the name.
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	info.text = "Day %d  |  $%.2f  |  last played %s" % [day, money, date_text]
	row.add_child(info)
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
			tw.tween_property(panel_style, "border_color", Color(1, 1, 1, 0.4), 0.08) \
					.set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "modulate", Color(1.0, 0.95, 0.7), 0.06) \
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
			tw.tween_property(panel_style, "border_color", Color(1, 1, 1, 0.15), 0.12) \
					.set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "modulate", Color.WHITE, 0.08) \
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

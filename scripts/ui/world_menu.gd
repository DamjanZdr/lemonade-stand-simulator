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
const HOVER_OVERSHOOT: float = 1.18
const HOVER_DURATION: float = 0.18

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
@onready var _saves_back: Button = $SavesPanel/SavesList/BackButton
@onready var _confirm_dialog: ConfirmationDialog = $ConfirmDialog
@onready var _name_entry_dialog: AcceptDialog = $NameEntryDialog
@onready var _name_entry_field: LineEdit = $NameEntryDialog/NameEntry

var _saves_data: Array = []
var _pending_delete: String = ""
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
	_confirm_dialog.confirmed.connect(_on_confirm_delete)
	_confirm_dialog.canceled.connect(
		func():
			_pending_delete = "",
	)
	_name_entry_dialog.confirmed.connect(_on_name_entry_confirmed)
	_name_entry_dialog.canceled.connect(
		func():
			_name_entry_field.text = "",
	)
	# Allow Enter in the line edit to confirm the dialog.
	_name_entry_field.text_submitted.connect(
		func(_text):
			_name_entry_dialog.hide()
			_on_name_entry_confirmed(),
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


## Show the name entry dialog (used by Play button when no saves exist).
func show_name_entry() -> void:
	_name_entry_field.text = ""
	_name_entry_dialog.popup_centered()
	_name_entry_field.grab_focus()


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


## Wire hover sound + slide-right animation for a button.
func _setup_hover_effect(btn: Button) -> void:
	if btn == null:
		return
	btn.mouse_entered.connect(
		func():
			AudioManager.play_sfx_ui("hover", 1.0, 0.05)
			if not btn.disabled:
				_animate_hover(btn, true),
	)
	btn.mouse_exited.connect(
		func():
			_animate_hover(btn, false),
	)


## Juicy centered scale "pop" on hover — overshoots then settles.
func _animate_hover(btn: Button, hover: bool) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	# Kill any existing tween on this button to avoid drift.
	if btn.has_meta("_hover_tween") and btn.get_meta("_hover_tween") is Tween:
		(btn.get_meta("_hover_tween") as Tween).kill()
	# Store the original scale on first hover.
	if not btn.has_meta("_base_scale"):
		btn.set_meta("_base_scale", btn.scale)
	# Set pivot to center so the pop is vertically centered.
	btn.pivot_offset = btn.size / 2.0
	var base_scale: Vector2 = btn.get_meta("_base_scale")
	var tw := create_tween()
	btn.set_meta("_hover_tween", tw)
	if hover:
		# Two-step bounce: snap to overshoot, then settle back.
		tw.set_parallel(true)
		tw.tween_property(btn, "scale", base_scale * HOVER_OVERSHOOT, 0.08) \
				.set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "modulate", Color(1.0, 0.95, 0.7), 0.1) \
				.set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(btn, "scale", base_scale * HOVER_POP, 0.1) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.set_parallel(true)
		tw.tween_property(btn, "scale", base_scale, 0.12) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "modulate", Color.WHITE, 0.12) \
				.set_ease(Tween.EASE_OUT)


## Play click sound and run the callback.
func _on_button_click(btn: Button, callback: Callable) -> void:
	AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
	# Quick press animation
	if btn != null and is_instance_valid(btn):
		var tw := create_tween()
		tw.tween_property(btn, "modulate", Color(0.8, 0.8, 0.85), 0.05)
		tw.tween_property(btn, "modulate", Color(1.0, 0.95, 0.7), 0.1)
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
	_name_entry_field.text = ""
	_name_entry_dialog.popup_centered()
	_name_entry_field.grab_focus()


func _on_name_entry_confirmed() -> void:
	var name := _name_entry_field.text.strip_edges()
	if name == "":
		return
	set_busy("Creating '%s'..." % name)
	new_stand_requested.emit(name)


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
func _build_save_row(
	slot_name: String,
	stand_name: String,
	day: int,
	money: float,
	date_text: String,
) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	# Top row: stand name button (large, yellow) + delete button.
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 0.9))
	btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.5, 1))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = stand_name
	_make_flat_button(btn)
	_setup_hover_effect(btn)
	btn.pressed.connect(
		func():
			_on_button_click(
				btn,
				func():
					_on_load_save(slot_name, stand_name),
			),
	)
	top_row.add_child(btn)
	# Delete button.
	var del_btn := Button.new()
	del_btn.custom_minimum_size = Vector2(70, 36)
	del_btn.add_theme_font_size_override("font_size", 14)
	del_btn.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 0.7))
	del_btn.add_theme_color_override("font_hover_color", Color(1, 0.3, 0.3, 1))
	del_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	del_btn.text = "Delete"
	_make_flat_button(del_btn)
	_setup_hover_effect(del_btn)
	del_btn.pressed.connect(
		func():
			_on_button_click(
				del_btn,
				func():
					_on_delete_save(slot_name, stand_name),
			),
	)
	top_row.add_child(del_btn)
	row.add_child(top_row)
	# Info line: small, dim text under the name.
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	info.text = "Day %d  |  $%.2f  |  last played %s" % [day, money, date_text]
	row.add_child(info)
	return row


func _on_load_save(slot_name: String, stand_name: String) -> void:
	set_busy("Loading %s..." % stand_name)
	load_stand_requested.emit(slot_name)


func _on_delete_save(slot_name: String, stand_name: String) -> void:
	_pending_delete = slot_name
	_confirm_dialog.dialog_text = "Delete '%s'? This cannot be undone." % stand_name
	_confirm_dialog.popup_centered()


func _on_confirm_delete() -> void:
	if _pending_delete == "":
		return
	SaveManager.delete_slot(_pending_delete)
	_pending_delete = ""
	_refresh_saves()

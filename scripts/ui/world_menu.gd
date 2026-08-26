extends CanvasLayer
## In-world main menu overlay. Professional left-aligned text buttons
## with hover animations and click sounds.

signal play_pressed
signal saves_pressed
signal join_pressed(lobby_id: int)
signal host_pressed

const SLOT_NAMES: Array[String] = ["Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5"]

# Text button scene for reuse
const HOVER_OFFSET: float = 12.0
const HOVER_DURATION: float = 0.12

@onready var _play_button: Button = $MenuBox/PlayButton
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
@onready var _slots_row: HBoxContainer = $SavesPanel/SlotsRow
@onready var _saves_back: Button = $SavesPanel/BackButton
@onready var _confirm_dialog: ConfirmationDialog = $ConfirmDialog

var _slot_buttons: Array[Button] = []
var _slot_infos: Array[Label] = []
var _delete_buttons: Array[Button] = []
var _saves_by_slot: Dictionary = { }
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
	_confirm_dialog.confirmed.connect(_on_confirm_delete)
	_confirm_dialog.canceled.connect(
		func():
			_pending_delete = "",
	)
	_version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.0.0")
	# Remove button backgrounds so they look like plain text, then wire hover.
	for btn in _menu_buttons:
		_make_flat_button(btn)
		_setup_hover_effect(btn)
	_make_flat_button(_join_submit)
	_setup_hover_effect(_join_submit)
	_make_flat_button(_saves_back)
	_setup_hover_effect(_saves_back)
	_collect_slot_nodes()
	_refresh_saves()


func show_menu() -> void:
	visible = true
	_saves_panel.visible = false
	_join_row.visible = false
	_status_label.text = ""
	# Animate buttons in
	_animate_buttons_in()


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


## Slide button slightly right on hover, back on exit.
func _animate_hover(btn: Button, hover: bool) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	# Kill any existing tween on this button to avoid drift.
	if btn.has_meta("_hover_tween") and btn.get_meta("_hover_tween") is Tween:
		(btn.get_meta("_hover_tween") as Tween).kill()
	# Store the original position on first hover.
	if not btn.has_meta("_base_pos"):
		btn.set_meta("_base_pos", btn.position)
	var base_pos: Vector2 = btn.get_meta("_base_pos")
	var tw := create_tween()
	btn.set_meta("_hover_tween", tw)
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	if hover:
		tw.tween_property(btn, "position", base_pos + Vector2(HOVER_OFFSET, 0), HOVER_DURATION)
		tw.tween_property(btn, "modulate", Color(1.0, 0.95, 0.7), HOVER_DURATION)
	else:
		tw.tween_property(btn, "position", base_pos, HOVER_DURATION)
		tw.tween_property(btn, "modulate", Color.WHITE, HOVER_DURATION)


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


func _on_saves_back() -> void:
	_saves_panel.visible = false


func _collect_slot_nodes() -> void:
	_slot_buttons.clear()
	_slot_infos.clear()
	_delete_buttons.clear()
	for i in SLOT_NAMES.size():
		var slot_node := _slots_row.get_child(i) as VBoxContainer
		_slot_buttons.append(slot_node.get_node("SlotButton") as Button)
		_slot_infos.append(slot_node.get_node("SlotInfo") as Label)
		_delete_buttons.append(slot_node.get_node("DeleteButton") as Button)
		# Wire hover/click for slot buttons
		_setup_hover_effect(_slot_buttons[i])
		_setup_hover_effect(_delete_buttons[i])


func _refresh_saves() -> void:
	_saves_by_slot.clear()
	for save in SaveManager.list_saves():
		var slot: String = save.get("slot", "")
		if SLOT_NAMES.has(slot):
			_saves_by_slot[slot] = save
	for i in SLOT_NAMES.size():
		var slot_name := SLOT_NAMES[i]
		var btn := _slot_buttons[i]
		var info := _slot_infos[i]
		var del_btn := _delete_buttons[i]
		if _saves_by_slot.has(slot_name):
			var save: Dictionary = _saves_by_slot[slot_name]
			var display_name: String = save.get("name", slot_name)
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
			btn.text = display_name
			info.text = "Day %d  |  $%.2f\n%s" % [day, money, date_text]
			del_btn.visible = true
		else:
			btn.text = "New Game"
			info.text = ""
			del_btn.visible = false
		if not btn.pressed.is_connected(_on_slot_pressed):
			btn.pressed.connect(_on_slot_pressed.bind(slot_name))
		if not del_btn.pressed.is_connected(_on_delete_pressed):
			del_btn.pressed.connect(_on_delete_pressed.bind(slot_name))


func _on_slot_pressed(slot_name: String) -> void:
	AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
	if _saves_by_slot.has(slot_name):
		set_busy("Loading %s..." % _saves_by_slot[slot_name].get("name", slot_name))
		SaveManager.load_existing_game(slot_name)
	else:
		set_busy("Starting new game...")
		SaveManager.start_new_game(slot_name)
	host_pressed.emit()


func _on_delete_pressed(slot_name: String) -> void:
	AudioManager.play_sfx_ui("tab_click", 1.0, 0.03)
	_pending_delete = slot_name
	var display_name: String = _saves_by_slot.get(slot_name, { }).get("name", slot_name)
	_confirm_dialog.dialog_text = "Delete '%s'? This cannot be undone." % display_name
	_confirm_dialog.popup_centered()


func _on_confirm_delete() -> void:
	if _pending_delete == "":
		return
	SaveManager.delete_slot(_pending_delete)
	_pending_delete = ""
	_refresh_saves()

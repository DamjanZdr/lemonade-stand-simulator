extends CanvasLayer
## In-world main menu overlay. Shown when the game loads directly into
## main.tscn without a multiplayer session. Provides Play, Saves, Join,
## and Quit buttons overlaid on the world view.

signal play_pressed
signal saves_pressed
signal join_pressed(lobby_id: int)
signal host_pressed

const SLOT_NAMES: Array[String] = ["Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5"]

@onready var _title: Label = $MenuBox/TitleLabel
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


func _ready() -> void:
	_play_button.pressed.connect(func(): play_pressed.emit())
	_saves_button.pressed.connect(_on_saves_pressed)
	_join_button.pressed.connect(_toggle_join_row)
	_join_submit.pressed.connect(_on_join_submit)
	_quit_button.pressed.connect(func(): get_tree().quit())
	_saves_back.pressed.connect(_on_saves_back)
	_confirm_dialog.confirmed.connect(_on_confirm_delete)
	_confirm_dialog.canceled.connect(func(): _pending_delete = "")
	_version_label.text = "v" + ProjectSettings.get_setting(
		"application/config/version", "0.0.0"
	)
	_collect_slot_nodes()
	_refresh_saves()


func show_menu() -> void:
	visible = true
	_saves_panel.visible = false
	_join_row.visible = false
	_status_label.text = ""


func hide_menu() -> void:
	visible = false


func set_status(text: String) -> void:
	_status_label.text = text


func set_busy(text: String) -> void:
	set_status(text)
	_play_button.disabled = true
	_saves_button.disabled = true
	_join_button.disabled = true


func set_enabled(enabled: bool) -> void:
	_play_button.disabled = not enabled
	_saves_button.disabled = not enabled
	_join_button.disabled = not enabled


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
	if _saves_by_slot.has(slot_name):
		set_busy("Loading %s..." % _saves_by_slot[slot_name].get("name", slot_name))
		SaveManager.load_existing_game(slot_name)
	else:
		set_busy("Starting new game...")
		SaveManager.start_new_game(slot_name)
	host_pressed.emit()


func _on_delete_pressed(slot_name: String) -> void:
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

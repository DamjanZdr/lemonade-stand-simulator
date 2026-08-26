extends Control
## Host menu: 5 save slots displayed as cards. Empty slots start a new game,
## used slots load the existing save. Used slots can be deleted with a
## confirmation dialog. After choosing, creates a Steam lobby and goes to
## the Lobby scene.

const SLOT_NAMES: Array[String] = ["Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5"]

@onready var _slots_row: HBoxContainer = $CenterBox/SlotsRow
@onready var _status_label: Label = $CenterBox/StatusLabel
@onready var _back_button: Button = $CenterBox/BackButton
@onready var _version_label: Label = $VersionLabel
@onready var _confirm_dialog: ConfirmationDialog = $ConfirmDialog

var _slot_buttons: Array[Button] = []
var _slot_infos: Array[Label] = []
var _delete_buttons: Array[Button] = []
var _saves_by_slot: Dictionary = { } # slot_name -> save dict
var _pending_delete: String = ""


func _ready() -> void:
	_back_button.pressed.connect(_on_back)
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	_version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.0.0")
	_confirm_dialog.confirmed.connect(_on_confirm_delete)
	_confirm_dialog.canceled.connect(
		func():
			_pending_delete = "",
	)
	_collect_slot_nodes()
	_refresh_saves()


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
	# Build a lookup of existing saves by slot name
	for save in SaveManager.list_saves():
		var slot: String = save.get("slot", "")
		if SLOT_NAMES.has(slot):
			_saves_by_slot[slot] = save

	# Update UI for each slot
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
		# Connect button (disconnect first to avoid duplicates)
		if not btn.pressed.is_connected(_on_slot_pressed):
			btn.pressed.connect(_on_slot_pressed.bind(slot_name))
		if not del_btn.pressed.is_connected(_on_delete_pressed):
			del_btn.pressed.connect(_on_delete_pressed.bind(slot_name))


func _on_slot_pressed(slot_name: String) -> void:
	if _saves_by_slot.has(slot_name):
		_set_busy("Loading %s..." % _saves_by_slot[slot_name].get("name", slot_name))
		SaveManager.load_existing_game(slot_name)
	else:
		_set_busy("Starting new game...")
		SaveManager.start_new_game(slot_name)
	NetworkManager.host_game()


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


func _on_lobby_created(_lobby_id: int) -> void:
	_go_to_lobby()


func _on_connection_failed(reason: String) -> void:
	_status_label.text = "Failed: %s" % reason
	_set_enabled(true)


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _set_busy(text: String) -> void:
	_status_label.text = text
	_set_enabled(false)


func _set_enabled(enabled: bool) -> void:
	for btn in _slot_buttons:
		btn.disabled = not enabled
	_back_button.disabled = not enabled


func _go_to_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

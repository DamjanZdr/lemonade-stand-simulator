extends Control
## Host menu: choose between New Game (fresh start) or Load Game (pick a
## previous save slot). After choosing, creates a Steam lobby and goes to
## the Lobby scene.

@onready var _new_game_button: Button = $VBox/NewGameButton
@onready var _back_button: Button = $VBox/BackButton
@onready var _save_list: VBoxContainer = $SaveScroll/SaveList
@onready var _refresh_button: Button = $SaveScroll/RefreshButton
@onready var _status_label: Label = $VBox/StatusLabel
@onready var _version_label: Label = $VersionLabel


func _ready() -> void:
	_new_game_button.pressed.connect(_on_new_game)
	_back_button.pressed.connect(_on_back)
	_refresh_button.pressed.connect(_refresh_saves)
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	_version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.0.0")
	_refresh_saves()


func _on_new_game() -> void:
	_set_busy("Starting new game...")
	# Generate a unique slot name based on timestamp
	var slot_name := "Game_%s" % str(int(Time.get_unix_time_from_system()))
	SaveManager.start_new_game(slot_name)
	_start_hosting()


func _on_load_save(slot_name: String) -> void:
	_set_busy("Loading save '%s'..." % slot_name)
	SaveManager.load_existing_game(slot_name)
	_start_hosting()


func _start_hosting() -> void:
	NetworkManager.host_game()


func _on_lobby_created(_lobby_id: int) -> void:
	_go_to_lobby()


func _on_connection_failed(reason: String) -> void:
	_status_label.text = "Failed: %s" % reason
	_new_game_button.disabled = false
	_back_button.disabled = false


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _set_busy(text: String) -> void:
	_status_label.text = text
	_new_game_button.disabled = true
	_back_button.disabled = true


func _refresh_saves() -> void:
	_refresh_button.disabled = true
	_refresh_button.text = "Loading..."
	for child in _save_list.get_children():
		child.queue_free()
	var saves := SaveManager.list_saves()
	if saves.is_empty():
		var label := Label.new()
		label.text = "No saved games yet"
		label.add_theme_font_size_override("font_size", 10)
		_save_list.add_child(label)
	else:
		for save in saves:
			_add_save_row(save)
	_refresh_button.disabled = false
	_refresh_button.text = "Refresh"


func _add_save_row(save: Dictionary) -> void:
	var row := HBoxContainer.new()
	_save_list.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_label := Label.new()
	name_label.text = save.get("name", save.get("slot", "Unknown"))
	name_label.add_theme_font_size_override("font_size", 12)
	info.add_child(name_label)

	var detail_label := Label.new()
	var day_text := "Day %d" % save.get("day", 1)
	var money_text := "$%.2f" % save.get("money", 0.0)
	var saved_at: float = save.get("saved_at", 0.0)
	var date_text := ""
	if saved_at > 0:
		var dict := Time.get_datetime_dict_from_unix_time(int(saved_at))
		date_text = "%04d-%02d-%02d %02d:%02d" % [dict["year"], dict["month"], dict["day"], dict["hour"], dict["minute"]]
	detail_label.text = "%s  |  %s  |  %s" % [day_text, money_text, date_text]
	detail_label.add_theme_font_size_override("font_size", 10)
	detail_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info.add_child(detail_label)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.add_theme_font_size_override("font_size", 10)
	var slot_name: String = save.get("slot", "")
	load_btn.pressed.connect(func(): _on_load_save(slot_name))
	row.add_child(load_btn)

	var delete_btn := Button.new()
	delete_btn.text = "Delete"
	delete_btn.add_theme_font_size_override("font_size", 10)
	delete_btn.pressed.connect(
		func():
			SaveManager.delete_slot(slot_name)
			_refresh_saves(),
	)
	row.add_child(delete_btn)


func _go_to_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

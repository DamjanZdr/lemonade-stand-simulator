extends Control
## Entry point of the game. Host starts a new Steam lobby; Join connects to
## an existing one by ID. Both transition to the Lobby scene once connected.
## Also shows a list of active lobbies on the left so you can join without
## copying lobby IDs manually.

@onready var _title_label: Label = $CenterBox/TitleLabel
@onready var _host_button: Button = $CenterBox/HostButton
@onready var _join_field: LineEdit = $CenterBox/JoinRow/JoinField
@onready var _join_button: Button = $CenterBox/JoinRow/JoinButton
@onready var _status_label: Label = $CenterBox/StatusLabel
@onready var _quit_button: Button = $CenterBox/QuitButton
@onready var _lobby_list: VBoxContainer = $LobbyScroll/LobbyList
@onready var _refresh_button: Button = $LobbyScroll/RefreshButton
@onready var _version_label: Label = $VersionLabel
var _eye_button: Button = null


func _ready() -> void:
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	# Add eye toggle button to show/hide lobby ID
	_eye_button = Button.new()
	_eye_button.text = "👁"
	_eye_button.flat = true
	_eye_button.custom_minimum_size = Vector2(36, 36)
	_eye_button.add_theme_font_size_override("font_size", 18)
	_eye_button.pressed.connect(_toggle_join_visibility)
	$CenterBox/JoinRow.add_child(_eye_button)
	$CenterBox/JoinRow.move_child(_eye_button, 1)
	_quit_button.pressed.connect(
		func():
			get_tree().quit(),
	)
	_refresh_button.pressed.connect(_on_refresh_pressed)
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.server_connected.connect(_on_server_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.lobby_list_received.connect(_on_lobby_list_received)
	LobbyManager.reset()
	_version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.0.0")
	# Auto-search for lobbies on startup so the list is populated immediately
	_on_refresh_pressed()


func _on_host_pressed() -> void:
	# Go to the Host menu where the player picks New Game or Load Game
	get_tree().change_scene_to_file("res://scenes/ui/host_menu.tscn")


func _toggle_join_visibility() -> void:
	_join_field.secret = not _join_field.secret
	_eye_button.text = "👁" if _join_field.secret else "🙈"


func _on_join_pressed() -> void:
	var text := _join_field.text.strip_edges()
	if not text.is_valid_int():
		_status_label.text = "Enter a valid lobby ID"
		return
	_set_busy("Joining lobby...")
	NetworkManager.join_game(int(text))


func _on_refresh_pressed() -> void:
	_refresh_button.disabled = true
	_refresh_button.text = "Searching..."
	NetworkManager.search_lobbies()


func _on_lobby_list_received(lobbies: Array) -> void:
	_refresh_button.disabled = false
	_refresh_button.text = "Refresh"
	for child in _lobby_list.get_children():
		child.queue_free()
	if lobbies.is_empty():
		var label := Label.new()
		label.text = "No active lobbies"
		label.add_theme_font_size_override("font_size", 10)
		_lobby_list.add_child(label)
		return
	for lobby in lobbies:
		var row := HBoxContainer.new()
		_lobby_list.add_child(row)
		var info := Label.new()
		info.text = "%s\n(%d players)" % [
			lobby.get("host_name", "Unknown"),
			lobby.get("member_count", 0),
		]
		info.add_theme_font_size_override("font_size", 10)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var join_btn := Button.new()
		join_btn.text = "Join"
		join_btn.add_theme_font_size_override("font_size", 10)
		var lobby_id: int = lobby.get("id", 0)
		join_btn.pressed.connect(
			func():
				_set_busy("Joining %s..." % lobby.get("host_name", "lobby"))
				NetworkManager.join_game(lobby_id),
		)
		row.add_child(join_btn)


func _set_busy(text: String) -> void:
	_status_label.text = text
	_host_button.disabled = true
	_join_button.disabled = true


func _on_lobby_created(_lobby_id: int) -> void:
	_go_to_lobby()


func _on_server_connected() -> void:
	_go_to_lobby()


func _on_connection_failed(reason: String) -> void:
	_status_label.text = "Failed: %s" % reason
	_host_button.disabled = false
	_join_button.disabled = false


func _go_to_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

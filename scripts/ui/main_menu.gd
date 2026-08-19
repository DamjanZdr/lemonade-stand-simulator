extends Control
## Entry point of the game. Host starts a new Steam lobby; Join connects to
## an existing one by ID. Both transition to the Lobby scene once connected.

@onready var _title_label: Label = $VBox/TitleLabel
@onready var _host_button: Button = $VBox/HostButton
@onready var _join_field: LineEdit = $VBox/JoinRow/JoinField
@onready var _join_button: Button = $VBox/JoinRow/JoinButton
@onready var _status_label: Label = $VBox/StatusLabel
@onready var _quit_button: Button = $VBox/QuitButton


func _ready() -> void:
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_quit_button.pressed.connect(func(): get_tree().quit())
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.server_connected.connect(_on_server_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	LobbyManager.reset()


func _on_host_pressed() -> void:
	_set_busy("Creating lobby...")
	NetworkManager.host_game()


func _on_join_pressed() -> void:
	var text := _join_field.text.strip_edges()
	if not text.is_valid_int():
		_status_label.text = "Enter a valid lobby ID"
		return
	_set_busy("Joining lobby...")
	NetworkManager.join_game(int(text))


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
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

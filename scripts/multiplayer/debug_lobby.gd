extends CanvasLayer
## Debug UI for hosting/joining multiplayer test games.

@onready var status_label: Label = $Control/VBox/StatusLabel
@onready var lobby_id_edit: LineEdit = $Control/VBox/LobbyIdEdit
@onready var host_button: Button = $Control/VBox/HostButton
@onready var join_button: Button = $Control/VBox/JoinButton
@onready var invite_button: Button = $Control/VBox/InviteButton
@onready var leave_button: Button = $Control/VBox/LeaveButton


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	invite_button.pressed.connect(_on_invite_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_connected.connect(_on_server_connected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	_update_status("Not connected")


func _on_host_pressed() -> void:
	_update_status("Creating lobby...")
	NetworkManager.host_game()


func _on_join_pressed() -> void:
	var text = lobby_id_edit.text.strip_edges()
	if text.is_valid_int():
		_update_status("Joining lobby...")
		NetworkManager.join_game(int(text))
	else:
		_update_status("Invalid lobby ID")


func _on_invite_pressed() -> void:
	NetworkManager.invite_friend()


func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	_update_status("Not connected")
	host_button.disabled = false
	join_button.disabled = false


func _on_lobby_created(lobby_id: int) -> void:
	_update_status("Hosting! Lobby ID: %d\nShare this ID or use Invite." % lobby_id)
	host_button.disabled = true
	join_button.disabled = true


func _on_lobby_joined(lobby_id: int) -> void:
	_update_status("Joined lobby: %d" % lobby_id)
	host_button.disabled = true
	join_button.disabled = true


func _on_connection_failed(reason: String) -> void:
	_update_status("Failed: %s" % reason)


func _on_server_connected() -> void:
	_update_status("Connected to server!")


func _on_server_disconnected() -> void:
	_update_status("Server disconnected")


func _update_status(text: String) -> void:
	status_label.text = text
	print("[DebugLobby] ", text)

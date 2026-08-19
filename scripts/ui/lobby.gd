extends Control
## Pre-game lobby: shows the room code, who's connected, lets each player
## pick a stand and ready up, and lets the host start the game once
## everyone's ready.

@onready var _room_code_label: Label = $VBox/RoomRow/RoomCodeLabel
@onready var _copy_button: Button = $VBox/RoomRow/CopyButton
@onready var _invite_button: Button = $VBox/RoomRow/InviteButton
@onready var _player_list: VBoxContainer = $VBox/PlayerList
@onready var _stand1_button: Button = $VBox/StandRow/Stand1Button
@onready var _stand2_button: Button = $VBox/StandRow/Stand2Button
@onready var _ready_button: Button = $VBox/ReadyRow/ReadyButton
@onready var _start_button: Button = $VBox/ReadyRow/StartButton
@onready var _leave_button: Button = $VBox/LeaveButton

const STAND_NAMES: Array[String] = ["Stand 1", "Stand 2"]


func _ready() -> void:
	_room_code_label.text = "Room: %d" % NetworkManager.lobby_id
	_copy_button.pressed.connect(_on_copy_pressed)
	_invite_button.pressed.connect(func(): NetworkManager.invite_friend())
	_stand1_button.pressed.connect(func(): LobbyManager.set_my_stand(0))
	_stand2_button.pressed.connect(func(): LobbyManager.set_my_stand(1))
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_button.pressed.connect(func(): LobbyManager.start_game())
	_leave_button.pressed.connect(_on_leave_pressed)
	LobbyManager.roster_changed.connect(_refresh)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.peer_disconnected.connect(func(_id): _refresh())
	_refresh()


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(str(NetworkManager.lobby_id))
	_copy_button.text = "Copied!"
	get_tree().create_timer(1.5).timeout.connect(func(): _copy_button.text = "Copy")


func _on_ready_pressed() -> void:
	var mine := LobbyManager.get_my_entry()
	var currently_ready: bool = mine.get("ready", false)
	LobbyManager.set_my_ready(not currently_ready)


func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	LobbyManager.reset()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_server_disconnected() -> void:
	LobbyManager.reset()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _refresh() -> void:
	for child in _player_list.get_children():
		child.queue_free()

	var my_id := multiplayer.get_unique_id()
	var mine: Dictionary = LobbyManager.roster.get(my_id, { })

	for peer_id in LobbyManager.roster:
		var entry: Dictionary = LobbyManager.roster[peer_id]
		var row := Label.new()
		var stand_idx: int = entry.get("stand_index", -1)
		var stand_text := STAND_NAMES[stand_idx] if stand_idx >= 0 and stand_idx < STAND_NAMES.size() else "(no stand)"
		var ready_text := "Ready" if entry.get("ready", false) else "Not ready"
		var you_text := " (you)" if peer_id == my_id else ""
		row.text = "%s%s — %s — %s" % [entry.get("name", "Player"), you_text, stand_text, ready_text]
		_player_list.add_child(row)

	var my_stand: int = mine.get("stand_index", -1)
	_stand1_button.button_pressed = my_stand == 0
	_stand2_button.button_pressed = my_stand == 1
	_ready_button.text = "Unready" if mine.get("ready", false) else "Ready Up"

	var is_host := multiplayer.is_server()
	_start_button.visible = is_host
	_start_button.disabled = not LobbyManager.all_ready()

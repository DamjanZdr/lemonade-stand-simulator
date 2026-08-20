extends Control
## Pre-game lobby: shows the room code, who's connected, lets each player
## pick a stand and ready up, and lets the host start the game once
## everyone's ready. Also includes character customization with a 3D preview.

@onready var _room_code_label: Label = $HBox/LeftPanel/VBox/RoomRow/RoomCodeLabel
@onready var _copy_button: Button = $HBox/LeftPanel/VBox/RoomRow/CopyButton
@onready var _invite_button: Button = $HBox/LeftPanel/VBox/RoomRow/InviteButton
@onready var _stand1_list: VBoxContainer = $HBox/LeftPanel/VBox/StandsRow/Stand1Col/Stand1List
@onready var _stand2_list: VBoxContainer = $HBox/LeftPanel/VBox/StandsRow/Stand2Col/Stand2List
@onready var _stand1_button: Button = $HBox/LeftPanel/VBox/StandsRow/Stand1Col/Stand1Button
@onready var _stand2_button: Button = $HBox/LeftPanel/VBox/StandsRow/Stand2Col/Stand2Button
@onready var _ready_button: Button = $HBox/LeftPanel/VBox/BottomRow/ReadyButton
@onready var _start_button: Button = $HBox/LeftPanel/VBox/BottomRow/StartButton
@onready var _back_button: Button = $HBox/LeftPanel/VBox/BottomRow/BackButton
@onready var _version_label: Label = $VersionLabel

# Customization UI
@onready var _preview_vp: SubViewport = $HBox/RightPanel/CustomizePanel/PreviewRect/PreviewVP
@onready var _player_visuals: PlayerVisuals = $HBox/RightPanel/CustomizePanel/PreviewRect/PreviewVP/PlayerVisuals
@onready var _male_button: Button = $HBox/RightPanel/CustomizePanel/GenderRow/MaleButton
@onready var _female_button: Button = $HBox/RightPanel/CustomizePanel/GenderRow/FemaleButton
@onready var _hair_name: Label = $HBox/RightPanel/CustomizePanel/HairRow/HairName
@onready var _hair_color_name: Label = $HBox/RightPanel/CustomizePanel/HairColorRow/HairColorName
@onready var _eyebrow_name: Label = $HBox/RightPanel/CustomizePanel/EyebrowRow/EyebrowName
@onready var _shirt_color_name: Label = $HBox/RightPanel/CustomizePanel/ShirtColorRow/ShirtColorName
@onready var _pants_color_name: Label = $HBox/RightPanel/CustomizePanel/PantsColorRow/PantsColorName
@onready var _shoes_color_name: Label = $HBox/RightPanel/CustomizePanel/ShoesColorRow/ShoesColorName

const STAND_NAMES: Array[String] = ["Stand 1", "Stand 2"]

# Customization state
var _is_male: bool = true
var _hair_index: int = 0
var _hair_color_index: int = 2 # medium brown
var _eyebrow_index: int = 0
var _shirt_color_index: int = 0
var _pants_color_index: int = 1
var _shoes_color_index: int = 2

const HAIR_COLOR_NAMES: Array[String] = [
	"Black",
	"Dark Brown",
	"Medium Brown",
	"Light Brown",
	"Blonde",
	"Auburn",
	"Grey",
	"White",
]
const CLOTHING_COLOR_NAMES: Array[String] = [
	"Red",
	"Blue",
	"Green",
	"Yellow",
	"Purple",
	"Orange",
	"Charcoal",
	"Light Grey",
	"Tan",
	"Teal",
	"Maroon",
	"Navy",
	"Pink",
	"Sky Blue",
	"Lime Green",
]


func _ready() -> void:
	_room_code_label.text = "Room: %d" % NetworkManager.lobby_id
	_copy_button.pressed.connect(_on_copy_pressed)
	_invite_button.pressed.connect(
		func():
			NetworkManager.invite_friend(),
	)
	_stand1_button.pressed.connect(
		func():
			LobbyManager.set_my_stand(0),
	)
	_stand2_button.pressed.connect(
		func():
			LobbyManager.set_my_stand(1),
	)
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_button.pressed.connect(
		func():
			LobbyManager.start_game(),
	)
	_back_button.pressed.connect(_on_leave_pressed)
	LobbyManager.roster_changed.connect(_refresh)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.peer_disconnected.connect(
		func(_id):
			_refresh(),
	)
	# Re-request the current roster in case roster_changed already fired
	# during the scene transition from MainMenu (before our _ready ran).
	LobbyManager.request_refresh()
	_version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.0.0")
	_setup_customization()
	_refresh()


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(str(NetworkManager.lobby_id))
	_copy_button.text = "Copied!"
	get_tree().create_timer(1.5).timeout.connect(
		func():
			_copy_button.text = "Copy",
	)


func _on_ready_pressed() -> void:
	var mine := LobbyManager.get_my_entry()
	var currently_ready: bool = mine.get("ready", false)
	LobbyManager.set_my_ready(not currently_ready)


func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	LobbyManager.reset()
	SaveManager.clear_current_slot()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_server_disconnected() -> void:
	LobbyManager.reset()
	SaveManager.clear_current_slot()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _refresh() -> void:
	for child in _stand1_list.get_children():
		child.queue_free()
	for child in _stand2_list.get_children():
		child.queue_free()

	var my_id := multiplayer.get_unique_id()
	var mine: Dictionary = LobbyManager.roster.get(my_id, { })

	for peer_id in LobbyManager.roster:
		var entry: Dictionary = LobbyManager.roster[peer_id]
		var stand_idx: int = entry.get("stand_index", -1)
		var ready_text := "✓" if entry.get("ready", false) else "..."
		var you_text := " (you)" if peer_id == my_id else ""
		var row := Label.new()
		row.text = "%s%s\n%s" % [entry.get("name", "Player"), you_text, ready_text]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 16)
		if stand_idx == 0:
			_stand1_list.add_child(row)
		elif stand_idx == 1:
			_stand2_list.add_child(row)
		else:
			# No stand chosen yet — show in both lists as unassigned
			var row2 := Label.new()
			row2.text = "%s%s\n(no stand)" % [entry.get("name", "Player"), you_text]
			row2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row2.add_theme_font_size_override("font_size", 16)
			_stand1_list.add_child(row2)

	var my_stand: int = mine.get("stand_index", -1)
	_stand1_button.button_pressed = my_stand == 0
	_stand2_button.button_pressed = my_stand == 1
	_ready_button.text = "Unready" if mine.get("ready", false) else "Ready Up"

	var is_host := multiplayer.is_server()
	_start_button.visible = is_host
	_start_button.disabled = not LobbyManager.all_ready()

# ── Character Customization ──────────────────────────────────────────────────


func _setup_customization() -> void:
	# Initialize the player visuals with default appearance
	_player_visuals.set_gender(_is_male)
	_player_visuals.set_hair(_hair_index, PlayerVisuals.HAIR_COLORS[_hair_color_index])
	_player_visuals.set_eyebrow(_eyebrow_index)
	_apply_clothing_colors()
	_player_visuals.play_anim("Idle")
	_update_all_labels()

	# Gender buttons
	_male_button.pressed.connect(
		func():
			_is_male = true
			_on_customization_changed(),
	)
	_female_button.pressed.connect(
		func():
			_is_male = false
			_on_customization_changed(),
	)

	# Hair style buttons
	$HBox/RightPanel/CustomizePanel/HairRow/HairPrev.pressed.connect(
		func():
			_hair_index = (_hair_index - 1 + _player_visuals.get_hair_count()) % _player_visuals.get_hair_count()
			_on_customization_changed(),
	)
	$HBox/RightPanel/CustomizePanel/HairRow/HairNext.pressed.connect(
		func():
			_hair_index = (_hair_index + 1) % _player_visuals.get_hair_count()
			_on_customization_changed(),
	)

	# Hair color buttons
	$HBox/RightPanel/CustomizePanel/HairColorRow/HairColorPrev.pressed.connect(
		func():
			_hair_color_index = (_hair_color_index - 1 + PlayerVisuals.HAIR_COLORS.size()) % PlayerVisuals \
					.HAIR_COLORS \
					.size()
			_on_customization_changed(),
	)
	$HBox/RightPanel/CustomizePanel/HairColorRow/HairColorNext.pressed.connect(
		func():
			_hair_color_index = (_hair_color_index + 1) % PlayerVisuals.HAIR_COLORS.size()
			_on_customization_changed(),
	)

	# Eyebrow buttons
	$HBox/RightPanel/CustomizePanel/EyebrowRow/EyebrowPrev.pressed.connect(
		func():
			_eyebrow_index = (_eyebrow_index - 1 + _player_visuals.get_eyebrow_count()) % _player_visuals.get_eyebrow_count()
			_on_customization_changed(),
	)
	$HBox/RightPanel/CustomizePanel/EyebrowRow/EyebrowNext.pressed.connect(
		func():
			_eyebrow_index = (_eyebrow_index + 1) % _player_visuals.get_eyebrow_count()
			_on_customization_changed(),
	)

	# Shirt color buttons
	$HBox/RightPanel/CustomizePanel/ShirtColorRow/ShirtColorPrev.pressed.connect(
		func():
			_shirt_color_index = (_shirt_color_index - 1 + PlayerVisuals.CLOTHING_COLORS.size()) % PlayerVisuals \
					.CLOTHING_COLORS \
					.size()
			_on_customization_changed(),
	)
	$HBox/RightPanel/CustomizePanel/ShirtColorRow/ShirtColorNext.pressed.connect(
		func():
			_shirt_color_index = (_shirt_color_index + 1) % PlayerVisuals.CLOTHING_COLORS.size()
			_on_customization_changed(),
	)

	# Pants color buttons
	$HBox/RightPanel/CustomizePanel/PantsColorRow/PantsColorPrev.pressed.connect(
		func():
			_pants_color_index = (_pants_color_index - 1 + PlayerVisuals.CLOTHING_COLORS.size()) % PlayerVisuals \
					.CLOTHING_COLORS \
					.size()
			_on_customization_changed(),
	)
	$HBox/RightPanel/CustomizePanel/PantsColorRow/PantsColorNext.pressed.connect(
		func():
			_pants_color_index = (_pants_color_index + 1) % PlayerVisuals.CLOTHING_COLORS.size()
			_on_customization_changed(),
	)

	# Shoes color buttons
	$HBox/RightPanel/CustomizePanel/ShoesColorRow/ShoesColorPrev.pressed.connect(
		func():
			_shoes_color_index = (_shoes_color_index - 1 + PlayerVisuals.CLOTHING_COLORS.size()) % PlayerVisuals \
					.CLOTHING_COLORS \
					.size()
			_on_customization_changed(),
	)
	$HBox/RightPanel/CustomizePanel/ShoesColorRow/ShoesColorNext.pressed.connect(
		func():
			_shoes_color_index = (_shoes_color_index + 1) % PlayerVisuals.CLOTHING_COLORS.size()
			_on_customization_changed(),
	)

	# Randomize button
	$HBox/RightPanel/CustomizePanel/RandomButton.pressed.connect(_on_randomize)

	# Update gender button states
	_update_gender_buttons()


func _on_customization_changed() -> void:
	_player_visuals.set_gender(_is_male)
	_player_visuals.set_hair(_hair_index, PlayerVisuals.HAIR_COLORS[_hair_color_index])
	_player_visuals.set_eyebrow(_eyebrow_index)
	_apply_clothing_colors()
	_player_visuals.play_anim("Idle")
	_update_all_labels()
	_update_gender_buttons()
	_broadcast_customization()


func _apply_clothing_colors() -> void:
	var colors: Dictionary = {
		"shirt": PlayerVisuals.CLOTHING_COLORS[_shirt_color_index],
		"top": PlayerVisuals.CLOTHING_COLORS[_shirt_color_index],
		"pants": PlayerVisuals.CLOTHING_COLORS[_pants_color_index],
		"trousers": PlayerVisuals.CLOTHING_COLORS[_pants_color_index],
		"shoes": PlayerVisuals.CLOTHING_COLORS[_shoes_color_index],
	}
	_player_visuals.set_clothing_colors(colors)


func _update_gender_buttons() -> void:
	_male_button.button_pressed = _is_male
	_female_button.button_pressed = not _is_male


func _update_all_labels() -> void:
	_hair_name.text = "Style %d" % (_hair_index + 1)
	_hair_color_name.text = HAIR_COLOR_NAMES[_hair_color_index]
	_eyebrow_name.text = (
		PlayerVisuals.EYEBROW_NAMES[_eyebrow_index]
		if _eyebrow_index
		< PlayerVisuals \
				.EYEBROW_NAMES \
				.size()
		else "Style %d" % (_eyebrow_index + 1)
	)
	_shirt_color_name.text = CLOTHING_COLOR_NAMES[_shirt_color_index]
	_pants_color_name.text = CLOTHING_COLOR_NAMES[_pants_color_index]
	_shoes_color_name.text = CLOTHING_COLOR_NAMES[_shoes_color_index]


func _on_randomize() -> void:
	_is_male = randi() % 2 == 0
	_hair_index = randi() % _player_visuals.get_hair_count()
	_hair_color_index = randi() % PlayerVisuals.HAIR_COLORS.size()
	_eyebrow_index = randi() % _player_visuals.get_eyebrow_count()
	_shirt_color_index = randi() % PlayerVisuals.CLOTHING_COLORS.size()
	_pants_color_index = randi() % PlayerVisuals.CLOTHING_COLORS.size()
	_shoes_color_index = randi() % PlayerVisuals.CLOTHING_COLORS.size()
	_on_customization_changed()


func _broadcast_customization() -> void:
	var data := _get_customization_data()
	LobbyManager.set_my_customization(data)


func _get_customization_data() -> Dictionary:
	return {
		"male": _is_male,
		"hair_index": _hair_index,
		"hair_color": PlayerVisuals.HAIR_COLORS[_hair_color_index],
		"eyebrow_index": _eyebrow_index,
		"clothing_colors": {
			"shirt": PlayerVisuals.CLOTHING_COLORS[_shirt_color_index],
			"top": PlayerVisuals.CLOTHING_COLORS[_shirt_color_index],
			"pants": PlayerVisuals.CLOTHING_COLORS[_pants_color_index],
			"trousers": PlayerVisuals.CLOTHING_COLORS[_pants_color_index],
			"shoes": PlayerVisuals.CLOTHING_COLORS[_shoes_color_index],
		},
	}

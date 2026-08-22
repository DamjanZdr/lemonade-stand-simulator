extends Control
## 2D lobby UI overlay. Lives inside main.tscn on top of the 3D world.
## The 3D world is already loaded — main.gd positions a LobbyCamera and
## player models in the world. This script only handles the 2D UI:
## room code, roster, stand selection, ready/start buttons, and
## character customization (which applies to the PlayerVisuals nodes
## in the 3D world — both PlayerModel1 and PlayerModel2 so the player
## sees their customization regardless of which stand they're viewing).

@onready var _room_code_label: Label = $LeftPanel/VBox/RoomRow/RoomCodeLabel
@onready var _copy_button: Button = $LeftPanel/VBox/RoomRow/CopyButton
@onready var _invite_button: Button = $LeftPanel/VBox/RoomRow/InviteButton
@onready var _stand1_list: VBoxContainer = $LeftPanel/VBox/StandsRow/Stand1Col/Stand1List
@onready var _stand2_list: VBoxContainer = $LeftPanel/VBox/StandsRow/Stand2Col/Stand2List
@onready var _stand1_button: Button = $LeftPanel/VBox/StandsRow/Stand1Col/Stand1Button
@onready var _stand2_button: Button = $LeftPanel/VBox/StandsRow/Stand2Col/Stand2Button
@onready var _ready_button: Button = $LeftPanel/VBox/BottomRow/ReadyButton
@onready var _start_button: Button = $LeftPanel/VBox/BottomRow/StartButton
@onready var _back_button: Button = $LeftPanel/VBox/BottomRow/BackButton
@onready var _version_label: Label = $VersionLabel

# Customization UI
@onready var _male_button: Button = $RightPanel/OptionsCol/GenderRow/MaleButton
@onready var _female_button: Button = $RightPanel/OptionsCol/GenderRow/FemaleButton
@onready var _hair_num: Label = $RightPanel/OptionsCol/OptionsGrid/HairNum
@onready var _hair_color_num: Label = $RightPanel/OptionsCol/OptionsGrid/HairColorNum
@onready var _eyebrow_num: Label = $RightPanel/OptionsCol/OptionsGrid/EyebrowNum
@onready var _shirt_color_num: Label = $RightPanel/OptionsCol/OptionsGrid/ShirtColorNum
@onready var _pants_color_num: Label = $RightPanel/OptionsCol/OptionsGrid/PantsColorNum
@onready var _shoes_color_num: Label = $RightPanel/OptionsCol/OptionsGrid/ShoesColorNum
@onready var _head_num: Label = $RightPanel/OptionsCol/OptionsGrid/HeadNum

## PlayerVisuals nodes in the 3D world. Customization applies to ALL of
## them so the player sees their character regardless of which stand
## the camera is looking at.
var _player_visuals: Array[PlayerVisuals] = []

## Signal emitted when the local player switches stands in the lobby.
## main.gd connects to this to tween the LobbyCamera.
signal stand_switched(stand_index: int)

const STAND_NAMES: Array[String] = ["Stand 1", "Stand 2"]

# Customization state
var _is_male: bool = true
var _hair_index: int = 0
var _hair_color_index: int = 2 # medium brown
var _eyebrow_index: int = 0
var _shirt_color_index: int = 0
var _pants_color_index: int = 1
var _shoes_color_index: int = 2
var _head_size_index: int = 4 # 0-8, maps to 0.5x - 2.0x (index 4 = 1.3x default)

const HEAD_SIZE_MIN: float = 0.5
const HEAD_SIZE_MAX: float = 2.0
const HEAD_SIZE_STEPS: int = 9 # 0.5, 0.7, 0.9, 1.1, 1.3, 1.5, 1.7, 1.9, 2.0

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


## Called by main.gd to provide PlayerVisuals nodes from the 3D world.
func set_player_visuals(models: Array[PlayerVisuals]) -> void:
	_player_visuals = models


func _ready() -> void:
	_room_code_label.text = "Room: %d" % NetworkManager.lobby_id
	_copy_button.pressed.connect(_on_copy_pressed)
	_invite_button.pressed.connect(
		func():
			NetworkManager.invite_friend(),
	)
	_stand1_button.pressed.connect(
		func():
			_on_stand_selected(0),
	)
	_stand2_button.pressed.connect(
		func():
			_on_stand_selected(1),
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
	# Defer customization setup to ensure PlayerVisuals @onready vars are ready
	call_deferred("_setup_customization")
	_refresh()


func _on_stand_selected(stand_index: int) -> void:
	LobbyManager.set_my_stand(stand_index)
	stand_switched.emit(stand_index)


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
		# Skip players who haven't selected a stand — they don't appear in either list.
		if stand_idx < 0:
			continue
		var ready_mark := "✓ " if entry.get("ready", false) else ""
		var you_text := " (you)" if peer_id == my_id else ""
		var row := Label.new()
		row.text = "%s%s%s" % [ready_mark, entry.get("name", "Player"), you_text]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 16)
		if stand_idx == 0:
			_stand1_list.add_child(row)
		elif stand_idx == 1:
			_stand2_list.add_child(row)

	var my_stand: int = mine.get("stand_index", -1)
	_stand1_button.button_pressed = my_stand == 0
	_stand2_button.button_pressed = my_stand == 1
	_ready_button.text = "Unready" if mine.get("ready", false) else "Ready Up"

	var is_host := multiplayer.is_server()
	_start_button.visible = is_host
	_start_button.disabled = not LobbyManager.all_ready()

# ── Character Customization ──────────────────────────────────────────────────


func _setup_customization() -> void:
	# If main.gd hasn't set the PlayerVisuals yet, find them in the scene
	if _player_visuals.is_empty():
		var models := get_tree().current_scene.find_child("LobbyPlayerModels", true, false) as Node
		if models:
			for child in models.get_children():
				var pv := child as PlayerVisuals
				if pv:
					_player_visuals.append(pv)
	if _player_visuals.is_empty():
		push_warning("LobbyUI: no PlayerVisuals found, customization will not be visible")
		return
	# Initialize all player visuals with default appearance
	_apply_customization_to_all()
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
	$RightPanel/OptionsCol/OptionsGrid/HairPrev.pressed.connect(
		func():
			_hair_index = (_hair_index - 1 + _player_visuals[0].get_hair_count()) % _player_visuals[
				0
			].get_hair_count()
			_on_customization_changed(),
	)
	$RightPanel/OptionsCol/OptionsGrid/HairNext.pressed.connect(
		func():
			_hair_index = (_hair_index + 1) % _player_visuals[0].get_hair_count()
			_on_customization_changed(),
	)

	# Hair color buttons
	$RightPanel/OptionsCol/OptionsGrid/HairColorPrev.pressed.connect(
		func():
			_hair_color_index = (_hair_color_index - 1 + PlayerVisuals.HAIR_COLORS.size()) % PlayerVisuals \
					.HAIR_COLORS \
					.size()
			_on_customization_changed(),
	)
	$RightPanel/OptionsCol/OptionsGrid/HairColorNext.pressed.connect(
		func():
			_hair_color_index = (_hair_color_index + 1) % PlayerVisuals.HAIR_COLORS.size()
			_on_customization_changed(),
	)

	# Eyebrow buttons
	$RightPanel/OptionsCol/OptionsGrid/EyebrowPrev.pressed.connect(
		func():
			_eyebrow_index = (_eyebrow_index - 1 + _player_visuals[0].get_eyebrow_count()) % _player_visuals[
				0
			].get_eyebrow_count()
			_on_customization_changed(),
	)
	$RightPanel/OptionsCol/OptionsGrid/EyebrowNext.pressed.connect(
		func():
			_eyebrow_index = (_eyebrow_index + 1) % _player_visuals[0].get_eyebrow_count()
			_on_customization_changed(),
	)

	# Shirt color buttons
	$RightPanel/OptionsCol/OptionsGrid/ShirtColorPrev.pressed.connect(
		func():
			_shirt_color_index = (_shirt_color_index - 1 + PlayerVisuals.CLOTHING_COLORS.size()) % PlayerVisuals \
					.CLOTHING_COLORS \
					.size()
			_on_customization_changed(),
	)
	$RightPanel/OptionsCol/OptionsGrid/ShirtColorNext.pressed.connect(
		func():
			_shirt_color_index = (_shirt_color_index + 1) % PlayerVisuals.CLOTHING_COLORS.size()
			_on_customization_changed(),
	)

	# Pants color buttons
	$RightPanel/OptionsCol/OptionsGrid/PantsColorPrev.pressed.connect(
		func():
			_pants_color_index = (_pants_color_index - 1 + PlayerVisuals.CLOTHING_COLORS.size()) % PlayerVisuals \
					.CLOTHING_COLORS \
					.size()
			_on_customization_changed(),
	)
	$RightPanel/OptionsCol/OptionsGrid/PantsColorNext.pressed.connect(
		func():
			_pants_color_index = (_pants_color_index + 1) % PlayerVisuals.CLOTHING_COLORS.size()
			_on_customization_changed(),
	)

	# Shoes color buttons
	$RightPanel/OptionsCol/OptionsGrid/ShoesColorPrev.pressed.connect(
		func():
			_shoes_color_index = (_shoes_color_index - 1 + PlayerVisuals.CLOTHING_COLORS.size()) % PlayerVisuals \
					.CLOTHING_COLORS \
					.size()
			_on_customization_changed(),
	)
	$RightPanel/OptionsCol/OptionsGrid/ShoesColorNext.pressed.connect(
		func():
			_shoes_color_index = (_shoes_color_index + 1) % PlayerVisuals.CLOTHING_COLORS.size()
			_on_customization_changed(),
	)

	# Head size buttons
	$RightPanel/OptionsCol/OptionsGrid/HeadPrev.pressed.connect(
		func():
			_head_size_index = max(0, _head_size_index - 1)
			_on_customization_changed(),
	)
	$RightPanel/OptionsCol/OptionsGrid/HeadNext.pressed.connect(
		func():
			_head_size_index = min(HEAD_SIZE_STEPS - 1, _head_size_index + 1)
			_on_customization_changed(),
	)

	# Randomize button
	$RightPanel/OptionsCol/RandomButton.pressed.connect(_on_randomize)

	# Update gender button states
	_update_gender_buttons()


func _on_customization_changed() -> void:
	if _player_visuals.is_empty():
		return
	_apply_customization_to_all()
	_update_all_labels()
	_update_gender_buttons()
	_broadcast_customization()


## Applies the current customization state to ALL player visual models.
func _apply_customization_to_all() -> void:
	for pv in _player_visuals:
		if pv == null:
			continue
		pv.set_gender(_is_male)
		pv.set_hair(_hair_index, PlayerVisuals.HAIR_COLORS[_hair_color_index])
		pv.set_eyebrow(_eyebrow_index)
		var colors: Dictionary = {
			"shirt": PlayerVisuals.CLOTHING_COLORS[_shirt_color_index],
			"top": PlayerVisuals.CLOTHING_COLORS[_shirt_color_index],
			"pants": PlayerVisuals.CLOTHING_COLORS[_pants_color_index],
			"trousers": PlayerVisuals.CLOTHING_COLORS[_pants_color_index],
			"shoes": PlayerVisuals.CLOTHING_COLORS[_shoes_color_index],
		}
		pv.set_clothing_colors(colors)
		pv.scale_head_bone(_head_size_to_scale())
		pv.play_anim("Idle")


func _head_size_to_scale() -> float:
	var step: float = (HEAD_SIZE_MAX - HEAD_SIZE_MIN) / float(HEAD_SIZE_STEPS - 1)
	return HEAD_SIZE_MIN + step * _head_size_index


func _update_gender_buttons() -> void:
	_male_button.button_pressed = _is_male
	_female_button.button_pressed = not _is_male


func _update_all_labels() -> void:
	_hair_num.text = str(_hair_index + 1)
	_hair_color_num.text = str(_hair_color_index + 1)
	_eyebrow_num.text = str(_eyebrow_index + 1)
	_shirt_color_num.text = str(_shirt_color_index + 1)
	_pants_color_num.text = str(_pants_color_index + 1)
	_shoes_color_num.text = str(_shoes_color_index + 1)
	_head_num.text = str(_head_size_index + 1)


func _on_randomize() -> void:
	if _player_visuals.is_empty():
		return
	_is_male = randi() % 2 == 0
	_hair_index = randi() % _player_visuals[0].get_hair_count()
	_hair_color_index = randi() % PlayerVisuals.HAIR_COLORS.size()
	_eyebrow_index = randi() % _player_visuals[0].get_eyebrow_count()
	_shirt_color_index = randi() % PlayerVisuals.CLOTHING_COLORS.size()
	_pants_color_index = randi() % PlayerVisuals.CLOTHING_COLORS.size()
	_shoes_color_index = randi() % PlayerVisuals.CLOTHING_COLORS.size()
	_head_size_index = randi() % HEAD_SIZE_STEPS
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
		"head_size": _head_size_to_scale(),
		"clothing_colors": {
			"shirt": PlayerVisuals.CLOTHING_COLORS[_shirt_color_index],
			"top": PlayerVisuals.CLOTHING_COLORS[_shirt_color_index],
			"pants": PlayerVisuals.CLOTHING_COLORS[_pants_color_index],
			"trousers": PlayerVisuals.CLOTHING_COLORS[_pants_color_index],
			"shoes": PlayerVisuals.CLOTHING_COLORS[_shoes_color_index],
		},
	}

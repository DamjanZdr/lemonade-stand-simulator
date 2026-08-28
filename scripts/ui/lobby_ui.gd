extends Control
## 2D lobby UI overlay. Lives inside main.tscn on top of the 3D world.
## Both panels (customize + lobby) are on the left side. The 3D world
## is visible on the right. Player models look at the camera and can
## be spun by clicking and dragging on the 3D viewport area.

const HOVER_POP: float = 1.12

@onready var _eye_button: Button = $LeftContainer/LobbyPanel/VBox/RoomRow/EyeButton
@onready var _room_code_label: Label = $LeftContainer/LobbyPanel/VBox/RoomRow/RoomCodeLabel
@onready var _copy_button: Button = $LeftContainer/LobbyPanel/VBox/RoomRow/CopyButton
@onready var _invite_button: Button = $LeftContainer/LobbyPanel/VBox/RoomRow/InviteButton
@onready var _switch_button: Button = $LeftContainer/LobbyPanel/VBox/SwitchRow/SwitchButton
@onready var _stand1_list: VBoxContainer = $LeftContainer/LobbyPanel/VBox/PlayersRow/Stand1Col/Stand1List
@onready var _stand2_list: VBoxContainer = $LeftContainer/LobbyPanel/VBox/PlayersRow/Stand2Col/Stand2List
@onready var _ready_button: Button = $LeftContainer/LobbyPanel/VBox/BottomRow/ReadyButton
@onready var _start_button: Button = $LeftContainer/LobbyPanel/VBox/BottomRow/StartButton
@onready var _back_button: Button = $LeftContainer/LobbyPanel/VBox/BottomRow/BackButton
@onready var _version_label: Label = $VersionLabel
@onready var _avatar_button: Button = $LeftContainer/LobbyPanel/VBox/CustomizeRow/AvatarButton
@onready var _house_button: Button = $LeftContainer/LobbyPanel/VBox/CustomizeRow/HouseButton
@onready var _customize_panel: PanelContainer = $LeftContainer/CustomizePanel
@onready var _lobby_panel: PanelContainer = $LeftContainer/LobbyPanel
@onready var _customize_back_button: Button = (
	$LeftContainer/CustomizePanel/OptionsCol/CustomizeBackButton
)
@onready var _customize_title: Label = $LeftContainer/CustomizePanel/OptionsCol/Title
@onready var _gender_row: HBoxContainer = $LeftContainer/CustomizePanel/OptionsCol/GenderRow
@onready var _random_button: Button = $LeftContainer/CustomizePanel/OptionsCol/RandomButton

# Customization UI — left column (under Male)
@onready var _male_button: Button = $LeftContainer/CustomizePanel/OptionsCol/GenderRow/MaleButton
@onready var _female_button: Button = $LeftContainer/CustomizePanel/OptionsCol/GenderRow/FemaleButton
@onready var _hair_name: Label = $LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/HairStyleRow/HairName
@onready var _eyebrow_name: Label = $LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/EyebrowsRow/EyebrowName
@onready var _shirt_color_name: Label = $LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/ShirtColorRow/ShirtColorName
@onready var _shoes_color_name: Label = $LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/ShoesColorRow/ShoesColorName
@onready var _walls_color_name: Label = $LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/WallsColorRow/WallsColorName

# Customization UI — right column (under Female)
@onready var _hair_color_name: Label = $LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/HairColorRow/HairColorName
@onready var _eyebrow_color_name: Label = $LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/EyebrowColorRow/EyebrowColorName
@onready var _pants_color_name: Label = $LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/PantsColorRow/PantsColorName
@onready var _head_name: Label = $LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/HeadSizeRow/HeadName
@onready var _roof_color_name: Label = $LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/RoofColorRow/RoofColorName
@onready var _skin_color_slider: HSlider = $LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/SkinColorRow/SkinColorSlider

## PlayerVisuals nodes in the 3D world. Customization applies to ALL of
## them so the player sees their character regardless of which stand
## the camera is looking at.
var _player_visuals: Array[PlayerVisuals] = []

## Signal emitted when the local player switches stands in the lobby.
## main.gd connects to this to tween the LobbyCamera.
signal stand_switched(stand_index: int)
signal return_to_menu_requested

const STAND_NAMES: Array[String] = ["Stand 1", "Stand 2"]

# Customization state
var _is_male: bool = true
var _hair_index: int = 0
var _hair_color_index: int = 2 # medium brown
var _eyebrow_index: int = 0
var _eyebrow_color_index: int = 0 # black
var _shirt_color_index: int = 0
var _pants_color_index: int = 1
var _shoes_color_index: int = 2
var _head_size_index: int = 4 # 0-8, maps to 0.5x - 2.0x (index 4 = 1.3x default)
var _walls_color_index: int = 0
var _roof_color_index: int = 0
var _skin_color_value: float = 0.0 # 0.0 = lightest, 1.0 = darkest

const HEAD_SIZE_MIN: float = 0.5
const HEAD_SIZE_MAX: float = 2.0
const HEAD_SIZE_STEPS: int = 9

const HAIR_COLOR_NAMES: Array[String] = [
	"Black",
	"Dark Brown",
	"Med Brown",
	"Lt Brown",
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
	"Lt Grey",
	"Tan",
	"Teal",
	"Maroon",
	"Navy",
	"Pink",
	"Sky Blue",
	"Lime",
]
const WALL_COLOR_NAMES: Array[String] = ["Cream", "Salmon", "Sky", "Sage", "Lilac"]
const ROOF_COLOR_NAMES: Array[String] = ["Brown", "Grey", "Green", "Blue", "Yellow"]

# ── State ─────────────────────────────────────────────────────────────────────
var _room_visible: bool = false
var _current_stand: int = 0
var _color_manager: Node = null

# ── Drag-to-spin state ────────────────────────────────────────────────────────
var _dragging: bool = false
var _drag_last_x: float = 0.0
var _model_yaw_offset: float = 0.0
## Original transforms of the player models from the scene, saved so
## yaw can be applied on top of them without losing base rotation.
var _model_base_transforms: Array[Transform3D] = []


## Called by main.gd to provide PlayerVisuals nodes from the 3D world.
func set_player_visuals(models: Array[PlayerVisuals]) -> void:
	_player_visuals = models
	_model_base_transforms.clear()
	for pv in _player_visuals:
		if pv:
			_model_base_transforms.append(pv.transform)
		else:
			_model_base_transforms.append(Transform3D.IDENTITY)


## Called by main.gd to set the look-at target (the lobby camera) so
## player models track it with their eyes.
func set_look_at_target(target: Node3D) -> void:
	for pv in _player_visuals:
		if pv:
			pv.look_at_target = target


## Apply main menu visual style: blur/dim overlay, transparent panels,
## flat buttons with hover pop effects, white text with drop shadows.
func _apply_menu_style() -> void:
	# 1. Add blur + dim overlay on the left side (matching main menu).
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)

	var blur_shader := load("res://shaders/ui_blur.gdshader") as Shader
	var blur_panel := ColorRect.new()
	blur_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blur_mat := ShaderMaterial.new()
	blur_mat.shader = blur_shader
	blur_mat.set_shader_parameter("blur_radius", 12.0)
	blur_mat.set_shader_parameter("fade_start", 0.35)
	blur_panel.material = blur_mat
	blur_panel.color = Color(0, 0, 0, 0)
	add_child(blur_panel)

	var dim_shader := load("res://shaders/ui_dim_fade.gdshader") as Shader
	var dim_panel := ColorRect.new()
	dim_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim_mat := ShaderMaterial.new()
	dim_mat.shader = dim_shader
	dim_mat.set_shader_parameter("dim_color", Color(0, 0, 0, 0.35))
	dim_mat.set_shader_parameter("fade_start", 0.35)
	dim_panel.material = dim_mat
	dim_panel.color = Color(0, 0, 0, 0)
	add_child(dim_panel)

	# Move LeftContainer to be on top of blur/dim.
	move_child(_get_node("LeftContainer"), -1)

	# 2. Remove panel backgrounds — make transparent.
	var customize_panel: PanelContainer = $LeftContainer/CustomizePanel
	var lobby_panel: PanelContainer = $LeftContainer/LobbyPanel
	var empty_sb := StyleBoxEmpty.new()
	customize_panel.add_theme_stylebox_override("panel", empty_sb)
	lobby_panel.add_theme_stylebox_override("panel", empty_sb)

	# 3. Style all labels: white text, larger fonts.
	_style_labels_recursive(customize_panel)
	_style_labels_recursive(lobby_panel)

	# 4. Style main buttons: flat, white text, drop shadow, hover pop.
	var main_buttons: Array[Button] = [
		_ready_button,
		_start_button,
		_back_button,
		_switch_button,
		_invite_button,
		_copy_button,
		_eye_button,
		_male_button,
		_female_button,
		_avatar_button,
		_house_button,
		_customize_back_button,
	]
	for btn in main_buttons:
		if btn:
			_make_flat_button(btn)
			_add_drop_shadow(btn)
			_setup_hover_effect(btn)
			btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
			btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
			btn.add_theme_font_size_override("font_size", 22)

	# Ready and Start buttons: bigger, cream text.
	_ready_button.add_theme_font_size_override("font_size", 28)
	_start_button.add_theme_font_size_override("font_size", 28)
	_back_button.add_theme_font_size_override("font_size", 24)

	# 5. Style arrow buttons: flat, smaller, white text.
	var arrow_buttons := _find_all_buttons_recursive(customize_panel)
	for btn in arrow_buttons:
		if btn not in main_buttons:
			_make_flat_button(btn)
			_setup_hover_effect(btn)
			btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
			btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))

	# Randomize button.
	var random_btn: Button = $LeftContainer/CustomizePanel/OptionsCol/RandomButton
	if random_btn:
		_make_flat_button(random_btn)
		_add_drop_shadow(random_btn)
		_setup_hover_effect(random_btn)
		random_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		random_btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7, 1))
		random_btn.add_theme_font_size_override("font_size", 22)

	# 6. Style title labels.
	var customize_title: Label = $LeftContainer/CustomizePanel/OptionsCol/Title
	customize_title.add_theme_font_size_override("font_size", 36)
	customize_title.add_theme_color_override("font_color", Color(1, 0.98, 0.88, 0.95))

	var lobby_title: Label = $LeftContainer/LobbyPanel/VBox/TitleLabel
	lobby_title.add_theme_font_size_override("font_size", 36)
	lobby_title.add_theme_color_override("font_color", Color(1, 0.98, 0.88, 0.95))

	# 7. Style separators to be subtle white.
	for sep in [
		_get_node("LeftContainer/LobbyPanel/VBox/Sep1"),
		_get_node("LeftContainer/LobbyPanel/VBox/Sep2"),
		_get_node("LeftContainer/LobbyPanel/VBox/PlayersRow/StandSep"),
	]:
		if sep is ColorRect:
			(sep as ColorRect).color = Color(1, 1, 1, 0.15)

	# 8. Style stand headers.
	var s1h: Label = $LeftContainer/LobbyPanel/VBox/SwitchRow/Stand1Header
	var s2h: Label = $LeftContainer/LobbyPanel/VBox/SwitchRow/Stand2Header
	s1h.add_theme_color_override("font_color", Color(1, 0.95, 0.7, 0.9))
	s2h.add_theme_color_override("font_color", Color(1, 0.95, 0.7, 0.9))
	s1h.add_theme_font_size_override("font_size", 18)
	s2h.add_theme_font_size_override("font_size", 18)

	# 9. Version label: subtle white.
	_version_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))


## Adapt the lobby layout based on the game mode.
## Solo: hide stand 2, switch, invite. Single stand only.
## Co-op: hide stand 2, switch. Single stand, invite friends.
## Versus: show both stands, switch, invite.
func _apply_mode_layout() -> void:
	var mode: int = LobbyManager.game_mode
	var is_versus := mode == GameState.GameMode.VERSUS
	var is_solo := mode == GameState.GameMode.SOLO
	# Stand 2 column + header + separator.
	var stand2_col: VBoxContainer = $LeftContainer/LobbyPanel/VBox/PlayersRow/Stand2Col
	var stand2_header: Label = $LeftContainer/LobbyPanel/VBox/SwitchRow/Stand2Header
	var stand_sep: ColorRect = $LeftContainer/LobbyPanel/VBox/PlayersRow/StandSep
	stand2_col.visible = is_versus
	stand2_header.visible = is_versus
	stand_sep.visible = is_versus
	# Switch button only makes sense in Versus.
	_switch_button.visible = is_versus
	# Invite button hidden in Solo (no friends needed).
	_invite_button.visible = not is_solo
	# Stand 1 header: in Solo/Co-op, just say "Players" instead of "Stand 1".
	var stand1_header: Label = $LeftContainer/LobbyPanel/VBox/SwitchRow/Stand1Header
	if is_versus:
		stand1_header.text = "Stand 1"
	else:
		stand1_header.text = "Players"
	# Update the lobby title to show the mode.
	var lobby_title: Label = $LeftContainer/LobbyPanel/VBox/TitleLabel
	var mode_name := "Solo"
	match mode:
		GameState.GameMode.COOP:
			mode_name = "Co-op"
		GameState.GameMode.VERSUS:
			mode_name = "Versus"
	lobby_title.text = "%s — %s" % [GameState.stand_name, mode_name]


## Recursively style all labels in a node tree: white text.
func _style_labels_recursive(node: Node) -> void:
	if node is Label:
		var lbl := node as Label
		var current_color: Color = lbl.get_theme_color("font_color")
		# If it's a small label (font_size <= 14), keep it dimmer.
		var fs: int = lbl.get_theme_font_size("font_size")
		if fs <= 13:
			lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.9))
		else:
			lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	for child in node.get_children():
		_style_labels_recursive(child)


## Find all Button nodes recursively in a tree.
func _find_all_buttons_recursive(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button:
		result.append(node as Button)
	for child in node.get_children():
		result.append_array(_find_all_buttons_recursive(child))
	return result


## Remove all stylebox backgrounds so the button looks like plain text.
func _make_flat_button(btn: Button) -> void:
	if btn == null:
		return
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.add_theme_stylebox_override("disabled", empty)


## Add a drop shadow to a button's text.
func _add_drop_shadow(btn: Button) -> void:
	if btn == null:
		return
	btn.add_theme_color_override("shadow_color", Color(0, 0, 0, 0.6))
	btn.add_theme_constant_override("shadow_offset_x", 2)
	btn.add_theme_constant_override("shadow_offset_y", 2)
	btn.add_theme_constant_override("shadow_outline_size", 4)


## Wire hover sound + pop animation for a button.
func _setup_hover_effect(btn: Button) -> void:
	if btn == null:
		return
	var base_scale := btn.scale
	btn.set_meta("_base_scale", base_scale)
	btn.mouse_entered.connect(
		func():
			if btn.disabled:
				return
			AudioManager.play_sfx_ui("blip_select", 1.0, 0.0)
			if btn.has_meta("_hover_tween") and btn.get_meta("_hover_tween") is Tween:
				(btn.get_meta("_hover_tween") as Tween).kill()
			btn.pivot_offset = Vector2(0, btn.size.y / 2.0)
			var tw := create_tween()
			btn.set_meta("_hover_tween", tw)
			tw.set_parallel(true)
			tw.tween_property(btn, "scale", base_scale * HOVER_POP, 0.06) \
					.set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "modulate", Color(1.0, 0.95, 0.7), 0.06) \
					.set_ease(Tween.EASE_OUT),
	)
	btn.mouse_exited.connect(
		func():
			if btn.has_meta("_hover_tween") and btn.get_meta("_hover_tween") is Tween:
				(btn.get_meta("_hover_tween") as Tween).kill()
			btn.pivot_offset = Vector2(0, btn.size.y / 2.0)
			var tw := create_tween()
			btn.set_meta("_hover_tween", tw)
			tw.set_parallel(true)
			tw.tween_property(btn, "scale", base_scale, 0.08) \
					.set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "modulate", Color.WHITE, 0.08) \
					.set_ease(Tween.EASE_OUT),
	)


func _get_node(path: String) -> Node:
	return get_node_or_null(path)


func _ready() -> void:
	_color_manager = get_tree().get_first_node_in_group("color_manager")
	_apply_menu_style()
	_apply_mode_layout()
	_update_room_display()
	_eye_button.pressed.connect(_on_eye_pressed)
	_copy_button.pressed.connect(_on_copy_pressed)
	_invite_button.pressed.connect(
		func():
			NetworkManager.invite_friend(),
	)
	_switch_button.pressed.connect(_on_switch_stand)
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_button.pressed.connect(
		func():
			LobbyManager.start_game(),
	)
	_back_button.pressed.connect(_on_leave_pressed)
	_avatar_button.pressed.connect(_on_avatar_pressed)
	_house_button.pressed.connect(_on_house_pressed)
	_customize_back_button.pressed.connect(_on_customize_back_pressed)
	# CustomizePanel is hidden by default; lobby is the main view.
	_customize_panel.visible = false
	LobbyManager.roster_changed.connect(_refresh)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.peer_disconnected.connect(
		func(_id):
			_refresh(),
	)
	LobbyManager.request_refresh()
	_version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.0.0")
	call_deferred("_setup_customization")
	call_deferred("_default_to_stand_1")
	_refresh()


## Defaults the local player to stand 1 on entering the lobby, if they
## haven't already selected a stand.
func _default_to_stand_1() -> void:
	var mine := LobbyManager.get_my_entry()
	if mine.get("stand_index", -1) < 0:
		LobbyManager.set_my_stand(0)
		_current_stand = 0
		stand_switched.emit(0)
	else:
		_current_stand = mine.get("stand_index", 0)
	# Set initial drag offset to 0 — per-model base yaw is handled
	# in _apply_yaw_to_models (model 0 = 0°, model 1 = 180°).
	_model_yaw_offset = 0.0
	_apply_yaw_to_models()


func _on_eye_pressed() -> void:
	_room_visible = not _room_visible
	_update_room_display()


func _update_room_display() -> void:
	if _room_visible:
		_room_code_label.text = "Room: %d" % NetworkManager.lobby_id
		_eye_button.text = "◉"
	else:
		_room_code_label.text = "Room: ************"
		_eye_button.text = "◎"


func _on_switch_stand() -> void:
	_current_stand = 1 - _current_stand
	LobbyManager.set_my_stand(_current_stand)
	stand_switched.emit(_current_stand)
	# Smoothly tween the drag offset back to 0 so the model rotates
	# gracefully instead of snapping.
	var start_yaw := _model_yaw_offset
	var tw := create_tween()
	tw \
			.tween_method(
		func(t: float) -> void:
			_model_yaw_offset = lerpf(start_yaw, 0.0, t)
			_apply_yaw_to_models(),
		0.0,
		1.0,
		0.4,
	) \
			.set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_IN_OUT)
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
	return_to_menu_requested.emit()


## Show the avatar customization view (hide lobby, show customize panel
## with only avatar options visible).
func _on_avatar_pressed() -> void:
	_lobby_panel.visible = false
	_customize_panel.visible = true
	_customize_title.text = "Avatar"
	# Show avatar-only rows, hide house-only rows.
	_gender_row.visible = true
	_random_button.visible = true
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/WallsColorRow",
		false,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/RoofColorRow",
		false,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/HairStyleRow",
		true,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/EyebrowsRow",
		true,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/ShirtColorRow",
		true,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/ShoesColorRow",
		true,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/HairColorRow",
		true,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/EyebrowColorRow",
		true,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/PantsColorRow",
		true,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/HeadSizeRow",
		true,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/SkinColorRow",
		true,
	)


## Show the house customization view (hide lobby, show customize panel
## with only house options visible).
func _on_house_pressed() -> void:
	_lobby_panel.visible = false
	_customize_panel.visible = true
	_customize_title.text = "House"
	# Hide avatar-only rows, show house-only rows.
	_gender_row.visible = false
	_random_button.visible = false
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/WallsColorRow",
		true,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/RoofColorRow",
		true,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/HairStyleRow",
		false,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/EyebrowsRow",
		false,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/ShirtColorRow",
		false,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/ShoesColorRow",
		false,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/HairColorRow",
		false,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/EyebrowColorRow",
		false,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/PantsColorRow",
		false,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/HeadSizeRow",
		false,
	)
	_set_node_visible(
		"LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/SkinColorRow",
		false,
	)


## Return from customization view to the lobby.
func _on_customize_back_pressed() -> void:
	_customize_panel.visible = false
	_lobby_panel.visible = true


## Helper to set a node's visibility by path.
func _set_node_visible(path: String, visible: bool) -> void:
	var node := get_node_or_null(path)
	if node is CanvasItem:
		(node as CanvasItem).visible = visible


func _on_server_disconnected() -> void:
	# Don't silently kick — show a popup so the player knows what happened.
	if has_node("HostLeftDialog"):
		return
	var dialog := AcceptDialog.new()
	dialog.name = "HostLeftDialog"
	dialog.title = "Host Left"
	dialog.dialog_text = "The host has left the lobby."
	dialog.ok_button_text = "Back to Menu"
	dialog.confirmed.connect(_go_to_main_menu)
	dialog.canceled.connect(_go_to_main_menu)
	add_child(dialog)
	dialog.popup_centered()


func _go_to_main_menu() -> void:
	return_to_menu_requested.emit()


func _refresh() -> void:
	# Re-apply mode layout in case the mode was synced from the host.
	_apply_mode_layout()
	for child in _stand1_list.get_children():
		child.queue_free()
	for child in _stand2_list.get_children():
		child.queue_free()

	var my_id := multiplayer.get_unique_id()
	var mine: Dictionary = LobbyManager.roster.get(my_id, { })

	# Keep _current_stand in sync with roster
	var my_stand: int = mine.get("stand_index", _current_stand)
	if my_stand >= 0:
		_current_stand = my_stand

	for peer_id in LobbyManager.roster:
		var entry: Dictionary = LobbyManager.roster[peer_id]
		var stand_idx: int = entry.get("stand_index", -1)
		if stand_idx < 0:
			continue
		var ready_mark := "✓ " if entry.get("ready", false) else ""
		var you_text := " (you)" if peer_id == my_id else ""
		var player_name: String = entry.get("name", "Player")

		var label := Label.new()
		label.text = "%s%s%s" % [ready_mark, player_name, you_text]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override(
			"font_color",
			Color(1, 0.95, 0.7, 1) if entry.get("ready", false) else Color(1, 1, 1, 0.85),
		)
		label.add_theme_font_size_override("font_size", 18)
		if stand_idx == 0:
			_stand1_list.add_child(label)
		elif stand_idx == 1:
			_stand2_list.add_child(label)

	_ready_button.text = "Unready" if mine.get("ready", false) else "Ready Up"

	var is_host := multiplayer.is_server()
	_start_button.visible = is_host
	_start_button.disabled = not LobbyManager.all_ready()

# ── Drag to spin player models ────────────────────────────────────────────────


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_last_x = mb.position.x
			else:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var delta_x := mm.position.x - _drag_last_x
		_model_yaw_offset += delta_x * 0.01
		_apply_yaw_to_models()
		_drag_last_x = mm.position.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_dragging = false


func _apply_yaw_to_models() -> void:
	for i in _player_visuals.size():
		var pv := _player_visuals[i]
		if pv == null or i >= _model_base_transforms.size():
			continue
		var base := _model_base_transforms[i]
		var pos := base.origin
		var base_basis := base.basis
		var scale := base_basis.get_scale()
		var base_rot := base_basis.get_rotation_quaternion()
		# Both models use 0° base yaw — the scene transforms already
		# orient each model to face its respective stand camera.
		# The drag offset is added on top for click-to-spin.
		var base_yaw: float = 0.0
		var total_yaw: float = base_yaw + _model_yaw_offset
		var yaw_rot := Quaternion(Vector3.UP, total_yaw)
		var combined := (yaw_rot * base_rot).normalized()
		var new_basis := Basis(combined).scaled(scale)
		pv.transform = Transform3D(new_basis, pos)

# ── Character Customization ──────────────────────────────────────────────────


func _setup_customization() -> void:
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
	_apply_customization_to_all()
	_update_all_names()

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

	# Left column: Hair style, Eyebrows, Shirt color, Shoes color, Walls color
	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/HairStyleRow/HairPrev \
			.pressed \
			.connect(
		func():
			_hair_index = (_hair_index - 1 + _player_visuals[0].get_hair_count()) % _player_visuals[
				0
			].get_hair_count()
			_on_customization_changed(),
	)
	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/HairStyleRow/HairNext \
			.pressed \
			.connect(
		func():
			_hair_index = (_hair_index + 1) % _player_visuals[0].get_hair_count()
			_on_customization_changed(),
	)

	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/EyebrowsRow/EyebrowPrev \
			.pressed \
			.connect(
		func():
			_eyebrow_index = (_eyebrow_index - 1 + _player_visuals[0].get_eyebrow_count()) % _player_visuals[
				0
			].get_eyebrow_count()
			_on_customization_changed(),
	)
	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/EyebrowsRow/EyebrowNext \
			.pressed \
			.connect(
		func():
			_eyebrow_index = (_eyebrow_index + 1) % _player_visuals[0].get_eyebrow_count()
			_on_customization_changed(),
	)

	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/ShirtColorRow/ShirtColorPrev \
			.pressed \
			.connect(
		func():
			_shirt_color_index = (_shirt_color_index - 1 + PlayerVisuals.CLOTHING_COLORS.size()) % PlayerVisuals \
					.CLOTHING_COLORS \
					.size()
			_on_customization_changed(),
	)
	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/ShirtColorRow/ShirtColorNext \
			.pressed \
			.connect(
		func():
			_shirt_color_index = (_shirt_color_index + 1) % PlayerVisuals.CLOTHING_COLORS.size()
			_on_customization_changed(),
	)

	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/ShoesColorRow/ShoesColorPrev \
			.pressed \
			.connect(
		func():
			_shoes_color_index = (_shoes_color_index - 1 + PlayerVisuals.CLOTHING_COLORS.size()) % PlayerVisuals \
					.CLOTHING_COLORS \
					.size()
			_on_customization_changed(),
	)
	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/ShoesColorRow/ShoesColorNext \
			.pressed \
			.connect(
		func():
			_shoes_color_index = (_shoes_color_index + 1) % PlayerVisuals.CLOTHING_COLORS.size()
			_on_customization_changed(),
	)

	var wall_count := _get_wall_colors().size()
	if wall_count > 0:
		$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/WallsColorRow/WallsColorPrev \
				.pressed \
				.connect(
			func():
				_walls_color_index = (_walls_color_index - 1 + wall_count) % wall_count
				_on_customization_changed(),
		)
		$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/LeftCol/WallsColorRow/WallsColorNext \
				.pressed \
				.connect(
			func():
				_walls_color_index = (_walls_color_index + 1) % wall_count
				_on_customization_changed(),
		)

	# Right column: Hair color, Eyebrow color, Pants color, Head size, Roof color
	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/HairColorRow/HairColorPrev \
			.pressed \
			.connect(
		func():
			_hair_color_index = (_hair_color_index - 1 + PlayerVisuals.HAIR_COLORS.size()) % PlayerVisuals \
					.HAIR_COLORS \
					.size()
			_on_customization_changed(),
	)
	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/HairColorRow/HairColorNext \
			.pressed \
			.connect(
		func():
			_hair_color_index = (_hair_color_index + 1) % PlayerVisuals.HAIR_COLORS.size()
			_on_customization_changed(),
	)

	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/EyebrowColorRow/EyebrowColorPrev \
			.pressed \
			.connect(
		func():
			_eyebrow_color_index = (_eyebrow_color_index - 1 + PlayerVisuals.HAIR_COLORS.size()) % PlayerVisuals \
					.HAIR_COLORS \
					.size()
			_on_customization_changed(),
	)
	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/EyebrowColorRow/EyebrowColorNext \
			.pressed \
			.connect(
		func():
			_eyebrow_color_index = (_eyebrow_color_index + 1) % PlayerVisuals.HAIR_COLORS.size()
			_on_customization_changed(),
	)

	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/PantsColorRow/PantsColorPrev \
			.pressed \
			.connect(
		func():
			_pants_color_index = (_pants_color_index - 1 + PlayerVisuals.CLOTHING_COLORS.size()) % PlayerVisuals \
					.CLOTHING_COLORS \
					.size()
			_on_customization_changed(),
	)
	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/PantsColorRow/PantsColorNext \
			.pressed \
			.connect(
		func():
			_pants_color_index = (_pants_color_index + 1) % PlayerVisuals.CLOTHING_COLORS.size()
			_on_customization_changed(),
	)

	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/HeadSizeRow/HeadPrev \
			.pressed \
			.connect(
		func():
			_head_size_index = max(0, _head_size_index - 1)
			_on_customization_changed(),
	)
	$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/HeadSizeRow/HeadNext \
			.pressed \
			.connect(
		func():
			_head_size_index = min(HEAD_SIZE_STEPS - 1, _head_size_index + 1)
			_on_customization_changed(),
	)

	var roof_count := _get_roof_colors().size()
	if roof_count > 0:
		$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/RoofColorRow/RoofColorPrev \
				.pressed \
				.connect(
			func():
				_roof_color_index = (_roof_color_index - 1 + roof_count) % roof_count
				_on_customization_changed(),
		)
		$LeftContainer/CustomizePanel/OptionsCol/ColumnsRow/RightCol/RoofColorRow/RoofColorNext \
				.pressed \
				.connect(
			func():
				_roof_color_index = (_roof_color_index + 1) % roof_count
				_on_customization_changed(),
		)

	$LeftContainer/CustomizePanel/OptionsCol/RandomButton.pressed.connect(_on_randomize)
	# Skin color slider
	if _skin_color_slider:
		_skin_color_slider.value_changed.connect(
			func(v: float):
				_skin_color_value = v
				_on_customization_changed(),
		)
	_update_gender_buttons()


func _get_wall_colors() -> Array[Color]:
	if (
		_color_manager and _color_manager.has_method("get")
		and _color_manager.get("wall_colors") != null
	):
		return _color_manager.wall_colors
	return []


func _get_roof_colors() -> Array[Color]:
	if (
		_color_manager and _color_manager.has_method("get")
		and _color_manager.get("roof_colors") != null
	):
		return _color_manager.roof_colors
	return []


func _on_customization_changed() -> void:
	if _player_visuals.is_empty():
		return
	_apply_customization_to_all()
	_update_all_names()
	_update_gender_buttons()
	_broadcast_customization()


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
		pv.set_skin_color(_skin_color_value)
		pv.scale_head_bone(_head_size_to_scale())
		pv.play_anim("Idle")


func _head_size_to_scale() -> float:
	var step: float = (HEAD_SIZE_MAX - HEAD_SIZE_MIN) / float(HEAD_SIZE_STEPS - 1)
	return HEAD_SIZE_MIN + step * _head_size_index


func _update_gender_buttons() -> void:
	_male_button.button_pressed = _is_male
	_female_button.button_pressed = not _is_male


func _update_all_names() -> void:
	if _player_visuals.is_empty():
		return
	var pv := _player_visuals[0]
	_hair_name.text = pv.get_hair_name(_hair_index)
	_hair_color_name.text = HAIR_COLOR_NAMES[_hair_color_index]
	_eyebrow_name.text = pv.get_eyebrow_name(_eyebrow_index)
	_eyebrow_color_name.text = HAIR_COLOR_NAMES[_eyebrow_color_index]
	_shirt_color_name.text = CLOTHING_COLOR_NAMES[_shirt_color_index]
	_pants_color_name.text = CLOTHING_COLOR_NAMES[_pants_color_index]
	_shoes_color_name.text = CLOTHING_COLOR_NAMES[_shoes_color_index]
	_head_name.text = "%.1fx" % _head_size_to_scale()
	_walls_color_name.text = WALL_COLOR_NAMES[_walls_color_index] if _walls_color_index < WALL_COLOR_NAMES.size() else "—"
	_roof_color_name.text = ROOF_COLOR_NAMES[_roof_color_index] if _roof_color_index < ROOF_COLOR_NAMES.size() else "—"


func _on_randomize() -> void:
	if _player_visuals.is_empty():
		return
	_is_male = randi() % 2 == 0
	_hair_index = randi() % _player_visuals[0].get_hair_count()
	_hair_color_index = randi() % PlayerVisuals.HAIR_COLORS.size()
	_eyebrow_index = randi() % _player_visuals[0].get_eyebrow_count()
	_eyebrow_color_index = randi() % PlayerVisuals.HAIR_COLORS.size()
	_shirt_color_index = randi() % PlayerVisuals.CLOTHING_COLORS.size()
	_pants_color_index = randi() % PlayerVisuals.CLOTHING_COLORS.size()
	_shoes_color_index = randi() % PlayerVisuals.CLOTHING_COLORS.size()
	_head_size_index = randi() % HEAD_SIZE_STEPS
	_skin_color_value = randf()
	if _skin_color_slider:
		_skin_color_slider.value = _skin_color_value
	var wc := _get_wall_colors()
	if not wc.is_empty():
		_walls_color_index = randi() % wc.size()
	var rc := _get_roof_colors()
	if not rc.is_empty():
		_roof_color_index = randi() % rc.size()
	_on_customization_changed()


func _broadcast_customization() -> void:
	var data := _get_customization_data()
	LobbyManager.set_my_customization(data)


func _get_customization_data() -> Dictionary:
	var wall_color: Color = Color.WHITE
	var roof_color: Color = Color.WHITE
	var wc := _get_wall_colors()
	if not wc.is_empty() and _walls_color_index < wc.size():
		wall_color = wc[_walls_color_index]
	var rc := _get_roof_colors()
	if not rc.is_empty() and _roof_color_index < rc.size():
		roof_color = rc[_roof_color_index]
	return {
		"male": _is_male,
		"hair_index": _hair_index,
		"hair_color": PlayerVisuals.HAIR_COLORS[_hair_color_index],
		"eyebrow_index": _eyebrow_index,
		"eyebrow_color": PlayerVisuals.HAIR_COLORS[_eyebrow_color_index],
		"head_size": _head_size_to_scale(),
		"skin_color": _skin_color_value,
		"clothing_colors": {
			"shirt": PlayerVisuals.CLOTHING_COLORS[_shirt_color_index],
			"top": PlayerVisuals.CLOTHING_COLORS[_shirt_color_index],
			"pants": PlayerVisuals.CLOTHING_COLORS[_pants_color_index],
			"trousers": PlayerVisuals.CLOTHING_COLORS[_pants_color_index],
			"shoes": PlayerVisuals.CLOTHING_COLORS[_shoes_color_index],
		},
		"wall_color": wall_color,
		"roof_color": roof_color,
	}

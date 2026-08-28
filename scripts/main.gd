extends Node
## Main scene root. Wires everything together at startup.

const CASH_PICKUP_SCENE: PackedScene = preload("res://scenes/objects/cash_pickup.tscn")
const OUTLINE_SCENE: PackedScene = preload("res://scenes/ui/outline_overlay.tscn")
const DAY_SUMMARY_SCENE: PackedScene = preload("res://scenes/ui/day_summary.tscn")
const WORLD_MENU_SCENE: PackedScene = preload("res://scenes/ui/world_menu.tscn")
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const DeliveryGrid := preload("res://scripts/systems/delivery_grid.gd")

## Game states. MAIN_MENU shows the in-world menu overlay; LOBBY is the
## pre-game customization phase; PLAYING is the active simulation.
enum MenuState {
	MAIN_MENU,
	LOBBY,
	PLAYING,
}

@onready var world: Node3D = $World
@onready var players_node: Node3D = $Players
@onready var world_objects: Node3D = $WorldObjects
@onready var player_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var world_spawner: MultiplayerSpawner = $WorldSpawner
@onready var spawner: Node = $CustomerSpawner
@onready var spawner2: Node = $CustomerSpawner2
@onready var ped_spawner: Node = $PedestrianSpawner
@onready var delivery: Node = $DeliverySystem
@onready var delivery2: Node = $DeliverySystem2
@onready var hud: CanvasLayer = $HUD
@onready var stand_unit: StandUnit = world.find_child("StandUnit", true, false) as StandUnit
@onready var stand_unit2: StandUnit = world.find_child("StandUnit2", true, false) as StandUnit
@onready var lobby_camera: Camera3D = $LobbyCamera
@onready var main_menu_camera: Camera3D = $MainMenuCameras/MainMenuCamera
@onready var lobby_ui: Control = $LobbyUI
@onready var lobby_player_models: Node3D = $LobbyPlayerModels
@onready var lobby_cam_stand1: Camera3D = $LobbyCamStand1
@onready var lobby_cam_stand2: Camera3D = $LobbyCamStand2
@onready var stand_change_cam_end: Marker3D = $MainMenuCameras/StandChangeCameraEnd
@onready var stand_change_cam_start: Marker3D = $MainMenuCameras/StandChangeCameraStart
@onready var stand1_start_position: Marker3D = $Stand1StartPosition
@onready var stand2_start_position: Marker3D = $Stand2StartPosition
@onready var _transition_blur_rect: ColorRect = $TransitionOverlay/BlurRect
@onready var _transition_overlay: CanvasLayer = $TransitionOverlay

## FPS counter label (toggled with F key)
var _fps_label: Label = null
var _fps_shown: bool = false
var _fps_timer: float = 0.0

## The locally-controlled player, once spawned. Player is now spawned
## dynamically per connected peer (host + anyone who joins) instead of
## being a static scene node, so a second real player can get their own
## instance instead of everyone sharing "the" Player.
var _local_player: Player = null
## peer_id -> StandUnit this peer's spawned player was assigned to.
## Assignment order: the host (peer 1) always gets the primary stand;
## whoever connects next gets the next stand, and so on.
var _assigned_stands: Dictionary = { }

var _cash_drop_pos: Vector3 = Vector3(0, 1.05, -0.4)

var _world_env: WorldEnvironment
var _default_ambient_color: Color
var _default_exposure: float

var _enhanced_lighting: bool = true
var _voxel_gi: VoxelGI = null
var _reflection_probe: ReflectionProbe = null
var _fill_light: OmniLight3D = null
var _orig_ssr: bool = false
var _orig_ssao: bool = false
var _orig_ssil: bool = false
var _orig_sdfgi: bool = false
var _orig_sdfgi_energy: float = 1.0
var _orig_tonemap_mode: int = 0
var _orig_tonemap_white: float = 1.0
var _orig_tonemap_exposure: float = 1.0
var _orig_ambient_source: int = 0
var _orig_ambient_color: Color = Color.WHITE
var _orig_ambient_sky: float = 0.0
var _orig_glow: bool = false
var _orig_shadow_blur: float = 1.0
var _orig_shadow_normal_bias: float = 1.0
var _orig_shadow_bias: float = 1.0
var _orig_fill_energy: float = 0.5

## Lobby phase: true while in the lobby, false once the game starts.
## During lobby, the LobbyCamera is active and game systems are paused.
var _in_lobby: bool = true

## Current game state. MAIN_MENU is the in-world menu overlay shown on
## first load; LOBBY is the pre-game customization; PLAYING is active sim.
var _game_state: MenuState = MenuState.LOBBY

## The in-world main menu overlay (instantiated when entering MAIN_MENU).
var _world_menu: CanvasLayer = null

## True for the local late joiner once the host has started their spawn-in.
var _late_join_camera_pending: bool = false

## Camera tween time for stand switching and game-start transition.
const CAMERA_TWEEN_TIME: float = 1.0

## --- Stand change transition ---
## When the player selects/creates a save from the menu, we play a
## looping camera whip transition while the save loads in the background.
## The camera tweens from current pos -> StandChangeCameraEnd, snaps to
## StandChangeCameraStart, then tweens back toward MainMenuCamera. If the
## save isn't loaded yet, it loops again. Motion blur intensifies during
## the whip and fades at the settle point.
var _transition_active: bool = false
var _transition_loaded: bool = false
var _world_setup_done: bool = false
var _transition_tween: Tween = null
var _transition_blur_tween: Tween = null
const TRANSITION_WHIP_TIME: float = 0.5
const TRANSITION_SETTLE_TIME: float = 0.8
# Mouse parallax for main menu camera.
var _menu_cam_base_pos: Vector3 = Vector3.ZERO
var _menu_cam_parallax_current: Vector2 = Vector2.ZERO
const MENU_CAM_PARALLAX_STRENGTH: float = 0.2
const MENU_CAM_PARALLAX_SMOOTH: float = 3.0


## Returns the camera node for the given stand index. These are
## Camera3D nodes placed in the editor — select one and click
## "Preview" in the editor viewport to see exactly what it sees.
func _get_lobby_cam(stand_index: int) -> Camera3D:
	match stand_index:
		0:
			return lobby_cam_stand1
		1:
			return lobby_cam_stand2
		_:
			return lobby_cam_stand1


func _ready() -> void:
	# Use the sky material set up in the editor (ProceduralSkyMaterial).
	_world_env = world.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if _world_env and _world_env.environment:
		_orig_ssr = _world_env.environment.ssr_enabled
		_orig_ssao = _world_env.environment.ssao_enabled
		_orig_ssil = _world_env.environment.ssil_enabled
		_orig_sdfgi = _world_env.environment.sdfgi_enabled
		_orig_sdfgi_energy = _world_env.environment.sdfgi_energy
		_orig_tonemap_mode = _world_env.environment.tonemap_mode
		_orig_tonemap_white = _world_env.environment.tonemap_white
		_orig_tonemap_exposure = _world_env.environment.tonemap_exposure
		_orig_glow = _world_env.environment.glow_enabled
		_orig_ambient_source = _world_env.environment.ambient_light_source
		_orig_ambient_color = _world_env.environment.ambient_light_color
		_orig_ambient_sky = _world_env.environment.ambient_light_sky_contribution
		_world_env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_world_env.environment.ambient_light_color = Color(0.35, 0.35, 0.38, 1)
		_world_env.environment.ambient_light_sky_contribution = 0.6
		_default_ambient_color = _world_env.environment.ambient_light_color
		_default_exposure = _world_env.environment.tonemap_exposure

	# Mark static meshes for LightmapGI baking
	_mark_static_gi(world)
	# Enhanced lighting is on by default; F2 toggles it off
	_enable_enhanced_lighting()

	# Create FPS counter label (toggled with F key)
	_fps_label = Label.new()
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_fps_label.offset_left = 8
	_fps_label.offset_top = -30
	_fps_label.offset_right = 120
	_fps_label.offset_bottom = -4
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 0.4, 0.9))
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 3)
	_fps_label.text = "FPS: --"
	_fps_label.visible = false
	hud.add_child(_fps_label)

	# Connect to game_starting signal — when the host starts the game,
	# transition from lobby to game phase (camera tween, hide UI, start systems).
	LobbyManager.game_starting.connect(_on_game_starting)
	LobbyManager.late_join_starting.connect(_on_late_join_starting)
	LobbyManager.late_join_denied.connect(_on_late_join_denied)

	# If we're connected to a server (joining an existing game), go
	# straight to the lobby/game flow. Otherwise, show the in-world
	# main menu so the player can choose Play, Saves, or Join.
	# Note: Steam init creates a default multiplayer peer, so
	# has_multiplayer_peer() is true even without hosting/joining.
	# Use NetworkManager.connected instead.
	var has_session := NetworkManager.connected or not LobbyManager.roster.is_empty()
	GameLog.log(
		"[Main] _ready: has_session=%s connected=%s roster=%s"
		% [has_session, NetworkManager.connected, not LobbyManager.roster.is_empty()]
	)
	if has_session:
		# Already connected or have a roster — set up networking and
		# enter lobby/game flow.
		_setup_lobby()
		_setup_networking()
		NetworkManager.server_disconnected.connect(_on_host_left)
		_game_state = MenuState.LOBBY
	else:
		# No multiplayer session — show the in-world main menu.
		# _setup_lobby() is deferred until we actually enter the lobby.
		_enter_main_menu()


## Sets up the lobby phase: positions the lobby camera, wires the lobby UI
## to the player model, and hides the HUD.
func _setup_lobby() -> void:
	_in_lobby = true
	# LobbyCamera is the active camera during the lobby
	lobby_camera.current = true
	# Hide the HUD during lobby — it'll be shown when the game starts
	if hud:
		hud.visible = false
	# Wire the lobby UI to all player models so customization applies
	# to both (player sees their character regardless of which stand
	# the camera is looking at).
	var models: Array[PlayerVisuals] = []
	for child in lobby_player_models.get_children():
		var pv := child as PlayerVisuals
		if pv:
			models.append(pv)
	if not models.is_empty() and lobby_ui.has_method("set_player_visuals"):
		lobby_ui.set_player_visuals(models)
	# Make player models look at the lobby camera with their eyes
	if lobby_ui.has_method("set_look_at_target"):
		lobby_ui.set_look_at_target(lobby_camera)
	# Position the lobby camera at the default stand (stand 1)
	_position_lobby_camera(0, false)
	# Connect stand switch signal from lobby UI for camera tweening
	if lobby_ui.has_signal("stand_switched"):
		if not lobby_ui.stand_switched.is_connected(_on_stand_switched):
			lobby_ui.stand_switched.connect(_on_stand_switched)
		if not lobby_ui.return_to_menu_requested.is_connected(_on_return_to_menu):
			lobby_ui.return_to_menu_requested.connect(_on_return_to_menu)
	# Lobby UI is visible during the lobby phase.
	lobby_ui.visible = true

## --- In-world main menu ---


## Enter the MAIN_MENU state: show the MainMenuCamera, instantiate the
## world menu overlay, and freeze game systems.
func _enter_main_menu() -> void:
	_game_state = MenuState.MAIN_MENU
	_in_lobby = false
	# Use the MainMenuCamera as the active camera.
	if main_menu_camera:
		main_menu_camera.current = true
		_menu_cam_base_pos = main_menu_camera.global_position
		# Eagerly store the home transform and FOV so they're available
		# even after _transition_to_lobby() moves the camera.
		set_meta("_main_menu_cam_transform", main_menu_camera.global_transform)
		set_meta("_main_menu_cam_fov", main_menu_camera.fov)
	if lobby_camera:
		lobby_camera.current = false
	# Hide the HUD and lobby UI during the menu.
	if hud:
		hud.visible = false
	if lobby_ui:
		lobby_ui.visible = false
	# Instantiate the world menu overlay if not already present.
	if _world_menu == null or not is_instance_valid(_world_menu):
		_world_menu = WORLD_MENU_SCENE.instantiate() as CanvasLayer
		add_child(_world_menu)
		_world_menu.play_pressed.connect(_on_menu_play)
		_world_menu.saves_pressed.connect(_on_menu_saves)
		_world_menu.join_pressed.connect(_on_menu_join)
		_world_menu.host_pressed.connect(_on_menu_host)
		_world_menu.new_stand_requested.connect(_on_menu_new_stand)
		_world_menu.load_stand_requested.connect(_on_menu_load_stand)
		_world_menu.fullscreen_toggled.connect(_on_fullscreen_toggled)
		_world_menu.vsync_toggled.connect(_on_vsync_toggled)
		_world_menu.enhanced_lighting_toggled.connect(_on_enhanced_lighting_toggled)
		_world_menu.fps_toggled.connect(_on_fps_toggled)
	_world_menu.show_menu()
	# If no save has been loaded yet (current_slot is empty), peek at
	# the most recent save's stand name so the sign shows the right
	# name on startup. The full save is only loaded on Play.
	if SaveManager.current_slot == "":
		var saves := SaveManager.list_saves()
		if not saves.is_empty():
			GameState.stand_name = saves[0].get("stand_name", saves[0].get("slot", ""))
	# Update stand sign: show the loaded stand name, or default text
	# if no saves exist at all (brand new player).
	var sign_text := GameState.stand_name
	if sign_text == "Lemonade Stand" and SaveManager.list_saves().is_empty():
		sign_text = "🍋 LEMONADE STAND 🍋"
	if stand_unit:
		stand_unit.set_stand_name(sign_text)
	if stand_unit2:
		stand_unit2.set_stand_name(sign_text)
	# Freeze game systems while in the menu.
	_set_systems_paused(true)
	# Connect network signals so we transition to the lobby when a
	# session is established (from Play/Host or Join).
	if not NetworkManager.lobby_created.is_connected(_on_menu_session_ready):
		NetworkManager.lobby_created.connect(_on_menu_session_ready)
	if not NetworkManager.server_connected.is_connected(_on_menu_session_ready):
		NetworkManager.server_connected.connect(_on_menu_session_ready)
	if not NetworkManager.connection_failed.is_connected(_on_menu_session_failed):
		NetworkManager.connection_failed.connect(_on_menu_session_failed)
	GameLog.log("[Main] Entered MAIN_MENU state")


## Pause or unpause game systems (spawners, day cycle, etc.) so the world
## stays frozen during the main menu.
func _set_systems_paused(paused: bool) -> void:
	var process_mode_val := Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	for node in [spawner, spawner2, ped_spawner, delivery, delivery2]:
		if node:
			node.process_mode = process_mode_val
	if DayManager:
		DayManager.process_mode = process_mode_val


## Play button: load the most recent save and go to lobby, or if no
## saves exist, prompt the player to name their first stand.
func _on_menu_play() -> void:
	var saves := SaveManager.list_saves()
	if not saves.is_empty():
		var latest: Dictionary = saves[0]
		var slot: String = latest.get("slot", "")
		if slot != "":
			SaveManager.load_existing_game(slot)
			NetworkManager.host_game()
			_world_menu.hide_menu()
			return
	# No saves — prompt for a stand name.
	_world_menu.show_name_entry()


## New stand created from the saves panel name dialog.
func _on_menu_new_stand(stand_name: String) -> void:
	SaveManager.start_new_game(stand_name)
	_start_stand_transition(stand_name, stand_name)


## Load an existing stand from the saves panel.
func _on_menu_load_stand(slot_name: String) -> void:
	var saves := SaveManager.list_saves()
	var stand_name := slot_name
	for s in saves:
		if s.get("slot", "") == slot_name:
			stand_name = s.get("stand_name", slot_name)
			break
	SaveManager.load_existing_game(slot_name)
	_start_stand_transition(slot_name, stand_name)


## Host button (from Saves panel): a save was selected, host a new game.
func _on_menu_host() -> void:
	NetworkManager.host_game()


## Settings handlers.
func _on_fullscreen_toggled(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_vsync_toggled(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	)


func _on_enhanced_lighting_toggled(enabled: bool) -> void:
	_enhanced_lighting = enabled
	if enabled:
		_enable_enhanced_lighting()
	else:
		_disable_enhanced_lighting()


func _on_fps_toggled(enabled: bool) -> void:
	_fps_shown = enabled
	if _fps_label:
		_fps_label.visible = _fps_shown

## --- Stand change transition ---


## Start the camera whip transition. The save should already be loaded
## (or loading) via SaveManager. We play a looping whip effect and
## settle once the world is ready.
func _start_stand_transition(slot_name: String, stand_name: String) -> void:
	if _transition_active:
		return
	_transition_active = true
	_transition_loaded = false
	if _transition_overlay:
		_transition_overlay.visible = true
	# Play the transition swoosh sound immediately on click,
	# skipping the first 0.3s, sped up 1.3x, with a short fade-in.
	AudioManager.play_sfx_ui("stand_transition_swoosh", 1.3, 0.0, 0.3, 0.1)
	_world_menu.set_busy("Loading %s..." % stand_name)
	# Hide the menu UI but keep the blur panel.
	_world_menu.hide_menu()
	# Make sure the MainMenuCamera is the active camera.
	if main_menu_camera:
		main_menu_camera.current = true
	print("[Transition] START slot=%s stand=%s" % [slot_name, stand_name])
	print("[Transition] MainMenuCamera pos=%s" % main_menu_camera.global_position)
	print("[Transition] End marker pos=%s" % stand_change_cam_end.global_position)
	print("[Transition] Start marker pos=%s" % stand_change_cam_start.global_position)
	print("[Transition] Stored main menu cam transform: %s" % _get_main_menu_cam_transform())
	# Mark as loaded — SaveManager.load_existing_game/start_new_game are
	# synchronous, so by the time we get here the state is already applied.
	# In the future if loading becomes async, this is where we'd wait.
	_transition_loaded = true
	# Start the whip loop.
	_do_transition_whip()


## One iteration of the whip: current pos -> End, snap to Start, then
## either settle to MainMenuCamera (if loaded) or loop again.
func _do_transition_whip() -> void:
	if not _transition_active:
		return
	print("[Transition] WHIP START from pos=%s" % main_menu_camera.global_position)
	# Blur in.
	_tween_blur(1.0, TRANSITION_WHIP_TIME * 0.5)
	# Whip to End.
	if _transition_tween:
		_transition_tween.kill()
	_transition_tween = create_tween()
	_transition_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Tween only position, keep rotation fixed to avoid dipping.
	_transition_tween.tween_property(
		main_menu_camera,
		"global_position",
		stand_change_cam_end.global_position,
		TRANSITION_WHIP_TIME,
	)
	_transition_tween.tween_callback(
		func():
			# Snap to Start position (keep rotation).
			main_menu_camera.global_position = stand_change_cam_start.global_position
			print("[Transition] SNAP to Start, pos=%s" % main_menu_camera.global_position)
			# Blur out slightly.
			_tween_blur(0.3, TRANSITION_SETTLE_TIME * 0.3)
			# Tween toward MainMenuCamera position.
			var target := _get_main_menu_cam_transform()
			print("[Transition] SETTLE to target pos=%s" % target.origin)
			var settle := create_tween()
			settle.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			settle.tween_property(
				main_menu_camera,
				"global_position",
				target.origin,
				TRANSITION_SETTLE_TIME,
			)
			settle.tween_callback(
				func():
					print(
						"[Transition] SETTLE DONE, pos=%s loaded=%s"
						% [main_menu_camera.global_position, _transition_loaded]
					)
					_tween_blur(0.0, 0.3)
					if _transition_loaded:
						_finish_transition()
					else:
						# Not loaded yet — loop.
						_do_transition_whip(),
			),
	)


## Finish the transition: restore the menu, stop blur, and run world setup
## (day cycle, containers, spawners, etc.) so it's ready before the lobby.
func _finish_transition() -> void:
	_transition_active = false
	_setup_world_systems()
	print("[Transition] FINISH, final pos=%s" % main_menu_camera.global_position)
	_tween_blur(0.0, 0.2)
	if _transition_overlay:
		# Hide after the blur fade completes.
		get_tree().create_timer(0.3).timeout.connect(
			func():
				if _transition_overlay:
					_transition_overlay.visible = false,
		)
	# Show the menu again (without animation — animation tween may not
	# process reliably right after the transition tweens).
	if _world_menu and is_instance_valid(_world_menu):
		_world_menu.show_menu_immediate()
		_world_menu.set_status("")
		_world_menu.set_enabled(true)
	# Update stand sign with the newly loaded stand name.
	if stand_unit:
		stand_unit.set_stand_name(GameState.stand_name)
	if stand_unit2:
		stand_unit2.set_stand_name(GameState.stand_name)
		# Check MenuBox visibility
		var menu_box := _world_menu.get_node_or_null("MenuBox")
		if menu_box:
			print(
				"[Transition] MenuBox visible=%s modulate=%s"
				% [menu_box.visible, menu_box.modulate]
			)
		else:
			print("[Transition] MenuBox is NULL!")
	else:
		print("[Transition] _world_menu is NULL or invalid!")
	# Ensure camera is exactly at the main menu position.
	if main_menu_camera:
		main_menu_camera.global_transform = _get_main_menu_cam_transform()
		main_menu_camera.current = true


## Returns the stored original transform of the MainMenuCamera, since
## we may have moved it during the transition.
func _get_main_menu_cam_transform() -> Transform3D:
	# Store the original transform on first call.
	if not has_meta("_main_menu_cam_transform"):
		set_meta("_main_menu_cam_transform", main_menu_camera.global_transform)
	return get_meta("_main_menu_cam_transform") as Transform3D


## Tween the motion blur amount.
func _tween_blur(target: float, duration: float) -> void:
	if _transition_blur_tween:
		_transition_blur_tween.kill()
	if _transition_blur_rect == null or _transition_blur_rect.material == null:
		return
	var mat := _transition_blur_rect.material as ShaderMaterial
	var current: float = mat.get_shader_parameter("blur_amount")
	_transition_blur_tween = create_tween()
	_transition_blur_tween \
			.tween_method(
		func(v: float):
			mat.set_shader_parameter("blur_amount", v),
		current,
		target,
		duration,
	) \
			.set_ease(Tween.EASE_OUT)


## Join button: connect to an existing lobby by ID.
func _on_menu_join(lobby_id: int) -> void:
	NetworkManager.join_game(lobby_id)


## Called when a lobby is created or a server connection succeeds while
## in the MAIN_MENU state. Transitions to the LOBBY state.
func _on_menu_session_ready(_arg: Variant = null) -> void:
	if _game_state != MenuState.MAIN_MENU:
		return
	GameLog.log("[Main] Session ready, transitioning to lobby")
	_transition_to_lobby()


## Called when a connection fails while in the MAIN_MENU state.
func _on_menu_session_failed(reason: String) -> void:
	if _world_menu:
		_world_menu.set_status("Failed: %s" % reason)
		_world_menu.set_enabled(true)


## Saves button: the world_menu handles showing the saves panel internally.
## Nothing extra needed here — the panel is toggled within world_menu.gd.
func _on_menu_saves() -> void:
	pass


## Transition from MAIN_MENU to LOBBY: tween the MainMenuCamera to the
## LobbyCamera, then activate the lobby UI.
func _transition_to_lobby() -> void:
	if _game_state != MenuState.MAIN_MENU:
		return
	_game_state = MenuState.LOBBY
	_in_lobby = true
	if _world_menu:
		_world_menu.hide_menu()
	# Set up the lobby now (camera, UI wiring, player models).
	# This was deferred from _ready() because we started in MAIN_MENU.
	_setup_lobby()
	# Tween MainMenuCamera to the LobbyCamera's transform, then switch.
	if main_menu_camera and lobby_camera:
		# Temporarily make lobby_camera current so _setup_lobby's wiring
		# works, then switch back to main_menu_camera for the tween.
		lobby_camera.current = false
		main_menu_camera.current = true
		# Show lobby UI now but at 0 alpha so it can fade in during the tween.
		if lobby_ui:
			lobby_ui.visible = true
			lobby_ui.modulate = Color(1, 1, 1, 0)
		var target := lobby_camera.global_transform
		var target_fov: float = lobby_camera.fov
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(main_menu_camera, "global_transform", target, CAMERA_TWEEN_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(main_menu_camera, "fov", target_fov, CAMERA_TWEEN_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.chain().tween_callback(
			func():
				main_menu_camera.global_transform = target
				main_menu_camera.fov = target_fov
				main_menu_camera.current = false
				lobby_camera.current = true,
		)
		# Fade in lobby UI right as the camera arrives.
		if lobby_ui:
			tw.tween_property(lobby_ui, "modulate:a", 1.0, 0.25) \
					.set_ease(Tween.EASE_OUT)
	else:
		if lobby_camera:
			lobby_camera.current = true
		if lobby_ui:
			lobby_ui.visible = true
	# Update stand signs with the loaded stand name.
	if stand_unit:
		stand_unit.set_stand_name(GameState.stand_name)
	if stand_unit2:
		stand_unit2.set_stand_name(GameState.stand_name)
	# Unfreeze game systems for the lobby phase (still no day cycle).
	_set_systems_paused(false)
	# Set up networking now that we're entering the lobby.
	_setup_networking()
	if not NetworkManager.server_disconnected.is_connected(_on_host_left):
		NetworkManager.server_disconnected.connect(_on_host_left)
	GameLog.log("[Main] Transitioned to LOBBY state")


## Smoothly transition from the lobby back to the main menu.
## Tweens the lobby camera back to the main menu camera's transform,
## fades out the lobby UI, then switches to the main menu in-place
## (no scene reload = no black flash).
func _on_return_to_menu() -> void:
	if _transition_active:
		return
	_transition_active = true
	# Clean up networking and save state now.
	NetworkManager.leave_game()
	LobbyManager.reset()
	SaveManager.clear_current_slot()
	# Fade out lobby UI.
	if lobby_ui:
		var fade_tw := create_tween()
		fade_tw.tween_property(lobby_ui, "modulate:a", 0.0, 0.3) \
				.set_ease(Tween.EASE_OUT)
	# Switch to main menu camera immediately, but set it to the lobby
	# camera's current transform so there's no visual snap. Then tween
	# the main menu camera back to its home position.
	if main_menu_camera and lobby_camera:
		var start_transform := lobby_camera.global_transform
		var start_fov: float = lobby_camera.fov
		var target := _get_main_menu_cam_transform()
		var target_fov: float = main_menu_camera.fov
		if has_meta("_main_menu_cam_fov"):
			target_fov = get_meta("_main_menu_cam_fov") as float
		# Snap main menu camera to lobby camera's current view.
		main_menu_camera.global_transform = start_transform
		main_menu_camera.fov = start_fov
		lobby_camera.current = false
		main_menu_camera.current = true
		# Tween main menu camera to its home position.
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(main_menu_camera, "global_transform", target, CAMERA_TWEEN_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(main_menu_camera, "fov", target_fov, CAMERA_TWEEN_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.chain().tween_callback(
			func():
				main_menu_camera.global_transform = target
				main_menu_camera.fov = target_fov
				_menu_cam_base_pos = target.origin
				if lobby_ui:
					lobby_ui.visible = false
					lobby_ui.modulate = Color(1, 1, 1, 1)
				if _world_menu:
					_world_menu.show_menu()
				_game_state = MenuState.MAIN_MENU
				_in_lobby = false
				_transition_active = false,
		)
	else:
		if lobby_ui:
			lobby_ui.visible = false
		if _world_menu:
			_world_menu.show_menu_immediate(0.4)
		_game_state = MenuState.MAIN_MENU
		_in_lobby = false
		_transition_active = false


## Positions the lobby camera at the given stand index, optionally tweening.
## Reads the transform from the LobbyCamStand1 / LobbyCamStand2 Camera3D
## nodes — position and rotate those in the editor to set the view.
func _position_lobby_camera(stand_index: int, tween: bool) -> void:
	var cam := _get_lobby_cam(stand_index)
	if cam == null:
		return
	var target_transform := cam.global_transform

	if tween:
		# Tween position directly, but rotate the LONG way around Y
		# so the camera pans in the opposite direction from the
		# default shortest-path slerp.
		var start_basis := lobby_camera.global_transform.basis
		var end_basis := target_transform.basis
		var start_euler := start_basis.get_euler()
		var end_euler := end_basis.get_euler()
		var start_yaw: float = start_euler.y
		var end_yaw: float = end_euler.y
		var diff: float = end_yaw - start_yaw
		# Normalize to [-PI, PI] (shortest path)
		while diff > PI:
			diff -= TAU
		while diff < -PI:
			diff += TAU
		# Flip to go the long way around
		if diff > 0.0:
			diff -= TAU
		elif diff < 0.0:
			diff += TAU
		var start_pitch: float = start_euler.x
		var end_pitch: float = end_euler.x
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(lobby_camera, "global_position", target_transform.origin, CAMERA_TWEEN_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw \
				.tween_method(
			func(t: float) -> void:
				var yaw: float = start_yaw + diff * t
				var pitch: float = lerpf(start_pitch, end_pitch, t)
				lobby_camera.global_rotation = Vector3(pitch, yaw, 0.0),
			0.0,
			1.0,
			CAMERA_TWEEN_TIME,
		) \
				.set_trans(Tween.TRANS_SINE) \
				.set_ease(Tween.EASE_IN_OUT)
	else:
		lobby_camera.global_transform = target_transform


## Called when the local player switches stands in the lobby UI.
func _on_stand_switched(stand_index: int) -> void:
	_position_lobby_camera(stand_index, true)


## Called when the host starts the game (LobbyManager.game_starting signal).
## Fades to black from the lobby, snaps the camera to the player's
## first-person position, then fades back in with a "Day X" overlay —
## like the player opening their eyes to start the day.
func _on_game_starting() -> void:
	if not _in_lobby:
		return
	_in_lobby = false
	_game_state = MenuState.PLAYING

	# Determine which stand this player is on
	var my_id := multiplayer.get_unique_id()
	var stand: StandUnit = _stand_for_peer(my_id)
	if stand == null:
		stand = stand_unit if stand_unit else stand_unit2
	if stand == null:
		_start_game_phase()
		return

	# Create the fade overlay immediately so it's on top of the lobby.
	var fade_rect := ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.anchors_preset = Control.PRESET_FULL_RECT
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.add_child(fade_rect)
	_transition_overlay.visible = true

	# Create the "Day X" label, hidden initially.
	var day_label := Label.new()
	var day_num := DayManager.day_number
	day_label.text = "Day %d" % day_num
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	day_label.anchors_preset = Control.PRESET_FULL_RECT
	day_label.modulate = Color(1, 1, 1, 0)
	day_label.add_theme_font_size_override("font_size", 48)
	day_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.add_child(day_label)

	# Phase 1: Fade to black (0.4s) — lobby is still visible underneath.
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, 0.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Phase 2: Behind the black screen — hide lobby, spawn player, snap camera.
	tw.tween_callback(
		func():
			# Hide lobby UI and player models.
			if lobby_ui:
				lobby_ui.modulate = Color(1, 1, 1, 0)
				lobby_ui.visible = false
			if lobby_player_models:
				lobby_player_models.visible = false
			# Spawn the player (deferred on host, so camera snap is also deferred).
			Player.defer_camera_claim = true
			_start_game_phase()
			call_deferred("_snap_to_player_camera", fade_rect, day_label),
	)


## Snap the camera to the player's first-person position, then fade in
## from black with a "Day X" overlay. Called after the player has spawned.
func _snap_to_player_camera(fade_rect: ColorRect, day_label: Label) -> void:
	if _local_player and _local_player.has_node("Head/Camera3D"):
		var player_cam := _local_player.get_node("Head/Camera3D") as Camera3D
		lobby_camera.current = false
		player_cam.make_current()
		Player.defer_camera_claim = false
	if hud:
		hud.visible = true
	# Start the day cycle (sun transitions smoothly).
	DayManager.start_morning()
	DayManager.start_day()
	# Phase 3: Fade in "Day X" label (0.3s), hold (1.0s), fade out (0.3s).
	# Phase 4: Fade in from black (0.5s) — like opening eyes.
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(fade_rect, "color:a", 0.0, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if day_label:
		tw.tween_property(day_label, "modulate:a", 1.0, 0.3) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.chain().tween_interval(1.0)
		tw.tween_property(day_label, "modulate:a", 0.0, 0.3) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Cleanup.
	tw.tween_callback(
		func():
			fade_rect.queue_free()
			if day_label:
				day_label.queue_free()
			_transition_overlay.visible = false,
	)


## Called on the host when a late joiner hits ready. Spawns the player and
## tells the client to transition from lobby to the game.
func _on_late_join_starting(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[Main] Late join starting for peer %d" % peer_id)
	_spawn_player_for_peer(peer_id)
	# Send manual spawn RPCs for ALL existing players to the late joiner
	# so they can see the host and any other players already in the game.
	# The MultiplayerSpawner may not replicate spawns that happened before
	# the client connected.
	for existing in players_node.get_children():
		var ep := existing as Player
		if ep == null or not is_instance_valid(ep):
			continue
		_spawn_player_on_client.rpc_id(
			peer_id,
			PLAYER_SCENE_PATH,
			ep.name,
			ep.global_position,
			ep.global_rotation,
		)
	# Defer the world state push so the client doesn't process everything
	# in a single frame (which causes the 1fps freeze).
	call_deferred("_push_world_state_to_client", peer_id)
	_start_late_join.rpc_id(peer_id, peer_id)


## Manually spawn a player on a late-joining client. This is a fallback
## for when the MultiplayerSpawner fails to replicate the spawn (which
## happens on repeated join/leave cycles). The client creates the player
## node directly and claims authority if it's their own.
@rpc("authority", "reliable")
func _spawn_player_on_client(
	scene_path: String,
	player_name: String,
	spawn_pos: Vector3,
	spawn_rot: Vector3,
) -> void:
	GameLog.log(
		"[Main] _spawn_player_on_client received: %s pos=%s" % [player_name, str(spawn_pos)]
	)
	var p: Player = null
	# If the spawner already created it, use the existing node but still
	# apply the correct position (the spawner may have placed it at 0,0,0).
	if players_node.has_node(player_name):
		p = players_node.get_node(player_name) as Player
		GameLog.log("[Main] Player %s already exists, updating pos" % player_name)
	else:
		var scene := load(scene_path) as PackedScene
		if scene == null:
			GameLog.log("[Main] Failed to load player scene: %s" % scene_path)
			return
		p = scene.instantiate() as Player
		p.name = player_name
		players_node.add_child(p)
		GameLog.log(
			"[Main] Manually spawned player %s, authority=%d my_id=%d"
			% [p.name, p.get_multiplayer_authority(), multiplayer.get_unique_id()]
		)
	# Always apply the host-provided position.
	p.global_position = spawn_pos
	p.global_rotation = spawn_rot
	# If this is our own player, claim authority and configure as local.
	var name_peer: int = int(player_name) if player_name.is_valid_int() else 0
	var is_local := name_peer == multiplayer.get_unique_id()
	if is_local and not p.is_multiplayer_authority():
		p.set_multiplayer_authority(name_peer)
		var sync := p.get_node_or_null("PositionSync") as MultiplayerSynchronizer
		if sync:
			sync.set_multiplayer_authority(name_peer)
		p._configure_local_player()
		p.visuals.visible = false
	# Set assigned stand from roster.
	if is_local:
		var stand := _stand_for_peer(multiplayer.get_unique_id())
		if stand:
			p.assigned_stand = stand
			_assigned_stands[multiplayer.get_unique_id()] = stand
		_on_local_player_ready(p)
	else:
		# Remote player — just cache it for WorldSync lookups.
		WorldSync._node_cache[p.name] = p


## Tells a specific peer to transition from the late-join lobby into the game.
@rpc("authority", "call_local", "reliable")
func _start_late_join(peer_id: int) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	print("[Main] Starting late join transition for peer %d" % peer_id)
	_late_join_camera_pending = true
	_do_late_join_transition()


## Transitions the local player from the late-join lobby into the running game.
func _do_late_join_transition() -> void:
	_in_lobby = false
	_game_state = MenuState.PLAYING
	# Hide the lobby UI and player models, show the HUD.
	if lobby_ui:
		lobby_ui.visible = false
	if lobby_player_models:
		lobby_player_models.visible = false
	if hud:
		hud.visible = true
	# Prevent the player's camera from claiming "current" immediately so
	# the lobby camera can tween into first-person smoothly.
	Player.defer_camera_claim = true
	# The local player will be spawned by the spawner; _on_local_player_ready
	# will finish the camera tween when it's ready.


## Shows a popup and returns to the main menu if a late join is denied.
func _on_late_join_denied(reason: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.name = "LateJoinDeniedDialog"
	dialog.title = "Can't Join"
	dialog.dialog_text = reason
	dialog.ok_button_text = "Back to Menu"
	dialog.confirmed.connect(_go_to_main_menu)
	dialog.canceled.connect(_go_to_main_menu)
	add_child(dialog)
	dialog.popup_centered()


## Sets up world systems (stand signs, spawners, delivery, day cycle,
## containers, etc.) during the main menu stand transition so they're
## ready before the player enters the lobby. Called from _finish_transition().
func _setup_world_systems() -> void:
	if _world_setup_done:
		return
	_world_setup_done = true
	# Update stand signs with the loaded stand name.
	if stand_unit:
		stand_unit.set_stand_name(GameState.stand_name)
	if stand_unit2:
		stand_unit2.set_stand_name(GameState.stand_name)
	# Queue markers / spawner wiring.
	if stand_unit:
		spawner.set_queue_spots(stand_unit.get_queue_spots(), stand_unit.get_queue_step())
		spawner.set_stand(stand_unit)
	if stand_unit2:
		spawner2.set_queue_spots(stand_unit2.get_queue_spots(), stand_unit2.get_queue_step())
		spawner2.set_stand(stand_unit2)
	ped_spawner.register_stand(spawner, stand_unit)
	if stand_unit2:
		ped_spawner.register_stand(spawner2, stand_unit2)
	# Wire delivery grid.
	if stand_unit:
		delivery.set_stand_name(stand_unit.name)
		var dgrid := stand_unit.get_delivery_grid()
		if dgrid == null:
			delivery.set_delivery_zone(stand_unit.get_delivery_marker_position())
		else:
			delivery.set_grid(dgrid)
	if stand_unit2:
		delivery2.set_truck_name("DeliveryTruck2")
		delivery2.set_stand_name(stand_unit2.name)
		var dgrid2 := stand_unit2.get_delivery_grid()
		if dgrid2 == null:
			delivery2.set_delivery_zone(stand_unit2.get_delivery_marker_position())
		else:
			delivery2.set_grid(dgrid2)
	# Cash pickup position.
	var cash_template: Node3D = world.find_child("CashPickup", true, false) as Node3D
	if cash_template:
		_cash_drop_pos = cash_template.global_position
		cash_template.visible = false
		var phys: Area3D = cash_template.get_node_or_null("Physics") as Area3D
		if phys:
			phys.collision_layer = 0
	# Event wiring.
	if not EventBus.cash_dropped.is_connected(_on_cash_dropped):
		EventBus.cash_dropped.connect(_on_cash_dropped)
	if not EventBus.day_timer_updated.is_connected(_on_day_timer_updated):
		EventBus.day_timer_updated.connect(_on_day_timer_updated)
	if not EventBus.debug_set_rain.is_connected(_on_debug_set_rain):
		EventBus.debug_set_rain.connect(_on_debug_set_rain)
	# Containers + evening summary (no day cycle yet — that starts
	# when the camera tween runs from lobby to first-person).
	SaveManager.capture_default_containers()
	SaveManager.respawn_placed_containers()
	add_child(DAY_SUMMARY_SCENE.instantiate())


## Starts the multiplayer game phase: spawns players and sets up network
## sync. World systems are already set up from the stand transition.
func _start_game_phase() -> void:
	# If world systems weren't set up during the stand transition
	# (e.g. late join, direct testing), do it now.
	_setup_world_systems()
	# Sync stand name to all clients so they see the host's save name.
	if multiplayer.is_server():
		_sync_stand_name.rpc(GameState.stand_name)
	# Spawn players and set up network sync.
	_spawn_all_players()
	WorldSync.setup(world_objects, world_spawner)
	# Push initial stand state to clients (money, prices, etc.)
	if WorldSync.is_host():
		call_deferred("_push_initial_stand_state")
		call_deferred("_push_world_state_to_clients")


## --- Networking / per-peer player spawning ---
## By the time this scene loads, hosting/joining already happened back in
## the MainMenu/Lobby scenes (see main_menu.gd, lobby.gd, lobby_manager.gd)
## Sets up the multiplayer spawner so it's ready to receive spawn
## requests. Called during _ready() so the spawner is available
## before any client requests arrive. Actual player spawning happens
## in _start_game_phase() or on-demand when clients request it.
func _setup_networking() -> void:
	# Spawner config is set in the scene file (spawn_path + spawnable_scenes).
	# Set a spawn_function so spawn() works for custom-named player nodes.
	player_spawner.spawn_function = _spawn_player
	if not player_spawner.spawned.is_connected(_on_spawner_spawned):
		player_spawner.spawned.connect(_on_spawner_spawned)
	if not NetworkManager.peer_connected.is_connected(_on_peer_connected):
		NetworkManager.peer_connected.connect(_on_peer_connected)
	if not NetworkManager.peer_disconnected.is_connected(_on_peer_disconnected):
		NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	GameLog.log(
		"[Main] _setup_networking done, spawner=%s spawn_path=%s"
		% [player_spawner.name, player_spawner.spawn_path]
	)


## Spawns players for all connected peers. Called from _start_game_phase()
## when the host starts the game.
func _spawn_all_players() -> void:
	if multiplayer.is_server():
		# Defer spawning so the spawner is fully ready before we add nodes
		# to its spawn_path. Without this, the spawner may not detect
		# manually-added nodes and fail to replicate them to clients.
		call_deferred("_host_spawn_players")
	else:
		# We're a client; our connection to the host was already
		# established during the lobby phase, so we can request our
		# spawn immediately instead of waiting for it again.
		print("[Main] Client requesting spawn from host")
		_request_spawn.rpc_id(1)


## Spawn function for MultiplayerSpawner. Called by the spawner when
## spawn() is invoked. The data parameter is the peer ID (int).
func _spawn_player(data: Variant) -> Node:
	var peer_id: int = int(data)
	GameLog.log("[Main] _spawn_player called with data=%s peer_id=%d" % [str(data), peer_id])
	var scene := load(PLAYER_SCENE_PATH) as PackedScene
	var p: Player = scene.instantiate()
	p.name = str(peer_id)
	return p


func _host_spawn_players() -> void:
	if LobbyManager.roster.is_empty():
		# No lobby was actually used to get here (e.g. testing
		# main.tscn directly in the editor) — fall back to plain
		# solo behavior: just spawn ourselves on the primary stand.
		_spawn_player_for_peer(1)
	else:
		for peer_id in LobbyManager.roster.keys():
			# Skip players who haven't selected a stand — they don't spawn.
			var stand_idx: int = LobbyManager.roster[peer_id].get("stand_index", -1)
			if stand_idx < 0:
				GameLog.log("[Main] Skipping player %d (no stand selected)" % peer_id)
				continue
			_spawn_player_for_peer(peer_id)


func _push_initial_stand_state() -> void:
	# Push both stands' initial state to clients so they see correct
	# money, prices, etc. from the start (not just 0).
	if stand_unit:
		stand_unit._push_state()
	if stand_unit2:
		stand_unit2._push_state()


## Send all placed containers and supply boxes to clients so they see
## the same world as the host immediately on join (not just empty space
## until the host moves something).
func _push_world_state_to_clients() -> void:
	WorldSync.sync_world_state_to_clients()


## Same as above but only to a specific peer (for late joiners).
func _push_world_state_to_client(peer_id: int) -> void:
	WorldSync.sync_world_state_to_peer(peer_id)


func _on_spawner_spawned(node: Node) -> void:
	var p := node as Player
	if p == null:
		GameLog.log("[Main] Spawner spawned non-player node: %s" % node.name)
		return
	GameLog.log(
		"[Main] Spawner spawned player: %s, is_auth=%s, my_id=%d"
		% [p.name, p.is_multiplayer_authority(), multiplayer.get_unique_id()]
	)
	# Cache the player node in WorldSync so transform RPCs can find it
	# quickly without doing a full scene tree search every frame.
	WorldSync._node_cache[p.name] = p
	# Only set up local-player stuff for OUR own player (the one we have
	# authority over). Remote players are just visual representations.
	# For late joiners the authority may not be claimed yet, so force it
	# when the node name matches the local peer ID.
	if not p.is_multiplayer_authority():
		var name_peer: int = int(p.name) if p.name.is_valid_int() else 0
		if name_peer != multiplayer.get_unique_id():
			return
		# Claim authority for our own player and run the local-only setup
		# that was skipped in _ready because the authority wasn't set yet.
		p.set_multiplayer_authority(name_peer)
		var sync := p.get_node_or_null("PositionSync") as MultiplayerSynchronizer
		if sync:
			sync.set_multiplayer_authority(name_peer)
		p._configure_local_player()
		p.visuals.visible = false
	# assigned_stand isn't replicated (only position/rotation are), so
	# set it locally from the lobby roster.
	var peer_id := multiplayer.get_unique_id()
	var stand := _stand_for_peer(peer_id)
	if stand:
		p.assigned_stand = stand
	_assigned_stands[peer_id] = stand
	_on_local_player_ready(p)


## Handles a peer connecting AFTER we've already loaded into the
## gameworld. If the game hasn't started yet, the normal lobby flow will
## spawn them when the host starts. If it has started, they're a late
## joiner: their stand is auto-assigned and they spawn once they hit ready.
func _on_peer_connected(peer_id: int) -> void:
	# During the active lobby, late joiners are spawned from the ready-up flow.
	if multiplayer.is_server() and not _in_lobby and LobbyManager.game_started:
		# Don't spawn here; _on_late_join_starting handles it after they ready up.
		return
	# Normal post-lobby connection (e.g. a peer that reconnected while still
	# transitioning) — spawn immediately and push world state.
	if multiplayer.is_server() and not _in_lobby:
		_spawn_player_for_peer(peer_id)
		# Send the full world state to the newly joined client so they
		# see all containers/supply boxes that were placed before they joined.
		call_deferred("_push_world_state_to_client", peer_id)
		# Sync the host's stand name to the new client.
		_sync_stand_name.rpc_id(peer_id, GameState.stand_name)


## Called when a client disconnects. The host removes their player
## from the world so they don't linger as a frozen body.
func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	GameLog.log("[Main] Peer %d disconnected, removing player" % peer_id)
	var player_name := str(peer_id)
	if players_node.has_node(player_name):
		var p := players_node.get_node(player_name)
		p.queue_free()
	# Clean up any cached references
	WorldSync._node_cache.erase(player_name)
	_assigned_stands.erase(peer_id)


@rpc("any_peer", "call_local", "reliable")
func _request_spawn() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	print("[Main] Host received spawn request from peer %d" % sender_id)
	if sender_id != 0 and multiplayer.is_server():
		if _in_lobby:
			# Still in lobby — defer spawn until game starts.
			# _spawn_all_players() will handle it when the host
			# starts the game.
			print("[Main] Still in lobby, deferring spawn for peer %d" % sender_id)
		else:
			_spawn_player_for_peer(sender_id)


## Host -> client: sync the host's stand name so all players see the
## same name on the stand sign.
@rpc("authority", "call_local", "reliable")
func _sync_stand_name(name: String) -> void:
	GameState.stand_name = name
	if stand_unit:
		stand_unit.set_stand_name(name)
	if stand_unit2:
		stand_unit2.set_stand_name(name)


func _spawn_player_for_peer(peer_id: int) -> void:
	if players_node.has_node(str(peer_id)):
		GameLog.log("[Main] Spawn skipped — player %d already exists" % peer_id)
		return
	var stand := _stand_for_peer(peer_id)
	# Use the spawner's spawn() with the peer_id as data. The spawn_function
	# (_spawn_player) creates the node with the correct name.
	GameLog.log("[Main] Spawning player for peer %d via spawner.spawn()" % peer_id)
	var p: Player = player_spawner.spawn(peer_id) as Player
	if p == null:
		GameLog.log("[Main] Failed to spawn player for peer %d — spawn() returned null" % peer_id)
		return
	GameLog.log("[Main] Spawned player %s, now in tree=%s" % [p.name, p.is_inside_tree()])
	_assigned_stands[peer_id] = stand
	if stand:
		p.assigned_stand = stand
		# Spawn the player at the stand's start marker position + rotation.
		var spawn_marker := _get_stand_start_marker(stand)
		if spawn_marker != null:
			p.global_position = spawn_marker.global_position
			p.global_rotation = Vector3(0, spawn_marker.global_rotation.y, 0)
		else:
			p.global_position = stand.global_position + Vector3(0, 0, 2)
	GameLog.log(
		"[Main] Spawned player %d (stand=%s, is_me=%s)"
		% [peer_id, stand.name if stand else "null", peer_id == multiplayer.get_unique_id()]
	)
	if peer_id == multiplayer.get_unique_id():
		_on_local_player_ready(p)


## Returns the start marker for the given stand, or null if not found.
func _get_stand_start_marker(stand: StandUnit) -> Marker3D:
	if stand == stand_unit and stand1_start_position:
		return stand1_start_position
	if stand == stand_unit2 and stand2_start_position:
		return stand2_start_position
	return null


## Returns the world position of the lobby player visual for the given
## peer, or Vector3.ZERO if not found.
func _get_lobby_visual_position(peer_id: int) -> Vector3:
	if lobby_player_models == null:
		return Vector3.ZERO
	var stand_idx: int = LobbyManager.roster.get(peer_id, { }).get("stand_index", -1)
	if stand_idx < 0:
		return Vector3.ZERO
	var model_idx := stand_idx
	if model_idx >= lobby_player_models.get_child_count():
		return Vector3.ZERO
	var model := lobby_player_models.get_child(model_idx) as Node3D
	if model:
		return model.global_position
	return Vector3.ZERO


## Returns the Y rotation of the lobby player visual for the given peer.
func _get_lobby_visual_yaw(peer_id: int) -> float:
	if lobby_player_models == null:
		return 0.0
	var stand_idx: int = LobbyManager.roster.get(peer_id, { }).get("stand_index", -1)
	if stand_idx < 0:
		return 0.0
	var model_idx := stand_idx
	if model_idx >= lobby_player_models.get_child_count():
		return 0.0
	var model := lobby_player_models.get_child(model_idx) as Node3D
	if model:
		return model.global_rotation.y
	return 0.0


## Returns the stand this peer picked in the lobby (LobbyManager.roster),
## or falls back to "next unassigned stand in a fixed order" if no lobby
## data exists for them (solo/direct-testing fallback, or a peer who
## somehow reached the gameworld without picking a stand).
func _stand_for_peer(peer_id: int) -> StandUnit:
	var entry: Dictionary = LobbyManager.roster.get(peer_id, { })
	var stand_index: int = entry.get("stand_index", -1)
	var stands: Array[StandUnit] = [stand_unit, stand_unit2]
	if stand_index >= 0 and stand_index < stands.size() and stands[stand_index] != null:
		return stands[stand_index]
	for s in stands:
		if s == null:
			continue
		if not _assigned_stands.values().has(s):
			return s
	return null


func _on_local_player_ready(p: Player) -> void:
	if _local_player != null and is_instance_valid(_local_player):
		# Already set up — don't create a second outline system.
		GameLog.log("[Main] _on_local_player_ready already called, skipping")
		return
	_local_player = p
	# Spawn the screen-space outline overlay and hand it the local
	# player's camera so it can mirror the transform every frame.
	var outline_sys: Node = OUTLINE_SCENE.instantiate()
	add_child(outline_sys)
	outline_sys.setup(p.get_node("Head/Camera3D") as Camera3D)
	if hud and hud.has_method("set_stand") and p.assigned_stand:
		hud.set_stand(p.assigned_stand)
	# If this is a late joiner, the fade transition was waiting for the player to exist.
	if _late_join_camera_pending:
		_late_join_camera_pending = false
		# Create a quick fade for late joiners.
		var fade_rect := ColorRect.new()
		fade_rect.color = Color(0, 0, 0, 1)
		fade_rect.anchors_preset = Control.PRESET_FULL_RECT
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_transition_overlay.add_child(fade_rect)
		_transition_overlay.visible = true
		call_deferred("_snap_to_player_camera", fade_rect, null)


## Called when the server (host) disconnects. Shows a popup so the
## client knows what happened instead of getting stuck.
func _on_host_left() -> void:
	# Only show this for clients (not the host themselves)
	if multiplayer.is_server():
		return
	# Avoid showing multiple popups
	if has_node("HostLeftDialog"):
		return
	var dialog := AcceptDialog.new()
	dialog.name = "HostLeftDialog"
	dialog.title = "Host Left"
	dialog.dialog_text = "The host has left the game."
	dialog.ok_button_text = "Back to Menu"
	dialog.confirmed.connect(_go_to_main_menu)
	dialog.canceled.connect(_go_to_main_menu)
	add_child(dialog)
	dialog.popup_centered()


func _go_to_main_menu() -> void:
	LobbyManager.reset()
	SaveManager.clear_current_slot()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_cash_dropped(drop_pos: Vector3, payment: float, change_due: float) -> void:
	if not WorldSync.is_host():
		return
	# Use the passed drop_pos (e.g. NPC CashPoint) if valid, otherwise fallback to register.
	var base_pos := drop_pos if drop_pos.length_squared() > 0.001 else _cash_drop_pos
	# Slight random offset so bills don't stack exactly
	var pos := base_pos + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1))
	WorldSync.spawn_networked(
		"res://scenes/objects/cash_pickup.tscn",
		self,
		pos,
		Vector3.ZERO,
		{ "payment": payment, "change_due": change_due },
	)


func _on_day_timer_updated(time_left: float, total_time: float) -> void:
	if total_time <= 0.0:
		return
	var t := 1.0 - time_left / total_time
	var sun_brightness := clampf(sin(t * PI) * 0.5 + 0.5, 0.0, 1.0)
	if _world_env:
		var ambient_brightness := clampf(sin(t * PI) * 0.4 + 0.6, 0.6, 1.15)
		var exposure_brightness := clampf(sin(t * PI) * 0.95 + 0.12, 0.12, 1.15)
		_world_env.environment.ambient_light_color = (_default_ambient_color * ambient_brightness)
		_world_env.environment.tonemap_exposure = _default_exposure * exposure_brightness
		EventBus.exposure_changed.emit(_default_exposure * exposure_brightness)


func _on_debug_set_rain(enabled: bool) -> void:
	if _world_env:
		var ambient := Color(0.35, 0.35, 0.37, 1) if enabled else _default_ambient_color
		var exposure := 0.75 if enabled else _default_exposure
		_world_env.environment.ambient_light_color = ambient
		_world_env.environment.tonemap_exposure = exposure


## Subtle mouse parallax for the main menu camera.
## Offsets the camera position slightly based on mouse position
## relative to the screen center, smoothed for a living feel.
func _menu_cam_parallax(delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var mouse_pos := get_viewport().get_mouse_position()
	# Normalize to -1..1 range from screen center.
	var target := Vector2(
		(mouse_pos.x / viewport_size.x - 0.5),
		(mouse_pos.y / viewport_size.y - 0.5),
	)
	# Smooth toward target.
	_menu_cam_parallax_current = _menu_cam_parallax_current.lerp(
		target,
		clamp(delta * MENU_CAM_PARALLAX_SMOOTH, 0.0, 1.0),
	)
	# Apply offset to camera position (invert Y so up = up).
	var offset := Vector3(
		_menu_cam_parallax_current.x * MENU_CAM_PARALLAX_STRENGTH,
		-_menu_cam_parallax_current.y * MENU_CAM_PARALLAX_STRENGTH,
		0.0,
	)
	main_menu_camera.global_position = _menu_cam_base_pos + offset


func _process(_delta: float) -> void:
	if _fps_shown and _fps_label:
		_fps_timer += _delta
		if _fps_timer >= 0.25:
			_fps_timer = 0.0
			_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	# Mouse parallax on main menu camera — subtle, smoothed.
	if _game_state == MenuState.MAIN_MENU and main_menu_camera and not _transition_active:
		_menu_cam_parallax(_delta)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F2 and event.pressed:
		_enhanced_lighting = not _enhanced_lighting
		if _enhanced_lighting:
			_enable_enhanced_lighting()
		else:
			_disable_enhanced_lighting()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode == KEY_F and event.pressed and not event.is_echo():
		_fps_shown = not _fps_shown
		if _fps_label:
			_fps_label.visible = _fps_shown
		get_viewport().set_input_as_handled()


func _enable_enhanced_lighting() -> void:
	if _world_env and _world_env.environment:
		var env := _world_env.environment
		env.ssr_enabled = false
		env.ssil_enabled = false
		# High contrast: deep SSAO for dark corners and crevices
		env.ssao_enabled = true
		env.ssao_radius = 0.5
		env.ssao_intensity = 4.0
		env.ssao_power = 2.0
		# VoxelGI only (not SDFGI) — VoxelGI respects gi_mode=DISABLED so grass
		# ground plane won't contribute green bounced light.
		env.sdfgi_enabled = false
		# Filmic tonemapping for natural contrast
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_white = 5.0
		env.tonemap_exposure = 1.0
		env.glow_enabled = false
		# Very low ambient so shadows are actually dark
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_color = Color(0.18, 0.18, 0.20, 1)
		env.ambient_light_sky_contribution = 0.4
		# Shorter fog for atmosphere without flattening
		env.volumetric_fog_density = 0.002
		env.volumetric_fog_length = 64.0
	# Sun: sharper, stronger shadows for clear definition
	var sun := world.find_child("DirectionalLight", true, false) as DirectionalLight3D
	if sun:
		_orig_shadow_blur = sun.shadow_blur
		_orig_shadow_normal_bias = sun.shadow_normal_bias
		_orig_shadow_bias = sun.shadow_bias
		sun.shadow_enabled = true
		sun.shadow_blur = 1.2
		sun.shadow_normal_bias = 1.0
		sun.shadow_bias = 0.04
		sun.directional_shadow_split_1 = 0.1
		sun.directional_shadow_split_2 = 0.3
		sun.directional_shadow_split_3 = 0.6
		sun.directional_shadow_blend_splits = true
		sun.directional_shadow_fade_start = 0.9
		sun.directional_shadow_max_distance = 60.0
	# Kill the fill light — we want dark shadows, not flat fill
	var fill := world.find_child("FillLight", true, false) as DirectionalLight3D
	if fill:
		_orig_fill_energy = fill.light_energy
		fill.visible = false
	# No warm fill point light — let shadows be shadows
	# VoxelGI: small volume, only for dynamic objects near stand
	if _voxel_gi == null:
		_voxel_gi = VoxelGI.new()
		_voxel_gi.position = Vector3(2, 2, -2)
		_voxel_gi.size = Vector3(16, 6, 12)
		_voxel_gi.subdiv = VoxelGI.SUBDIV_256
		world.add_child(_voxel_gi)
	_voxel_gi.visible = true
	# Reflection probe: subtle, just for a hint of reflection on surfaces
	if _reflection_probe == null:
		_reflection_probe = ReflectionProbe.new()
		_reflection_probe.position = Vector3(2, 2.5, -2)
		_reflection_probe.size = Vector3(16, 6, 12)
		_reflection_probe.update_mode = ReflectionProbe.UPDATE_ONCE
		_reflection_probe.intensity = 0.5
		_reflection_probe.max_distance = 15.0
		_reflection_probe.interior = false
		world.add_child(_reflection_probe)
	_reflection_probe.visible = true
	# Disable GI contribution on grass surfaces to prevent green color bleeding
	_set_grass_gi(false)
	print("[Lighting] Enhanced mode ON — High contrast: deep shadows + VoxelGI")


func _disable_enhanced_lighting() -> void:
	if _world_env and _world_env.environment:
		var env := _world_env.environment
		env.ssr_enabled = _orig_ssr
		env.ssao_enabled = _orig_ssao
		env.ssil_enabled = _orig_ssil
		env.sdfgi_enabled = _orig_sdfgi
		env.sdfgi_energy = _orig_sdfgi_energy
		env.tonemap_mode = _orig_tonemap_mode as Environment.ToneMapper
		env.tonemap_white = _orig_tonemap_white
		env.tonemap_exposure = _orig_tonemap_exposure
		env.glow_enabled = _orig_glow
		env.ambient_light_source = _orig_ambient_source as Environment.AmbientSource
		env.ambient_light_color = _orig_ambient_color
		env.ambient_light_sky_contribution = _orig_ambient_sky
		env.volumetric_fog_density = 0.001
		env.volumetric_fog_length = 333.13
	var sun := world.find_child("DirectionalLight", true, false) as DirectionalLight3D
	if sun:
		sun.shadow_blur = _orig_shadow_blur
		sun.shadow_normal_bias = _orig_shadow_normal_bias
		sun.shadow_bias = _orig_shadow_bias
	var fill := world.find_child("FillLight", true, false) as DirectionalLight3D
	if fill:
		fill.visible = true
		fill.light_energy = _orig_fill_energy
	if _voxel_gi:
		_voxel_gi.visible = false
	if _reflection_probe:
		_reflection_probe.visible = false
	if _fill_light:
		_fill_light.visible = false
	# Re-enable GI on grass surfaces
	_set_grass_gi(true)
	print("[Lighting] Enhanced mode OFF — original settings restored")


func _set_grass_gi(enabled: bool) -> void:
	var mode := GeometryInstance3D.GI_MODE_DYNAMIC if enabled else GeometryInstance3D.GI_MODE_DISABLED
	for node in get_tree().get_nodes_in_group(&"grass_surface"):
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).gi_mode = mode


const BAKE_RADIUS := 70.0
const STAND_POSITIONS := [
	Vector3(2.0, 0.0, -2.0), # StandUnit
	Vector3(-8.1, 0.0, -24.0), # StandUnit2
]


func _mark_static_gi(node: Node) -> void:
	# Distance-based GI mode: meshes within BAKE_RADIUS of either stand
	# are STATIC (use baked lightmaps), meshes outside are DYNAMIC (lit
	# by VoxelGI at runtime). Street lights are always DISABLED.
	# This matches set_lightmap_gi.gd so the bake only processes nearby
	# geometry instead of the entire 2000+ node neighborhood.
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var parent := mi.get_parent()
		if parent is StaticBody3D or parent.get_meta("static_gi", false):
			var is_street_light := false
			var p: Node = mi
			while p:
				if p.name.begins_with("street light"):
					is_street_light = true
					break
				p = p.get_parent()
			if is_street_light:
				mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			else:
				var min_dist := INF
				for pos in STAND_POSITIONS:
					var d := mi.global_position.distance_to(pos)
					if d < min_dist:
						min_dist = d
				if min_dist <= BAKE_RADIUS:
					mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
				else:
					mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for child in node.get_children():
		_mark_static_gi(child)


func _set_material_roughness(node: Node, roughness: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in range(mi.get_surface_override_material_count()):
			var mat := mi.get_surface_override_material(i)
			if mat == null:
				mat = mi.mesh.surface_get_material(i) if mi.mesh else null
			if mat == null:
				continue
			if mat is StandardMaterial3D:
				var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.roughness = roughness
				mi.set_surface_override_material(i, dup)
	for child in node.get_children():
		_set_material_roughness(child, roughness)

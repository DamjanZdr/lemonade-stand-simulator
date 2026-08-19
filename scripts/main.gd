extends Node
## Main scene root. Wires everything together at startup.

const CASH_PICKUP_SCENE: PackedScene = preload("res://scenes/objects/cash_pickup.tscn")
const OUTLINE_SCENE: PackedScene = preload("res://scenes/ui/outline_overlay.tscn")
const DAY_SUMMARY_SCENE: PackedScene = preload("res://scenes/ui/day_summary.tscn")
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const DeliveryGrid := preload("res://scripts/systems/delivery_grid.gd")

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
@onready var stand_unit: StandUnit = world.get_node_or_null("StandUnit") as StandUnit
@onready var stand_unit2: StandUnit = world.get_node_or_null("StandUnit2") as StandUnit

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


func _ready() -> void:
	# QueueMarkerActive is the spot for the customer currently at the stand.
	# QueueMarker1 is the first waiting spot (second customer in line).
	# QueueMarker2 sets the direction and spacing for the rest of the waiting line.
	# Move/rotate these markers in the editor to reorient the whole queue.
	# Up to 299 waiting customer slots are generated automatically from that direction.
	# (Now sourced from StandUnit so multiple stands can each have their own queue.)
	if stand_unit:
		spawner.set_queue_spots(stand_unit.get_queue_spots(), stand_unit.get_queue_step())
		spawner.set_stand(stand_unit)
	if stand_unit2:
		spawner2.set_queue_spots(stand_unit2.get_queue_spots(), stand_unit2.get_queue_step())
		spawner2.set_stand(stand_unit2)

	# Use the sky material set up in the editor (ProceduralSkyMaterial).
	_world_env = world.get_node_or_null("WorldEnvironment") as WorldEnvironment
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

	# Pedestrian spawner reads its PedestrianPath children automatically.
	# No wiring needed here — add paths in the editor as children of PedestrianSpawner.
	# Registered with its StandUnit so pedestrians are routed here weighted
	# by this stand's actual popularity once other stands are also
	# registered (see register_stand()); with only one stand registered,
	# every pedestrian who wants to join ends up here regardless of weight.
	ped_spawner.register_stand(spawner, stand_unit)
	if stand_unit2:
		ped_spawner.register_stand(spawner2, stand_unit2)

	# Wire delivery grid (now sourced from StandUnit)
	if stand_unit:
		var dgrid := stand_unit.get_delivery_grid()
		if dgrid == null:
			delivery.set_delivery_zone(stand_unit.get_delivery_marker_position())
		else:
			delivery.set_grid(dgrid)
	if stand_unit2:
		delivery2.set_truck_name("DeliveryTruck2")
		var dgrid2 := stand_unit2.get_delivery_grid()
		if dgrid2 == null:
			delivery2.set_delivery_zone(stand_unit2.get_delivery_marker_position())
		else:
			delivery2.set_grid(dgrid2)

	# Find the CashPickup placed in the stand scene — use its position, then hide it
	var cash_template: Node3D = world.find_child("CashPickup", true, false) as Node3D
	if cash_template:
		_cash_drop_pos = cash_template.global_position
		cash_template.visible = false
		var phys: StaticBody3D = cash_template.get_node_or_null("Physics") as StaticBody3D
		if phys:
			phys.collision_layer = 0

	# Pitcher is placed in world.tscn — its _ready() captures its own position.
	EventBus.cash_dropped.connect(_on_cash_dropped)
	EventBus.day_timer_updated.connect(_on_day_timer_updated)
	EventBus.debug_set_rain.connect(_on_debug_set_rain)

	# Players are now spawned dynamically per connected peer (host + anyone
	# who joins) instead of being a static scene node. The screen-space
	# outline overlay, HUD stand assignment, etc. that depend on "the"
	# local player now happen in _on_local_player_ready() once our own
	# player actually exists, instead of here.
	_setup_networking()
	WorldSync.setup(world_objects, world_spawner)

	# Add the evening summary overlay
	add_child(DAY_SUMMARY_SCENE.instantiate())

	# Start the day cycle — morning setup then immediately begin the day
	DayManager.start_morning()
	DayManager.start_day()
	SaveManager.capture_default_containers()
	SaveManager.respawn_placed_containers()
	# Push initial stand state to clients (money, prices, etc.)
	if WorldSync.is_host():
		call_deferred("_push_initial_stand_state")
	# Mark static meshes for LightmapGI baking
	_mark_static_gi(world)
	# Enhanced lighting is on by default; F2 toggles it off
	_enable_enhanced_lighting()


## --- Networking / per-peer player spawning ---
## By the time this scene loads, hosting/joining already happened back in
## the MainMenu/Lobby scenes (see main_menu.gd, lobby.gd, lobby_manager.gd)
## — connections are already established and every connected peer already
## picked a stand in the lobby (tracked in LobbyManager.roster, which
## survives the scene change since it's an autoload). So we don't need to
## wait for lobby_created/peer_connected here; we just spawn a player for
## everyone already known.
func _setup_networking() -> void:
	# Spawner config is set in the scene file (spawn_path + spawnable_scenes).
	# Set a spawn_function so spawn() works for custom-named player nodes.
	player_spawner.spawn_function = _spawn_player
	player_spawner.spawned.connect(_on_spawner_spawned)

	if multiplayer.is_server():
		# Defer spawning so the spawner is fully ready before we add nodes
		# to its spawn_path. Without this, the spawner may not detect
		# manually-added nodes and fail to replicate them to clients.
		call_deferred("_host_spawn_players")
		NetworkManager.peer_connected.connect(_on_peer_connected)
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
			_spawn_player_for_peer(peer_id)


func _push_initial_stand_state() -> void:
	# Push both stands' initial state to clients so they see correct
	# money, prices, etc. from the start (not just 0).
	if stand_unit:
		stand_unit._push_state()
	if stand_unit2:
		stand_unit2._push_state()


func _on_spawner_spawned(node: Node) -> void:
	var p := node as Player
	if p == null:
		print("[Main] Spawner spawned non-player node: %s" % node.name)
		return
	print(
		"[Main] Spawner spawned player: %s, is_auth=%s, my_id=%d"
		% [p.name, p.is_multiplayer_authority(), multiplayer.get_unique_id()]
	)
	# Only set up local-player stuff for OUR own player (the one we have
	# authority over). Remote players are just visual representations.
	if not p.is_multiplayer_authority():
		return
	# assigned_stand isn't replicated (only position/rotation are), so
	# set it locally from the lobby roster.
	var peer_id := multiplayer.get_unique_id()
	var stand := _stand_for_peer(peer_id)
	if stand:
		p.assigned_stand = stand
	_assigned_stands[peer_id] = stand
	_on_local_player_ready(p)


## Handles a peer connecting AFTER we've already loaded into the
## gameworld (shouldn't normally happen with the lobby-gates-entry flow,
## but guards against edge cases like a very late straggling connection).
func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_spawn_player_for_peer(peer_id)


@rpc("any_peer", "call_local", "reliable")
func _request_spawn() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	print("[Main] Host received spawn request from peer %d" % sender_id)
	if sender_id != 0 and multiplayer.is_server():
		_spawn_player_for_peer(sender_id)


func _spawn_player_for_peer(peer_id: int) -> void:
	if players_node.has_node(str(peer_id)):
		print("[Main] Spawn skipped — player %d already exists" % peer_id)
		return
	var stand := _stand_for_peer(peer_id)
	# Use the spawner's spawn() with the peer_id as data. The spawn_function
	# (_spawn_player) creates the node with the correct name.
	var p: Player = player_spawner.spawn(peer_id) as Player
	if p == null:
		push_warning("[Main] Failed to spawn player for peer %d" % peer_id)
		return
	_assigned_stands[peer_id] = stand
	if stand:
		p.assigned_stand = stand
		p.global_position = stand.global_position + Vector3(0, 0, 2)
	print(
		"[Main] Spawned player %d (stand=%s, is_me=%s)"
		% [peer_id, stand.name if stand else "null", peer_id == multiplayer.get_unique_id()]
	)
	if peer_id == multiplayer.get_unique_id():
		_on_local_player_ready(p)


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
	# Spawn the screen-space outline overlay and hand it the local
	# player's camera so it can mirror the transform every frame.
	var outline_sys: Node = OUTLINE_SCENE.instantiate()
	add_child(outline_sys)
	outline_sys.setup(p.get_node("Head/Camera3D") as Camera3D)
	if hud and hud.has_method("set_stand") and p.assigned_stand:
		hud.set_stand(p.assigned_stand)


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


func _process(_delta: float) -> void:
	pass


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F2 and event.pressed:
		_enhanced_lighting = not _enhanced_lighting
		if _enhanced_lighting:
			_enable_enhanced_lighting()
		else:
			_disable_enhanced_lighting()
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
	var sun := world.get_node_or_null("DirectionalLight") as DirectionalLight3D
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
	var fill := world.get_node_or_null("FillLight") as DirectionalLight3D
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
	var sun := world.get_node_or_null("DirectionalLight") as DirectionalLight3D
	if sun:
		sun.shadow_blur = _orig_shadow_blur
		sun.shadow_normal_bias = _orig_shadow_normal_bias
		sun.shadow_bias = _orig_shadow_bias
	var fill := world.get_node_or_null("FillLight") as DirectionalLight3D
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


func _mark_static_gi(node: Node) -> void:
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
				mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
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

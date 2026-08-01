extends Node
## Main scene root. Wires everything together at startup.

const CASH_PICKUP_SCENE: PackedScene = preload("res://scenes/objects/cash_pickup.tscn")
const OUTLINE_SCENE: PackedScene = preload("res://scenes/ui/outline_overlay.tscn")
const DAY_SUMMARY_SCENE: PackedScene = preload("res://scenes/ui/day_summary.tscn")
const DeliveryGrid := preload("res://scripts/systems/delivery_grid.gd")

@onready var world: Node3D = $World
@onready var player: CharacterBody3D = $Player
@onready var spawner: Node = $CustomerSpawner
@onready var ped_spawner: Node = $PedestrianSpawner
@onready var delivery: Node = $DeliverySystem

var _cash_drop_pos: Vector3 = Vector3(0, 1.05, -0.4)

var _world_env: WorldEnvironment
var _default_ambient_color: Color
var _default_exposure: float

var _enhanced_lighting: bool = false
var _voxel_gi: VoxelGI = null
var _reflection_probe: ReflectionProbe = null
var _fill_light: OmniLight3D = null
var _orig_ssr: bool = false
var _orig_ssao: bool = false
var _orig_ssil: bool = false
var _orig_sdfgi: bool = false
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
	var m_active: Marker3D = world.get_node_or_null("QueueMarkerActive") as Marker3D
	var m1: Marker3D = world.get_node_or_null("QueueMarker1") as Marker3D
	var m2: Marker3D = world.get_node_or_null("QueueMarker2") as Marker3D
	var active_pos := Vector3(0.0, 0.0, -1.0)
	var start := Vector3(0.0, 0.0, -2.0)
	var step := Vector3(0.0, 0.0, -1.0)
	if m_active:
		active_pos = m_active.global_position
	if m1:
		start = m1.global_position
		if m2:
			step = m2.global_position - m1.global_position
	var spots: Array[Vector3] = []
	spots.append(active_pos)
	for i in range(299):
		spots.append(start + step * float(i))
	spawner.set_queue_spots(spots, step)

	# Use the sky material set up in the editor (ProceduralSkyMaterial).
	_world_env = world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _world_env and _world_env.environment:
		_orig_ssr = _world_env.environment.ssr_enabled
		_orig_ssao = _world_env.environment.ssao_enabled
		_orig_ssil = _world_env.environment.ssil_enabled
		_orig_sdfgi = _world_env.environment.sdfgi_enabled
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
	ped_spawner.setup(spawner)

	# Wire delivery grid
	var dgrid := world.get_node_or_null("DeliveryGrid") as DeliveryGrid
	if dgrid == null:
		var dmarker := world.get_node_or_null("DeliveryMarker") as Marker3D
		if dmarker:
			delivery.set_delivery_zone(dmarker.global_position)
	else:
		delivery.set_grid(dgrid)

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

	# Spawn the screen-space outline overlay and hand it the main camera so it
	# can mirror the transform every frame.
	var outline_sys: Node = OUTLINE_SCENE.instantiate()
	add_child(outline_sys)
	outline_sys.setup(player.get_node("Head/Camera3D") as Camera3D)

	# Add the evening summary overlay
	add_child(DAY_SUMMARY_SCENE.instantiate())

	# Start the day cycle — morning setup then immediately begin the day
	DayManager.start_morning()
	DayManager.start_day()
	SaveManager.capture_default_containers()
	SaveManager.respawn_placed_containers()
	# Mark static meshes for LightmapGI baking
	_mark_static_gi(world)


func _on_cash_dropped(drop_pos: Vector3, payment: float, change_due: float) -> void:
	var pickup: CashPickup = CASH_PICKUP_SCENE.instantiate()
	pickup.payment = payment
	pickup.change_due = change_due
	# Use the passed drop_pos (e.g. NPC CashPoint) if valid, otherwise fallback to register.
	var base_pos := drop_pos if drop_pos.length_squared() > 0.001 else _cash_drop_pos
	# Slight random offset so bills don't stack exactly
	pickup.position = base_pos + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1))
	add_child(pickup)


func _on_day_timer_updated(time_left: float, total_time: float) -> void:
	if total_time <= 0.0:
		return
	var t := 1.0 - time_left / total_time
	if _world_env:
		# Ambient keeps a much higher floor (0.6 instead of 0.35) so shadowed
		# building faces at dawn/dusk still show detail instead of going
		# near-black. Exposure uses its own gentler curve — multiplying it by
		# the same steep ambient curve compounded the darkening and crushed
		# shadow detail even further.
		var ambient_brightness := clampf(sin(t * PI) * 0.4 + 0.6, 0.6, 1.15)
		var exposure_brightness := clampf(sin(t * PI) * 0.15 + 0.85, 0.85, 1.15)
		_world_env.environment.ambient_light_color = (_default_ambient_color * ambient_brightness)
		_world_env.environment.tonemap_exposure = _default_exposure * exposure_brightness


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
		# SDFGI for subtle bounced light, not flat fill
		env.sdfgi_enabled = true
		env.sdfgi_probe_bias = 1.1
		# Filmic tonemapping for natural contrast
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_white = 5.0
		env.tonemap_exposure = 1.0
		env.glow_enabled = false
		# Very low ambient so shadows are actually dark
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_color = Color(0.12, 0.12, 0.14, 1)
		env.ambient_light_sky_contribution = 0.3
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
		_voxel_gi.position = Vector3(2, 1.5, -2)
		_voxel_gi.size = Vector3(8, 4, 6)
		_voxel_gi.subdiv = VoxelGI.SUBDIV_256
		world.add_child(_voxel_gi)
	_voxel_gi.visible = true
	# Reflection probe: subtle, just for a hint of reflection on surfaces
	if _reflection_probe == null:
		_reflection_probe = ReflectionProbe.new()
		_reflection_probe.position = Vector3(2, 2.5, -2)
		_reflection_probe.size = Vector3(8, 5, 6)
		_reflection_probe.update_mode = ReflectionProbe.UPDATE_ONCE
		_reflection_probe.intensity = 0.5
		_reflection_probe.max_distance = 15.0
		_reflection_probe.interior = false
		world.add_child(_reflection_probe)
	_reflection_probe.visible = true
	# Disable GI contribution on grass surfaces to prevent green color bleeding
	_set_grass_gi(false)
	print("[Lighting] Enhanced mode ON — High contrast: deep shadows + SDFGI")


func _disable_enhanced_lighting() -> void:
	if _world_env and _world_env.environment:
		var env := _world_env.environment
		env.ssr_enabled = _orig_ssr
		env.ssao_enabled = _orig_ssao
		env.ssil_enabled = _orig_ssil
		env.sdfgi_enabled = _orig_sdfgi
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

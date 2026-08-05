@tool
extends Node3D
## Randomizes pickup truck body colors without touching wheels or windows.

const PALETTE: Array[Color] = [
	Color(0.75, 0.05, 0.05), # red
	Color(0.95, 0.95, 0.95), # white
	Color(0.08, 0.08, 0.08), # black
	Color(0.15, 0.25, 0.65), # blue
	Color(0.6, 0.6, 0.6), # silver
	Color(0.2, 0.45, 0.2), # green
	Color(0.85, 0.6, 0.15), # tan/orange
]
const RED_THRESHOLD := 0.35
const EXCLUDED: Array[StringName] = [&"pickup truck12"]
const SKIP_RECOLOR_HOUSES: Array[StringName] = [&"player_house"]

const _FALLBACK_ROOF_DEFAULT: Color = Color(0.15, 0.15, 0.17)
const _FALLBACK_WALL_DEFAULT: Color = Color.TRANSPARENT

const HOUSE_LOD_SCENE: PackedScene = preload("res://blender/house lod.glb")
const HOUSE_LOD_DISTANCE: float = 200.0
const HOUSE_LOD_OVERLAP: float = 2.0

const _DEFAULT_ROOF_COLORS: Array[Color] = [
	Color(0.5, 0.25, 0.2),
	Color(0.42, 0.42, 0.45),
	Color(0.30, 0.50, 0.30),
	Color(0.15, 0.30, 0.55),
	Color(0.70, 0.70, 0.15),
]
const _DEFAULT_WALL_COLORS: Array[Color] = [
	Color(0.95, 0.85, 0.55),
	Color(0.85, 0.55, 0.45),
	Color(0.45, 0.65, 0.85),
	Color(0.55, 0.75, 0.45),
	Color(0.75, 0.55, 0.80),
]


func _enter_tree() -> void:
	add_to_group("neighborhood")


var _street_light_omnis: Array[OmniLight3D] = []
var _bulb_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	_apply_colors()
	_apply_grass_shader()
	_apply_grass_lod()
	_disable_street_light_gi()
	_setup_house_lod()
	if not Engine.is_editor_hint():
		EventBus.day_timer_updated.connect(_on_day_timer_updated)
		EventBus.debug_set_color_roofs.connect(
			func(enabled: bool):
				GameState.color_roofs = enabled
				_apply_house_colors(),
		)
		EventBus.debug_set_color_walls.connect(
			func(enabled: bool):
				GameState.color_walls = enabled
				_apply_house_colors(),
		)
		EventBus.debug_house_palette_changed.connect(_apply_house_colors)


func _disable_street_light_gi() -> void:
	# Find all street light instances recursively — covers both
	# manually placed lights and generated ones from neighborhood_generator.
	var street_lights := find_children("*street light*", "", true, true)
	for sl in street_lights:
		var omnis := sl.find_children("*", "OmniLight3D", true, false)
		if omnis.size() > 0:
			_street_light_omnis.append(omnis[0] as OmniLight3D)
		for child in sl.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			if mi.name == "Icosphere":
				var bulb_mat := StandardMaterial3D.new()
				bulb_mat.albedo_color = Color(0.9, 0.85, 0.6, 1)
				bulb_mat.metallic = 0.0
				bulb_mat.roughness = 0.3
				bulb_mat.emission_enabled = true
				bulb_mat.emission = Color(1.0, 0.9, 0.5, 1)
				bulb_mat.emission_energy_multiplier = 8.0
				bulb_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				mi.material_override = bulb_mat
				_bulb_materials.append(bulb_mat)


func _on_day_timer_updated(time_left: float, total_time: float) -> void:
	if total_time <= 0.0:
		return
	var t := clampf(1.0 - time_left / total_time, 0.0, 1.0)
	# Day maps 0→9am, 1→6pm. 11am≈0.222, 3pm≈0.667
	var light_on := 0.0
	if t <= 0.222:
		var dim := clampf((0.222 - t) / 0.03, 0.0, 1.0)
		light_on = dim
	elif t >= 0.667:
		var ramp := clampf((t - 0.667) / 0.03, 0.0, 1.0)
		light_on = ramp
	for omni in _street_light_omnis:
		omni.light_energy = 10.0 * light_on
		omni.omni_range = 20.0
	for mat in _bulb_materials:
		mat.emission_energy_multiplier = 8.0 * light_on


func _apply_grass_shader() -> void:
	if Engine.is_editor_hint():
		return
	var grass_root := get_node_or_null("Grass")
	if grass_root == null:
		return
	for child in grass_root.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		var mat := mmi.multimesh.mesh.surface_get_material(0) as ShaderMaterial
		if mat == null:
			continue
		# Make sure the existing grass shader sways, without replacing its shader.
		mat.set_shader_parameter("sway_strength", 0.1)
		mat.set_shader_parameter("wind_speed", 0.75)
		mat.set_shader_parameter("wind_frequency", 0.5)
		mat.set_shader_parameter("fade_start", 10.0)
		mat.set_shader_parameter("fade_end", 40.0)


func _process(_delta: float) -> void:
	pass


func _apply_grass_lod() -> void:
	if Engine.is_editor_hint():
		return
	var grass_root := get_node_or_null("Grass")
	if grass_root == null:
		return
	for child in grass_root.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mmi.visible = true
		mmi.visibility_range_end = 80.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _setup_house_lod() -> void:
	if Engine.is_editor_hint():
		return
	var houses_groups: Array[Node] = []
	var local_houses := get_node_or_null("Houses")
	if local_houses != null:
		houses_groups.append(local_houses)
	var np_houses := get_node_or_null("NonPlayableArea/Houses")
	if np_houses != null:
		houses_groups.append(np_houses)
	var nested_houses := get_node_or_null("Neighborhood/Houses")
	if nested_houses != null:
		houses_groups.append(nested_houses)
	var nested_np_houses := get_node_or_null("Neighborhood/NonPlayableArea/Houses")
	if nested_np_houses != null:
		houses_groups.append(nested_np_houses)

	for group in houses_groups:
		for child in group.get_children():
			if not child.name.to_lower().contains("house"):
				continue
			if child.name in SKIP_RECOLOR_HOUSES:
				continue
			if child.has_node("LOD"):
				continue
			# Collect original meshes before adding LOD child
			var original_meshes := _find_mesh_instances(child)
			# Instance LOD at the same position (child of the house, zero offset)
			var lod_instance := HOUSE_LOD_SCENE.instantiate()
			lod_instance.name = "LOD"
			child.add_child(lod_instance)
			# Original meshes: hide beyond LOD distance
			for mi in original_meshes:
				mi.visibility_range_end = HOUSE_LOD_DISTANCE
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			# LOD meshes: show slightly before LOD distance so there's no gap
			for mi in _find_mesh_instances(lod_instance):
				mi.visibility_range_begin = HOUSE_LOD_DISTANCE - HOUSE_LOD_OVERLAP
				mi.visibility_range_end = 0.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _apply_colors() -> void:
	_apply_vehicle_colors()
	_apply_house_colors()


func _apply_vehicle_colors() -> void:
	var vehicles := get_node_or_null("Neighborhood/NonPlayableArea/Vehicles")
	if vehicles == null:
		vehicles = get_node_or_null("NonPlayableArea/Vehicles")
	if vehicles == null:
		return
	var index := 0
	for child in vehicles.get_children():
		if child.name.begins_with("pickup truck"):
			if child.name in EXCLUDED:
				_reset_pickup(child)
				continue
			var color := PALETTE[index % PALETTE.size()]
			_recolor_pickup(child, color)
			index += 1


func _apply_house_colors() -> void:
	# In the editor we don't have GameState defaults, so match the in-game defaults.
	var color_roofs := GameState.color_roofs if not Engine.is_editor_hint() else true
	var color_walls := GameState.color_walls if not Engine.is_editor_hint() else false

	var houses_groups: Array[Node] = []
	var local_houses := get_node_or_null("Houses")
	if local_houses != null:
		houses_groups.append(local_houses)
	var np_houses := get_node_or_null("NonPlayableArea/Houses")
	if np_houses != null:
		houses_groups.append(np_houses)
	var nested_houses := get_node_or_null("Neighborhood/Houses")
	if nested_houses != null:
		houses_groups.append(nested_houses)
	var nested_np_houses := get_node_or_null("Neighborhood/NonPlayableArea/Houses")
	if nested_np_houses != null:
		houses_groups.append(nested_np_houses)

	for group in houses_groups:
		for child in group.get_children():
			if child.name.to_lower().contains("house"):
				var house_index: int = child.get_meta("house_color_index", -1)
				if house_index < 0:
					house_index = _house_name_index(child.name)
					child.set_meta("house_color_index", house_index)
				if child.name in SKIP_RECOLOR_HOUSES:
					continue
				var wall_index: int = child.get_meta("house_wall_index", house_index)
				var roof_color: Color
				if color_roofs:
					roof_color = _roof_color(house_index)
				else:
					roof_color = _roof_default_color()
				var wall_color: Color
				if color_walls:
					wall_color = _wall_color(wall_index)
				else:
					wall_color = _wall_default_color()
				_recolor_house(child, roof_color, wall_color)


func randomize_house_colors(target: String = "both") -> void:
	var cm := _get_color_manager()
	var roof_count: int = cm.roof_colors.size() if cm != null else _DEFAULT_ROOF_COLORS.size()
	var wall_count: int = cm.wall_colors.size() if cm != null else _DEFAULT_WALL_COLORS.size()
	var houses_groups: Array[Node] = []
	var local_houses := get_node_or_null("Houses")
	if local_houses != null:
		houses_groups.append(local_houses)
	var np_houses := get_node_or_null("NonPlayableArea/Houses")
	if np_houses != null:
		houses_groups.append(np_houses)
	var nested_houses := get_node_or_null("Neighborhood/Houses")
	if nested_houses != null:
		houses_groups.append(nested_houses)
	var nested_np_houses := get_node_or_null("Neighborhood/NonPlayableArea/Houses")
	if nested_np_houses != null:
		houses_groups.append(nested_np_houses)

	var prev_roof := -1
	var prev_wall := -1
	for group in houses_groups:
		for child in group.get_children():
			if child.name.to_lower().contains("house"):
				if target == "roofs" or target == "both":
					var roof_idx: int = randi() % roof_count
					while roof_count > 1 and roof_idx == prev_roof:
						roof_idx = randi() % roof_count
					prev_roof = roof_idx
					child.set_meta("house_color_index", roof_idx)
				if target == "walls" or target == "both":
					var wall_idx: int = randi() % wall_count
					while wall_count > 1 and wall_idx == prev_wall:
						wall_idx = randi() % wall_count
					prev_wall = wall_idx
					child.set_meta("house_wall_index", wall_idx)
	_apply_house_colors()


func default_house_colors(target: String = "both") -> void:
	var houses_groups: Array[Node] = []
	var local_houses := get_node_or_null("Houses")
	if local_houses != null:
		houses_groups.append(local_houses)
	var np_houses := get_node_or_null("NonPlayableArea/Houses")
	if np_houses != null:
		houses_groups.append(np_houses)
	var nested_houses := get_node_or_null("Neighborhood/Houses")
	if nested_houses != null:
		houses_groups.append(nested_houses)
	var nested_np_houses := get_node_or_null("Neighborhood/NonPlayableArea/Houses")
	if nested_np_houses != null:
		houses_groups.append(nested_np_houses)

	for group in houses_groups:
		for child in group.get_children():
			if child.name.to_lower().contains("house"):
				if target == "roofs" or target == "both":
					child.set_meta("house_color_index", _house_name_index(child.name))
				if target == "walls" or target == "both":
					child.remove_meta("house_wall_index")
	_apply_house_colors()


func _get_color_manager() -> Node:
	var tree := get_tree()
	if tree != null:
		return tree.get_first_node_in_group("color_manager")
	return null


func _house_name_index(house_name: String) -> int:
	var m := RegEx.create_from_string("house(\\d+)$").search(house_name)
	if m == null:
		return 0
	return (int(m.get_string(1)) - 1) % 5


func _roof_color(index: int) -> Color:
	var cm := _get_color_manager()
	var colors: Array[Color] = cm.roof_colors if cm != null else _DEFAULT_ROOF_COLORS
	return colors[index % colors.size()]


func _wall_color(index: int) -> Color:
	var cm := _get_color_manager()
	var colors: Array[Color] = cm.wall_colors if cm != null else _DEFAULT_WALL_COLORS
	return colors[index % colors.size()]


func _roof_default_color() -> Color:
	var cm := _get_color_manager()
	return cm.roof_default_color if cm != null else _FALLBACK_ROOF_DEFAULT


func _wall_default_color() -> Color:
	var cm := _get_color_manager()
	return cm.wall_default_color if cm != null else _FALLBACK_WALL_DEFAULT


func _recolor_pickup(root: Node, color: Color) -> void:
	for mesh_instance in _find_mesh_instances(root):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for i in range(mesh.get_surface_count()):
			var mat := mesh_instance.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			if _is_red(mat.albedo_color):
				var new_mat := mat.duplicate() as BaseMaterial3D
				new_mat.albedo_color = color
				mesh_instance.set_surface_override_material(i, new_mat)


func _recolor_house(root: Node, roof_color: Color, wall_color: Color) -> void:
	for mesh_instance in _find_mesh_instances(root):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for i in range(mesh.get_surface_count()):
			var mat := mesh_instance.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var surface_name := ""
			if mesh is ArrayMesh:
				surface_name = mesh.surface_get_name(i)
			if _is_roof_material(mat, surface_name):
				if roof_color == Color.TRANSPARENT:
					mesh_instance.set_surface_override_material(i, null)
				else:
					var new_mat := mat.duplicate() as BaseMaterial3D
					new_mat.albedo_color = roof_color
					mesh_instance.set_surface_override_material(i, new_mat)
			elif _is_wall_material(mat, surface_name):
				if wall_color == Color.TRANSPARENT:
					mesh_instance.set_surface_override_material(i, null)
				else:
					var new_mat := mat.duplicate() as BaseMaterial3D
					new_mat.albedo_color = wall_color
					mesh_instance.set_surface_override_material(i, new_mat)


func _reset_pickup(root: Node) -> void:
	for mesh_instance in _find_mesh_instances(root):
		for i in range(mesh_instance.mesh.get_surface_count()):
			mesh_instance.set_surface_override_material(i, null)


func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result


func _is_red(c: Color) -> bool:
	return c.r > RED_THRESHOLD and c.r > c.g * 1.3 and c.r > c.b * 1.3


func _is_roof_material(mat: BaseMaterial3D, surface_name: String = "") -> bool:
	var rn := mat.resource_name
	if rn == "Red" or rn == "Material.002":
		return true
	if surface_name.to_lower() == "roof":
		return true
	if rn == "" and _is_red(mat.albedo_color):
		return true
	return false


func _is_wall_material(mat: BaseMaterial3D, surface_name: String = "") -> bool:
	var rn := mat.resource_name.to_lower()
	if rn == "wall" or rn == "walls" or rn == "material.001":
		return true
	if surface_name.to_lower() == "wall" or surface_name.to_lower() == "walls":
		return true
	if surface_name == "Material.001":
		return true
	return false

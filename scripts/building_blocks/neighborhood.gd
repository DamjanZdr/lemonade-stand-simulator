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
const EXCLUDED_HOUSES: Array[StringName] = [&"player_house"]


func _ready() -> void:
	_apply_colors()
	_apply_grass_shader()


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
		mat.set_shader_parameter("fade_start", 20.0)
		mat.set_shader_parameter("fade_end", 50.0)


func _apply_colors() -> void:
	_apply_vehicle_colors()
	_apply_roof_colors()


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


func _apply_roof_colors() -> void:
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

	var base_color := Color(0.5, 0.25, 0.2)
	var base_found := false
	for group in houses_groups:
		for child in group.get_children():
			if child.name.to_lower().contains("house"):
				var c := _find_roof_base(child)
				if c != Color.TRANSPARENT:
					base_color = c
					base_found = true
					break
		if base_found:
			break

	var index := 0
	for group in houses_groups:
		for child in group.get_children():
			if child.name.to_lower().contains("house") and not child.name in EXCLUDED_HOUSES:
				var color := _roof_color(index, base_color)
				_recolor_roof(child, color)
				index += 1


func _find_roof_base(root: Node) -> Color:
	for mesh_instance in _find_mesh_instances(root):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for i in range(mesh.get_surface_count()):
			var mat := mesh_instance.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			if _is_red(mat.albedo_color) or mat.resource_name.find("Material.002") != -1:
				return mat.albedo_color
	return Color.TRANSPARENT


func _roof_color(index: int, base: Color) -> Color:
	match index % 5:
		0:
			return base
		1:
			return Color(0.42, 0.42, 0.45)
		2:
			return Color(0.30, 0.50, 0.30)
		3:
			return Color(0.15, 0.30, 0.55)
		4:
			return Color(0.70, 0.70, 0.15)
	return base


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


func _recolor_roof(root: Node, color: Color) -> void:
	for mesh_instance in _find_mesh_instances(root):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for i in range(mesh.get_surface_count()):
			var mat := mesh_instance.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			if _is_red(mat.albedo_color) or mat.resource_name.find("Material.002") != -1:
				var new_mat := mat.duplicate() as BaseMaterial3D
				new_mat.albedo_color = color
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

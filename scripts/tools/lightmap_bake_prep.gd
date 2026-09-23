class_name LightmapBakePrep
extends RefCounted

const BAKE_RADIUS := 70.0
const STAND_POSITIONS := [Vector3(2.0, 0.0, -2.0), Vector3(-8.1, 0.0, -24.0)]


static func prepare(root: Node, versus: bool) -> void:
	if root.name != "World" or root.find_child("LightmapGI", true, false) == null:
		push_error("LightmapBakePrep: open scenes/world/world.tscn before running this script.")
		return
	var counts := { "static": 0, "dynamic": 0, "disabled": 0 }
	_set_radius_gi(root, counts)
	var neighborhood := root.find_child("Neighborhood", true, false)
	if neighborhood == null or not neighborhood.has_method("apply_runtime_house_colors_for_bake"):
		push_error("LightmapBakePrep: Neighborhood color preparation is unavailable.")
		return
	var temp_cm := _ensure_color_manager(root)
	if temp_cm == null and root.get_tree().get_first_node_in_group("color_manager") == null:
		push_error("LightmapBakePrep: could not provide a ColorManager for bake colors.")
		return
	neighborhood.apply_runtime_house_colors_for_bake()
	if temp_cm != null:
		temp_cm.queue_free()
	var material_overrides := _count_material_overrides(neighborhood)
	if material_overrides <= 0:
		push_error("LightmapBakePrep: runtime house materials were not applied.")
		return
	var single_house := root.find_child("single_stand_house2", true, false)
	var player_house2 := root.find_child("player_house2", true, false)
	if single_house == null or player_house2 == null:
		push_error(
			"LightmapBakePrep: missing houses (single=%s, player2=%s)"
			% [single_house, player_house2]
		)
		return
	_set_variant(single_house, not versus)
	_set_variant(player_house2, versus)
	var single_visible := (single_house as Node3D).visible
	var player_visible := (player_house2 as Node3D).visible
	if single_visible != not versus or player_visible != versus:
		push_error(
			"LightmapBakePrep: visibility failed (single=%s, player2=%s)"
			% [single_visible, player_visible]
		)
		return
	print(
		(
			"Lightmap bake prepared: %s, single_visible=%s, player2_visible=%s, "
			+ "radius=%.0f, material_overrides=%d, static=%d, dynamic=%d, disabled=%d"
		)
		% [
			"VERSUS" if versus else "CO-OP",
			single_visible,
			player_visible,
			BAKE_RADIUS,
			material_overrides,
			counts.static,
			counts.dynamic,
			counts.disabled,
		]
	)


static func _set_radius_gi(node: Node, counts: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if _is_street_light(mesh):
			mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			counts.disabled += 1
		else:
			var min_distance := INF
			for stand_position in STAND_POSITIONS:
				min_distance = minf(min_distance, mesh.global_position.distance_to(stand_position))
			if min_distance <= BAKE_RADIUS:
				mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
				counts.static += 1
			else:
				mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
				counts.dynamic += 1
	for child in node.get_children():
		_set_radius_gi(child, counts)


static func _ensure_color_manager(root: Node) -> Node:
	var tree := root.get_tree()
	if tree != null:
		var existing := tree.get_first_node_in_group("color_manager")
		if existing != null:
			return existing
	var main_ps := load("res://scenes/main.tscn") as PackedScene
	if main_ps == null:
		push_error("LightmapBakePrep: failed to load res://scenes/main.tscn")
		return null
	var main_inst := main_ps.instantiate()
	var source_cm := main_inst.get_node_or_null("Managers/ColorManager")
	if source_cm == null:
		source_cm = _find_node_by_script(main_inst, "res://scripts/managers/color_manager.gd")
	if source_cm == null:
		push_error("LightmapBakePrep: ColorManager not found in main.tscn")
		main_inst.queue_free()
		return null
	var script := load("res://scripts/managers/color_manager.gd") as Script
	if script == null:
		main_inst.queue_free()
		return null
	var cm := script.new()
	cm.name = "ColorManager"
	cm.roof_default_color = source_cm.roof_default_color
	cm.wall_default_color = source_cm.wall_default_color
	cm.roof_colors = source_cm.roof_colors
	cm.wall_colors = source_cm.wall_colors
	cm.add_to_group("color_manager")
	root.add_child(cm)
	cm.owner = root
	main_inst.queue_free()
	return cm


static func _find_node_by_script(root: Node, script_path: String) -> Node:
	for node in root.get_children():
		if node.get_script() != null and node.get_script().resource_path == script_path:
			return node
		var found := _find_node_by_script(node, script_path)
		if found != null:
			return found
	return null


static func _count_material_overrides(root: Node) -> int:
	var count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.get_surface_override_material_count()):
			if mesh.get_surface_override_material(surface) != null:
				count += 1
	return count


static func _set_variant(house: Node, active: bool) -> void:
	if house is Node3D:
		house.visible = active
	for mesh in house.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).gi_mode = (
			GeometryInstance3D.GI_MODE_STATIC
			if active
			else GeometryInstance3D.GI_MODE_DISABLED
		)


static func _is_street_light(node: Node) -> bool:
	var ancestor := node
	while ancestor != null:
		if ancestor.name.begins_with("street light"):
			return true
		ancestor = ancestor.get_parent()
	return false

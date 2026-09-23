class_name LightmapBakePrep
extends RefCounted

const BAKE_RADIUS := 70.0
const STAND_POSITIONS := [
	Vector3(2.0, 0.0, -2.0),
	Vector3(-8.1, 0.0, -24.0),
]


static func prepare(root: Node, versus: bool) -> void:
	var counts := { "static": 0, "dynamic": 0, "disabled": 0 }
	_set_radius_gi(root, counts)
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
	print(
		"Lightmap bake prepared: %s, radius=%.0f, static=%d, dynamic=%d, disabled=%d"
		% ["VERSUS" if versus else "CO-OP", BAKE_RADIUS, counts.static, counts.dynamic, counts.disabled]
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
				min_distance = minf(
					min_distance,
					mesh.global_position.distance_to(stand_position),
				)
			if min_distance <= BAKE_RADIUS:
				mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
				counts.static += 1
			else:
				mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
				counts.dynamic += 1
	for child in node.get_children():
		_set_radius_gi(child, counts)


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

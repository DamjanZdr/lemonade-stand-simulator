@tool
extends Node3D
## Procedural suburban neighborhood using Path3D / Curve3D for curved roads.
## Defines winding roads, a cul-de-sac, and places houses along curves
## sampled from Curve3D tangent directions.

# --- Config ---
@export var road_width: float = 8.0
@export var sidewalk_width: float = 2.0
@export var house_spacing: float = 18.0
@export var house_setback: float = 9.0
@export var light_spacing: float = 30.0
@export var tree_chance: float = 0.3
@export var neighborhood_radius: float = 90.0
@export var generate_on_ready: bool = true

# --- Resources ---
const _HOUSE_SCENES: Array[String] = [
	"res://blender/surroundings/Houses/1.glb",
	"res://blender/surroundings/Houses/2.glb",
	"res://blender/surroundings/Houses/3.glb",
	"res://blender/surroundings/Houses/4.glb",
	"res://blender/surroundings/Houses/5.glb",
	"res://blender/surroundings/Houses/6.glb",
	"res://blender/surroundings/Houses/7.glb",
	"res://blender/surroundings/Houses/8.glb",
]
const _HOUSE_COL_SCENES: Array[String] = [
	"res://blender/surroundings/Houses/Skewed/1 skewed - col.glb",
	"res://blender/surroundings/Houses/Skewed/2 skewed - col.glb",
	"res://blender/surroundings/Houses/Skewed/3 skewed - col.glb",
	"res://blender/surroundings/Houses/Skewed/4 skewed - col.glb",
	"res://blender/surroundings/Houses/Skewed/5 skewed - col.glb",
	"res://blender/surroundings/Houses/Skewed/6 skewed - col.glb",
	"res://blender/surroundings/Houses/Skewed/7 skewed - col.glb",
	"res://blender/surroundings/Houses/Skewed/8 skewed - col.glb",
]
const _TREE_SCENES: Array[String] = [
	"res://blender/surroundings/Trees/1.glb",
	"res://blender/surroundings/Trees/2.glb",
	"res://blender/surroundings/Trees/3.glb",
	"res://blender/surroundings/Trees/4.glb",
	"res://blender/surroundings/Trees/5.glb",
	"res://blender/surroundings/Trees/6.glb",
	"res://blender/surroundings/Trees/7.glb",
	"res://blender/surroundings/Trees/8.glb",
	"res://blender/surroundings/Trees/9.glb",
]
const _STREET_LIGHT_SCENE := "res://blender/surroundings/StreetLight/street light.glb"
const _ROAD_TEXTURE := "res://Visuals/Street/street_road base texture.png"
const _SIDEWALK_TEXTURE := "res://Visuals/Sidewalk/sidewalk_sidewalk base texture.png"

var _road_material: StandardMaterial3D
var _sidewalk_material: StandardMaterial3D
var _grass_material: StandardMaterial3D

var _house_packs: Array[PackedScene] = []
var _tree_packs: Array[PackedScene] = []
var _street_light_pack: PackedScene = null

# Track occupied house positions to avoid overlap
var _occupied_positions: Array[Vector3] = []


func _ready() -> void:
	if generate_on_ready:
		generate()


func _enter_tree() -> void:
	if Engine.is_editor_hint() and generate_on_ready:
		call_deferred("generate")


func _property_can_revert(property: StringName) -> bool:
	return property in [
		&"road_width",
		&"sidewalk_width",
		&"house_spacing",
		&"house_setback",
		&"light_spacing",
		&"tree_chance",
		&"neighborhood_radius",
		&"generate_on_ready",
	]


func _ensure_materials() -> void:
	if _road_material == null:
		_road_material = StandardMaterial3D.new()
		if ResourceLoader.exists(_ROAD_TEXTURE):
			_road_material.albedo_texture = load(_ROAD_TEXTURE)
			_road_material.uv1_scale = Vector3(1.0, 1.0, 1.0)
		else:
			_road_material.albedo_color = Color(0.18, 0.18, 0.18)
		_road_material.roughness = 0.9
		_road_material.metallic = 0.0
	if _sidewalk_material == null:
		_sidewalk_material = StandardMaterial3D.new()
		if ResourceLoader.exists(_SIDEWALK_TEXTURE):
			_sidewalk_material.albedo_texture = load(_SIDEWALK_TEXTURE)
		else:
			_sidewalk_material.albedo_color = Color(0.72, 0.70, 0.65)
		_sidewalk_material.roughness = 0.85
	if _grass_material == null:
		_grass_material = StandardMaterial3D.new()
		_grass_material.albedo_color = Color(0.35, 0.55, 0.22)


func _load_resources() -> void:
	if _house_packs.is_empty():
		for path in _HOUSE_SCENES:
			if ResourceLoader.exists(path):
				_house_packs.append(load(path))
	for path in _TREE_SCENES:
		if ResourceLoader.exists(path):
			_tree_packs.append(load(path))
	if _street_light_pack == null and ResourceLoader.exists(_STREET_LIGHT_SCENE):
		_street_light_pack = load(_STREET_LIGHT_SCENE)

# ============================================================
#  Public API
# ============================================================


func generate() -> void:
	_ensure_materials()
	_load_resources()
	_clear_children()
	_occupied_positions.clear()
	_build_ground()
	_build_suburb()


func _clear_children() -> void:
	for child in get_children():
		child.free()

# ============================================================
#  Ground
# ============================================================


func _build_ground() -> void:
	var r := neighborhood_radius
	var ground := CSGBox3D.new()
	ground.name = "Ground"
	ground.size = Vector3(r * 2.4, 0.4, r * 2.4)
	ground.position = Vector3(0, -0.2, 0)
	ground.use_collision = true
	ground.material = _grass_material
	add_child(ground)

# ============================================================
#  Suburban layout — curved roads, cul-de-sac, houses
# ============================================================


func _build_suburb() -> void:
	var paths_node := Node3D.new()
	paths_node.name = "Paths"
	add_child(paths_node)

	var roads := Node3D.new()
	roads.name = "Roads"
	add_child(roads)

	var sidewalks := Node3D.new()
	sidewalks.name = "Sidewalks"
	add_child(sidewalks)

	var houses := Node3D.new()
	houses.name = "Houses"
	add_child(houses)

	var lights := Node3D.new()
	lights.name = "StreetLights"
	add_child(lights)

	var trees := Node3D.new()
	trees.name = "Trees"
	add_child(trees)

	# Define road curves for the suburban layout
	var road_curves: Array[Curve3D] = []

	# Main road: gentle S-curve from west to east
	var main_road := Curve3D.new()
	main_road.add_point(Vector3(-90, 0, 0), Vector3(0, 0, 0), Vector3(20, 0, 0))
	main_road.add_point(Vector3(-30, 0, 20), Vector3(-20, 0, -5), Vector3(20, 0, 5))
	main_road.add_point(Vector3(30, 0, -20), Vector3(-20, 0, -5), Vector3(20, 0, 5))
	main_road.add_point(Vector3(90, 0, 0), Vector3(-20, 0, 0), Vector3(0, 0, 0))
	road_curves.append(main_road)

	# North spur: branches off main road, curves up to a cul-de-sac
	var north_spur := Curve3D.new()
	north_spur.add_point(Vector3(-30, 0, 20), Vector3(0, 0, -10), Vector3(0, 0, 10))
	north_spur.add_point(Vector3(-20, 0, 50), Vector3(-5, 0, -10), Vector3(5, 0, 10))
	north_spur.add_point(Vector3(-10, 0, 70), Vector3(-5, 0, -10), Vector3(5, 0, 10))
	road_curves.append(north_spur)

	# Cul-de-sac: circular loop at end of north spur
	var cul_de_sac := Curve3D.new()
	var cd_center := Vector3(-10, 0, 70)
	var cd_radius := 14.0
	for i in range(13):
		var angle := float(i) / 12.0 * TAU
		var pt := cd_center + Vector3(cos(angle) * cd_radius, 0, sin(angle) * cd_radius)
		if i == 0:
			cul_de_sac.add_point(pt, Vector3(0, 0, 0), Vector3(-sin(angle) * 5, 0, cos(angle) * 5))
		else:
			cul_de_sac.add_point(
				pt,
				Vector3(-sin(angle) * 5, 0, cos(angle) * 5),
				Vector3(sin(angle) * 5, 0, -cos(angle) * 5),
			)
	road_curves.append(cul_de_sac)

	# South spur: branches off main road, curves down
	var south_spur := Curve3D.new()
	south_spur.add_point(Vector3(30, 0, -20), Vector3(0, 0, 10), Vector3(0, 0, -10))
	south_spur.add_point(Vector3(45, 0, -45), Vector3(-5, 0, 10), Vector3(5, 0, -10))
	south_spur.add_point(Vector3(35, 0, -70), Vector3(-5, 0, 10), Vector3(5, 0, -10))
	road_curves.append(south_spur)

	# South cul-de-sac
	var south_cd := Curve3D.new()
	var scd_center := Vector3(35, 0, -70)
	var scd_radius := 12.0
	for i in range(13):
		var angle := float(i) / 12.0 * TAU
		var pt := scd_center + Vector3(cos(angle) * scd_radius, 0, sin(angle) * scd_radius)
		if i == 0:
			south_cd.add_point(pt, Vector3(0, 0, 0), Vector3(-sin(angle) * 4, 0, cos(angle) * 4))
		else:
			south_cd.add_point(
				pt,
				Vector3(-sin(angle) * 4, 0, cos(angle) * 4),
				Vector3(sin(angle) * 4, 0, -cos(angle) * 4),
			)
	road_curves.append(south_cd)

	# Build each road
	for i in range(road_curves.size()):
		var curve := road_curves[i]
		var path := Path3D.new()
		path.name = "Road_%d" % i
		path.curve = curve
		paths_node.add_child(path)
		_build_road_mesh(roads, sidewalks, curve, "Road_%d" % i)
		_place_props_along_curve(houses, lights, trees, curve, i >= 2) # cul-de-sacs: one side only

# ============================================================
#  Custom mesh road from curve — SurfaceTool generated geometry
# ============================================================


func _build_road_mesh(
	roads: Node3D,
	sidewalks: Node3D,
	curve: Curve3D,
	name_prefix: String,
) -> void:
	var baked := curve.get_baked_points()
	if baked.size() < 2:
		return
	var total_len := curve.get_baked_length()

	# --- Road mesh ---
	var road_mesh := _generate_road_mesh(curve, baked, total_len, road_width, 0.0)
	var road_mi := MeshInstance3D.new()
	road_mi.name = "%s_road" % name_prefix
	road_mi.mesh = road_mesh
	road_mi.material_override = _road_material
	roads.add_child(road_mi)
	_add_collision(roads, road_mesh, "%s_road_col" % name_prefix)

	# --- Sidewalk meshes (left & right) ---
	var sw_off := road_width * 0.5 + sidewalk_width * 0.5
	for side in [-1.0, 1.0]:
		var sw_mesh := _generate_sidewalk_mesh(
			curve,
			baked,
			total_len,
			sidewalk_width,
			sw_off,
			side,
		)
		var sw_mi := MeshInstance3D.new()
		sw_mi.name = "%s_sw_%d" % [name_prefix, int(side)]
		sw_mi.mesh = sw_mesh
		sw_mi.material_override = _sidewalk_material
		sidewalks.add_child(sw_mi)
		_add_collision(sidewalks, sw_mesh, "%s_sw_%d_col" % [name_prefix, int(side)])


func _generate_road_mesh(
	curve: Curve3D,
	baked: PackedVector3Array,
	total_len: float,
	width: float,
	offset: float,
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w := width * 0.5
	var n := baked.size()
	var uv_v := 0.0
	for i in range(n):
		var pos := baked[i]
		var tangent := _get_tangent(curve, baked, i, total_len)
		var normal := Vector3(-tangent.z, 0, tangent.x)
		var left := pos + normal * (half_w + offset)
		var right := pos - normal * (half_w + offset)
		st.set_uv(Vector2(0.0, uv_v))
		st.add_vertex(Vector3(left.x, 0.02, left.z))
		st.set_uv(Vector2(1.0, uv_v))
		st.add_vertex(Vector3(right.x, 0.02, right.z))
		if i > 0:
			uv_v += baked[i].distance_to(baked[i - 1]) / width
	# Build triangles between consecutive vertex pairs
	for i in range(n - 1):
		var i0 := i * 2
		var i1 := i * 2 + 1
		var i2 := (i + 1) * 2
		var i3 := (i + 1) * 2 + 1
		st.add_index(i0)
		st.add_index(i2)
		st.add_index(i1)
		st.add_index(i1)
		st.add_index(i2)
		st.add_index(i3)
	st.generate_normals()
	return st.commit()


func _generate_sidewalk_mesh(
	curve: Curve3D,
	baked: PackedVector3Array,
	total_len: float,
	width: float,
	center_offset: float,
	side: float,
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w := width * 0.5
	var n := baked.size()
	var uv_v := 0.0
	for i in range(n):
		var pos := baked[i]
		var tangent := _get_tangent(curve, baked, i, total_len)
		var normal := Vector3(-tangent.z, 0, tangent.x)
		var center := pos + normal * side * center_offset
		var left := center + normal * side * half_w
		var right := center - normal * side * half_w
		st.set_uv(Vector2(0.0, uv_v))
		st.add_vertex(Vector3(left.x, 0.05, left.z))
		st.set_uv(Vector2(1.0, uv_v))
		st.add_vertex(Vector3(right.x, 0.05, right.z))
		if i > 0:
			uv_v += baked[i].distance_to(baked[i - 1]) / width
	for i in range(n - 1):
		var i0 := i * 2
		var i1 := i * 2 + 1
		var i2 := (i + 1) * 2
		var i3 := (i + 1) * 2 + 1
		st.add_index(i0)
		st.add_index(i2)
		st.add_index(i1)
		st.add_index(i1)
		st.add_index(i2)
		st.add_index(i3)
	st.generate_normals()
	return st.commit()


func _get_tangent(_curve: Curve3D, baked: PackedVector3Array, i: int, _total_len: float) -> Vector3:
	var n := baked.size()
	if i < n - 1 and i > 0:
		return (baked[i + 1] - baked[i - 1]).normalized()
	if i == 0:
		return (baked[1] - baked[0]).normalized()
	return (baked[n - 1] - baked[n - 2]).normalized()


func _add_collision(parent: Node3D, mesh: ArrayMesh, col_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = col_name
	body.collision_layer = 2
	var shape := ConcavePolygonShape3D.new()
	shape.faces = mesh.get_faces()
	var cshape := CollisionShape3D.new()
	cshape.shape = shape
	body.add_child(cshape)
	parent.add_child(body)

# ============================================================
#  Place houses, lights, trees along a curve
# ============================================================


func _place_props_along_curve(
	houses: Node3D,
	lights: Node3D,
	trees: Node3D,
	curve: Curve3D,
	one_side_only: bool,
) -> void:
	var baked := curve.get_baked_points()
	if baked.size() < 2:
		return
	var total_len := curve.get_baked_length()
	var n_houses := int(total_len / house_spacing)
	if n_houses < 1:
		return

	# Place houses at evenly spaced intervals along the curve
	for i in range(n_houses):
		var t := float(i) / float(n_houses)
		var offset := t * total_len
		var pos := curve.sample_baked(offset)
		# Get tangent direction at this point
		var pos_ahead := curve.sample_baked(minf(offset + 1.0, total_len))
		var pos_behind := curve.sample_baked(maxf(offset - 1.0, 0.0))
		var tangent := (pos_ahead - pos_behind).normalized()
		# Normal (perpendicular in XZ plane)
		var normal := Vector3(-tangent.z, 0, tangent.x)

		var sides: Array[float] = [-1.0, 1.0] if not one_side_only else [1.0]
		for side in sides:
			var house_pos := pos + normal * side * house_setback
			# Skip if too close to an existing house
			if _is_occupied(house_pos, house_spacing * 0.7):
				continue
			_occupied_positions.append(house_pos)
			# Face the road
			var face_angle := atan2(-normal.x, -normal.z)
			if side < 0:
				face_angle += PI
			_place_house_oriented(houses, house_pos, face_angle)
			# Tree between house and road
			if randf() < tree_chance:
				var tree_pos := pos + normal * side * (house_setback - 3.0)
				_place_tree(trees, tree_pos)

	# Street lights along the curve
	var n_lights := int(total_len / light_spacing)
	for i in range(n_lights):
		var t := float(i + 0.5) / float(n_lights)
		var offset := t * total_len
		var pos := curve.sample_baked(offset)
		var pos_ahead := curve.sample_baked(minf(offset + 1.0, total_len))
		var pos_behind := curve.sample_baked(maxf(offset - 1.0, 0.0))
		var tangent := (pos_ahead - pos_behind).normalized()
		var normal := Vector3(-tangent.z, 0, tangent.x)
		var light_pos := pos + normal * (road_width * 0.5 + sidewalk_width + 0.5)
		_place_street_light(lights, light_pos)


func _is_occupied(pos: Vector3, min_dist: float) -> bool:
	for occ in _occupied_positions:
		if pos.distance_to(occ) < min_dist:
			return true
	return false

# ============================================================
#  Prop placement
# ============================================================


func _place_house_oriented(parent: Node3D, pos: Vector3, y_angle: float) -> void:
	if _house_packs.is_empty():
		return
	var pack := _house_packs[randi() % _house_packs.size()]
	var house := pack.instantiate()
	house.position = pos
	house.rotation.y = y_angle
	parent.add_child(house)
	if not _HOUSE_COL_SCENES.is_empty():
		var col_path := _HOUSE_COL_SCENES[randi() % _HOUSE_COL_SCENES.size()]
		if ResourceLoader.exists(col_path):
			var col_pack := load(col_path)
			var col: Node3D = col_pack.instantiate()
			col.visible = false
			house.add_child(col)


func _place_street_light(parent: Node3D, pos: Vector3) -> void:
	if _street_light_pack == null:
		return
	var light := _street_light_pack.instantiate()
	light.position = pos
	parent.add_child(light)


func _place_tree(parent: Node3D, pos: Vector3) -> void:
	if _tree_packs.is_empty():
		return
	var pack := _tree_packs[randi() % _tree_packs.size()]
	var tree := pack.instantiate()
	tree.position = pos
	tree.rotation.y = randf() * TAU
	var s := randf_range(0.8, 1.2)
	tree.scale = Vector3(s, s, s)
	parent.add_child(tree)

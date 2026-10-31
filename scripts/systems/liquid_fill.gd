class_name LiquidFill
extends RefCounted
## Clip-height liquid display: a mesh with the liquid_clip shader clipped at
## fill_y plus a thin disc rendering the flat liquid surface — the same look
## the CSGCombiner+eraser produced, without per-frame CSG rebuilds.
##
## fill_y lives in MESH-LOCAL space so node-level transforms (e.g. the
## dispenser's authored 0.95/0.98 scale) don't distort the clip. Per-instance
## uniforms (set_instance_shader_parameter) keep shared materials safe across
## duplicated and network-synced nodes.

const SHADER: Shader = preload("res://shaders/liquid_clip.gdshader")
const CAP_HEIGHT: float = 0.02
const CAP_INSET: float = 0.97


static func make_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	return m


static func make_cap(mat: Material) -> MeshInstance3D:
	var cap := MeshInstance3D.new()
	cap.name = "LiquidCap"
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = CAP_HEIGHT
	cm.radial_segments = 24
	cap.mesh = cm
	cap.material_override = mat
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return cap


## Sample the mesh's radius profile as sorted (y, radius) pairs so the cap
## can match the cross-section at any clip height.
static func build_profile(mesh: Mesh, bucket := 0.1) -> PackedVector2Array:
	if mesh == null or mesh.get_surface_count() == 0:
		return PackedVector2Array()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var buckets := {}
	for v in verts:
		var k := snappedf(v.y, bucket)
		var r := Vector2(v.x, v.z).length()
		if r > buckets.get(k, 0.0):
			buckets[k] = r
	var keys := buckets.keys()
	keys.sort()
	var out := PackedVector2Array()
	for k in keys:
		out.append(Vector2(k, buckets[k]))
	return out


static func radius_at(profile: PackedVector2Array, y: float) -> float:
	if profile.is_empty():
		return 1.0
	if y <= profile[0].x:
		return profile[0].y
	for i in range(1, profile.size()):
		if y <= profile[i].x:
			var a := profile[i - 1]
			var b := profile[i]
			var f := inverse_lerp(a.x, b.x, y) if b.x > a.x else 0.0
			return lerpf(a.y, b.y, f)
	return profile[profile.size() - 1].y


## Apply a fill fraction: clip the mesh at its local height, place the cap
## disc there, set the color. cap_* params map mesh-local units into the
## cap's parent space when the mesh node carries a non-identity transform.
static func apply(
	mesh_i: MeshInstance3D,
	cap_i: MeshInstance3D,
	profile: PackedVector2Array,
	bottom: float,
	top: float,
	t: float,
	color: Color,
	cap_y_scale := 1.0,
	cap_y_offset := 0.0,
	cap_r_scale := 1.0
) -> void:
	var vis := t > 0.001
	var y := lerpf(bottom, top, clampf(t, 0.0, 1.0))
	if mesh_i != null:
		mesh_i.visible = vis
		mesh_i.set_instance_shader_parameter("fill_y", y)
		if color.a >= 0.0:
			mesh_i.set_instance_shader_parameter("albedo", color)
	if cap_i != null:
		cap_i.visible = vis
		cap_i.position.y = y * cap_y_scale + cap_y_offset + CAP_HEIGHT * 0.5
		var r := maxf(radius_at(profile, y) * CAP_INSET * cap_r_scale, 0.01)
		cap_i.scale = Vector3(r, 1.0, r)
		if color.a >= 0.0:
			cap_i.set_instance_shader_parameter("albedo", color)

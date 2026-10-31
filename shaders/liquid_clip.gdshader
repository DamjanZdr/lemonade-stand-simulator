shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Liquid volume with a flat horizontal clip — replaces the CSG-eraser
// trick. Fragments above fill_y (mesh-local space) are discarded, so the
// mesh keeps its authored silhouette below the liquid level instead of
// being squashed by scale.y. A separate flat cap mesh renders the surface.
uniform vec4 albedo : source_color = vec4(1.0, 0.9, 0.3, 1.0);
uniform float fill_y = 99999.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.3;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	if (local_y > fill_y) {
		discard;
	}
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.5;
}

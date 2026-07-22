shader_type spatial;
render_mode unshaded, cull_disabled, billboard;

uniform float ratio : hint_range(0.0, 1.0) = 1.0;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.35;
uniform float outer_radius : hint_range(0.0, 1.0) = 0.5;
uniform vec3 color_empty : source_color = vec3(1.0, 0.0, 0.0);
uniform vec3 color_full : source_color = vec3(0.0, 1.0, 0.0);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv);
	if (d < inner_radius || d > outer_radius) {
		discard;
	}

	float theta = atan(uv.y, uv.x);
	float angle = 1.57079633 - theta;
	if (angle < 0.0) {
		angle += 6.28318531;
	}
	if (angle > ratio * 6.28318531) {
		discard;
	}

	ALBEDO = mix(color_empty, color_full, ratio);
}

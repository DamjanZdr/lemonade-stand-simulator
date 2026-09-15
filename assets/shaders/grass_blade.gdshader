shader_type spatial;
render_mode cull_disabled;

uniform vec4 bottom_color : source_color = vec4(0.12, 0.35, 0.08, 1.0);
uniform vec4 top_color : source_color = vec4(0.42, 0.68, 0.20, 1.0);
uniform float color_mix_power : hint_range(0.1, 5.0) = 1.2;

uniform float wind_speed = 1.2;
uniform float wind_frequency = 0.5;
uniform float sway_strength = 0.12;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float hash = fract(sin(dot(world_pos.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float phase = hash * TAU;
	float wave = sin(TIME * wind_speed + (world_pos.x + world_pos.z) * wind_frequency + phase);
	float height = clamp(VERTEX.y, 0.0, 1.0);
	float bend = wave * height * sway_strength;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.6;
}

void fragment() {
	float v = 1.0 - clamp(UV.y, 0.0, 1.0);
	float t = pow(v, color_mix_power);
	ALBEDO = mix(bottom_color.rgb, top_color.rgb, t);
	ROUGHNESS = 0.85;
}

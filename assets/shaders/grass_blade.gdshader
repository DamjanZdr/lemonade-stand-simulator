shader_type spatial;
render_mode cull_disabled, unshaded;

uniform vec4 bottom_color : source_color = vec4(0.12, 0.35, 0.08, 1.0);
uniform vec4 top_color : source_color = vec4(0.42, 0.68, 0.20, 1.0);
uniform float color_mix_power : hint_range(0.1, 5.0) = 1.2;

uniform float wind_speed = 1.2;
uniform float wind_frequency = 0.5;
uniform float sway_strength = 0.12;
uniform vec3 player_pos = vec3(0.0);
uniform float fade_radius = 30.0;
uniform float fade_width = 8.0;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float hash = fract(sin(dot(world_pos.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float phase = hash * TAU;
	float wave = sin(TIME * wind_speed + (world_pos.x + world_pos.z) * wind_frequency + phase);
	// The imported blade mesh is lengthwise along local Z; UV.y maps from
	// tip (0) to base (1). Lock the bottom/base vertices so they don't sway.
	float height = 1.0 - clamp(UV.y, 0.0, 1.0);
	float bend = wave * pow(height, 0.5) * sway_strength;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.6;

	// Shrink blades to zero as they leave the radius around the player.
	float dist = distance(world_pos.xz, player_pos.xz);
	float fade = 1.0 - smoothstep(fade_radius - fade_width, fade_radius, dist);
	VERTEX *= fade;
}

void fragment() {
	// The grassblade mesh UV has the tip at UV.y=0 and base at UV.y=1.
	float v = 1.0 - clamp(UV.y, 0.0, 1.0);
	float t = pow(v, color_mix_power);
	ALBEDO = mix(bottom_color.rgb, top_color.rgb, t) * 2.0;
	ROUGHNESS = 0.85;
}

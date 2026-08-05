shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture;

uniform float wind_speed = 1.2;
uniform float wind_frequency = 0.5;
uniform float sway_strength = 0.15;

void vertex() {
	vec3 instance_world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	float hash = fract(sin(dot(instance_world_pos.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float phase = hash * TAU;
	float wave = sin(TIME * wind_speed + (instance_world_pos.x + instance_world_pos.z) * wind_frequency + phase);

	float height = clamp(VERTEX.y, 0.0, 1.0);
	float bend = wave * height * sway_strength;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.6;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * albedo_color.rgb;
	ROUGHNESS = 0.8;
}

shader_type spatial;
render_mode cull_disabled;

uniform vec3 color : source_color = vec3(0.2, 0.7, 0.2);
uniform vec3 color2 : source_color = vec3(0.05, 0.2, 0.05);
uniform sampler2D noise;
uniform float noiseScale = 10.0;

uniform float wind_speed = 1.5;
uniform float sway_strength = 0.3;
uniform float wind_frequency = 0.5;

varying vec3 localPos;

void vertex() {
	localPos = VERTEX;

	// Per-instance random wind
	vec3 instance_world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float hash = fract(sin(dot(instance_world_pos.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float phase = hash * TAU;
	float wind_main = sin(TIME * wind_speed + (instance_world_pos.x + instance_world_pos.z) * wind_frequency + phase);
	float wind_gust = sin(TIME * wind_speed * 0.55 + (instance_world_pos.x - instance_world_pos.z) * wind_frequency * 0.35 + phase * 1.7);
	float wind_wave = wind_main + wind_gust * 0.35;
	float sway_factor = clamp(VERTEX.y, 0.0, 1.0) * sway_strength;
	VERTEX.x += wind_wave * sway_factor;
	VERTEX.z += wind_wave * sway_factor * 0.5;
}

void fragment() {
	vec3 noiseLevel = texture(noise, localPos.xz * noiseScale).rgb;
	ALBEDO = mix(color, color2, 1.0- UV.y) * mix(color, color2, noiseLevel.r);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
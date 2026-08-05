shader_type spatial;
render_mode cull_disabled;

uniform vec3 color : source_color;
uniform vec3 color2 : source_color;
uniform sampler2D noise;
uniform float noiseScale = 20.0;

uniform float wind_speed = 1.2;
uniform float wind_frequency = 0.5;
uniform float sway_strength = 0.1;
uniform float fade_start = 60.0;
uniform float fade_end = 100.0;

varying vec3 worldPos;

void vertex() {
	worldPos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 instance_world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float dist = distance(instance_world_pos, cam_pos);
	float fade = 1.0 - clamp((dist - fade_start) / (fade_end - fade_start), 0.0, 1.0);
	float hash = fract(sin(dot(instance_world_pos.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float phase = hash * TAU;
	float wave = sin(TIME * wind_speed + (instance_world_pos.x + instance_world_pos.z) * wind_frequency + phase);
	float height = clamp(UV.y, 0.0, 1.0);
	float bend = wave * height * sway_strength;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.5;
	VERTEX *= fade;
}

void fragment() {
	vec3 noiseLevel = texture(noise, worldPos.xz * noiseScale).rgb;
	ALBEDO = mix(color, color2, 1.0- UV.y) * mix(color, color2, noiseLevel.r);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
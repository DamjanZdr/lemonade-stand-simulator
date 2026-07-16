shader_type spatial;
render_mode double_sided;

uniform vec3 color : source_color;
uniform vec3 color2 : source_color;
uniform sampler2D noise;
uniform float noiseScale = 10.0;

varying vec3 localPos;

void vertex() {
	localPos = VERTEX;
}

void fragment() {
	vec3 noiseLevel = texture(noise, localPos.xz * noiseScale).rgb;
	ALBEDO = mix(color, color2, 1.0- UV.y) * mix(color, color2, noiseLevel.r);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// 0.0 = no blur, 1.0 = max blur
uniform float blur_amount : hint_range(0.0, 1.0) = 0.0;
// Direction of the blur (normalized)
uniform vec2 blur_dir = vec2(1.0, 0.0);
uniform int samples = 16;

void fragment() {
	// If blur is negligible, just pass through.
	float effective = max(blur_amount, 0.01);
	vec2 dir = normalize(blur_dir) * effective * 0.05;
	vec4 col = vec4(0.0);
	float total = 0.0;

	for (int i = 0; i < samples; i++) {
		float t = float(i) / float(samples - 1) - 0.5;
		float weight = 1.0 - abs(t) * 2.0;
		col += texture(screen_tex, SCREEN_UV + dir * t) * weight;
		total += weight;
	}

	// Blend between sharp and blurred based on actual blur_amount.
	vec4 sharp = texture(screen_tex, SCREEN_UV);
	COLOR = mix(sharp, col / total, smoothstep(0.01, 0.05, blur_amount));
}

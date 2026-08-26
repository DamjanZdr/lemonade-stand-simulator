shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_radius : hint_range(0.0, 16.0) = 8.0;
// UV.x at which the fade starts (0=left edge, 1=right edge).
uniform float fade_start : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	// Fade factor: 1.0 (full blur) on the left, 0.0 (no blur) on the right.
	float fade = smoothstep(1.0, fade_start, UV.x);

	float r = blur_radius * fade;
	float sigma = max(r * 0.5, 0.1);
	vec4 col = vec4(0.0);
	float total = 0.0;

	for (float x = -r; x <= r; x += 1.0) {
		for (float y = -r; y <= r; y += 1.0) {
			float weight = exp(-(x * x + y * y) / (2.0 * sigma * sigma));
			col += texture(screen_tex, SCREEN_UV + vec2(x, y) * SCREEN_PIXEL_SIZE) * weight;
			total += weight;
		}
	}

	col /= total;
	col.a = fade;
	COLOR = col;
}

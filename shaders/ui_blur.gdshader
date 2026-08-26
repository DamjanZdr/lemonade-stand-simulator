shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_radius : hint_range(0.0, 8.0) = 4.0;

void fragment() {
	vec2 texel = 1.0 / SCREEN_PIXEL_SIZE;
	vec4 col = vec4(0.0);
	float total = 0.0;
	float r = blur_radius;
	float sigma = r * 0.5;

	for (float x = -r; x <= r; x += 1.0) {
		for (float y = -r; y <= r; y += 1.0) {
			float weight = exp(-(x * x + y * y) / (2.0 * sigma * sigma));
			col += texture(screen_tex, SCREEN_UV + vec2(x, y) * SCREEN_PIXEL_SIZE) * weight;
			total += weight;
		}
	}

	COLOR = col / total;
}

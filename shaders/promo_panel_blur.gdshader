shader_type canvas_item;

varying vec2 v_pos;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 overlay_color : source_color = vec4(0.15, 0.22, 0.32, 0.85);
uniform float blur_radius : hint_range(0.0, 16.0) = 6.0;
uniform vec2 size_pixels = vec2(280.0, 40.0);
uniform float corner_radius : hint_range(0.0, 32.0) = 8.0;

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE;
	vec4 col = vec4(0.0);
	float total = 0.0;
	float sigma = max(blur_radius * 0.5, 0.1);
	float r = blur_radius;

	for (float x = -r; x <= r; x += 1.0) {
		for (float y = -r; y <= r; y += 1.0) {
			float weight = exp(-(x * x + y * y) / (2.0 * sigma * sigma));
			col += texture(screen_tex, SCREEN_UV + vec2(x, y) * ps) * weight;
			total += weight;
		}
	}

	col /= total;
	vec4 final = mix(col, overlay_color, overlay_color.a);

	float w = size_pixels.x;
	float h = size_pixels.y;
	float cr = corner_radius;
	float alpha = 1.0;

	if (v_pos.x < cr && v_pos.y > h - cr) {
		float d = length(v_pos - vec2(cr, h - cr));
		alpha = clamp(cr - d + 0.5, 0.0, 1.0);
	} else if (v_pos.x > w - cr && v_pos.y > h - cr) {
		float d = length(v_pos - vec2(w - cr, h - cr));
		alpha = clamp(cr - d + 0.5, 0.0, 1.0);
	}

	final.a *= alpha;
	COLOR = final;
}

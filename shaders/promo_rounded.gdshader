shader_type canvas_item;

varying vec2 v_pos;
uniform float corner_radius : hint_range(0.0, 32.0) = 10.0;
uniform vec2 size_pixels = vec2(280.0, 80.0);

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	vec2 half_size = size_pixels * 0.5;
	vec2 d = abs(v_pos - half_size) - (half_size - corner_radius);
	float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - corner_radius;
	float alpha = clamp(-dist, 0.0, 1.0);
	COLOR = texture(TEXTURE, UV) * alpha;
}

shader_type canvas_item;

uniform vec4 dim_color : source_color = vec4(0.0, 0.0, 0.0, 0.35);
// UV.x at which the fade starts (0=left, 1=right).
uniform float fade_start : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	float alpha = dim_color.a * smoothstep(1.0, fade_start, UV.x);
	COLOR = vec4(dim_color.rgb, alpha);
}

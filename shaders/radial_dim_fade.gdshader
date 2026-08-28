shader_type canvas_item;

uniform vec4 dim_color : source_color = vec4(0.0, 0.0, 0.0, 0.25);
// How far from center the fade starts (0=center, 1=edges).
uniform float fade_radius : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	// Distance from center (0 at center, ~0.707 at corners).
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 1.4142;
	// Smoothstep: opaque in center, transparent at edges.
	float alpha = dim_color.a * (1.0 - smoothstep(fade_radius, 0.7, dist));
	COLOR = vec4(dim_color.rgb, alpha);
}

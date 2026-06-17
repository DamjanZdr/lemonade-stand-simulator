// Screen-space silhouette outline — works in GL Compatibility renderer.
//
// How it works:
//   The TextureRect this shader is on displays a SubViewport that renders
//   only the highlighted object's fill mask (white, fully opaque).
//   For each screen pixel we sample 8 neighbours.  If a neighbour is inside
//   the mask but the current pixel is not, this pixel is on the outer edge
//   → draw the outline colour.  The object body is never touched.
shader_type canvas_item;
render_mode blend_mix;

uniform float outline_width : hint_range(0.5, 6.0) = 2.5;
uniform vec4  outline_color : source_color = vec4(1.0, 0.85, 0.0, 1.0);

void fragment() {
	float center = texture(TEXTURE, UV).a;
	vec2  step   = TEXTURE_PIXEL_SIZE * outline_width;

	float n =
		texture(TEXTURE, UV + vec2( step.x,  0.0    )).a +
		texture(TEXTURE, UV + vec2(-step.x,  0.0    )).a +
		texture(TEXTURE, UV + vec2( 0.0,     step.y )).a +
		texture(TEXTURE, UV + vec2( 0.0,    -step.y )).a +
		texture(TEXTURE, UV + vec2( step.x,  step.y )).a +
		texture(TEXTURE, UV + vec2(-step.x,  step.y )).a +
		texture(TEXTURE, UV + vec2( step.x, -step.y )).a +
		texture(TEXTURE, UV + vec2(-step.x, -step.y )).a;

	// edge = neighbour is filled, this pixel is not  →  outer border only
	float edge = clamp(n, 0.0, 1.0) * (1.0 - center);
	COLOR = outline_color * edge;
}

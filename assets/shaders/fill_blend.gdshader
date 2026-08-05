shader_type spatial;
render_mode depth_draw_always;

uniform sampler2D texture_albedo;
uniform float blend_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex_color = texture(texture_albedo, UV);
	ALBEDO = tex_color.rgb;
	ALPHA = tex_color.a * blend_alpha;
}

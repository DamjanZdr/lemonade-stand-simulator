shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_radius : hint_range(0.0, 16.0) = 6.0;
uniform vec4 overlay_color : source_color = vec4(0.15, 0.22, 0.32, 0.75);

void fragment() {
	// Use mipmaps to approximate a soft blur of whatever is behind the panel.
	vec4 blurred = textureLod(screen_tex, SCREEN_UV, blur_radius * 0.5);
	COLOR = mix(blurred, overlay_color, overlay_color.a);
}

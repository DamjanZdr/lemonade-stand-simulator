shader_type canvas_item;

uniform vec4 dim_color : source_color = vec4(0.0, 0.0, 0.0, 0.25);
// How far from center the fade starts (0=center, 1=edges).
uniform float fade_radius : hint_range(0.0, 1.0) = 0.3;
// 0 = no blur; higher = stronger radial blur sampled from the screen.
uniform float blur_amount : hint_range(0.0, 16.0) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	// Distance from center (0 at center, ~0.707 at corners).
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 1.4142;
	// Smoothstep: opaque in center, transparent at edges.
	float alpha = dim_color.a * (1.0 - smoothstep(fade_radius, 0.7, dist));

	if (blur_amount <= 0.001) {
		COLOR = vec4(dim_color.rgb, alpha);
	} else {
		// Simple radial blur along the center→fragment direction.
		vec2 dir = normalize(centered + vec2(0.0001));
		vec4 sample_sum = vec4(0.0);
		float total = 0.0;
		int samples = 16;
		vec2 texel = 1.0 / vec2(textureSize(screen_texture, 0));
		for (int i = -samples; i <= samples; i++) {
			float w = 1.0 / (abs(float(i)) + 1.0);
			vec2 offset = dir * (float(i) * blur_amount * texel.x);
			sample_sum += texture(screen_texture, SCREEN_UV + offset) * w;
			total += w;
		}
		vec4 blurred = sample_sum / total;
		vec3 tinted = mix(blurred.rgb, dim_color.rgb, alpha);
		COLOR = vec4(tinted, alpha);
	}
}

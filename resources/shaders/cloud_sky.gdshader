shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.35, 0.6, 1.0);
uniform vec3 sky_horizon_color : source_color = vec3(0.72, 0.87, 1.0);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_variation : hint_range(0.0, 1.0) = 0.6;
uniform float cloud_speed : hint_range(0.0, 1.0) = 0.05;
uniform float cloud_scale : hint_range(0.1, 5.0) = 1.5;
uniform float time_of_day : hint_range(0.0, 1.0) = 0.0;
uniform vec3 morning_top_color : source_color = vec3(0.25, 0.45, 0.85);
uniform vec3 morning_horizon_color : source_color = vec3(1.0, 0.55, 0.2);
uniform vec3 evening_top_color : source_color = vec3(0.15, 0.2, 0.45);
uniform vec3 evening_horizon_color : source_color = vec3(1.0, 0.42, 0.55);
uniform bool raining = false;
uniform vec3 rain_top_color : source_color = vec3(0.08, 0.1, 0.12);
uniform vec3 rain_horizon_color : source_color = vec3(0.15, 0.18, 0.22);
uniform vec3 rain_cloud_color : source_color = vec3(0.3, 0.32, 0.35);

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)),
	                      dot(p, vec2(269.5, 183.3)))) * 43758.5453) * 2.0 - 1.0;
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n00 = dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float n10 = dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float n01 = dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float n11 = dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(n00, n10, f.x), mix(n01, n11, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void sky() {
	float y = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 top;
	vec3 hor;
	if (raining) {
		top = rain_top_color;
		hor = rain_horizon_color;
	} else if (time_of_day < 0.5) {
		float m = time_of_day * 2.0;
		top = mix(morning_top_color, sky_top_color, m);
		hor = mix(morning_horizon_color, sky_horizon_color, m);
	} else {
		float m = (time_of_day - 0.5) * 2.0;
		top = mix(sky_top_color, evening_top_color, m);
		hor = mix(sky_horizon_color, evening_horizon_color, m);
	}
	vec3 col = mix(hor, top, y);

	if (EYEDIR.y > -0.05) {
		vec2 uv = EYEDIR.xz / max(EYEDIR.y + 0.1, 0.001);
		uv *= cloud_scale;
		uv.x += TIME * cloud_speed;
		float n = fbm(uv) * 0.5 + 0.5;
		float cover_noise = fbm(uv * 0.3) * 0.5 + 0.5;
		float cover = clamp(cloud_cover + (cover_noise - 0.5) * cloud_variation, -0.1, 1.0);
		float cloud = smoothstep(cover, cover + 0.3, n);
		vec3 ccol = raining ? rain_cloud_color : cloud_color;
		col = mix(col, ccol, cloud * (raining ? 0.8 : 0.6));
	}

	if (raining) {
		float x = EYEDIR.x * 20.0;
		float y = EYEDIR.y * 80.0 + TIME * 12.0;
		vec2 i = floor(vec2(x, y));
		vec2 f = fract(vec2(x, y));
		float drop = hash2(i).x * 0.5 + 0.5;
		float x_offset = hash2(i + vec2(34.0, 0.0)).x * 0.5 + 0.5;
		float streak = smoothstep(0.97, 1.0, drop) *
		               smoothstep(0.06, 0.0, abs(f.x - x_offset));
		col += vec3(0.15, 0.18, 0.2) * streak;
	}

	COLOR = col;
}

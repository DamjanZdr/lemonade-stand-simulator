shader_type spatial;
render_mode depth_prepass_alpha;

uniform float fill_amount : hint_range(0.0, 1.0) = 0.5;
uniform vec4 liquid_color : source_color = vec4(0.2, 0.6, 1.0, 0.9);
uniform float wave_speed : hint_range(0.0, 5.0) = 1.5;
uniform float wave_amplitude : hint_range(0.0, 0.05) = 0.01;
uniform float wave_frequency : hint_range(0.0, 20.0) = 8.0;
uniform float mesh_min_y : hint_range(-10.0, 0.0) = -0.5;
uniform float mesh_max_y : hint_range(0.0, 10.0) = 0.5;

varying float deformed_y;

void vertex() {
    float fill_y = mix(mesh_min_y, mesh_max_y, fill_amount);

    if (VERTEX.y >= mesh_max_y - 0.001) {
        float wave = sin(VERTEX.x * wave_frequency + TIME * wave_speed)
                   * cos(VERTEX.z * wave_frequency * 0.7 + TIME * wave_speed * 0.8)
                   * wave_amplitude;
        VERTEX.y = fill_y + wave;
    }

    deformed_y = VERTEX.y;
}

void fragment() {
    float fill_line = mix(mesh_min_y, mesh_max_y, fill_amount);

    if (deformed_y > fill_line + wave_amplitude) {
        discard;
    }

    ALBEDO = liquid_color.rgb;
    ALPHA = liquid_color.a;
}
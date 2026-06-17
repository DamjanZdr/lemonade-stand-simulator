shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 color_top : source_color = vec4(0.2, 0.7, 0.2, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.05, 0.2, 0.05, 1.0);

uniform float wind_speed = 1.5;
uniform float wind_strength = 0.15;
uniform float wind_frequency = 0.5;

void vertex() {
	// --- KROK 1: EFEKT Y-BILLBOARD DLA MULTIMESH ---
	// Pobieramy pozycję instancji z macierzy widoku modelu
	vec3 instance_world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	
	// Resetujemy rotację w osiach X i Z dla macierzy widoku, pozostawiając tylko skalowanie
	// To sprawia, że wierzchołki obracają się w stronę kamery tylko w osi Y
	MODELVIEW_MATRIX[0] = vec4(normalize(MODELVIEW_MATRIX[0].xyz), 0.0);
	MODELVIEW_MATRIX[2] = vec4(normalize(MODELVIEW_MATRIX[2].xyz), 0.0);
	
	// --- KROK 2: GENEROWANIE WIATRU ---
	// Używamy globalnej pozycji instancji, aby wiatr falował płynnie przez całą łąkę
	float wind_wave = sin(TIME * wind_speed + (instance_world_pos.x + instance_world_pos.z) * wind_frequency);
	
	// UV.y = 0.0 to zazwyczaj czubek trawy, a UV.y = 1.0 to podstawa.
	// Mnożnik sprawia, że tylko góra trawy faluje, a dół zostaje w miejscu.
	float sway_factor = (1.0 - UV.y) * wind_strength;
	
	// Aplikujemy ruch wiatru (tutaj bezpośrednio w lokalnych współrzędnych wierzchołka)
	VERTEX.x += wind_wave * sway_factor;
	VERTEX.z += wind_wave * sway_factor * 0.5;
}

void fragment() {
	// Poprawa wyświetlania tekstury/koloru z obu stron (wyłączenie błędów cieniowania tyłu)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	
	// Kontrolowany gradient od dołu do góry
	vec3 final_color = mix(color_bottom.rgb, color_top.rgb, 1.0 - UV.y);
	
	ALBEDO = final_color;
	ROUGHNESS = 0.8;
	SPECULAR = 0.1;
}

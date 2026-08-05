shader_type spatial;
// No transparency flags: Godot renders this in the opaque pass (before the
// transparent glass mesh), so the glass composites naturally on top.
render_mode unshaded;

// World-space Y above which fragments are discarded.
// Default 9999 = show everything (overwritten immediately in _ready).
uniform float clip_world_y = 9999.0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.88, 0.25, 1.0);

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	if (world_y > clip_world_y) {
		discard;
	}
	ALBEDO = fill_color.rgb;
	// Do not write ALPHA — keeps this material in the opaque render pass.
}

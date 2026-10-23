shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Disco plano de color uniforme con borde suave (mapa de calor del tablero). No le afecta
// la luz: se ve igual en la penumbra. El alfa lo fija `color.a` (cae con la distancia).
uniform vec4 color : source_color = vec4(1.0);
// Fracción del radio de la malla donde empieza a difuminarse el borde.
uniform float edge_start : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	float r = length((UV - vec2(0.5)) * 2.0);
	float a = 1.0 - smoothstep(edge_start, 1.0, r);
	// Núcleo algo más intenso que el borde.
	a *= mix(0.75, 1.0, 1.0 - smoothstep(0.0, edge_start, r));
	ALBEDO = color.rgb;
	ALPHA = color.a * a;
}

shader_type canvas_item;
render_mode unshaded;

// Fondo del menú: una luz roja apagada que parpadea sobre el negro, con viñeta y grano.
uniform vec4 glow_color : source_color = vec4(0.30, 0.03, 0.03, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - vec2(0.5, 0.42);
	float flicker = 0.80 + 0.12 * sin(TIME * 1.7) + 0.08 * sin(TIME * 13.0 + sin(TIME * 3.1) * 4.0);
	// Cae de golpe de vez en cuando, como una bombilla que falla.
	float cut = step(0.985, hash(vec2(floor(TIME * 9.0), 1.0)));
	flicker *= 1.0 - 0.7 * cut;
	float d = length(uv * vec2(1.0, 1.4));
	vec3 col = glow_color.rgb * flicker * smoothstep(0.75, 0.0, d);
	float grain = hash(UV * 900.0 + floor(TIME * 24.0)) - 0.5;
	col += grain * 0.03;
	col *= smoothstep(1.05, 0.35, length((UV - 0.5) * 1.5));
	COLOR = vec4(max(col, vec3(0.008)), 1.0);
}

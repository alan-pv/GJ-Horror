shader_type canvas_item;
// Visión de túnel del estrés: el centro (el tablero) queda nítido y los bordes se desenfocan.
// 12 muestras en espiral con giro por ruido: barato (corre en web, renderer Compatibility).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Radio máximo del desenfoque, como fracción de la altura de la pantalla.
uniform float max_radius = 0.012;

const int TAPS = 12;
const float GOLDEN = 2.39996323;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	// Elipse ancha: el reloj (a un costado del tablero) debe seguir legible con estrés alto.
	vec2 c = (uv - vec2(0.5)) * vec2(aspect * 0.6, 1.0);
	float d = length(c);
	// Zona nítida: radio (en alturas de pantalla) que se cierra con el estrés.
	float inner = mix(0.42, 0.32, amount);
	float outer = mix(0.95, 0.75, amount);
	float m = smoothstep(inner, outer, d) * amount;
	vec3 col = texture(screen_tex, uv).rgb;
	if (m > 0.002) {
		float r = m * max_radius;
		float rot = hash(FRAGCOORD.xy) * 6.2831853;
		vec3 sum = col;
		for (int i = 0; i < TAPS; i++) {
			float f = (float(i) + 0.5) / float(TAPS);
			float ang = float(i) * GOLDEN + rot;
			vec2 off = vec2(cos(ang) / aspect, sin(ang)) * sqrt(f) * r;
			sum += texture(screen_tex, uv + off).rgb;
		}
		col = sum / float(TAPS + 1);
	}
	COLOR = vec4(col, 1.0);
}

shader_type canvas_item;
render_mode unshaded;

uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = 0.0;
uniform float softness : hint_range(0.0005, 0.3) = 0.004;
uniform float aspect = 1.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 p = (UV - center) * vec2(aspect, 1.0);
	float d = length(p);
	// Opaque outside the circle, clear inside: the hole is the transition.
	float a = smoothstep(radius - softness, radius + softness, d);
	COLOR = vec4(tint.rgb, tint.a * a);
}
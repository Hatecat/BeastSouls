// Viñeta suave y un poco de grano (pantalla completa, por encima del 3D y por debajo del HUD).
shader_type canvas_item;

uniform float vignette = 0.4;
uniform float grain = 0.035;

void fragment() {
	vec2 p = SCREEN_UV - 0.5;
	float v = smoothstep(0.3, 0.9, length(p * vec2(1.0, 0.8)) * 1.3) * vignette;
	float n = fract(sin(dot(floor(FRAGCOORD.xy) + fract(TIME * 7.0) * 113.0, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float g = abs(n) * grain;
	// Donde domina la viñeta, negro translúcido; si no, grano claro u oscuro.
	COLOR = v > g ? vec4(0.0, 0.0, 0.0, v) : vec4(vec3(step(0.0, n)), g);
}

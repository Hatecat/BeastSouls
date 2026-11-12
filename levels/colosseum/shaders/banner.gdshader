// Estandarte de tela que ondea con el viento. La malla es un QuadMesh subdividido colgado por arriba
// (borde superior en y = +alto/2). Dibujo procedural: franjas y un emblema circular.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 cloth_color : source_color = vec3(0.45, 0.05, 0.04);
uniform vec3 trim_color : source_color = vec3(0.75, 0.55, 0.2);
uniform float height = 3.5;
uniform float sway = 0.25;
uniform float phase = 0.0;

void vertex() {
	// 0 arriba (fijo) → 1 abajo (libre).
	float t = clamp((height * 0.5 - VERTEX.y) / height, 0.0, 1.0);
	float wave = sin(TIME * 1.7 + phase + VERTEX.y * 1.3) + 0.5 * sin(TIME * 3.1 + phase * 2.0 + VERTEX.x * 3.0);
	VERTEX.z += wave * sway * t * t;
	VERTEX.x += sin(TIME * 1.1 + phase) * sway * 0.3 * t * t;
}

void fragment() {
	vec2 uv = UV;
	vec3 c = cloth_color;
	// Ribete en los bordes y franja.
	float edge = step(uv.x, 0.06) + step(0.94, uv.x) + step(0.88, uv.y) * step(uv.y, 0.92);
	// Emblema: anillo con un punto.
	vec2 p = (uv - vec2(0.5, 0.35)) * vec2(1.0, 2.6);
	float d = length(p);
	float emblem = smoothstep(0.31, 0.29, d) * smoothstep(0.21, 0.23, d) + smoothstep(0.1, 0.08, d);
	c = mix(c, trim_color, clamp(edge + emblem, 0.0, 1.0));
	// Punta hacia abajo: se recortan las esquinas inferiores.
	if (uv.y > 1.0 - abs(uv.x - 0.5) * 0.24) {
		discard;
	}
	ALBEDO = c * (0.85 + 0.15 * sin(uv.x * 120.0));
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = c * 0.4;
}

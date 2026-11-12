// Suelo de losas del coliseo: texturas en coordenadas de mundo (XZ), variación a gran escala para que no se
// note la repetición, arena acumulada en las juntas y junto al muro, y un emblema circular en el centro.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float tile_size = 4.0;
uniform float arena_radius = 22.0;
uniform vec3 sand_color : source_color = vec3(0.5, 0.41, 0.3);
uniform vec3 inlay_color : source_color = vec3(0.12, 0.1, 0.1);
uniform float normal_strength = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Bandas del emblema: 1 dentro del anillo, 0 fuera (suavizado con la derivada para no parpadear).
float band(float x, float a, float b) {
	float w = fwidth(x) * 1.5;
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

void fragment() {
	vec2 uv = wpos.xz / tile_size;
	// Girar un poco la segunda muestra para romper la repetición.
	vec3 macro = texture(macro_tex, wpos.xz / 41.0).rgb;
	vec3 albedo = texture(albedo_tex, uv).rgb;
	vec3 orm = texture(orm_tex, uv).rgb;
	vec3 nrm = texture(normal_tex, uv).rgb;
	albedo *= mix(0.75, 1.2, macro.r) * mix(vec3(1.0), vec3(1.05, 0.98, 0.9), macro.g);

	// Emblema: anillos de piedra oscura pulida y radios.
	float r = length(wpos.xz);
	float ang = atan(wpos.z, wpos.x);
	float rings = max(band(r, 2.7, 3.0), band(r, 5.4, 5.65));
	float spokes = band(abs(fract(ang / 6.2831853 * 8.0) - 0.5), 0.0, 0.035 * 3.0 / max(r, 0.5)) * band(r, 3.0, 5.4);
	float inlay = max(rings, spokes);
	albedo = mix(albedo, inlay_color * (0.8 + 0.4 * macro.g), inlay);
	float rough = mix(orm.r, 0.35, inlay);

	// Arena: en las juntas (poca altura), en manchas y cerca del muro.
	float near_wall = smoothstep(arena_radius - 6.0, arena_radius + 0.5, r);
	float in_grout = clamp((0.3 - orm.g) * 2.0, 0.0, 0.45);
	float patches = clamp((macro.b - 0.58) * 3.0, 0.0, 1.0);
	float sand = clamp(in_grout + patches + near_wall * 1.2, 0.0, 1.0) * (1.0 - inlay);
	vec3 sand_c = sand_color * (0.8 + 0.4 * macro.g);
	ALBEDO = mix(albedo, sand_c, sand);
	ROUGHNESS = mix(rough, 0.97, sand);
	NORMAL_MAP = mix(nrm, vec3(0.5, 0.5, 1.0), sand * 0.85);
	NORMAL_MAP_DEPTH = normal_strength;
	AO = mix(orm.b, 1.0, sand * 0.6);
	AO_LIGHT_AFFECT = 0.4;
	SPECULAR = 0.4;
}

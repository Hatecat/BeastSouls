// Piedra de sillares con proyección triplanar en coordenadas de mundo (muros, columnas, escombros):
// no necesita UVs, así que sirve para cualquier malla generada. Suciedad cerca del suelo y polvo encima.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float tile_size = 4.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float grime_height = 1.6;
uniform vec3 grime_color : source_color = vec3(0.35, 0.3, 0.26);
uniform vec3 dust_color : source_color = vec3(0.62, 0.52, 0.4);
uniform float normal_strength = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack(vec3 c) {
	vec3 n = c * 2.0 - 1.0;
	n.xy *= normal_strength;
	return n;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	// Proyecciones (receta "whiteout" de Ben Golus; V invertida porque en Godot la imagen crece hacia abajo).
	vec3 sgn = sign(n);
	vec2 uvx = vec2(wpos.z * sgn.x, -wpos.y) / tile_size;
	vec2 uvy = vec2(wpos.x * sgn.y, -wpos.z) / tile_size;
	vec2 uvz = vec2(-wpos.x * sgn.z, -wpos.y) / tile_size;
	vec3 albedo = texture(albedo_tex, uvx).rgb * w.x + texture(albedo_tex, uvy).rgb * w.y + texture(albedo_tex, uvz).rgb * w.z;
	vec3 orm = texture(orm_tex, uvx).rgb * w.x + texture(orm_tex, uvy).rgb * w.y + texture(orm_tex, uvz).rgb * w.z;
	vec3 tx = unpack(texture(normal_tex, uvx).rgb);
	vec3 ty = unpack(texture(normal_tex, uvy).rgb);
	vec3 tz = unpack(texture(normal_tex, uvz).rgb);
	tx.x *= sgn.x;
	ty.x *= sgn.y;
	tz.x *= -sgn.z;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 wn = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	vec3 macro = texture(macro_tex, wpos.xz / 29.0 + wpos.y / 53.0).rgb;
	albedo *= tint * mix(0.75, 1.2, macro.r);
	// Suciedad que sube desde el suelo, irregular.
	float grime = 1.0 - smoothstep(0.0, grime_height * (0.6 + 0.8 * macro.g), wpos.y);
	albedo = mix(albedo, albedo * grime_color * 1.6, grime * 0.8);
	// Polvo y arena sobre las superficies que miran arriba.
	float dust = smoothstep(0.55, 0.95, n.y) * smoothstep(0.3, 0.7, macro.b + 0.2);
	ALBEDO = mix(albedo, dust_color * (0.8 + 0.4 * macro.g), dust * 0.8);
	ROUGHNESS = clamp(orm.r + grime * 0.08, 0.0, 1.0);
	AO = orm.b;
	AO_LIGHT_AFFECT = 0.4;
	SPECULAR = 0.35;
}

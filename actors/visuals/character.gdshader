shader_type spatial;
// Piel de los personajes: textura original + microdetalle repetido (normal en RG, altura en B) que da relieve,
// oscurece los huecos y varía la rugosidad. Con capa de barniz (quitina, piel mojada), luz de contorno, luz
// que atraviesa (pelaje, membranas) y brillo de borde (fantasma). No usa tangentes propias: valen las de Godot.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 12.0;
uniform float detail_strength = 0.7;
uniform float cavity : hint_range(0.0, 1.0) = 0.4;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_variation = 0.2;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float clearcoat : hint_range(0.0, 1.0) = 0.0;
uniform float clearcoat_roughness : hint_range(0.0, 1.0) = 0.2;
uniform float rim : hint_range(0.0, 1.0) = 0.35;
uniform float rim_tint : hint_range(0.0, 1.0) = 0.6;
uniform vec3 backlight : source_color = vec3(0.0);
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float glow = 0.0;
uniform float saturation = 1.08;

void fragment() {
	vec4 base = texture(albedo_tex, UV) * albedo_color;
	vec3 d = texture(detail_tex, UV * detail_scale).rgb;
	// De lejos el microdetalle se convierte en ruido: se apaga con la distancia.
	float near = 1.0 - smoothstep(9.0, 22.0, -VERTEX.z);
	float height = mix(0.5, d.b, near);
	vec3 col = base.rgb * mix(1.0, 0.62 + 0.55 * height, cavity);
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	ALBEDO = max(mix(vec3(grey), col, saturation), vec3(0.0));
	NORMAL_MAP = vec3(d.rg, 1.0);
	NORMAL_MAP_DEPTH = detail_strength * near;
	ROUGHNESS = clamp(roughness + (0.5 - height) * roughness_variation, 0.05, 1.0);
	SPECULAR = specular;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	RIM = rim;
	RIM_TINT = rim_tint;
	BACKLIGHT = backlight;
	AO = mix(1.0, 0.55 + 0.45 * height, cavity);
	AO_LIGHT_AFFECT = 0.35;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = glow_color * glow * fresnel;
}

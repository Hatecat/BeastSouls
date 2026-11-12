extends Node
## Autoload "Graphics": calidad gráfica (Bajo / Medio / Alto / Ultra), guardada en user://settings.cfg.
## Se aplica sola a cada WorldEnvironment y a las luces/efectos opcionales que entran en el árbol:
##   grupo "brazier_lights" → sombras de luces puntuales; grupo "optional_fx" → efectos prescindibles.

signal changed

enum Quality { LOW, MEDIUM, HIGH, ULTRA }
const NAMES := ["Bajo", "Medio", "Alto", "Ultra"]
const PATH := "user://settings.cfg"

## Por calidad: escala de render (FSR 2), GI, oclusión, niebla volumétrica, sombras...
const PRESETS := {
	Quality.LOW: {scale = 0.6, sdfgi = false, ssil = false, ssao = RenderingServer.ENV_SSAO_QUALITY_LOW,
		vol_fog = false, fog_size = 64, shadow_size = 2048, soft = RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		point_shadows = false, optional_fx = false, gi_half = true},
	Quality.MEDIUM: {scale = 0.7, sdfgi = true, ssil = false, ssao = RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		vol_fog = true, fog_size = 64, shadow_size = 2048, soft = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		point_shadows = false, optional_fx = true, gi_half = true},
	Quality.HIGH: {scale = 0.8, sdfgi = true, ssil = true, ssao = RenderingServer.ENV_SSAO_QUALITY_HIGH,
		vol_fog = true, fog_size = 96, shadow_size = 4096, soft = RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		point_shadows = true, optional_fx = true, gi_half = true},
	Quality.ULTRA: {scale = 1.0, sdfgi = true, ssil = true, ssao = RenderingServer.ENV_SSAO_QUALITY_ULTRA,
		vol_fog = true, fog_size = 128, shadow_size = 4096, soft = RenderingServer.SHADOW_QUALITY_SOFT_ULTRA,
		point_shadows = true, optional_fx = true, gi_half = false},
}

var quality := Quality.HIGH


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		quality = clampi(int(cfg.get_value("graphics", "quality", Quality.HIGH)), 0, 3) as Quality
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			quality = clampi(int(a.trim_prefix("--quality=")), 0, 3) as Quality
	get_tree().node_added.connect(_on_node_added)
	_apply_global()


func preset() -> Dictionary:
	return PRESETS[quality]


func quality_name() -> String:
	return NAMES[quality]


func set_quality(q: int) -> void:
	quality = clampi(q, 0, 3) as Quality
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("graphics", "quality", quality)
	cfg.save(PATH)
	_apply_global()
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_apply_environment((n as WorldEnvironment).environment)
	for n in get_tree().get_nodes_in_group(&"brazier_lights"):
		_apply_light(n)
	for n in get_tree().get_nodes_in_group(&"optional_fx"):
		_apply_optional(n)
	changed.emit()


func cycle() -> void:
	set_quality((quality + 1) % 4)


func _apply_global() -> void:
	var p := preset()
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	vp.scaling_3d_scale = p.scale
	vp.positional_shadow_atlas_size = 4096 if p.point_shadows else 1024
	RenderingServer.directional_shadow_atlas_set_size(p.shadow_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p.soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(p.soft)
	RenderingServer.gi_set_use_half_resolution(p.gi_half)
	RenderingServer.environment_set_ssao_quality(p.ssao, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM if quality < Quality.ULTRA else RenderingServer.ENV_SSIL_QUALITY_HIGH, true, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_volumetric_fog_volume_size(p.fog_size, p.fog_size)
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_32 if quality >= Quality.HIGH else RenderingServer.ENV_SDFGI_RAY_COUNT_16)


func _apply_environment(env: Environment) -> void:
	if env == null:
		return
	var p := preset()
	env.sdfgi_enabled = p.sdfgi
	env.ssil_enabled = p.ssil
	env.volumetric_fog_enabled = p.vol_fog


func _apply_light(light: Light3D) -> void:
	light.shadow_enabled = preset().point_shadows


func _apply_optional(n: Node) -> void:
	if n is Node3D:
		(n as Node3D).visible = preset().optional_fx
	if n is GPUParticles3D:
		(n as GPUParticles3D).emitting = preset().optional_fx


func _on_node_added(n: Node) -> void:
	if n is WorldEnvironment:
		_apply_environment.call_deferred((n as WorldEnvironment).environment)
	elif n.is_in_group(&"brazier_lights"):
		_apply_light(n)
	elif n.is_in_group(&"optional_fx"):
		_apply_optional.call_deferred(n)

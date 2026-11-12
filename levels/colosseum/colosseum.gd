@tool
extends Node3D
## Escenario: coliseo en ruinas al atardecer. Se construye por código al cargar (también en el editor):
## suelo de losas, muro con pilastras y dos portones, columnata y gradas con un tramo derrumbado hacia el sol,
## columnas rotas y escombros para cubrirse, braseros, estandartes, polvo en el aire y montañas a lo lejos.
##
## Ángulos: posición = (cos a, 0, sin a) * r. El jugador aparece en (0, 0, 6) mirando a -Z (a = 270°).

const TEX := "res://levels/colosseum/textures/"
const ARENA_R := 22.6  ## Cara interior del muro.
const WALL_TOP := 4.0
const COLONNADE_R := 23.5
## Tramo derrumbado (grados) y dirección del sol.
const GAP_FROM := 200.0
const GAP_TO := 240.0
const SUN_AZIMUTH := 220.0
const SUN_ELEVATION := 13.0

@export var seed := 1234
@export_tool_button("Reconstruir") var rebuild_button := _rebuild

var _rng := RandomNumberGenerator.new()
var _stone: ShaderMaterial
var _metal: StandardMaterial3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_rng.seed = seed
	_make_materials()
	_environment()
	_floor()
	_wall()
	_colonnade_and_tiers()
	_arena_columns()
	_rubble()
	_braziers()
	_banners()
	_mountains()
	_dust()


# --- Materiales -------------------------------------------------------------------------

func _make_materials() -> void:
	_stone = ShaderMaterial.new()
	_stone.shader = load("res://levels/colosseum/shaders/stone.gdshader")
	_stone.set_shader_parameter(&"albedo_tex", load(TEX + "stone_albedo.png"))
	_stone.set_shader_parameter(&"normal_tex", load(TEX + "stone_normal.png"))
	_stone.set_shader_parameter(&"orm_tex", load(TEX + "stone_orm.png"))
	_stone.set_shader_parameter(&"macro_tex", load(TEX + "macro.png"))
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.09, 0.08, 0.07)
	_metal.metallic = 0.85
	_metal.roughness = 0.55


func _stone_variant(tint: Color) -> ShaderMaterial:
	var m := _stone.duplicate() as ShaderMaterial
	m.set_shader_parameter(&"tint", tint)
	return m


# --- Entorno ----------------------------------------------------------------------------

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.22, 0.36)
	sky_mat.sky_horizon_color = Color(0.95, 0.6, 0.38)
	sky_mat.sky_curve = 0.12
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_bottom_color = Color(0.06, 0.05, 0.05)
	sky_mat.ground_horizon_color = Color(0.7, 0.45, 0.32)
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_energy = 1.1
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.85, 0.62, 0.48)
	env.fog_light_energy = 0.8
	env.fog_sun_scatter = 0.35
	env.fog_density = 0.0011
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.15
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0055
	env.volumetric_fog_albedo = Color(0.9, 0.78, 0.66)
	env.volumetric_fog_anisotropy = 0.65
	env.volumetric_fog_length = 70.0
	env.volumetric_fog_detail_spread = 1.5
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var az := deg_to_rad(SUN_AZIMUTH)
	var el := deg_to_rad(SUN_ELEVATION)
	var to_sun := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	sun.light_color = Color(1.0, 0.76, 0.52)
	sun.light_energy = 2.2
	sun.light_volumetric_fog_energy = 1.6
	sun.light_angular_distance = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)


# --- Suelo ------------------------------------------------------------------------------

func _floor() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://levels/colosseum/shaders/floor.gdshader")
	mat.set_shader_parameter(&"albedo_tex", load(TEX + "floor_albedo.png"))
	mat.set_shader_parameter(&"normal_tex", load(TEX + "floor_normal.png"))
	mat.set_shader_parameter(&"orm_tex", load(TEX + "floor_orm.png"))
	mat.set_shader_parameter(&"macro_tex", load(TEX + "macro.png"))
	mat.set_shader_parameter(&"arena_radius", ARENA_R)
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	plane.material = mat
	var body := _static_body("Floor")
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = Vector3(120, 1, 120)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -0.5
	body.add_child(cs)


# --- Muro con pilastras y portones -------------------------------------------------------

func _wall() -> void:
	var st := _begin()
	var segs := 120
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var mid := rad_to_deg((a0 + a1) * 0.5)
		var top := WALL_TOP
		if _in_gap(mid):
			# Tramo derrumbado: muro bajo y desigual.
			top = 1.8 + _rng.randf() * 1.2
		_ring(st, ARENA_R, ARENA_R + 1.0, 0.0, top, a0, a1)
		_ring(st, ARENA_R - 0.25, ARENA_R, 0.0, 0.45, a0, a1)  # zócalo
		if not _in_gap(mid):
			_ring(st, ARENA_R - 0.35, ARENA_R + 1.2, top, top + 0.4, a0, a1)  # cornisa
	# Pilastras.
	for k in 48:
		var a := TAU * k / 48.0
		if _in_gap(rad_to_deg(a)) or _near_gate(rad_to_deg(a), 8.0):
			continue
		_box(st, _polar(ARENA_R - 0.15, a, 0.45), Vector3(0.75, WALL_TOP - 0.45, 0.35), a, Vector3(0, (WALL_TOP - 0.45) * 0.5, 0))
	var mesh := st.commit()
	var body := _static_body("Wall")
	_mesh(body, mesh, _stone)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	# Portones: hueco oscuro con rastrillo de hierro (solo decoración: el muro sigue cerrando).
	for gate in [90.0, 270.0]:
		var a := deg_to_rad(gate)
		var g := _begin()
		_box(g, _polar(ARENA_R - 0.02, a, 0.0), Vector3(3.2, 3.2, 0.1), a, Vector3(0, 1.6, 0))
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.015, 0.012, 0.01)
		dark.roughness = 1.0
		_mesh(self, g.commit(), dark)
		var bars := _begin()
		for b in 9:
			var off := (b - 4) * 0.36
			var p := _polar(ARENA_R - 0.12, a, 0.0) + Vector3(-sin(a), 0, cos(a)) * off
			_box(bars, p, Vector3(0.07, 3.2, 0.07), a, Vector3(0, 1.6, 0))
		for h in [0.8, 1.9, 2.9]:
			_box(bars, _polar(ARENA_R - 0.14, a, h), Vector3(3.2, 0.08, 0.06), a)
		# Arco de sillares encima.
		_box(bars, _polar(ARENA_R - 0.3, a, 3.2), Vector3(4.0, 0.5, 0.5), a, Vector3(0, 0.25, 0))
		var bm := bars.commit()
		_mesh(self, bm, _metal)


func _near_gate(deg: float, tolerance: float) -> bool:
	for g in [90.0, 270.0]:
		if absf(angle_difference(deg_to_rad(deg), deg_to_rad(g))) < deg_to_rad(tolerance):
			return true
	return false


func _in_gap(deg: float) -> bool:
	deg = fposmod(deg, 360.0)
	return deg >= GAP_FROM and deg <= GAP_TO


# --- Columnata y gradas -------------------------------------------------------------------

func _colonnade_and_tiers() -> void:
	var base_y := WALL_TOP + 0.4
	var col_h := 4.4
	var cols := 48
	var transforms: Array[Transform3D] = []
	var standing: Array[bool] = []
	for k in cols:
		var a := TAU * k / cols
		var deg := rad_to_deg(a)
		var ok := not _in_gap(deg) and _rng.randf() > 0.12
		var h := col_h if _rng.randf() > 0.2 else col_h * _rng.randf_range(0.25, 0.7)
		standing.append(ok and h >= col_h)
		if not ok:
			continue
		var t := Transform3D(Basis().scaled(Vector3(1, h / col_h, 1)), _polar(COLONNADE_R, a, base_y + h * 0.5))
		transforms.append(t)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.36
	cyl.height = col_h
	cyl.radial_segments = 12
	cyl.rings = 1
	_multimesh("Colonnade", cyl, transforms, _stone_variant(Color(1.05, 1.0, 0.95)))
	# Arquitrabe sobre pares de columnas en pie.
	var st := _begin()
	for k in cols:
		if standing[k] and standing[(k + 1) % cols]:
			var a0 := TAU * k / cols
			_ring(st, COLONNADE_R - 0.5, COLONNADE_R + 0.5, base_y + col_h, base_y + col_h + 0.7, a0 - 0.02, a0 + TAU / cols + 0.02)
	# Gradas: escalones desde detrás de la columnata hacia fuera, con el tramo derrumbado.
	var seats := _begin()
	var steps := 8
	var segs := 96
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var mid := rad_to_deg((a0 + a1) * 0.5)
		if _in_gap(mid):
			continue
		for s in steps:
			var r_in := COLONNADE_R + 0.7 + s * 1.2
			var top := base_y + 0.4 + s * 0.95
			_ring(st, r_in, 36.0, base_y, top, a0, a1)
			_ring(seats, r_in - 0.12, r_in + 0.55, top, top + 0.12, a0, a1)  # losa de asiento
		_ring(st, 36.0, 37.0, 0.0, base_y + 9.5, a0, a1)  # muro exterior
	_mesh(self, st.commit(), _stone_variant(Color(0.95, 0.92, 0.88)))
	_mesh(self, seats.commit(), _stone_variant(Color(1.25, 1.18, 1.08)))
	# En el hueco: restos de gradas a distintas alturas.
	var ruins := _begin()
	for i in 14:
		var a := deg_to_rad(_rng.randf_range(GAP_FROM, GAP_TO))
		var r := _rng.randf_range(24.5, 35.0)
		var size := Vector3(_rng.randf_range(1.0, 3.0), _rng.randf_range(0.6, 4.5), _rng.randf_range(1.0, 2.5))
		_box(ruins, _polar(r, a, 0.0), size, a + _rng.randf_range(-0.3, 0.3), Vector3(0, size.y * 0.5, 0))
	_mesh(self, ruins.commit(), _stone)


# --- Columnas rotas dentro de la arena (cobertura) ----------------------------------------

func _arena_columns() -> void:
	var heights := [6.5, 2.2, 5.0, 3.0, 7.2, 1.5]
	for k in 6:
		var a := deg_to_rad(15.0 + 60.0 * k)
		var pos := _polar(12.5, a, 0.0)
		var h: float = heights[k]
		var body := _static_body("Column%d" % k)
		body.position = pos
		var st := _begin()
		_box(st, Vector3.ZERO, Vector3(1.7, 0.5, 1.7), a, Vector3(0, 0.25, 0))
		_box(st, Vector3.ZERO, Vector3(1.45, 0.3, 1.45), a, Vector3(0, 0.65, 0))
		_mesh(body, st.commit(), _stone)
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.55
		shaft.bottom_radius = 0.62
		shaft.height = h
		shaft.radial_segments = 16
		var mi := _mesh(body, shaft, _stone)
		mi.position.y = 0.8 + h * 0.5
		# Corte irregular de la parte rota: un trozo inclinado encima.
		if h < 6.0:
			var chunk := CylinderMesh.new()
			chunk.top_radius = 0.4
			chunk.bottom_radius = 0.55
			chunk.height = 0.5
			chunk.radial_segments = 16
			var cm := _mesh(body, chunk, _stone)
			cm.position = Vector3(0.1, 0.8 + h + 0.15, -0.05)
			cm.rotation = Vector3(0.35, 0.0, 0.25)
		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.65
		cyl.height = h + 0.8
		col.shape = cyl
		col.position.y = (h + 0.8) * 0.5
		body.add_child(col)
		var base := CollisionShape3D.new()
		var bb := BoxShape3D.new()
		bb.size = Vector3(1.7, 0.5, 1.7)
		base.shape = bb
		base.position.y = 0.25
		base.rotation.y = -a
		body.add_child(base)
	# Una columna caída.
	var fallen := _static_body("FallenColumn")
	var a := deg_to_rad(165.0)
	fallen.position = _polar(10.5, a, 0.6)
	fallen.rotation = Vector3(0, -a + 0.3, PI * 0.5)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.55
	shaft.bottom_radius = 0.6
	shaft.height = 5.5
	shaft.radial_segments = 16
	_mesh(fallen, shaft, _stone)
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.6
	cyl.height = 5.5
	col.shape = cyl
	fallen.add_child(col)


# --- Escombros ----------------------------------------------------------------------------

func _rubble() -> void:
	var transforms: Array[Transform3D] = []
	var big := _static_body("Rubble")
	var add := func(center: Vector3, spread: float, count: int, smin: float, smax: float) -> void:
		for i in count:
			var p := center + Vector3(_rng.randf_range(-spread, spread), 0, _rng.randf_range(-spread, spread))
			var s := Vector3(_rng.randf_range(smin, smax), _rng.randf_range(smin, smax) * 0.7, _rng.randf_range(smin, smax))
			var b := Basis.from_euler(Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf(), _rng.randf_range(-0.4, 0.4)))
			var t := Transform3D(b.scaled(s), p + Vector3(0, s.y * 0.3, 0))
			transforms.append(t)
			if s.x > 0.55 and s.z > 0.55:
				var cs := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = s * 0.85
				cs.shape = box
				cs.transform = Transform3D(b, t.origin)
				big.add_child(cs)
	for k in 6:
		var a := deg_to_rad(15.0 + 60.0 * k)
		add.call(_polar(12.5, a, 0.0) + _polar(1.4, a + 0.8, 0.0), 0.9, 7, 0.15, 0.55)
	# Derrumbe junto al hueco (dentro del muro, pegado a él).
	for i in 5:
		var a := deg_to_rad(_rng.randf_range(GAP_FROM + 3.0, GAP_TO - 3.0))
		add.call(_polar(ARENA_R - 1.2, a, 0.0), 1.3, 9, 0.2, 0.95)
	# Piedras sueltas por el borde.
	for i in 24:
		var a := _rng.randf() * TAU
		add.call(_polar(ARENA_R - 0.7, a, 0.0), 0.5, 2, 0.1, 0.35)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_multimesh("RubbleMesh", box, transforms, _stone)


# --- Braseros -----------------------------------------------------------------------------

func _braziers() -> void:
	for k in 4:
		var a := deg_to_rad(45.0 + 90.0 * k)
		var body := _static_body("Brazier%d" % k)
		body.position = _polar(17.5, a, 0.0)
		var ped := CylinderMesh.new()
		ped.top_radius = 0.28
		ped.bottom_radius = 0.42
		ped.height = 1.1
		ped.radial_segments = 12
		var pm := _mesh(body, ped, _stone)
		pm.position.y = 0.55
		var bowl := CylinderMesh.new()
		bowl.top_radius = 0.7
		bowl.bottom_radius = 0.28
		bowl.height = 0.4
		bowl.radial_segments = 16
		var bm := _mesh(body, bowl, _metal)
		bm.position.y = 1.3
		var coals := CylinderMesh.new()
		coals.top_radius = 0.6
		coals.bottom_radius = 0.6
		coals.height = 0.05
		var hot := StandardMaterial3D.new()
		hot.albedo_color = Color(0.2, 0.05, 0.02)
		hot.emission_enabled = true
		hot.emission = Color(1.0, 0.35, 0.08)
		hot.emission_energy_multiplier = 2.5
		var cm := _mesh(body, coals, hot)
		cm.position.y = 1.47
		if not Engine.is_editor_hint():
			var fire := Fx.fire(Fx.FIRE, 1.3)
			body.add_child(fire)
			fire.position.y = 1.55
			var embers := Fx.embers(Color(1.0, 0.45, 0.12), 0.35, 14)
			embers.emitting = true
			body.add_child(embers)
			embers.position.y = 1.8
		var light := FlickerLight.new()
		light.light_color = Color(1.0, 0.58, 0.28)
		light.base_energy = 2.2
		light.omni_range = 11.0
		light.omni_attenuation = 1.4
		light.shadow_enabled = true
		light.light_volumetric_fog_energy = 0.6
		light.add_to_group(&"brazier_lights")
		body.add_child(light)
		light.position.y = 2.3
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.5
		cyl.height = 1.5
		cs.shape = cyl
		cs.position.y = 0.75
		body.add_child(cs)


# --- Estandartes --------------------------------------------------------------------------

func _banners() -> void:
	var shader := load("res://levels/colosseum/shaders/banner.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 3.2)
	quad.subdivide_depth = 12
	quad.subdivide_width = 2
	for k in 12:
		var deg := 15.0 + 30.0 * k
		if _in_gap(deg) or _near_gate(deg, 14.0):
			continue
		var a := deg_to_rad(deg)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter(&"height", 3.2)
		mat.set_shader_parameter(&"phase", k * 1.7)
		mat.set_shader_parameter(&"sway", 0.12)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		add_child(mi)
		# Colgado de la cornisa, de cara al centro.
		var p := _polar(ARENA_R - 0.45, a, WALL_TOP + 0.2 - 1.6)
		mi.transform = Transform3D(Basis.looking_at(-p * Vector3(1, 0, 1), Vector3.UP).rotated(Vector3.UP, PI), p)


# --- Lejanía ------------------------------------------------------------------------------

func _mountains() -> void:
	# Dos cordilleras: anillos de silueta irregular (cerca más oscura y baja, lejos más clara y alta).
	_ridge(270.0, 18.0, 38.0, Color(0.13, 0.11, 0.12), 3)
	_ridge(420.0, 35.0, 75.0, Color(0.2, 0.17, 0.19), 7)


func _ridge(radius: float, h_min: float, h_max: float, color: Color, seed_offset: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed + seed_offset
	noise.frequency = 0.9
	noise.fractal_octaves = 4
	var st := _begin()
	var segs := 240
	var prev := Vector3.ZERO
	var prev_top := 0.0
	for i in segs + 1:
		var a := TAU * i / segs
		# Ruido sobre el círculo (cerrado sin costura).
		var n := noise.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0) * 0.5 + 0.5
		var top := lerpf(h_min, h_max, pow(n, 1.6))
		var p := Vector3(cos(a) * radius, 0, sin(a) * radius)
		if i > 0:
			var inward := -(p + prev).normalized()
			_quad(st, prev + Vector3.DOWN * 20.0, p + Vector3.DOWN * 20.0, p + Vector3.UP * top, prev + Vector3.UP * prev_top, inward)
		prev = p
		prev_top = top
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	var mi := _mesh(self, st.commit(), mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## Motas de polvo flotando (se ven en los haces de luz).
func _dust() -> void:
	if Engine.is_editor_hint():
		return
	var p := GPUParticles3D.new()
	p.name = "Dust"
	p.amount = 500
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.visibility_aabb = AABB(Vector3(-25, -2, -25), Vector3(50, 16, 50))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(22, 6, 22)
	m.direction = Vector3(1, 0.2, 0.3)
	m.spread = 180.0
	m.initial_velocity_min = 0.05
	m.initial_velocity_max = 0.25
	m.gravity = Vector3(0.05, -0.01, 0.02)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.4
	m.turbulence_noise_speed_random = 0.2
	m.scale_min = 0.4
	m.scale_max = 1.0
	m.color = Color(1.0, 0.85, 0.65, 0.35)
	m.alpha_curve = Fx._curve_tex([Vector2(0, 0), Vector2(0.2, 1), Vector2(0.8, 1), Vector2(1, 0)])
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = Fx._soft_texture()
	quad.material = qm
	p.draw_pass_1 = quad
	p.position.y = 5.0
	p.add_to_group(&"optional_fx")
	add_child(p)


# --- Utilidades de mallas -----------------------------------------------------------------

func _polar(r: float, a: float, y: float) -> Vector3:
	return Vector3(cos(a) * r, y, sin(a) * r)


func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Cuadrilátero con normal plana; corrige el orden para que la cara mire hacia `n`.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = d
		d = t
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(v)


## Sector de anillo macizo entre radios y alturas (caras superior, interior, exterior y tapas).
func _ring(st: SurfaceTool, r_in: float, r_out: float, y0: float, y1: float, a0: float, a1: float) -> void:
	var p := func(r: float, a: float, y: float) -> Vector3: return Vector3(cos(a) * r, y, sin(a) * r)
	var am := (a0 + a1) * 0.5
	var radial := Vector3(cos(am), 0, sin(am))
	_quad(st, p.call(r_in, a0, y1), p.call(r_out, a0, y1), p.call(r_out, a1, y1), p.call(r_in, a1, y1), Vector3.UP)
	_quad(st, p.call(r_in, a0, y0), p.call(r_in, a1, y0), p.call(r_in, a1, y1), p.call(r_in, a0, y1), -radial)
	_quad(st, p.call(r_out, a0, y0), p.call(r_out, a1, y0), p.call(r_out, a1, y1), p.call(r_out, a0, y1), radial)
	var t0 := Vector3(-sin(a0), 0, cos(a0))
	var t1 := Vector3(-sin(a1), 0, cos(a1))
	_quad(st, p.call(r_in, a0, y0), p.call(r_out, a0, y0), p.call(r_out, a0, y1), p.call(r_in, a0, y1), -t0)
	_quad(st, p.call(r_in, a1, y0), p.call(r_out, a1, y0), p.call(r_out, a1, y1), p.call(r_in, a1, y1), t1)


## Caja orientada: `pos` en el suelo, girada para que su eje Z apunte al centro según el ángulo `a`.
func _box(st: SurfaceTool, pos: Vector3, size: Vector3, a: float, offset := Vector3.ZERO) -> void:
	var b := Basis(Vector3.UP, -a - PI * 0.5)
	var c := pos + b * offset
	var h := size * 0.5
	var corners := []
	for z in [-1, 1]:
		for y in [-1, 1]:
			for x in [-1, 1]:
				corners.append(c + b * Vector3(x * h.x, y * h.y, z * h.z))
	# Índices: x + 2y + 4z.
	var faces := [[[0, 2, 6, 4], Vector3.LEFT], [[1, 5, 7, 3], Vector3.RIGHT], [[0, 4, 5, 1], Vector3.DOWN],
		[[2, 3, 7, 6], Vector3.UP], [[0, 1, 3, 2], Vector3.FORWARD], [[4, 6, 7, 5], Vector3.BACK]]
	for f in faces:
		var i: Array = f[0]
		_quad(st, corners[i[0]], corners[i[1]], corners[i[2]], corners[i[3]], b * f[1])


func _mesh(parent: Node, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


func _static_body(node_name: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = node_name
	b.collision_layer = 1
	b.collision_mask = 0
	add_child(b)
	return b

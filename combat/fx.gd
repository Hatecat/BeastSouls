class_name Fx
extends RefCounted
## Constructores de efectos visuales reutilizables. Solo presentación.

## Color por defecto de los efectos (fuego).
const FIRE := Color(1.0, 0.42, 0.12)

static var _soft_tex: GradientTexture2D
## Materiales y mallas ya creados, por clave. Crear recursos nuevos en cada efecto cuesta decenas
## de milisegundos en partida (el renderizador los registra); reutilizarlos lo deja en ~0.
static var _cache := {}


static func _cached(key: String, build: Callable) -> Variant:
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]


## Chorro continuo (lanzallamas, hidrobomba...). Emite hacia -Z del nodo.
static func flame_jet(color := FIRE) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 110
	p.lifetime = 0.55
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-6, -6, -10), Vector3(12, 12, 14))
	p.process_material = _cached("flame_ppm_" + color.to_html(), _flame_ppm.bind(Vector3(0, 0, -1), 11.0, 9.0, 12.0, color))
	p.draw_pass_1 = _cached("quad_0.7", _billboard_quad.bind(0.7, true))
	return p


static func _flame_ppm(direction: Vector3, spread: float, v_min: float, v_max: float, c: Color) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = direction
	m.spread = spread
	m.initial_velocity_min = v_min
	m.initial_velocity_max = v_max
	m.gravity = Vector3(0, 1.5, 0)
	m.damping_min = 3.0
	m.damping_max = 5.0
	m.scale_min = 0.5
	m.scale_max = 0.9
	m.scale_curve = _curve_tex([Vector2(0, 0.25), Vector2(0.5, 1.0), Vector2(1, 1.6)])
	var hot := c.lerp(Color.WHITE, 0.4)
	m.color_ramp = _gradient_tex([
		[0.0, Color(hot.r * 1.6, hot.g * 1.6, hot.b * 1.6, 0.7)],
		[0.25, Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, 0.6)],
		[0.65, Color(c.r * 0.8, c.g * 0.6, c.b * 0.6, 0.35)],
		[1.0, Color(c.r * 0.1, c.g * 0.1, c.b * 0.1, 0.0)]])
	m.angle_min = -180.0
	m.angle_max = 180.0
	return m


## Ascuas que suben (quemadura, aura de mejora). `radius` = anchura del emisor.
static func embers(color: Color, radius: float, amount := 24, burst := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.local_coords = false
	p.emitting = false
	var key := "embers_%s_%.2f_%s" % [color.to_html(), radius, burst]
	p.process_material = _cached(key, _embers_ppm.bind(color, radius, burst))
	p.draw_pass_1 = _cached("quad_0.5" if burst else "quad_0.18", _billboard_quad.bind(0.5 if burst else 0.18, true))
	return p


static func _embers_ppm(color: Color, radius: float, burst: bool) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = radius
	m.direction = Vector3(0, 1, 0)
	m.spread = 180.0 if burst else 25.0
	m.initial_velocity_min = 2.0 if burst else 0.8
	m.initial_velocity_max = 5.0 if burst else 2.0
	m.gravity = Vector3(0, 1.0, 0)
	m.scale_min = 0.5
	m.scale_max = 1.2
	m.scale_curve = _curve_tex([Vector2(0, 1.0), Vector2(1, 0.0)])
	m.color_ramp = _gradient_tex([
		[0.0, Color(color.r * 2.5, color.g * 2.5, color.b * 2.5, 1.0)],
		[1.0, Color(color.r, color.g * 0.3, color.b * 0.2, 0.0)]])
	return m


## Núcleo de un proyectil (bola de fuego, bola sombra...): esfera emisiva + estela + luz.
static func fireball_visual(color := FIRE) -> Node3D:
	var root := Node3D.new()
	var core := MeshInstance3D.new()
	core.mesh = _cached("fireball_core_" + color.to_html(), func():
		var sphere := SphereMesh.new()
		sphere.radius = 0.32
		sphere.height = 0.64
		sphere.radial_segments = 24
		sphere.rings = 12
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(color.r * 2.0 + 0.1, color.g * 2.0 + 0.1, color.b * 2.0 + 0.1)
		sphere.material = mat
		return sphere)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var trail := GPUParticles3D.new()
	trail.amount = 90
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.process_material = _cached("trail_ppm_" + color.to_html(), _flame_ppm.bind(Vector3(0, 0, 1), 25.0, 1.0, 2.5, color))
	trail.draw_pass_1 = _cached("quad_0.7", _billboard_quad.bind(0.7, true))
	trail.emitting = true
	root.add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = color.lerp(Color.WHITE, 0.2)
	light.light_energy = 2.5
	light.omni_range = 5.0
	root.add_child(light)
	return root


## Onda expansiva en el suelo (rugido).
static func shockwave(parent: Node, pos: Vector3, radius: float, color := Color(1.0, 0.75, 0.45)) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _cached("torus", func():
		var torus := TorusMesh.new()
		torus.inner_radius = 0.85
		torus.outer_radius = 1.0
		torus.rings = 48
		return torus)
	ring.material_override = _cached("shock_%s" % color.to_html(), func():
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 0.9)
		return m)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.3
	ring.scale = Vector3(0.5, 1.5, 0.5)
	# El material es compartido: cada onda se desvanece con la transparencia de su propio nodo.
	var tw := ring.create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3(radius, 0.4, radius), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ring, "transparency", 1.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)


## Crea cada efecto una vez, escondido bajo el suelo, para que Godot compile sus shaders al
## cargar el nivel y no a mitad de combate (evita tirones la primera vez que se usan).
## `colors`: colores de los efectos que se van a usar (los de las habilidades de los personajes en juego).
static func prewarm(parent: Node3D, colors: Array[Color] = []) -> void:
	var at := Vector3(0, -2.0, 0)
	var nodes: Array[Node3D] = [embers(Color(1.0, 0.4, 0.1), 0.5, 40)]
	for c in [FIRE] + colors:
		nodes.append(flame_jet(c))
		nodes.append(fireball_visual(c))
	for n in nodes:
		parent.add_child(n)
		n.global_position = at
		if n is GPUParticles3D:
			(n as GPUParticles3D).emitting = true
	for k in HitFx.Kind.values():
		HitFx.spawn(parent, at, Vector3.UP, k)
	for c in [FIRE] + colors:
		explosion(parent, at, c)
		shockwave(parent, at, 1.0, c)
	await parent.get_tree().create_timer(0.5).timeout
	for n in nodes:
		n.queue_free()


## Explosión: chispas grandes + destello.
static func explosion(parent: Node, pos: Vector3, color := FIRE, size := 1.0) -> void:
	HitFx.spawn(parent, pos, Vector3.UP, HitFx.Kind.HIT, 2.5 * size)
	var burst := embers(color, 0.6 * size, 60, true)
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.emitting = true
	parent.add_child(burst)
	burst.global_position = pos
	burst.get_tree().create_timer(1.5).timeout.connect(burst.queue_free)


# --- Utilidades ---------------------------------------------------------------------

static func _billboard_quad(size: float, soft: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if soft:
		m.albedo_texture = _soft_texture()
	q.material = m
	return q


static func _soft_texture() -> GradientTexture2D:
	if _soft_tex == null:
		_soft_tex = GradientTexture2D.new()
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(0.5, 0.0)
		_soft_tex.width = 64
		_soft_tex.height = 64
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft_tex.gradient = g
	return _soft_tex


static func _curve_tex(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 2.0
	for pt: Vector2 in points:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _gradient_tex(stops: Array) -> GradientTexture1D:
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s: Array in stops:
		offsets.append(s[0])
		colors.append(s[1])
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	return t

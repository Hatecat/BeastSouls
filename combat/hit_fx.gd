class_name HitFx
extends RefCounted
## Efectos de impacto: chispas (GPUParticles3D de un solo disparo) y un destello de luz.
## Es solo presentación: nunca afecta a la simulación.

enum Kind { HIT, BLOCK, GUARD_BREAK }

const COLORS := {
	Kind.HIT: Color(1.0, 0.5, 0.15),
	Kind.BLOCK: Color(0.75, 0.88, 1.0),
	Kind.GUARD_BREAK: Color(1.0, 0.85, 0.4),
}

static var _draw_mesh: QuadMesh
static var _process_mats := {}


static func spawn(parent: Node, pos: Vector3, normal: Vector3, kind: Kind, strength := 1.0) -> void:
	var color: Color = COLORS[kind]
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = int(18 + 18 * strength)
	p.lifetime = 0.45
	p.process_material = _process_material(kind)
	p.draw_pass_1 = _mesh()
	p.local_coords = false
	p.emitting = true
	parent.add_child(p)
	p.global_position = pos
	if normal.length_squared() > 0.001:
		p.look_at(pos + normal, Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0 * strength
	light.omni_range = 3.5
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.15)
	tw.tween_callback(light.queue_free)
	p.get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


static func _mesh() -> QuadMesh:
	if _draw_mesh == null:
		_draw_mesh = QuadMesh.new()
		_draw_mesh.size = Vector2(0.09, 0.09)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		# Color HDR (>1) multiplicado por el color de la partícula: así brilla con el bloom.
		m.albedo_color = Color(2.2, 2.2, 2.2, 1.0)
		_draw_mesh.material = m
	return _draw_mesh


static func _process_material(kind: Kind) -> ParticleProcessMaterial:
	if _process_mats.has(kind):
		return _process_mats[kind]
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0, -1)
	m.spread = 70.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 10.0
	m.gravity = Vector3(0, -12, 0)
	m.damping_min = 2.0
	m.damping_max = 4.0
	m.scale_min = 0.6
	m.scale_max = 1.6
	var ramp := Gradient.new()
	var c: Color = COLORS[kind]
	ramp.set_color(0, Color(1, 1, 1, 1).lerp(c, 0.3))
	ramp.set_color(1, Color(c.r, c.g * 0.4, c.b * 0.2, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	_process_mats[kind] = m
	return m

class_name AttackTrail
extends MeshInstance3D
## Estela de un golpe: cinta en coordenadas de mundo que se desvanece. El Beast le va dando muestras
## (borde interior y exterior) siguiendo el barrido de la hitbox, así la estela enseña por dónde pega.
## Solo presentación. La malla se reconstruye cada fotograma con las últimas muestras.

const LIFE := 0.2

var color := Color(1.0, 0.8, 0.5)

var _samples: Array = []  ## [edad, interior, exterior, tira]
var _strip := 0
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = Fx._cached("attack_trail_mat", func() -> Material:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(2.4, 2.4, 2.4)  # por encima de 1: el bloom la hace brillar
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		return m)


## Empieza una cinta nueva (otro ataque): no se une con la anterior.
func begin() -> void:
	_strip += 1


func add_sample(inner: Vector3, outer: Vector3) -> void:
	_samples.append([0.0, inner, outer, _strip])


func _process(delta: float) -> void:
	for s: Array in _samples:
		s[0] += delta
	while not _samples.is_empty() and _samples[0][0] > LIFE:
		_samples.pop_front()
	_mesh.clear_surfaces()
	var i := 0
	while i < _samples.size():
		var j := i
		while j < _samples.size() and _samples[j][3] == _samples[i][3]:
			j += 1
		if j - i >= 2:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for n in range(i, j):
				var s: Array = _samples[n]
				var a: float = 1.0 - s[0] / LIFE
				# Más brillante en el borde exterior y en la punta reciente.
				_mesh.surface_set_color(Color(color.r, color.g, color.b, 0.0))
				_mesh.surface_add_vertex(s[1])
				_mesh.surface_set_color(Color(color.r, color.g, color.b, a * a))
				_mesh.surface_add_vertex(s[2])
			_mesh.surface_end()
		i = j

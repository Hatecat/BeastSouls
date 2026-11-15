class_name CharacterVisual
extends Node3D
## Capa visual de un personaje: modelo, animaciones y puntos de anclaje ("sockets").
##
## El resto del juego (movimiento, combate, red) solo habla con esta clase usando nombres
## LÓGICOS de acción ("idle", "walk", "attack_light_1", ...) y de socket ("mouth", "hand_r", ...).
## Cambiar de modelo = crear otra escena con otro `model_scene` y otros mapas; nada más se toca.

signal action_finished(action: StringName)

## Escena importada del modelo (.glb).
@export var model_scene: PackedScene
## Altura final del modelo en metros (se mide en la pose de "idle").
@export var target_height := 2.2
## Giro extra del modelo en grados. glTF mira a +Z y Godot considera "adelante" -Z.
@export var model_yaw_offset := 180.0
## Acción lógica -> clip del modelo.
@export var action_map: Dictionary[StringName, StringName] = {}
## Velocidad de reproducción por acción lógica (1.0 si no está).
@export var action_speed: Dictionary[StringName, float] = {}
## Acciones que se repiten en bucle.
@export var looping_actions: Array[StringName] = [&"idle", &"walk", &"run"]
## Socket lógico -> nombre del hueso.
@export var sockets: Dictionary[StringName, StringName] = {}
## Mezcla por defecto entre clips, en segundos.
@export var default_blend := 0.15

## Tipo de superficie del cuerpo: elige el microdetalle y el comportamiento con la luz (ver SURFACES).
@export var surface: StringName = &"skin"

@export_group("Movimiento procedural")
## Inclinación del cuerpo con la aceleración y los giros, y aplastamiento al saltar/aterrizar/recibir golpes.
@export var motion_enabled := true
## Escala de la inclinación (los personajes pesados se inclinan menos).
@export var lean_scale := 1.0
## Huesos con física de muelle (colas, antenas, orejas): cadenas cuyo nombre contiene alguno de estos textos.
@export var spring_patterns: PackedStringArray = ["Tail", "Feeler", "Ear", "Tongue"]
## Superficie para las piezas que por nombre parecen ojos pero son la cara entera (Aipom: su malla "Eye" es
## toda la cara). Vacío = se tratan como ojos (material original, brillante).
@export var face_surface: StringName = &""
## Escala de cadenas de huesos enteras (texto contenido en el nombre → factor): se aplica al primer hueso de
## cada cadena, p. ej. {"Tail": 0.6} para acortar colas que tapan la cámara.
@export var bone_scale: Dictionary[String, float] = {}
@export var spring_stiffness := 3.0
@export var spring_drag := 0.45

## Parámetros del shader de personaje (actors/visuals/character.gdshader) por tipo de superficie.
const SURFACES := {
	&"skin": {detail = "skin", detail_scale = 12.0, detail_strength = 0.5, cavity = 0.3, roughness = 0.62,
		roughness_variation = 0.2, specular = 0.45, rim = 0.35},
	&"scales": {detail = "scales", detail_scale = 4.0, detail_strength = 0.6, cavity = 0.32, roughness = 0.5,
		roughness_variation = 0.35, specular = 0.55, rim = 0.35, backlight = Color(0.25, 0.08, 0.02)},
	&"chitin": {detail = "chitin", detail_scale = 7.0, detail_strength = 0.45, cavity = 0.3, roughness = 0.3,
		roughness_variation = 0.25, specular = 0.6, clearcoat = 0.7, clearcoat_roughness = 0.12, rim = 0.4},
	&"ghost": {detail = "skin", detail_scale = 9.0, detail_strength = 0.35, cavity = 0.25, roughness = 0.45,
		roughness_variation = 0.15, specular = 0.5, rim = 0.45, rim_tint = 0.5, backlight = Color(0.2, 0.05, 0.3),
		glow_color = Color(0.5, 0.2, 1.0), glow = 0.45},
	&"fur": {detail = "fur", detail_scale = 11.0, detail_strength = 1.0, cavity = 0.5, roughness = 0.85,
		roughness_variation = 0.2, specular = 0.25, rim = 0.5, rim_tint = 0.8, backlight = Color(0.22, 0.2, 0.16)},
	&"wet": {detail = "skin", detail_scale = 10.0, detail_strength = 0.4, cavity = 0.25, roughness = 0.22,
		roughness_variation = 0.2, specular = 0.65, clearcoat = 0.85, clearcoat_roughness = 0.08, rim = 0.45,
		backlight = Color(0.03, 0.12, 0.2)},
}

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var current_action: StringName = &""

var _socket_nodes: Dictionary[StringName, BoneAttachment3D] = {}
var _flash_mat: StandardMaterial3D
var _flash_tween: Tween
var _pivot: Node3D
var _pose: PoseModifier
var _springs: SpringBoneSimulator3D
var _trail: AttackTrail
## Análisis de los clips de ataque, compartido entre instancias del mismo modelo: clip -> [impacto (s), hueso].
static var _impact_cache := {}
var _impacts := {}
var _has_prev := false
var _prev_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _vel := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _acc := Vector3.ZERO
var _yaw_rate := 0.0
var _lean := Vector2.ZERO  ## x = cabeceo, y = alabeo (rad)
var _squash := 0.0
var _squash_vel := 0.0
var _stretch := 0.0


func _ready() -> void:
	if model_scene == null:
		push_error("CharacterVisual: falta model_scene")
		return
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	model = model_scene.instantiate()
	_pivot.add_child(model)
	model.rotation_degrees.y = model_yaw_offset
	var skels := model.find_children("*", "Skeleton3D", true, false)
	skeleton = skels[0] if not skels.is_empty() else null
	var players := model.find_children("*", "AnimationPlayer", true, false)
	anim_player = players[0] if not players.is_empty() else null
	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)
		_setup_loops()
	_fix_materials()
	_analyze_attacks()
	# Medir en la pose de idle: el reposo de estos modelos no es representativo.
	play(&"idle", 0.0)
	if anim_player:
		anim_player.advance(0.0)
	_fit_to_height()
	_create_sockets()
	_setup_procedural()


## Reproduce una acción lógica. Devuelve false si el modelo no la tiene.
func play(action: StringName, blend := -1.0, speed := 1.0) -> bool:
	if anim_player == null:
		return false
	var clip := get_clip(action)
	if clip == &"" or not anim_player.has_animation(clip):
		return false
	current_action = action
	var s: float = action_speed.get(action, 1.0) * speed
	if anim_player.current_animation == clip and action not in looping_actions:
		# Repetir una acción de un solo uso (p. ej. dos esquivas seguidas) la reinicia.
		anim_player.seek(0.0, true)
	anim_player.play(clip, default_blend if blend < 0.0 else blend, s)
	return true


## Reproduce `action` clavada a un instante del clip (`clip_time`, en segundos del clip) que avanza a `rate`
## (segundos de clip por segundo real). La usa el Beast para que el impacto visual de un ataque coincida con su
## ventana activa: el reloj es el de la simulación, no el del AnimationPlayer.
func drive(action: StringName, clip_time: float, rate: float, blend := 0.06) -> void:
	if anim_player == null:
		return
	var clip := get_clip(action)
	if clip == &"" or not anim_player.has_animation(clip):
		return
	if anim_player.current_animation != clip or current_action != action:
		current_action = action
		anim_player.play(clip, blend, 1.0)
		anim_player.seek(clip_time, false)
	var err := clip_time - anim_player.current_animation_position
	if absf(err) > 0.2:
		anim_player.seek(clip_time, true)
		err = 0.0
	anim_player.speed_scale = maxf(0.0, rate + err * 10.0)


## Duración del clip tal cual (sin `action_speed`).
func get_clip_length(action: StringName) -> float:
	return anim_player.get_animation(get_clip(action)).length if has_action(action) else 0.0


## Instante del clip (s) en el que el golpe llega más lejos hacia delante.
func get_impact_time(action: StringName) -> float:
	var info: Array = _impacts.get(get_clip(action), [])
	return info[0] if not info.is_empty() else get_clip_length(action) * 0.45


## Estela del golpe: `begin_trail` al empezar la ventana activa y `add_trail` con cada tramo del barrido (mundo).
func begin_trail(color: Color) -> void:
	if _trail:
		_trail.color = color
		_trail.begin()


func add_trail(inner: Vector3, outer: Vector3) -> void:
	if _trail:
		_trail.add_sample(inner, outer)


## Punto del mundo al que mira la cabeza (Vector3.INF = al frente).
func look_at_point(point: Vector3) -> void:
	if _pose:
		_pose.look_point = point


## Reacción a un golpe: el torso se dobla hacia `push_dir` (mundo) y el cuerpo se aplasta un instante.
func flinch(push_dir: Vector3, strength: float) -> void:
	if _pose:
		_pose.flinch(push_dir, strength)
	punch(-strength * 0.5)


## Impulso de aplastamiento (negativo) o estiramiento (positivo) con rebote.
func punch(amount: float) -> void:
	_squash_vel += amount * 9.0


## Tras un teletransporte (reaparecer): olvida la inercia para que no haya latigazos.
func reset_motion() -> void:
	_has_prev = false
	_vel = Vector3.ZERO
	_acc = Vector3.ZERO
	_lean = Vector2.ZERO
	_squash = 0.0
	_squash_vel = 0.0
	if _springs:
		_springs.reset()


## Congela el modelo en un instante (fracción 0..1) de una acción: poses estáticas como la guardia.
func hold_pose(action: StringName, fraction: float, blend := -1.0) -> void:
	if not play(action, blend):
		return
	var clip := anim_player.get_animation(get_clip(action))
	anim_player.seek(clip.length * fraction, true)
	anim_player.speed_scale = 0.0


## Destello breve sobre todo el modelo (al recibir un golpe, al bloquear...).
func flash(color: Color, duration := 0.12) -> void:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			m.material_overlay = _flash_mat
	if _flash_tween:
		_flash_tween.kill()
	_flash_mat.albedo_color = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, duration).from(color.a)


## Transparencia del modelo entero (0 = opaco, 1 = invisible). La usa la cámara cuando queda muy pegada.
func set_fade(amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		m.transparency = amount


## Multiplicador global de velocidad (p. ej. ajustar el ciclo de caminar a la velocidad real).
func set_playback_speed(scale: float) -> void:
	if anim_player:
		anim_player.speed_scale = scale


func has_action(action: StringName) -> bool:
	return anim_player != null and anim_player.has_animation(get_clip(action))


func get_clip(action: StringName) -> StringName:
	return action_map.get(action, action)


## Duración real (segundos, ya con la velocidad) de una acción.
func get_action_length(action: StringName) -> float:
	if not has_action(action):
		return 0.0
	var speed: float = action_speed.get(action, 1.0)
	return anim_player.get_animation(get_clip(action)).length / maxf(speed, 0.001)


## Nodo que sigue al hueso del socket (para hitboxes, partículas, proyectiles...).
func get_socket(socket: StringName) -> Node3D:
	return _socket_nodes.get(socket, self)


func get_clip_names() -> PackedStringArray:
	return anim_player.get_animation_list() if anim_player else PackedStringArray()


func _on_animation_finished(_clip: StringName) -> void:
	action_finished.emit(current_action)


func _setup_loops() -> void:
	for action in looping_actions:
		var clip := get_clip(action)
		if anim_player.has_animation(clip):
			anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func _create_sockets() -> void:
	if skeleton == null:
		return
	for socket: StringName in sockets:
		var bone_name: StringName = sockets[socket]
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			push_warning("CharacterVisual: el hueso '%s' del socket '%s' no existe" % [bone_name, socket])
			continue
		var att := BoneAttachment3D.new()
		att.name = "Socket_" + socket
		att.bone_idx = idx
		skeleton.add_child(att)
		_socket_nodes[socket] = att


# --- Movimiento procedural ------------------------------------------------------

func _setup_procedural() -> void:
	if skeleton == null:
		set_process(false)
		return
	_pose = PoseModifier.new()
	_pose.name = "PoseModifier"
	_pose.visual = self
	_pose.head_bone = skeleton.find_bone(sockets.get(&"head", &""))
	_pose.chest_bone = skeleton.find_bone(sockets.get(&"chest", &""))
	if _pose.head_bone >= 0:
		var parent := skeleton.get_bone_parent(_pose.head_bone)
		if parent < 0:
			_pose.head_bone = -1  # la cabeza es la raíz (Gengar): girarla giraría el cuerpo entero
		elif parent != _pose.chest_bone and String(skeleton.get_bone_name(parent)).containsn("neck"):
			_pose.neck_bone = parent
	for b in skeleton.get_bone_count():
		var bone_name := String(skeleton.get_bone_name(b))
		var parent := skeleton.get_bone_parent(b)
		for pattern: String in bone_scale:
			if bone_name.contains(pattern) and not (parent >= 0 and String(skeleton.get_bone_name(parent)).contains(pattern)):
				_pose.scaled_bones[b] = bone_scale[pattern]
	skeleton.add_child(_pose)
	_setup_springs()
	_trail = AttackTrail.new()
	_trail.name = "AttackTrail"
	add_child(_trail)


## Colas, antenas y orejas: cadenas de huesos con muelle, encima del clip (arrastran y rebotan con el movimiento).
func _setup_springs() -> void:
	var chains: Array = []
	for b in skeleton.get_bone_count():
		if not _is_spring_bone(b):
			continue
		var parent := skeleton.get_bone_parent(b)
		if parent >= 0 and _is_spring_bone(parent):
			continue
		var end := b
		while true:
			var next := -1
			for c in skeleton.get_bone_children(end):
				if _is_spring_bone(c):
					next = c
					break
			if next < 0:
				break
			end = next
		chains.append([b, end])
	if chains.is_empty():
		return
	_springs = SpringBoneSimulator3D.new()
	_springs.name = "Springs"
	skeleton.add_child(_springs)
	_springs.setting_count = chains.size()
	for i in chains.size():
		_springs.set_root_bone(i, chains[i][0])
		_springs.set_end_bone(i, chains[i][1])
		if chains[i][0] == chains[i][1]:
			_springs.set_extend_end_bone(i, true)
			_springs.set_end_bone_length(i, 0.2)
		_springs.set_stiffness(i, spring_stiffness)
		_springs.set_drag(i, spring_drag)
		_springs.set_gravity(i, 0.0)


func _is_spring_bone(b: int) -> bool:
	var n := String(skeleton.get_bone_name(b))
	for p in spring_patterns:
		if n.contains(p):
			return true
	return false


func _process(delta: float) -> void:
	if _springs and delta > 0.0:
		# El simulador parte del reposo del hueso y descarta lo que anima el clip: en ataques y habilidades se
		# apaga para que se vea el coletazo; al volver a moverse, la cola recupera el muelle.
		var s := String(current_action)
		var animated := s.begins_with("attack") or s.begins_with("skill")
		_springs.influence = move_toward(_springs.influence, 0.0 if animated else 1.0, delta * 7.0)
	if not motion_enabled or _pivot == null or delta <= 0.0:
		return
	var xf := get_global_transform_interpolated()
	var yaw := xf.basis.get_euler().y
	if not _has_prev:
		_has_prev = true
		_prev_pos = xf.origin
		_prev_yaw = yaw
	var v := (xf.origin - _prev_pos) / delta
	_prev_pos = xf.origin
	if v.length() > 40.0:
		v = Vector3.ZERO  # teletransporte
	_vel = _vel.lerp(v, 1.0 - exp(-16.0 * delta))
	_acc = _acc.lerp((_vel - _prev_vel) / delta, 1.0 - exp(-9.0 * delta))
	_prev_vel = _vel
	_yaw_rate = lerpf(_yaw_rate, angle_difference(_prev_yaw, yaw) / delta, 1.0 - exp(-10.0 * delta))
	_prev_yaw = yaw
	# En el espacio del personaje (adelante = -Z).
	var inv := Basis(Vector3.UP, yaw).inverse()
	var lv := inv * _vel
	var la := inv * _acc
	var pitch := clampf(la.z * 0.008 + lv.z * 0.009, -0.15, 0.15)
	var roll := clampf(_yaw_rate * maxf(-lv.z, 0.0) * 0.0035 - la.x * 0.008 - lv.x * 0.01, -0.16, 0.16)
	_lean = _lean.lerp(Vector2(pitch, roll) * lean_scale, 1.0 - exp(-9.0 * delta))
	var tilt := Vector3(_lean.x, 0.0, _lean.y)
	if _pose:
		tilt += _pose.flinch_amount() * 0.35  # el golpe también ladea el cuerpo entero
	_pivot.rotation = tilt
	# Aplastar / estirar: velocidad vertical (salto) + impulsos con rebote (aterrizar, golpes).
	var was_falling := _stretch < -0.04
	_stretch = lerpf(_stretch, clampf(_vel.y * 0.016, -0.1, 0.14), 1.0 - exp(-12.0 * delta))
	if was_falling and v.y > -0.5:
		_squash_vel -= 2.2
		_stretch = 0.0
	_squash_vel += (-200.0 * _squash - 17.0 * _squash_vel) * delta
	_squash += _squash_vel * delta
	var k := clampf(1.0 + _squash + _stretch, 0.7, 1.3)
	var side := 1.0 / sqrt(k)
	_pivot.scale = Vector3(side, k, side)


## Para cada clip de ataque busca el instante en que el cuerpo llega más lejos hacia delante (el impacto) y
## qué hueso es. El Beast lo usa para clavar ese instante en la ventana activa del ataque.
func _analyze_attacks() -> void:
	if anim_player == null or skeleton == null:
		return
	var key := model_scene.resource_path
	if _impact_cache.has(key):
		_impacts = _impact_cache[key]
		return
	var fwd := _relative_transform(skeleton).basis.orthonormalized().inverse() * Vector3(0, 0, 1)
	var bones: Array[int] = []
	for b in skeleton.get_bone_count():
		var n := String(skeleton.get_bone_name(b))
		if not (n.containsn("camera") or n.containsn("skin") or n.containsn("origin") or n.containsn("root")
				or n.containsn("tongue") or n.containsn("feeler") or n.containsn("ear") or n.containsn("jaw")):
			bones.append(b)
	for action: StringName in action_map:
		if not String(action).begins_with("attack"):
			continue
		var clip: StringName = action_map[action]
		if _impacts.has(clip) or not anim_player.has_animation(clip):
			continue
		var length := anim_player.get_animation(clip).length
		anim_player.play(clip, 0.0)
		# Avance de cada hueso respecto al inicio del clip: gana el que más se lanza hacia delante.
		anim_player.seek(0.0, true)
		var start := {}
		for b in bones:
			start[b] = skeleton.get_bone_global_pose(b).origin.dot(fwd)
		var tail_attack := String(clip).containsn("tail")
		var best := -INF
		var best_t := length * 0.45
		var best_bone := -1
		var steps := 36
		for i in steps:
			var t := length * lerpf(0.15, 0.85, i / float(steps - 1))
			anim_player.seek(t, true)
			for b in bones:
				if not tail_attack and String(skeleton.get_bone_name(b)).containsn("tail"):
					continue
				var reach: float = skeleton.get_bone_global_pose(b).origin.dot(fwd) - start[b]
				if reach > best:
					best = reach
					best_t = t
					best_bone = b
		_impacts[clip] = [best_t, best_bone]
	anim_player.stop()
	_impact_cache[key] = _impacts


# --- Materiales ---------------------------------------------------------------

func _fix_materials() -> void:
	var preset: Dictionary = SURFACES.get(surface, SURFACES[&"skin"])
	var shader: Shader = load("res://actors/visuals/character.gdshader")
	var detail: Texture2D = load("res://assets/textures/characters/%s.png" % preset.detail)
	for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var n := mat.resource_name
			if n.begins_with("FireCore") or n.begins_with("FireSten"):
				m.set_surface_override_material(i, _fire_material(mat, n.begins_with("FireCore")))
			elif mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
					or (face_surface == &"" and (n.containsn("eye") or n.containsn("iris"))):
				# Ojos y piezas con recorte: material original, pero brillante (ojo húmedo).
				var eye := mat.duplicate() as BaseMaterial3D
				eye.roughness = 0.12
				eye.metallic = 0.0
				eye.metallic_specular = 0.7
				m.set_surface_override_material(i, eye)
			else:
				var look := preset
				var look_detail := detail
				if face_surface != &"" and (n.containsn("eye") or n.containsn("iris")):
					look = SURFACES.get(face_surface, preset)
					look_detail = load("res://assets/textures/characters/%s.png" % look.detail)
				var body := ShaderMaterial.new()
				body.shader = shader
				body.set_shader_parameter(&"albedo_tex", mat.albedo_texture)
				body.set_shader_parameter(&"albedo_color", mat.albedo_color)
				body.set_shader_parameter(&"detail_tex", look_detail)
				for key: StringName in look:
					if key != &"detail":
						body.set_shader_parameter(key, look[key])
				if mat.cull_mode == BaseMaterial3D.CULL_DISABLED:
					body.render_priority = 0
				m.set_surface_override_material(i, body)


## Llama de la cola: aditiva y emisiva para que el bloom la haga brillar.
func _fire_material(src: BaseMaterial3D, core: bool) -> StandardMaterial3D:
	var fire := StandardMaterial3D.new()
	fire.albedo_texture = src.albedo_texture
	fire.albedo_color = Color(1.0, 0.85, 0.35) if core else Color(1.0, 0.45, 0.1)
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire.cull_mode = BaseMaterial3D.CULL_DISABLED
	fire.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fire.emission_enabled = true
	fire.emission = fire.albedo_color
	fire.emission_energy_multiplier = 3.0 if core else 2.0
	return fire


# --- Escala y apoyo en el suelo ------------------------------------------------

func _fit_to_height() -> void:
	var aabb := AABB()
	var first := true
	for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var a := _skinned_aabb(m)
		aabb = a if first else aabb.merge(a)
		first = false
	if first or aabb.size.y <= 0.0:
		return
	var s := target_height / aabb.size.y
	model.scale = Vector3.ONE * s
	model.position.y = -aabb.position.y * s


## AABB de la malla deformada por la pose actual, relativa al modelo (muestrea ~2000 vértices).
func _skinned_aabb(m: MeshInstance3D) -> AABB:
	var skel := m.get_node_or_null(m.skeleton) as Skeleton3D
	if m.skin == null or skel == null:
		return _relative_transform(m) * m.get_aabb()
	var binds: Array[Transform3D] = []
	for b in m.skin.get_bind_count():
		var bone := m.skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(m.skin.get_bind_name(b))
		binds.append(skel.get_bone_global_pose(bone) * m.skin.get_bind_pose(b))
	var to_model := _relative_transform(skel)
	var aabb := AABB()
	var first := true
	for surface in m.mesh.get_surface_count():
		var arrays := m.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones.is_empty():
			continue
		var per := bones.size() / verts.size()
		for i in range(0, verts.size(), maxi(1, verts.size() / 2000)):
			var p := Vector3.ZERO
			for k in per:
				var w := weights[i * per + k]
				if w > 0.0:
					p += (binds[bones[i * per + k]] * verts[i]) * w
			p = to_model * p
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb


## Transformación de `node` relativa a `model` (sin la escala/posición que se le aplica al ajustar).
func _relative_transform(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != model and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

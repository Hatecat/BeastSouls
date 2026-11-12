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

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var current_action: StringName = &""

var _socket_nodes: Dictionary[StringName, BoneAttachment3D] = {}
var _flash_mat: StandardMaterial3D
var _flash_tween: Tween


func _ready() -> void:
	if model_scene == null:
		push_error("CharacterVisual: falta model_scene")
		return
	model = model_scene.instantiate()
	add_child(model)
	model.rotation_degrees.y = model_yaw_offset
	var skels := model.find_children("*", "Skeleton3D", true, false)
	skeleton = skels[0] if not skels.is_empty() else null
	var players := model.find_children("*", "AnimationPlayer", true, false)
	anim_player = players[0] if not players.is_empty() else null
	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)
		_setup_loops()
	_fix_materials()
	# Medir en la pose de idle: el reposo de estos modelos no es representativo.
	play(&"idle", 0.0)
	if anim_player:
		anim_player.advance(0.0)
	_fit_to_height()
	_create_sockets()


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


# --- Materiales ---------------------------------------------------------------

func _fix_materials() -> void:
	for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var n := mat.resource_name
			if n.begins_with("FireCore") or n.begins_with("FireSten"):
				m.set_surface_override_material(i, _fire_material(mat, n.begins_with("FireCore")))
			else:
				var body := mat.duplicate() as BaseMaterial3D
				body.roughness = 0.7
				body.metallic = 0.0
				# Un poco de luz de contorno para que el personaje se lea sobre el escenario.
				body.rim_enabled = true
				body.rim = 0.35
				body.rim_tint = 0.6
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

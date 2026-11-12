class_name ThirdPersonCamera
extends Node3D
## Cámara en tercera persona al estilo Dark Souls.
##
## Estructura: este nodo (yaw, sigue al personaje) → Pitch (inclinación) → SpringArm3D (choca
## con el escenario) → Camera3D. Con objetivo fijado la cámara mira entre el jugador y el rival.
## Se mueve en `_process` (frecuencia de pantalla) leyendo la posición interpolada del personaje.

signal lock_changed(target: Node3D)

@export var follow: Beast
var _base_framing := {}
@export_group("Encuadre")
@export var height := 1.8
@export var distance := 4.6
@export var lock_distance := 6.0
## Altura del punto de mira al fijar objetivo (más alta para ver por encima de las alas).
@export var lock_height := 2.2
## Desplazamiento lateral (m, a la derecha) del punto de mira: cámara "sobre el hombro".
@export var shoulder_offset := 0.3
@export var lock_shoulder_offset := 1.0
## Suavizado del seguimiento (mayor = más pegado al personaje).
@export var follow_sharpness := 12.0
@export_range(-89, 0) var pitch_min_deg := -65.0
@export_range(0, 89) var pitch_max_deg := 40.0
@export_group("Control")
@export var mouse_sensitivity := 0.0025
@export var stick_speed := Vector2(3.2, 2.2)
@export var invert_y := false
@export_group("Fijar objetivo")
@export var lock_range := 22.0
@export var lock_break_range := 30.0
## Cono (grados, desde el centro de la cámara) en el que se buscan objetivos.
@export var lock_cone_deg := 60.0
@export var lock_sharpness := 8.0
## Inclinación extra hacia abajo al fijar (radianes).
@export var lock_pitch_offset := -0.12
@export var lock_pitch_min_deg := -25.0
@export var lock_pitch_max_deg := 10.0
## Segundos que el objetivo puede estar tapado antes de soltarlo.
@export var lock_occlusion_grace := 2.0
## Píxeles de ratón en horizontal que cuentan como "gesto" para cambiar de objetivo.
@export var flick_pixels := 120.0
@export var recenter_sharpness := 10.0
@export_group("Vibración")
## Desplazamiento máximo (m) y giro máximo (rad) con la vibración al máximo.
@export var shake_offset := 0.18
@export var shake_roll := 0.05
@export var shake_decay := 2.2
@export_group("Desvanecer personaje")
## Longitud del brazo a la que el personaje empieza a volverse transparente…
@export var fade_far := 2.0
## …y a la que alcanza la transparencia máxima.
@export var fade_near := 0.9
## Transparencia del personaje cuando tapa en pantalla al objetivo fijado.
@export var occlude_target_fade := 0.55
## Distancia en pantalla (fracción del alto) entre ambos por debajo de la cual se considera que lo tapa.
@export var occlude_screen_radius := 0.22

@onready var pitch_node: Node3D = $Pitch
@onready var arm: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D

var yaw := 0.0
var pitch := deg_to_rad(-15.0)
var lock_target: Node3D = null

var _recentering := 0.0
var _flick := 0.0
var _flick_cooldown := 0.0
var _occluded := 0.0
var _indicator: Label3D
var _snapped := false
var _fade := 0.0
var _shoulder := 0.0
var _height := 0.0
var _trauma := 0.0
var _shake_time := 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	top_level = true
	# La cámara se mueve en _process; la interpolación física no debe tocarla.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arm.collision_mask = 1  # solo el escenario; los personajes no empujan la cámara
	arm.spring_length = distance
	_indicator = _make_indicator()
	add_child(_indicator)


## Coloca la cámara detrás del personaje al instante.
## Escala el encuadre (altura y distancia, libre y fijado) para personajes más grandes o pequeños.
func fit_to_size(scale: float) -> void:
	if _base_framing.is_empty():
		_base_framing = {height = height, distance = distance, lock_distance = lock_distance, lock_height = lock_height}
	height = _base_framing.height * scale
	distance = _base_framing.distance * scale
	lock_distance = _base_framing.lock_distance * scale
	lock_height = _base_framing.lock_height * scale


func snap_behind() -> void:
	if follow == null:
		return
	yaw = follow.facing
	_snapped = false


func toggle_lock() -> void:
	if lock_target:
		_set_lock(null)
		return
	var t := _find_target(null)
	if t:
		_set_lock(t)
	else:
		# Sin objetivos: recentrar detrás del personaje, como en Dark Souls.
		_recentering = 0.35


## Cambia al siguiente objetivo hacia la izquierda (-1) o derecha (+1) de la pantalla.
func switch_target(dir: int) -> void:
	if lock_target == null:
		return
	var cur_x := camera.unproject_position(_lock_pos(lock_target)).x
	var best: Node3D = null
	var best_dx := INF
	for n in _candidates(lock_target):
		var dx := (camera.unproject_position(_lock_pos(n)).x - cur_x) * dir
		if dx > 0.0 and dx < best_dx:
			best_dx = dx
			best = n
	if best:
		_set_lock(best)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.screen_relative
		if lock_target:
			_flick += rel.x
		else:
			var sens := mouse_sensitivity * Settings.mouse_sensitivity
			yaw -= rel.x * sens
			pitch -= rel.y * sens * _y_sign()


## Invertir Y: el export de la escena y la opción del jugador se combinan.
func _y_sign() -> float:
	return -1.0 if invert_y != Settings.invert_y else 1.0


func _process(delta: float) -> void:
	if follow == null:
		return
	_flick_cooldown -= delta
	var look := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")

	if lock_target:
		_validate_lock(delta)
	if lock_target:
		# Gesto con ratón o stick para cambiar de objetivo.
		if _flick_cooldown <= 0.0:
			var dir := 0
			if absf(_flick) > flick_pixels:
				dir = signi(int(_flick))
			elif absf(look.x) > 0.8:
				dir = signi(int(signf(look.x)))
			if dir != 0:
				switch_target(dir)
				_flick_cooldown = 0.35
				_flick = 0.0
		_flick = move_toward(_flick, 0.0, flick_pixels * 4.0 * delta)
		_track_target(delta)
	else:
		yaw -= look.x * stick_speed.x * Settings.stick_sensitivity * delta
		pitch -= look.y * stick_speed.y * Settings.stick_sensitivity * delta * _y_sign()
		if _recentering > 0.0:
			_recentering -= delta
			var k := 1.0 - exp(-recenter_sharpness * delta)
			yaw = lerp_angle(yaw, follow.facing, k)
			pitch = lerp_angle(pitch, deg_to_rad(-15.0), k)

	pitch = clampf(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	yaw = wrapf(yaw, -PI, PI)

	var k_frame := 1.0 - exp(-4.0 * delta)
	_shoulder = lerpf(_shoulder, lock_shoulder_offset if lock_target else shoulder_offset, k_frame)
	_height = lerpf(_height, lock_height if lock_target else height, k_frame)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var anchor := follow.get_global_transform_interpolated().origin + Vector3.UP * _height + right * _shoulder
	if not _snapped:
		_shoulder = shoulder_offset
		_height = height
		global_position = anchor
		_snapped = true
	else:
		global_position = global_position.lerp(anchor, 1.0 - exp(-follow_sharpness * delta))
	rotation = Vector3(0.0, yaw, 0.0)
	pitch_node.rotation = Vector3(pitch, 0.0, 0.0)
	var want_len := lock_distance if lock_target else distance
	arm.spring_length = lerpf(arm.spring_length, want_len, k_frame)
	_update_indicator()
	_update_fade()
	_update_shake(delta)


# --- Fijar objetivo -----------------------------------------------------------------

func _track_target(delta: float) -> void:
	var player := follow.get_global_transform_interpolated().origin
	var target := _lock_pos(lock_target)
	var to := target - player
	to.y = 0.0
	if to.length_squared() > 0.01:
		var k := 1.0 - exp(-lock_sharpness * delta)
		yaw = lerp_angle(yaw, Beast.yaw_of(to), k)
		# Inclinación medida desde donde está la cámara (detrás del personaje), no desde su cabeza:
		# así el ángulo es suave aunque el rival esté muy cerca.
		var eye := player + Vector3.UP * _height
		var d := target - eye
		var horizontal := Vector2(d.x, d.z).length() + arm.spring_length
		var want_pitch := clampf(atan2(d.y, horizontal) + lock_pitch_offset, deg_to_rad(lock_pitch_min_deg), deg_to_rad(lock_pitch_max_deg))
		pitch = lerp_angle(pitch, want_pitch, k)


func _validate_lock(delta: float) -> void:
	var t := lock_target
	if not is_instance_valid(t) or not t.is_inside_tree() or (t.has_method("is_dead") and t.is_dead()):
		_set_lock(null)
		return
	if follow.global_position.distance_to(t.global_position) > lock_break_range:
		_set_lock(null)
		return
	_occluded = _occluded + delta if _is_occluded(_lock_pos(t)) else 0.0
	if _occluded > lock_occlusion_grace:
		_set_lock(null)


func _set_lock(t: Node3D) -> void:
	lock_target = t
	_occluded = 0.0
	_flick = 0.0
	lock_changed.emit(t)


func _find_target(exclude: Node3D) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var cam_fwd := -camera.global_basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	for n in _candidates(exclude):
		var to := _lock_pos(n) - follow.global_position
		to.y = 0.0
		var angle := cam_fwd.angle_to(to.normalized())
		if angle > deg_to_rad(lock_cone_deg):
			continue
		var score := angle * 2.0 + to.length() * 0.05
		if score < best_score:
			best_score = score
			best = n
	return best


## Objetivos posibles: en el grupo "lockable", vivos, a rango y visibles.
func _candidates(exclude: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n: Node in get_tree().get_nodes_in_group(&"lockable"):
		if n == follow or n == exclude or not n is Node3D or not n.is_inside_tree():
			continue
		if n.has_method("is_dead") and n.is_dead():
			continue
		var p := _lock_pos(n)
		if follow.global_position.distance_to(p) > lock_range:
			continue
		if camera.is_position_behind(p) or _is_occluded(p):
			continue
		out.append(n)
	return out


func _lock_pos(n: Node3D) -> Vector3:
	return n.get_lock_position() if n.has_method("get_lock_position") else n.global_position + Vector3.UP


func _is_occluded(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(camera.global_position, p, 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Añade vibración (0..1). Se acumula y se desvanece sola; su intensidad es trauma².
func add_shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _update_shake(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - shake_decay * delta)
	_shake_time += delta * 60.0
	var k := _trauma * _trauma
	camera.h_offset = shake_offset * k * _noise.get_noise_2d(_shake_time, 0.0)
	camera.v_offset = shake_offset * k * _noise.get_noise_2d(0.0, _shake_time)
	camera.rotation.z = shake_roll * k * _noise.get_noise_2d(_shake_time, 100.0)


## Si una pared empuja la cámara hasta el personaje, este se vuelve transparente para no tapar la vista.
func _update_fade() -> void:
	var fade := clampf(remap(arm.get_hit_length(), fade_far, fade_near, 0.0, 0.85), 0.0, 0.85)
	if lock_target and not camera.is_position_behind(_lock_pos(lock_target)):
		# El personaje tapa al rival: se vuelve semitransparente para ver sus ataques.
		var a := camera.unproject_position(follow.get_lock_position())
		var b := camera.unproject_position(_lock_pos(lock_target))
		var screen_h := get_viewport().get_visible_rect().size.y
		var closer := camera.global_position.distance_to(follow.global_position) < camera.global_position.distance_to(lock_target.global_position)
		if closer and a.distance_to(b) < occlude_screen_radius * screen_h:
			fade = maxf(fade, occlude_target_fade)
	# Suavizado para que no parpadee al entrar/salir.
	var smoothed := move_toward(_fade, fade, get_process_delta_time() * 3.0)
	if not is_equal_approx(smoothed, _fade):
		_fade = smoothed
		follow.visual.set_fade(_fade)


# --- Indicador ----------------------------------------------------------------------

func _make_indicator() -> Label3D:
	var l := Label3D.new()
	l.text = "●"
	l.font_size = 64
	l.outline_size = 18
	l.modulate = Color(1.0, 0.95, 0.85)
	l.outline_modulate = Color(0.15, 0.05, 0.0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0004
	l.render_priority = 10
	l.top_level = true
	l.visible = false
	return l


func _update_indicator() -> void:
	_indicator.visible = lock_target != null
	if lock_target:
		_indicator.global_position = _lock_pos(lock_target)

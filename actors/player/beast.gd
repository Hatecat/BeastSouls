class_name Beast
extends CharacterBody3D
## Una bestia jugable: simulación de movimiento, esquiva y estamina.
##
## La simulación (`simulate`) solo depende de un PlayerInput y del delta, nunca de `Input`:
## así la puede alimentar el jugador local, una IA o (Fase 5) la red.
## La presentación (animaciones, giro del modelo) va aparte en `_update_presentation`.

signal state_changed(old_state: State, new_state: State)

enum State { LOCOMOTION, DODGE, DEAD }

@export_group("Movimiento")
@export var jog_speed := 4.5
@export var sprint_speed := 7.5
## Velocidad al moverse con un objetivo fijado (caminar de lado / hacia atrás).
@export var strafe_speed := 3.2
@export var acceleration := 12.0
@export var deceleration := 16.0
## Rapidez de giro hacia la dirección deseada (mayor = más brusco).
@export var turn_speed := 12.0
@export var gravity := 22.0

@export_group("Esquiva")
@export var dodge_distance := 4.5
@export var dodge_duration := 0.6
## Ventana de invulnerabilidad (segundos desde el inicio): x = desde, y = hasta.
@export var dodge_iframes := Vector2(0.04, 0.38)
@export var backstep_distance := 2.2
@export var backstep_duration := 0.4
@export var backstep_iframes := Vector2(0.03, 0.2)
## Tramo final de la esquiva en el que ya se puede encadenar otra.
@export var dodge_recovery := 0.12

@export_group("Recursos")
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var stamina_regen := 45.0
@export var stamina_regen_delay := 0.6
@export var sprint_cost := 14.0
@export var dodge_cost := 22.0
## Tras vaciar la estamina corriendo, no se puede volver a correr hasta recuperar esto.
@export var exhausted_threshold := 20.0
## Tiempo que se recuerda una pulsación que aún no se pudo ejecutar (input buffer).
@export var input_buffer_time := 0.25

@export_group("Presentación")
## Velocidad (m/s) a la que el clip de caminar se ve natural con speed_scale 1.
@export var walk_anim_speed := 2.6
## Velocidad (m/s) a la que el clip de correr se ve natural con speed_scale 1.
@export var run_anim_speed := 7.0

@onready var visual: CharacterVisual = $Visual
@onready var lock_point: Marker3D = $LockPoint

## Input del tick actual. El controlador (local, IA o red) lo reemplaza cada tick.
var input := PlayerInput.new()
var state := State.LOCOMOTION
var state_time := 0.0
## Hacia dónde mira (yaw, radianes). Adelante = -Z girado `facing`.
var facing := 0.0
var health := 0.0
var stamina := 0.0
var sprinting := false
var locked_on := false

var _exhausted := false
var _regen_wait := 0.0
var _dodge_dir := Vector3.ZERO
var _dodge_distance := 0.0
var _dodge_duration := 0.0
var _dodge_iframes := Vector2.ZERO
var _buffered := 0
var _buffer_time := 0.0
var _anim := &""


func _ready() -> void:
	add_to_group(&"beasts")
	add_to_group(&"lockable")
	health = max_health
	stamina = max_stamina
	# La rotación del nodo en el editor solo marca la orientación inicial; el cuerpo no rota.
	facing = rotation.y
	rotation.y = 0.0
	_update_presentation()


func _physics_process(delta: float) -> void:
	simulate(input, delta)
	# El input dura un solo tick: si el controlador deja de mandarlo, el personaje se queda quieto.
	# (En la Fase 5, para el rival remoto, se repetirá el último input recibido como predicción.)
	input = PlayerInput.new()


## Avanza la simulación un tick.
func simulate(inp: PlayerInput, delta: float) -> void:
	state_time += delta
	_update_buffer(inp, delta)
	locked_on = is_instance_valid(inp.lock_target) and inp.lock_target != self
	match state:
		State.LOCOMOTION:
			_tick_locomotion(inp, delta)
		State.DODGE:
			_tick_dodge(inp, delta)
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	_tick_stamina(delta)
	_update_presentation()


# --- Consultas -------------------------------------------------------------------

func is_invulnerable() -> bool:
	return state == State.DODGE and state_time >= _dodge_iframes.x and state_time <= _dodge_iframes.y


func is_dead() -> bool:
	return state == State.DEAD


func get_lock_position() -> Vector3:
	return lock_point.global_position


func forward() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


# --- Estados ---------------------------------------------------------------------

func _set_state(new_state: State) -> void:
	var old := state
	state = new_state
	state_time = 0.0
	state_changed.emit(old, new_state)


func _tick_locomotion(inp: PlayerInput, delta: float) -> void:
	var dir := inp.move_3d()
	var amount := minf(dir.length(), 1.0)
	sprinting = inp.is_held(PlayerInput.SPRINT) and amount > 0.3 and not _exhausted and stamina > 0.0
	if _try_dodge(inp):
		return
	var speed := sprint_speed if sprinting else (strafe_speed if locked_on else jog_speed)
	var desired := dir.normalized() * amount * speed if amount > 0.01 else Vector3.ZERO
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if desired.length() > h.length() else deceleration
	h = h.lerp(desired, 1.0 - exp(-rate * delta))
	velocity.x = h.x
	velocity.z = h.z
	if locked_on and not sprinting:
		_face_towards(inp.lock_target.global_position - global_position, delta)
	elif amount > 0.05:
		_face_towards(dir, delta)


func _try_dodge(inp: PlayerInput) -> bool:
	if _buffered & PlayerInput.DODGE == 0 or stamina <= 0.0:
		return false
	_buffered &= ~PlayerInput.DODGE
	var dir := inp.move_3d()
	if dir.length() < 0.2:
		# Sin dirección: paso atrás corto.
		_dodge_dir = -forward()
		_dodge_distance = backstep_distance
		_dodge_duration = backstep_duration
		_dodge_iframes = backstep_iframes
	else:
		_dodge_dir = dir.normalized()
		_dodge_distance = dodge_distance
		_dodge_duration = dodge_duration
		_dodge_iframes = dodge_iframes
		facing = yaw_of(_dodge_dir)
	sprinting = false
	_anim = &""  # para que una esquiva encadenada reinicie el clip
	_spend_stamina(dodge_cost)
	_set_state(State.DODGE)
	return true


func _tick_dodge(inp: PlayerInput, delta: float) -> void:
	var t := state_time / _dodge_duration
	if t >= 1.0:
		_set_state(State.LOCOMOTION)
		_tick_locomotion(inp, delta)
		return
	# Perfil de velocidad 1 - t²: salida explosiva que se frena al final. Su integral es 2/3,
	# así que el pico es 1.5 * distancia / duración para recorrer exactamente `_dodge_distance`.
	var speed := 1.5 * _dodge_distance / _dodge_duration * (1.0 - t * t)
	velocity.x = _dodge_dir.x * speed
	velocity.z = _dodge_dir.z * speed
	if state_time >= _dodge_duration - dodge_recovery:
		_try_dodge(inp)


func _face_towards(dir: Vector3, delta: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	facing = lerp_angle(facing, yaw_of(dir), 1.0 - exp(-turn_speed * delta))


# --- Recursos ----------------------------------------------------------------------

func _spend_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_regen_wait = stamina_regen_delay


func _tick_stamina(delta: float) -> void:
	if sprinting and horizontal_speed() > 1.0:
		stamina = maxf(0.0, stamina - sprint_cost * delta)
		_regen_wait = stamina_regen_delay * 0.5
	_regen_wait -= delta
	if _regen_wait <= 0.0 and state != State.DODGE:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)
	if stamina <= 0.0:
		_exhausted = true
	elif _exhausted and stamina >= exhausted_threshold:
		_exhausted = false


func _update_buffer(inp: PlayerInput, delta: float) -> void:
	if inp.buttons != 0:
		_buffered |= inp.buttons
		_buffer_time = input_buffer_time
	else:
		_buffer_time -= delta
		if _buffer_time <= 0.0:
			_buffered = 0


# --- Presentación --------------------------------------------------------------------

func _update_presentation() -> void:
	visual.rotation.y = facing
	match state:
		State.DODGE:
			if _anim != &"dodge":
				_play_anim(&"dodge", 0.06)
				# Encaja el clip en la duración de la esquiva.
				visual.set_playback_speed(visual.get_action_length(&"dodge") / _dodge_duration)
		State.DEAD:
			_play_anim(&"death", 0.2)
		State.LOCOMOTION:
			var h := horizontal_speed()
			if h < 0.3:
				_play_anim(&"idle", 0.2)
				visual.set_playback_speed(1.0)
			elif sprinting:
				_play_anim(&"run", 0.2)
				visual.set_playback_speed(h / run_anim_speed)
			else:
				_play_anim(&"walk", 0.2)
				visual.set_playback_speed(h / walk_anim_speed)


func _play_anim(action: StringName, blend: float) -> void:
	if _anim == action:
		return
	_anim = action
	visual.play(action, blend)

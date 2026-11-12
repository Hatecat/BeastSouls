class_name Beast
extends CharacterBody3D
## Una bestia jugable: simulación de movimiento, combate y recursos.
##
## La simulación (`simulate`) solo depende de un PlayerInput y del delta, nunca de `Input`:
## así la puede alimentar el jugador local, una IA o (Fase 5) la red.
## La presentación (animaciones, giro del modelo, efectos) va en `_update_presentation` y en los
## `_fx_*`; nunca decide nada de la partida.

signal state_changed(old_state: State, new_state: State)
## Este Beast ha golpeado a `target` (también al ser bloqueado). En red, si el objetivo es remoto, llega
## cuando su dueño lo confirma (`atk` puede ser null entonces).
signal hit_landed(target: Beast, result: HitResult, atk: AttackData)
## Este Beast ha recibido un golpe de `attacker`.
signal hit_received(attacker: Beast, result: HitResult, damage: float)
signal died
## Ha empezado una habilidad de la ranura `slot`.
signal ability_used(slot: int)
## Petición de vibración de cámara para quien controle a este Beast (rugido, mejoras...).
signal shake_requested(amount: float)

enum State { LOCOMOTION, DODGE, ATTACK, ABILITY, BLOCK, STAGGER, DEAD }
enum HitResult { IGNORED, HIT, STAGGERED, BLOCKED, GUARD_BREAK, KILLED }

## Capa de físicas de las hurtboxes (capa 4 → bit 8).
const HURTBOX_MASK := 8

const ABILITY_SLOTS := 4

## Dibuja las hitboxes activas (F1 en la arena de pruebas).
static var debug_hitboxes := false

@export var moveset: Moveset
## Personaje aplicado (apply_character). Null = lo que trae la escena.
var character: CharacterDef
## Sin control (cuenta atrás, fin de ronda): ignora el input y no recibe golpes.
var frozen := false
## Proxy de un jugador remoto: no simula; su estado llega por la red (NetProxy) y solo se presenta.
## Los golpes A un Beast remoto no se aplican aquí: los decide su dueño (la víctima).
var is_remote := false
## Sube cada vez que empieza una acción (ataque, habilidad, esquiva, aturdimiento, reaparición):
## así el proxy remoto sabe que hay que reiniciar la animación y la lista de golpeados.
var action_seq := 0

@export_group("Movimiento")
@export var jog_speed := 4.5
@export var sprint_speed := 7.5
## Velocidad al moverse con un objetivo fijado (caminar de lado / hacia atrás).
@export var strafe_speed := 3.2
@export var block_speed := 2.0
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
## Tramo final de la esquiva en el que ya se puede encadenar otra acción.
@export var dodge_recovery := 0.12

@export_group("Defensa")
## Postura base: cuánto daño de postura aguanta antes de quedar aturdido.
@export var max_poise := 10.0
@export var poise_regen := 15.0
@export var poise_regen_delay := 1.5
## Fracción de daño que absorbe el bloqueo.
@export var block_absorb := 0.85
## Medio ángulo (grados) del frente que cubre el bloqueo.
@export var block_angle := 75.0
## Retroceso tras bloquear un golpe (no se puede atacar).
@export var block_recoil := 0.25
@export var guard_break_time := 1.2
## Multiplicador de la regeneración de estamina con la guardia alzada.
@export var block_regen_factor := 0.4

@export_group("Recursos")
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var stamina_regen := 45.0
@export var stamina_regen_delay := 0.6
@export var sprint_cost := 14.0
@export var dodge_cost := 22.0
## Salto: velocidad vertical inicial (altura ≈ v²/2g) y coste de estamina.
@export var jump_velocity := 8.0
@export var jump_cost := 12.0
## Tras vaciar la estamina corriendo, no se puede volver a correr hasta recuperar esto.
@export var exhausted_threshold := 20.0
## Tiempo que se recuerda una pulsación que aún no se pudo ejecutar (input buffer).
@export var input_buffer_time := 0.3

@export_group("Calor")
## Recurso de las habilidades: se gana golpeando (AttackData.heat_gain) y recibiendo golpes.
@export var max_heat := 100.0
@export var start_heat := 30.0
@export var heat_on_hit_taken := 5.0
## Daño por segundo de la quemadura.
@export var burn_dps := 3.0

@export_group("Presentación")
## Velocidad (m/s) a la que el clip de caminar se ve natural con speed_scale 1.
@export var walk_anim_speed := 2.6
## Velocidad (m/s) a la que el clip de correr se ve natural con speed_scale 1.
@export var run_anim_speed := 7.0
## Instante (fracción) del clip "block" que se usa como pose de guardia.
@export var block_pose := 0.15

@onready var visual: CharacterVisual = $Visual
@onready var lock_point: Marker3D = $LockPoint
@onready var hurtbox: Area3D = $Hurtbox

## Input del tick actual. El controlador (local, IA o red) lo reemplaza cada tick.
var input := PlayerInput.new()
var state := State.LOCOMOTION
var state_time := 0.0
## Hacia dónde mira (yaw, radianes). Adelante = -Z girado `facing`.
var facing := 0.0
var health := 0.0
var stamina := 0.0
var poise := 0.0
var sprinting := false
var locked_on := false
## Ataque en curso (estado ATTACK).
var attack: AttackData
## Carga acumulada del ataque en curso (segundos).
var charge := 0.0
var heat := 0.0
## Habilidad en curso (estado ABILITY) y su ranura.
var ability: AbilityData
var ability_slot := -1
## Recarga restante de cada ranura de habilidad.
var cooldowns := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## Mejoras activas: {id, time, damage, speed, action, color}.
var buffs: Array[Dictionary] = []
var burn_time := 0.0
## Objetivo fijado en este tick (lo usan las habilidades teledirigidas).
var lock_target: Node3D

var _exhausted := false
var _regen_wait := 0.0
var _poise_wait := 0.0
var _dodge_dir := Vector3.ZERO
var _dodge_distance := 0.0
var _dodge_duration := 0.0
var _dodge_iframes := Vector2.ZERO
var _buffered := 0
var _buffer_time := 0.0
var _combo_chain: Array[AttackData] = []
var _combo_index := -1
var _charge_done := false
var _hit_targets: Array[Beast] = []
var _hitstop := 0.0
var _stagger_duration := 0.0
var _recoil := 0.0
var _knockback := Vector3.ZERO
var _anim := &""
var _step_accum := 0.0
## Este tick se ha saltado: no pegar al suelo (velocity.y = -0.5) antes de despegar.
var _jumped := false
var _was_airborne := false
## Último instante del ataque hasta el que se ha dibujado la estela (-1 = sin empezar).
var _trail_t := -1.0
var _debug_sphere: MeshInstance3D
var _cast := {}
## Valores originales de las estadísticas que ha sobrescrito algún CharacterDef.
var _stat_defaults := {}
var _burn_fx: GPUParticles3D
var _aura_fx: GPUParticles3D


func _ready() -> void:
	add_to_group(&"beasts")
	add_to_group(&"lockable")
	# La rotación del nodo en el editor solo marca la orientación inicial; el cuerpo no rota.
	facing = rotation.y
	rotation.y = 0.0
	revive()


func _physics_process(delta: float) -> void:
	if is_remote:
		return
	simulate(input, delta)
	# El input dura un solo tick: si el controlador deja de mandarlo, el personaje se queda quieto.
	# (En la Fase 5, para el rival remoto, se repetirá el último input recibido como predicción.)
	input = PlayerInput.new()


## Avanza la simulación un tick.
func simulate(inp: PlayerInput, delta: float) -> void:
	if frozen:
		inp = PlayerInput.new()
	_update_buffer(inp, delta)
	if _hitstop > 0.0:
		# Congelado por impacto: no avanza nada salvo el buffer de input.
		_hitstop -= delta
		_update_presentation()
		return
	var acting := state == State.ATTACK or state == State.ABILITY
	var sim_delta := delta * (action_speed_multiplier() if acting else 1.0)
	state_time += sim_delta
	locked_on = is_instance_valid(inp.lock_target) and inp.lock_target != self
	lock_target = inp.lock_target if locked_on else null
	match state:
		State.LOCOMOTION:
			_tick_locomotion(inp, delta)
		State.BLOCK:
			_tick_block(inp, delta)
		State.DODGE:
			_tick_dodge(inp, delta)
		State.ATTACK:
			_tick_attack(inp, sim_delta)
		State.ABILITY:
			_tick_ability(inp, sim_delta, delta)
		State.STAGGER:
			_tick_stagger(inp, delta)
		State.DEAD:
			_brake(delta)
	if _jumped:
		_jumped = false
	elif is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	_tick_resources(delta)
	_update_presentation()


# --- Consultas -------------------------------------------------------------------

func is_invulnerable() -> bool:
	if frozen:
		return true
	return state == State.DODGE and state_time >= _dodge_iframes.x and state_time <= _dodge_iframes.y


func is_dead() -> bool:
	return state == State.DEAD


func is_charging() -> bool:
	return state == State.ATTACK and attack and attack.chargeable and not _charge_done and state_time >= attack.charge_point


func get_lock_position() -> Vector3:
	return lock_point.global_position


func forward() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## Cambia de personaje: modelo, moveset, estadísticas y tamaño del cuerpo. Deja al Beast como recién revivido.
func apply_character(def: CharacterDef) -> void:
	if def == null:
		return
	character = def
	moveset = def.moveset
	# Restaurar lo que cambió el personaje anterior y aplicar lo del nuevo.
	for k: StringName in _stat_defaults:
		set(k, _stat_defaults[k])
	for k: StringName in def.stats:
		if not _stat_defaults.has(k):
			_stat_defaults[k] = get(k)
		set(k, def.stats[k])
	var old := get_node_or_null(^"Visual")
	if old:
		# Liberarlo en el mismo fotograma en que se creó deja materiales colgando en el renderizador:
		# se esconde y se libera un poco después.
		old.name = &"OldVisual"
		old.visible = false
		if is_inside_tree():
			get_tree().create_timer(0.5).timeout.connect(old.queue_free)
		else:
			old.free()
	visual = def.visual.instantiate()
	visual.name = &"Visual"
	add_child(visual)
	# Las formas son subrecursos compartidos entre instancias de beast.tscn: duplicar antes de tocar.
	var shape := $Shape as CollisionShape3D
	var cap := shape.shape.duplicate() as CapsuleShape3D
	cap.radius = def.body_radius
	cap.height = maxf(def.body_height, def.body_radius * 2.0)
	shape.shape = cap
	shape.position.y = cap.height * 0.5
	var hurt := $Hurtbox/Shape as CollisionShape3D
	var hcap := hurt.shape.duplicate() as CapsuleShape3D
	hcap.radius = def.body_radius + 0.1
	hcap.height = cap.height + 0.1
	hurt.shape = hcap
	hurt.position.y = hcap.height * 0.5
	lock_point.position.y = def.lock_height
	for fx in [_burn_fx, _aura_fx, _debug_sphere]:
		if fx:
			fx.queue_free()
	_burn_fx = null
	_aura_fx = null
	_debug_sphere = null
	revive()


## Vuelve a la vida con todo lleno (respawn de la arena de pruebas / nueva ronda).
func revive() -> void:
	health = max_health
	stamina = max_stamina
	poise = max_poise
	heat = start_heat
	for i in ABILITY_SLOTS:
		cooldowns[i] = 0.0
	buffs.clear()
	burn_time = 0.0
	_hitstop = 0.0
	_buffered = 0
	velocity = Vector3.ZERO
	action_seq += 1
	hurtbox.set_deferred(&"monitorable", true)
	_anim = &""
	visual.reset_motion()
	if state != State.LOCOMOTION:
		_set_state(State.LOCOMOTION)
	_update_presentation()


# --- Recibir golpes -------------------------------------------------------------------

## Aplica un golpe de `attacker`. En red lo llamará solo el host (autoridad).
## `source` es de dónde viene el golpe (para el bloqueo y el empuje): el atacante, o el
## proyectil/explosión. Vector3.INF = la posición del atacante.
func receive_hit(attacker: Beast, atk: AttackData, multiplier := 1.0, source := Vector3.INF) -> HitResult:
	if is_dead() or is_invulnerable():
		return HitResult.IGNORED
	if source == Vector3.INF:
		source = attacker.global_position
	var to_attacker := source - global_position
	to_attacker.y = 0.0
	var push_dir := -to_attacker.normalized() if to_attacker.length_squared() > 0.001 else -forward()
	var damage := atk.damage * multiplier
	var result: HitResult
	var front := forward().angle_to(to_attacker) <= deg_to_rad(block_angle)

	if state == State.BLOCK and front and not atk.unblockable:
		damage *= 1.0 - block_absorb
		_spend_stamina(atk.guard_stamina_damage * multiplier)
		health -= damage
		if health <= 0.0:
			result = HitResult.KILLED
		elif stamina <= 0.0:
			result = HitResult.GUARD_BREAK
			_enter_stagger(guard_break_time, push_dir * atk.knockback)
		else:
			result = HitResult.BLOCKED
			_recoil = block_recoil
			_knockback = push_dir * atk.knockback * 0.6
	else:
		health -= damage
		poise -= atk.poise_damage * multiplier
		_poise_wait = poise_regen_delay
		if health <= 0.0:
			result = HitResult.KILLED
		elif poise + _current_hyper_armor() <= 0.0:
			result = HitResult.STAGGERED
			poise = max_poise
			_enter_stagger(atk.stagger_time, push_dir * atk.knockback)
		else:
			result = HitResult.HIT

	if result == HitResult.KILLED:
		health = 0.0
		_die()
	else:
		heat = minf(max_heat, heat + heat_on_hit_taken)
		if atk.burn_time > 0.0 and result != HitResult.BLOCKED:
			burn_time = maxf(burn_time, atk.burn_time)
	_hitstop = atk.hitstop
	hit_received.emit(attacker, result, damage)
	_fx_hit_received(attacker, result)
	return result


func _current_hyper_armor() -> float:
	if state == State.ATTACK and attack and state_time <= attack.active_end:
		return attack.hyper_armor
	return 0.0


func _enter_stagger(duration: float, knock: Vector3) -> void:
	_stagger_duration = duration
	_knockback = knock
	action_seq += 1
	_anim = &""
	_set_state(State.STAGGER)


func _die() -> void:
	_set_state(State.DEAD)
	hurtbox.set_deferred(&"monitorable", false)
	died.emit()


# --- Estados ---------------------------------------------------------------------

func _set_state(new_state: State) -> void:
	var old := state
	if old == State.ABILITY and ability:
		# Interrumpida o terminada: que limpie sus efectos.
		ability.finish(self, _cast)
		ability = null
		ability_slot = -1
	state = new_state
	state_time = 0.0
	if new_state != State.ATTACK:
		attack = null
	state_changed.emit(old, new_state)


func _tick_locomotion(inp: PlayerInput, delta: float) -> void:
	var dir := inp.move_3d()
	var amount := minf(dir.length(), 1.0)
	sprinting = inp.is_held(PlayerInput.SPRINT) and amount > 0.3 and not _exhausted and stamina > 0.0
	if not is_on_floor():
		# En el aire: solo control de dirección; lo pulsado queda en el buffer para el aterrizaje.
		_steer(dir, amount, (sprint_speed if sprinting else jog_speed) * speed_multiplier(), delta * 0.35)
		return
	if _try_jump():
		return
	if _try_actions(inp):
		return
	if inp.is_held(PlayerInput.BLOCK):
		sprinting = false
		_set_state(State.BLOCK)
		_tick_block(inp, delta)
		return
	var speed := sprint_speed if sprinting else (strafe_speed if locked_on else jog_speed)
	_steer(dir, amount, speed * speed_multiplier(), delta)
	if locked_on and not sprinting:
		_face_towards(inp.lock_target.global_position - global_position, delta)
	elif amount > 0.05:
		_face_towards(dir, delta)


func _tick_block(inp: PlayerInput, delta: float) -> void:
	sprinting = false
	if _recoil > 0.0:
		# Retroceso de un golpe bloqueado: solo se puede esquivar.
		_recoil -= delta
		_knockback = _knockback.move_toward(Vector3.ZERO, 12.0 * delta)
		velocity.x = _knockback.x
		velocity.z = _knockback.z
		_try_dodge(inp)
		return
	if not inp.is_held(PlayerInput.BLOCK):
		_set_state(State.LOCOMOTION)
		return
	if _try_actions(inp):
		return
	var dir := inp.move_3d()
	_steer(dir, minf(dir.length(), 1.0), block_speed * speed_multiplier(), delta)
	if locked_on:
		_face_towards(inp.lock_target.global_position - global_position, delta)
	elif dir.length() > 0.05:
		_face_towards(dir, delta)


func _try_jump() -> bool:
	if _buffered & PlayerInput.JUMP == 0 or stamina <= 0.0 or _exhausted:
		return false
	_buffered &= ~PlayerInput.JUMP
	velocity.y = jump_velocity
	_jumped = true
	_spend_stamina(jump_cost)
	Sfx.play("dodge", global_position + Vector3.UP, -6.0, 1.25 * _voice_pitch())
	return true


func is_airborne() -> bool:
	if is_remote:
		return absf(velocity.y) > 1.0
	return not is_on_floor() or _jumped


## Intenta empezar una acción con lo que hay en el buffer: ataque o esquiva.
func _try_actions(inp: PlayerInput) -> bool:
	return _try_attack(inp) or _try_ability(inp) or _try_dodge(inp)


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
	_combo_index = -1
	action_seq += 1
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
		_try_actions(inp)


# --- Ataques ------------------------------------------------------------------------

func _try_attack(inp: PlayerInput) -> bool:
	if moveset == null or stamina <= 0.0:
		return false
	var kind := 0
	if _buffered & PlayerInput.LIGHT:
		kind = PlayerInput.LIGHT
	elif _buffered & PlayerInput.HEAVY:
		kind = PlayerInput.HEAVY
	else:
		return false
	var atk: AttackData
	if kind == PlayerInput.LIGHT and sprinting and moveset.running_attack:
		atk = moveset.running_attack
		_combo_index = -1
	else:
		var chain := moveset.light_combo if kind == PlayerInput.LIGHT else moveset.heavy_combo
		if chain.is_empty():
			return false
		# Se continúa el combo solo si venimos de un ataque del mismo tipo.
		var continuing := state == State.ATTACK and _combo_chain == chain and _combo_index >= 0
		_combo_index = (_combo_index + 1) % chain.size() if continuing else 0
		_combo_chain = chain
		atk = chain[_combo_index]
	_buffered &= ~kind
	_start_attack(atk, inp)
	return true


func _start_attack(atk: AttackData, inp: PlayerInput) -> void:
	# Orientación inicial: al objetivo fijado o hacia donde apunta el stick.
	if locked_on:
		var to := inp.lock_target.global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.01:
			facing = yaw_of(to)
	elif inp.move.length() > 0.2:
		facing = yaw_of(inp.move_3d())
	sprinting = false
	_spend_stamina(atk.stamina_cost)
	_set_state(State.ATTACK)
	attack = atk
	action_seq += 1
	charge = 0.0
	_charge_done = not atk.chargeable
	_hit_targets.clear()
	_anim = &""


func _tick_attack(inp: PlayerInput, delta: float) -> void:
	var a := attack
	# Carga: el ataque se congela en charge_point mientras se mantenga el botón.
	if not _charge_done and state_time >= a.charge_point:
		if inp.is_held(PlayerInput.HEAVY_HELD) and charge < a.max_charge:
			charge += delta
			state_time = a.charge_point
		else:
			_charge_done = true
	# Seguimiento del objetivo durante la anticipación.
	if state_time < a.active_start and a.tracking > 0.0:
		var want := Vector3.ZERO
		if locked_on:
			want = inp.lock_target.global_position - global_position
		elif inp.move.length() > 0.2:
			want = inp.move_3d()
		want.y = 0.0
		if want.length_squared() > 0.001:
			facing = rotate_toward(facing, yaw_of(want), a.tracking * delta)
	# Embestida.
	if state_time >= a.lunge_start and state_time <= a.lunge_end and not is_charging():
		var f := forward() * a.lunge_speed
		velocity.x = f.x
		velocity.z = f.z
	else:
		_brake(delta)
	# Golpe.
	if a.is_active_at(state_time):
		_check_hits(a)
	# Salidas.
	if state_time >= a.combo_start and _try_attack(inp):
		return
	if state_time >= a.cancel_start and (_try_dodge(inp) or _try_ability(inp)):
		return
	if state_time >= a.duration:
		_set_state(State.LOCOMOTION)


## Multiplicador por carga del ataque en curso.
func charge_multiplier() -> float:
	if attack == null or not attack.chargeable or attack.max_charge <= 0.0:
		return 1.0
	return lerpf(1.0, attack.charge_multiplier, clampf(charge / attack.max_charge, 0.0, 1.0))


func hitbox_center() -> Vector3:
	if attack == null:
		return global_position
	return global_position + Basis(Vector3.UP, facing) * attack.hitbox_offset_at(state_time)


func _check_hits(a: AttackData) -> void:
	var shape := SphereShape3D.new()
	shape.radius = a.hitbox_radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, hitbox_center())
	q.collision_mask = HURTBOX_MASK
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var victim := (r.collider as Node).get_parent() as Beast
		if victim == null or victim == self or victim in _hit_targets:
			continue
		var result := deal_hit(victim, a, Vector3.INF, charge_multiplier())
		if result == HitResult.IGNORED:
			continue  # esquivado: si sigue dentro tras las i-frames, puede alcanzarle
		_hit_targets.append(victim)
		_hitstop = a.hitstop


## Aplica un golpe de este Beast a `victim` (ataques, habilidades, proyectiles).
## Aplica las mejoras de daño, da Calor y emite `hit_landed`.
func deal_hit(victim: Beast, atk: AttackData, source := Vector3.INF, multiplier := 1.0) -> HitResult:
	if victim.is_remote:
		# En red decide la víctima, en su máquina; aquí llegará su confirmación (confirm_remote_hit).
		return HitResult.IGNORED
	var result := victim.receive_hit(self, atk, multiplier * damage_multiplier(), source)
	if result != HitResult.IGNORED:
		var gain := atk.heat_gain * (0.5 if result == HitResult.BLOCKED else 1.0)
		heat = minf(max_heat, heat + gain)
		hit_landed.emit(victim, result, atk)
	return result


## El dueño de `target` (remoto) confirma que nuestro golpe le alcanzó: Calor, hitstop y efectos.
func confirm_remote_hit(target: Beast, result: HitResult, heat_gain: float, hitstop: float) -> void:
	heat = minf(max_heat, heat + heat_gain * (0.5 if result == HitResult.BLOCKED else 1.0))
	if state == State.ATTACK:
		_hitstop = maxf(_hitstop, hitstop * 0.5)  # llega tarde: medio hitstop para no frenar de más
	target._fx_hit_received(self, result)
	hit_landed.emit(target, result, null)


## Bestias vivas (menos esta) cuya hurtbox toca la esfera.
func beasts_in_sphere(center: Vector3, radius: float) -> Array[Beast]:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = HURTBOX_MASK
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var out: Array[Beast] = []
	for r in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var b := (r.collider as Node).get_parent() as Beast
		if b and b != self and not b.is_dead() and b not in out:
			out.append(b)
	return out


## Bestias dentro de un cono (`angle_deg` = medio ángulo) y con línea de visión desde `origin`.
func beasts_in_cone(origin: Vector3, dir: Vector3, reach: float, angle_deg: float) -> Array[Beast]:
	var out: Array[Beast] = []
	for b in beasts_in_sphere(origin, reach):
		var to := b.get_lock_position() - origin
		var flat := Vector3(to.x, 0.0, to.z)
		# Margen por el tamaño del cuerpo: a poca distancia el cono se "ensancha".
		var margin := atan2(0.6, maxf(flat.length(), 0.1))
		if flat.length() > 0.01 and dir.angle_to(flat) > deg_to_rad(angle_deg) + margin:
			continue
		var ray := PhysicsRayQueryParameters3D.create(origin, b.get_lock_position(), 1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		out.append(b)
	return out


# --- Habilidades --------------------------------------------------------------------

func can_use_ability(slot: int) -> bool:
	if moveset == null or slot < 0 or slot >= moveset.abilities.size():
		return false
	var ab := moveset.abilities[slot]
	return ab != null and cooldowns[slot] <= 0.0 and heat >= ab.heat_cost


func _try_ability(inp: PlayerInput) -> bool:
	for slot in ABILITY_SLOTS:
		var bit := PlayerInput.ABILITY_1 << slot
		if _buffered & bit == 0:
			continue
		if not can_use_ability(slot):
			continue  # se queda en el buffer por si se libera a tiempo
		_buffered &= ~bit
		_start_ability(slot, inp)
		return true
	return false


func _start_ability(slot: int, inp: PlayerInput) -> void:
	var ab := moveset.abilities[slot]
	if locked_on:
		var to := inp.lock_target.global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.01:
			facing = yaw_of(to)
	elif inp.move.length() > 0.2:
		facing = yaw_of(inp.move_3d())
	sprinting = false
	heat -= ab.heat_cost
	cooldowns[slot] = ab.cooldown
	_set_state(State.ABILITY)
	ability = ab
	ability_slot = slot
	action_seq += 1
	_cast = {}
	_anim = &""
	ab.start(self, _cast)
	ability_used.emit(slot)


func _tick_ability(inp: PlayerInput, delta: float, real_delta: float) -> void:
	var ab := ability
	if state_time <= ab.track_until and ab.tracking > 0.0:
		var want := Vector3.ZERO
		if locked_on:
			want = inp.lock_target.global_position - global_position
		elif inp.move.length() > 0.2:
			want = inp.move_3d()
		want.y = 0.0
		if want.length_squared() > 0.001:
			facing = rotate_toward(facing, yaw_of(want), ab.tracking * real_delta)
	if ab.move_factor > 0.0:
		var dir := inp.move_3d()
		_steer(dir, minf(dir.length(), 1.0), jog_speed * ab.move_factor * speed_multiplier(), real_delta)
	else:
		_brake(real_delta)
	ab.tick(self, _cast, state_time, delta)
	if state != State.ABILITY:
		return  # la propia habilidad pudo cambiar el estado
	if state_time >= ab.cancel_start and _try_dodge(inp):
		return
	if state_time >= ab.duration:
		_set_state(State.LOCOMOTION)


# --- Red ----------------------------------------------------------------------------

## Estado completo para enviar al rival (lo aplica NetProxy en el otro lado).
func net_snapshot() -> Array:
	var buff_list := []
	for b in buffs:
		buff_list.append([String(b.id), b.time, b.damage, b.speed, b.action, b.color])
	return [
		Time.get_ticks_usec() / 1_000_000.0, global_position, velocity, facing, state, state_time,
		action_seq, moveset.attack_index(attack) if moveset else -1, ability_slot, charge, _charge_done,
		health, stamina, heat, poise, burn_time, buff_list, sprinting, _dodge_duration, _stagger_duration,
		locked_on, _hitstop,
	]


# --- Mejoras ------------------------------------------------------------------------

func add_buff(id: StringName, duration: float, damage := 1.0, speed := 1.0, action := 1.0, color := Color.WHITE) -> void:
	for b in buffs:
		if b.id == id:
			b.time = duration
			return
	buffs.append({id = id, time = duration, damage = damage, speed = speed, action = action, color = color})


func has_buff(id: StringName) -> bool:
	return buffs.any(func(b): return b.id == id)


func damage_multiplier() -> float:
	var m := 1.0
	for b in buffs:
		m *= b.damage
	return m


func speed_multiplier() -> float:
	var m := 1.0
	for b in buffs:
		m *= b.speed
	return m


func action_speed_multiplier() -> float:
	var m := 1.0
	for b in buffs:
		m *= b.action
	return m


func _tick_stagger(_inp: PlayerInput, delta: float) -> void:
	_knockback = _knockback.move_toward(Vector3.ZERO, 10.0 * delta)
	velocity.x = _knockback.x
	velocity.z = _knockback.z
	if state_time >= _stagger_duration:
		_set_state(State.LOCOMOTION)


# --- Movimiento común ----------------------------------------------------------------

func _steer(dir: Vector3, amount: float, speed: float, delta: float) -> void:
	var desired := dir.normalized() * amount * speed if amount > 0.01 else Vector3.ZERO
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if desired.length() > h.length() else deceleration
	h = h.lerp(desired, 1.0 - exp(-rate * delta))
	velocity.x = h.x
	velocity.z = h.z


func _brake(delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, deceleration * delta)
	velocity.x = h.x
	velocity.z = h.z


func _face_towards(dir: Vector3, delta: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	facing = lerp_angle(facing, yaw_of(dir), 1.0 - exp(-turn_speed * delta))


# --- Recursos ----------------------------------------------------------------------

func _spend_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_regen_wait = stamina_regen_delay


func _tick_resources(delta: float) -> void:
	if sprinting and horizontal_speed() > 1.0:
		stamina = maxf(0.0, stamina - sprint_cost * delta)
		_regen_wait = stamina_regen_delay * 0.5
	_regen_wait -= delta
	if _regen_wait <= 0.0 and state != State.DODGE and state != State.ATTACK and state != State.ABILITY and state != State.DEAD:
		var regen := stamina_regen * (block_regen_factor if state == State.BLOCK else 1.0)
		stamina = minf(max_stamina, stamina + regen * delta)
	if stamina <= 0.0:
		_exhausted = true
	elif _exhausted and stamina >= exhausted_threshold:
		_exhausted = false
	_poise_wait -= delta
	if _poise_wait <= 0.0:
		poise = minf(max_poise, poise + poise_regen * delta)
	for i in ABILITY_SLOTS:
		cooldowns[i] = maxf(0.0, cooldowns[i] - delta)
	for i in range(buffs.size() - 1, -1, -1):
		buffs[i].time -= delta
		if buffs[i].time <= 0.0:
			buffs.remove_at(i)
	if burn_time > 0.0 and not is_dead():
		burn_time -= delta
		health -= burn_dps * delta
		if health <= 0.0:
			health = 0.0
			_die()


func _update_buffer(inp: PlayerInput, delta: float) -> void:
	if inp.buttons != 0:
		# Solo se recuerda la última pulsación (como en los souls): un ataque pisa a una esquiva.
		_buffered = inp.buttons
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
		State.ATTACK:
			if _anim != attack.action:
				_anim = attack.action
				_sound_for(attack.action)
			# El clip va clavado al reloj de la simulación: el impacto cae dentro de la ventana activa.
			var ct := _attack_clip_time(attack, state_time)
			var rate := 0.0
			if not is_charging():
				rate = (_attack_clip_time(attack, state_time + 0.02) - ct) / 0.02 * action_speed_multiplier()
			visual.drive(attack.action, ct, rate)
		State.ABILITY:
			if _anim != ability.action:
				_play_anim(ability.action, 0.08, ability.anim_speed)
			visual.set_playback_speed(action_speed_multiplier())
		State.BLOCK:
			if _anim != &"block":
				_anim = &"block"
				visual.hold_pose(&"block", block_pose, 0.1)
		State.STAGGER:
			if _anim != &"hit":
				_play_anim(&"hit", 0.04)
			visual.set_playback_speed(visual.get_action_length(&"hit") / maxf(_stagger_duration, 0.1))
		State.DEAD:
			_play_anim(&"death", 0.15)
			visual.set_playback_speed(1.0)
		State.LOCOMOTION:
			var h := horizontal_speed()
			var air := is_airborne()
			if air:
				if _anim != &"air":
					_anim = &"air"
					visual.hold_pose(&"run", 0.3, 0.12)
			elif _was_airborne:
				_anim = &""
				Sfx.play("step", global_position, -4.0, 0.8 * _voice_pitch(), 0.05)
			_was_airborne = air
			if air:
				pass
			elif h < 0.3:
				_play_anim(&"idle", 0.2)
				visual.set_playback_speed(1.0)
			elif sprinting:
				_play_anim(&"run", 0.2)
				visual.set_playback_speed(h / run_anim_speed)
			else:
				_play_anim(&"walk", 0.2)
				visual.set_playback_speed(h / walk_anim_speed)
	if _hitstop > 0.0:
		visual.set_playback_speed(0.0)
	_update_trail()
	var looking := locked_on and is_instance_valid(lock_target) and (state == State.LOCOMOTION or state == State.BLOCK)
	visual.look_at_point((lock_target as Beast).get_lock_position() if looking and lock_target is Beast else Vector3.INF)
	_update_footsteps(get_physics_process_delta_time())
	_update_status_fx()
	_update_debug_hitbox()


## Instante del clip para el instante `t` del ataque: anticipación que acelera, golpe seco justo en la ventana
## activa (el impacto del clip en su centro) y recuperación que frena.
func _attack_clip_time(a: AttackData, t: float) -> float:
	var length := visual.get_clip_length(a.action)
	if length <= 0.0:
		return 0.0
	var impact := visual.get_impact_time(a.action)
	var strike_from := impact - minf(0.07, impact * 0.5)
	var strike_to := impact + minf(0.09, (length - impact) * 0.5)
	if t < a.active_start:
		return strike_from * pow(t / maxf(a.active_start, 0.01), 1.6)
	if t < a.active_end:
		return lerpf(strike_from, strike_to, (t - a.active_start) / maxf(a.active_end - a.active_start, 0.01))
	var u := clampf((t - a.active_end) / maxf(a.duration - a.active_end, 0.01), 0.0, 1.0)
	return lerpf(strike_to, length, 1.0 - (1.0 - u) * (1.0 - u))


## Estela que barre el mismo arco que la hitbox durante la ventana activa (con pasos intermedios para que
## la curva salga suave aunque la ventana dure pocos ticks).
func _update_trail() -> void:
	if state != State.ATTACK or attack == null or state_time < attack.active_start:
		_trail_t = -1.0
		return
	var from := _trail_t
	if from < 0.0:
		from = attack.active_start
		visual.begin_trail(_trail_color())
	var to := minf(state_time, attack.active_end)
	if to <= from and _trail_t >= 0.0:
		return
	var basis := Basis(Vector3.UP, facing)
	var steps := 4
	for i in range(1 if _trail_t >= 0.0 else 0, steps + 1):
		var off := attack.hitbox_offset_at(lerpf(from, to, i / float(steps)))
		var flat := Vector3(off.x, 0.0, off.z)
		var dir := flat.normalized() if flat.length() > 0.05 else Vector3.FORWARD
		var center := global_position + Vector3(0.0, off.y, 0.0)
		var reach := flat.length() + attack.hitbox_radius * 0.8
		visual.add_trail(center + basis * (dir * reach * 0.45), center + basis * (dir * reach))
	_trail_t = to


func _trail_color() -> Color:
	var c := character.color if character else Color(1.0, 0.8, 0.5)
	return c.lerp(Color.WHITE, 0.45)


func _play_anim(action: StringName, blend: float, speed := 1.0) -> void:
	if _anim == action:
		return
	_anim = action
	visual.play(action, blend, speed)
	_sound_for(action)


## Sonidos ligados al inicio de una acción (sirven igual para el Beast local y el proxy remoto).
func _sound_for(action: StringName) -> void:
	var pos := global_position + Vector3.UP
	var size_pitch := _voice_pitch()
	match state:
		State.ATTACK:
			var heavy := String(action).begins_with("attack_heavy") or (attack and attack.chargeable)
			Sfx.play("swing", pos, -1.0 if heavy else -5.0, (0.8 if heavy else 1.05) * size_pitch)
		State.DODGE:
			Sfx.play("dodge", pos, -4.0, size_pitch)
		State.ABILITY:
			Sfx.play("cast_special", pos, -8.0, size_pitch)
		State.DEAD:
			Sfx.play("death", pos, 0.0, size_pitch, 0.02)


## Más grave cuanto más grande es el personaje.
func _voice_pitch() -> float:
	return clampf(1.9 / (character.body_height if character else 1.9), 0.7, 1.3)


func _update_footsteps(delta: float) -> void:
	if state != State.LOCOMOTION or not is_on_floor_or_remote():
		_step_accum = 0.0
		return
	var h := horizontal_speed()
	if h < 0.5:
		_step_accum = 0.0
		return
	_step_accum += delta * h
	var stride := 1.6 if sprinting else 1.2
	stride *= character.body_height / 1.9 if character else 1.0
	if _step_accum >= stride:
		_step_accum -= stride
		Sfx.play("step", global_position, -14.0 if not sprinting else -10.0, _voice_pitch(), 0.12)


func is_on_floor_or_remote() -> bool:
	return is_remote or is_on_floor()


func _fx_hit_received(attacker: Beast, result: HitResult) -> void:
	if result == HitResult.IGNORED:
		return
	var toward_attacker := (attacker.get_lock_position() - get_lock_position())
	var pos := get_lock_position() + toward_attacker.limit_length(0.5)
	var kind := HitFx.Kind.HIT
	match result:
		HitResult.BLOCKED:
			Sfx.play("block", pos, -2.0)
		HitResult.GUARD_BREAK:
			Sfx.play("guard_break", pos, 0.0)
		HitResult.STAGGERED, HitResult.KILLED:
			Sfx.play("hit_heavy", pos, 0.0)
		_:
			Sfx.play("hit_light", pos, -2.0)
	match result:
		HitResult.BLOCKED:
			kind = HitFx.Kind.BLOCK
			visual.flash(Color(0.6, 0.8, 1.0, 0.5), 0.1)
		HitResult.GUARD_BREAK:
			kind = HitFx.Kind.GUARD_BREAK
			visual.flash(Color(1.0, 0.9, 0.5, 0.7), 0.25)
		_:
			visual.flash(Color(1.0, 0.35, 0.2, 0.6), 0.15)
	HitFx.spawn(get_parent(), pos, toward_attacker.normalized(), kind, 1.0 if result != HitResult.BLOCKED else 0.6)
	var strength := 0.12
	match result:
		HitResult.BLOCKED:
			strength = 0.06
		HitResult.STAGGERED, HitResult.GUARD_BREAK, HitResult.KILLED:
			strength = 0.22
	visual.flinch(-toward_attacker, strength)


## Quemadura (ascuas en el cuerpo) y aura de las mejoras.
func _update_status_fx() -> void:
	var burning := burn_time > 0.0 and not is_dead()
	if burning and _burn_fx == null:
		_burn_fx = Fx.embers(Color(1.0, 0.4, 0.1), 0.5, 40)
		add_child(_burn_fx)
		_burn_fx.position = Vector3(0, 1.0, 0)
	if _burn_fx:
		_burn_fx.emitting = burning
	var buffed := not buffs.is_empty() and not is_dead()
	if buffed and _aura_fx == null:
		_aura_fx = Fx.embers(buffs[0].color, 0.9, 30)
		add_child(_aura_fx)
		_aura_fx.position = Vector3(0, 0.4, 0)
	if _aura_fx:
		_aura_fx.emitting = buffed


func _update_debug_hitbox() -> void:
	var show := debug_hitboxes and state == State.ATTACK and attack and attack.is_active_at(state_time)
	if not show:
		if _debug_sphere:
			_debug_sphere.visible = false
		return
	if _debug_sphere == null:
		_debug_sphere = MeshInstance3D.new()
		_debug_sphere.mesh = SphereMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.1, 0.1, 0.35)
		m.no_depth_test = true
		_debug_sphere.material_override = m
		_debug_sphere.top_level = true
		_debug_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_sphere)
	_debug_sphere.visible = true
	_debug_sphere.global_position = hitbox_center()
	var d := attack.hitbox_radius * 2.0
	_debug_sphere.scale = Vector3(d, d, d)

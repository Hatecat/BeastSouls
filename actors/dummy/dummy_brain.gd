class_name DummyBrain
extends Node
## IA de práctica. Genera PlayerInput igual que un jugador, así que usa la misma simulación que él.
## Modos (F2 en la arena los recorre):
##   PASSIVE    quieto, para probar combos y daño.
##   STRAFE     rodea al objetivo y esquiva de vez en cuando (prueba del fijado).
##   AGGRESSIVE se acerca y ataca con combos y fuertes; a veces bloquea o esquiva tus ataques.
##   GUARD      se queda en guardia mirándote (prueba de bloqueo y rotura de guardia).

enum Mode { PASSIVE, STRAFE, AGGRESSIVE, GUARD }

@export var beast: Beast
@export var target: Beast
@export var mode := Mode.STRAFE
## Distancia que intenta mantener al rodear.
@export var keep_distance := 6.0
## Distancia a la que empieza a atacar en modo agresivo.
@export var attack_range := 2.6

var _strafe_dir := 1.0
var _next_switch := 2.0
var _next_dodge := 3.0
var _cooldown := 1.0
## Pulsaciones programadas: [segundos restantes, bit].
var _queue: Array = []
var _block_time := 0.0
var _react_cooldown := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_physics_priority = -10
	_rng.seed = 1234


func next_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	_queue.clear()
	_block_time = 0.0


func _physics_process(delta: float) -> void:
	if beast == null or target == null or beast.is_dead():
		return
	var frame := PlayerInput.new()
	if target.is_dead():
		beast.input = frame
		return
	frame.lock_target = target
	match mode:
		Mode.PASSIVE:
			frame.lock_target = null
		Mode.STRAFE:
			_strafe(frame, delta)
		Mode.AGGRESSIVE:
			_aggressive(frame, delta)
		Mode.GUARD:
			frame.held |= PlayerInput.BLOCK
	beast.input = frame


func _to_target() -> Vector3:
	var to := target.global_position - beast.global_position
	to.y = 0.0
	return to


func _strafe(frame: PlayerInput, delta: float) -> void:
	var to := _to_target()
	var dist := to.length()
	var fwd := to / maxf(dist, 0.001)
	var side := Vector3(-fwd.z, 0.0, fwd.x) * _strafe_dir
	var approach := clampf((dist - keep_distance) * 0.5, -1.0, 1.0)
	var m := (side + fwd * approach).limit_length(1.0) * 0.8
	frame.move = Vector2(m.x, m.z)
	_next_switch -= delta
	if _next_switch <= 0.0:
		_strafe_dir = -_strafe_dir
		_next_switch = _rng.randf_range(1.5, 3.5)
	_next_dodge -= delta
	if _next_dodge <= 0.0:
		frame.buttons |= PlayerInput.DODGE
		_next_dodge = _rng.randf_range(2.5, 5.0)


func _aggressive(frame: PlayerInput, delta: float) -> void:
	var to := _to_target()
	var dist := to.length()
	var fwd := to / maxf(dist, 0.001)
	_cooldown -= delta
	_react_cooldown -= delta

	# Pulsaciones programadas (combos).
	for q in _queue:
		q[0] -= delta
	while not _queue.is_empty() and _queue[0][0] <= 0.0:
		frame.buttons |= _queue.pop_front()[1]

	# Reaccionar a un ataque del jugador que aún no ha golpeado.
	var threatened := target.state == Beast.State.ATTACK and target.attack \
			and target.state_time < target.attack.active_start and dist < 4.0
	if threatened and _react_cooldown <= 0.0 and _queue.is_empty():
		_react_cooldown = 1.2
		var r := _rng.randf()
		if r < 0.35:
			var side := Vector3(-fwd.z, 0.0, fwd.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
			frame.move = Vector2(side.x, side.z)
			frame.buttons |= PlayerInput.DODGE
			return
		elif r < 0.7:
			_block_time = 0.8

	if _block_time > 0.0:
		_block_time -= delta
		frame.held |= PlayerInput.BLOCK
		return

	# Habilidades: a distancia, bola de fuego; cerca, lanzallamas o rugido; y mejorarse si puede.
	if _cooldown <= 0.0 and _queue.is_empty():
		var slot := _pick_ability(dist)
		if slot >= 0:
			frame.buttons |= PlayerInput.ABILITY_1 << slot
			_cooldown = _rng.randf_range(1.2, 2.0)
			return

	if dist > attack_range:
		# Acercarse (corriendo si está lejos).
		frame.move = Vector2(fwd.x, fwd.z)
		if dist > 8.0:
			frame.held |= PlayerInput.SPRINT
		return

	if _cooldown <= 0.0 and _queue.is_empty() and beast.stamina > 30.0:
		var r := _rng.randf()
		if r < 0.6:
			var hits := _rng.randi_range(1, 3)
			for i in hits:
				_queue.append([0.0 + i * 0.4, PlayerInput.LIGHT])
		elif r < 0.85:
			_queue.append([0.0, PlayerInput.HEAVY])
		else:
			_block_time = 1.0
		_cooldown = _rng.randf_range(1.4, 2.4)
	else:
		# Entre ataques, rodea despacio.
		var side := Vector3(-fwd.z, 0.0, fwd.x) * _strafe_dir * 0.5
		frame.move = Vector2(side.x, side.z)


## Ranura de habilidad a usar ahora (-1 = ninguna). Supone el kit de Charizard:
## 0 bola de fuego, 1 lanzallamas, 2 rugido, 3 danza dragón.
func _pick_ability(dist: float) -> int:
	var r := _rng.randf()
	if beast.can_use_ability(3) and beast.buffs.is_empty() and r < 0.3:
		return 3
	if dist > 5.0 and dist < 16.0 and beast.can_use_ability(0) and r < 0.5:
		return 0
	if dist <= 4.5:
		if beast.can_use_ability(2) and r < 0.15:
			return 2
		if beast.can_use_ability(1) and r < 0.3:
			return 1
	return -1

class_name NetProxy
extends Node
## Mueve un Beast remoto (`beast.is_remote = true`) a partir de las instantáneas de su dueño.
##
## - Interpola entre instantáneas con un retardo fijo (`interp_delay`): el rival se ve un poco en el pasado,
##   pero suave aunque lleguen con jitter o se pierda alguna. Si faltan, extrapola un máximo de 0.25 s.
## - Reproduce sus ataques y habilidades (hitboxes, conos, proyectiles) contra el Beast LOCAL: aquí se decide
##   si nos golpea (la víctima manda). Los efectos visuales salen igual que si fuera local.

## Índices de la instantánea (Beast.net_snapshot).
enum { T, POS, VEL, FACING, STATE, STATE_TIME, SEQ, ATTACK, ABILITY, CHARGE, CHARGE_DONE, HEALTH, STAMINA,
	PP, POISE, BURN, BUFFS, SPRINTING, DODGE_DUR, STAGGER_DUR, LOCKED, HITSTOP }

## Retardo de interpolación (s). Debe cubrir el intervalo entre instantáneas (~33 ms) más el jitter.
@export var interp_delay := 0.1
@export var max_extrapolation := 0.25

var beast: Beast
## Beast del jugador local (el único al que puede golpear este proxy).
var local: Beast

var _buf: Array[Array] = []
## Diferencia de relojes estimada: hora_local - hora_del_remitente (incluye la latencia mínima).
var _offset := INF
var _last_seq := -1
var _last_state := -1
var _last_st := 0.0
var _has_state := false


func setup(remote_beast: Beast, local_beast: Beast) -> void:
	beast = remote_beast
	local = local_beast
	beast.is_remote = true
	process_physics_priority = -5


func push(data: Array) -> void:
	if data.size() <= HITSTOP:
		return
	var now := _now()
	var t: float = data[T]
	var off := now - t
	if off < _offset:
		_offset = off
	else:
		_offset += (off - _offset) * 0.002  # se adapta despacio a la deriva de relojes
	if not _buf.is_empty() and t <= _buf[-1][T]:
		return  # repetida o desordenada
	_buf.append(data)
	while _buf.size() > 2 and _buf[1][T] < t - 1.0:
		_buf.pop_front()


## Retardo con el que se ve al rival respecto a la instantánea más reciente (interpolación + jitter), en segundos.
## No incluye la latencia mínima de ida, que se absorbe en la estimación de relojes.
func view_delay() -> float:
	if _buf.is_empty():
		return 0.0
	return _now() - _offset - _buf[-1][T] + interp_delay


func _physics_process(delta: float) -> void:
	if _buf.is_empty() or beast == null:
		return
	var rt := _now() - _offset - interp_delay
	var a: Array = _buf[0]
	var b: Array = _buf[0]
	var alpha := 0.0
	var extra := 0.0
	if rt >= _buf[-1][T]:
		a = _buf[-1]
		b = a
		extra = minf(rt - a[T], max_extrapolation)
	elif rt > _buf[0][T]:
		for i in range(_buf.size() - 1):
			if _buf[i + 1][T] >= rt:
				a = _buf[i]
				b = _buf[i + 1]
				alpha = inverse_lerp(a[T], b[T], rt)
				break
	_apply(a, b, alpha, extra, rt, delta)


func _apply(a: Array, b: Array, alpha: float, extra: float, rt: float, _delta: float) -> void:
	var moveset := beast.moveset
	# Continuo.
	var pos: Vector3 = (a[POS] as Vector3).lerp(b[POS], alpha)
	var vel: Vector3 = (a[VEL] as Vector3).lerp(b[VEL], alpha)
	if extra > 0.0:
		pos += Vector3(vel.x, 0.0, vel.z) * extra
	beast.global_position = pos
	beast.velocity = vel
	beast.facing = lerp_angle(a[FACING], b[FACING], alpha)
	var st: float
	if a != b and a[SEQ] == b[SEQ] and a[STATE] == b[STATE]:
		st = lerpf(a[STATE_TIME], b[STATE_TIME], alpha)
	else:
		st = a[STATE_TIME] + maxf(0.0, rt - a[T]) if a[HITSTOP] <= 0.0 else a[STATE_TIME]

	# Discreto (de la instantánea más antigua del par).
	var new_state: int = a[STATE]
	var seq: int = a[SEQ]
	var leaving_ability := _last_state == Beast.State.ABILITY and (seq != _last_seq or new_state != Beast.State.ABILITY)
	if leaving_ability and beast.ability:
		beast.ability.finish(beast, beast._cast)
		beast.ability = null
	beast.state = new_state as Beast.State
	beast.state_time = st
	beast.attack = moveset.attack_by_index(a[ATTACK]) if moveset else null
	beast.ability_slot = a[ABILITY]
	beast.charge = a[CHARGE]
	beast._charge_done = a[CHARGE_DONE]
	beast.health = a[HEALTH]
	beast.stamina = a[STAMINA]
	beast.pp = a[PP]
	beast.poise = a[POISE]
	beast.burn_time = a[BURN]
	beast.sprinting = a[SPRINTING]
	beast._dodge_duration = a[DODGE_DUR]
	beast._stagger_duration = a[STAGGER_DUR]
	beast._hitstop = a[HITSTOP]
	beast.locked_on = a[LOCKED]
	beast.lock_target = local if beast.locked_on else null
	beast.buffs.clear()
	for e: Array in a[BUFFS]:
		beast.buffs.append({id = StringName(e[0]), time = e[1], damage = e[2], speed = e[3], action = e[4], color = e[5]})

	if seq != _last_seq:
		# Acción nueva: reiniciar animación y golpeados; arrancar la habilidad (efectos).
		beast._hit_targets.clear()
		beast._anim = &""
		if new_state == Beast.State.ABILITY and beast.ability_slot >= 0 and beast.ability_slot < beast.abilities.size():
			beast.ability = beast.abilities[beast.ability_slot]
			beast._cast = {}
			beast.ability.start(beast, beast._cast)
			_last_st = 0.0

	# Golpes del rival contra el jugador local (decidimos aquí: somos la víctima).
	if local and not local.is_dead():
		if beast.state == Beast.State.ATTACK and beast.attack and beast.attack.is_active_at(st):
			beast._check_hits(beast.attack)
	if beast.state == Beast.State.ABILITY and beast.ability:
		beast.ability.tick(beast, beast._cast, st, maxf(st - _last_st, 0.0))
		_last_st = st

	_last_seq = seq
	_last_state = new_state
	beast._update_presentation()


static func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0

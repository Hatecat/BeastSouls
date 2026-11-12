class_name AreaAbility
extends AbilityData
## Golpe en área alrededor del lanzador en `trigger_time` (rugido).

@export var hit: AttackData
@export var trigger_time := 0.45
@export var radius := 6.0
## Vibración de cámara para el lanzador (el que recibe ya vibra al ser golpeado).
@export var caster_shake := 0.5


func _init() -> void:
	interruptible = false  # los golpes de área son compromisos lentos: aguantan los golpes flojos


func tick(beast: Beast, _cast: Dictionary, t: float, delta: float) -> void:
	if not crossed(t, delta, trigger_time):
		return
	var center := beast.global_position + Vector3.UP
	for v in beast.beasts_in_sphere(center, radius):
		beast.deal_hit(v, hit, beast.global_position)
	Fx.shockwave(beast.get_parent(), beast.global_position, radius, color)
	Sfx.play("quake", beast.global_position, 2.0, clampf(4.0 / radius, 0.7, 1.2))
	beast.shake_requested.emit(caster_shake)

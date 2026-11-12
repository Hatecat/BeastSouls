class_name BuffAbility
extends AbilityData
## Mejora temporal sobre el propio lanzador (danza dragón).

@export var buff_id: StringName = &"buff"
@export var trigger_time := 0.5
@export var buff_duration := 10.0
@export var damage_multiplier := 1.25
## Multiplica la velocidad de movimiento.
@export var speed_multiplier := 1.2
## Multiplica la velocidad de ataques y habilidades.
@export var action_speed_multiplier := 1.1
## Curación instantánea al activarse (fracción de la vida máxima).
@export_range(0.0, 1.0) var heal := 0.0


func tick(beast: Beast, _cast: Dictionary, t: float, delta: float) -> void:
	if not crossed(t, delta, trigger_time):
		return
	if heal > 0.0 and not beast.is_remote:
		beast.health = minf(beast.max_health, beast.health + beast.max_health * heal)
	beast.add_buff(buff_id, buff_duration, damage_multiplier, speed_multiplier, action_speed_multiplier, color)
	beast.visual.flash(Color(color.r, color.g, color.b, 0.8), 0.4)
	Fx.shockwave(beast.get_parent(), beast.global_position, 2.5, color)
	Sfx.play("heal" if heal > 0.0 else "buff", beast.global_position, -1.0, 1.0, 0.02)
	beast.shake_requested.emit(0.2)

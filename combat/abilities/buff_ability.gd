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


func tick(beast: Beast, _cast: Dictionary, t: float, delta: float) -> void:
	if not crossed(t, delta, trigger_time):
		return
	beast.add_buff(buff_id, buff_duration, damage_multiplier, speed_multiplier, action_speed_multiplier, color)
	beast.visual.flash(Color(color.r, color.g, color.b, 0.8), 0.4)
	Fx.shockwave(beast.get_parent(), beast.global_position, 2.5, color)
	beast.shake_requested.emit(0.2)

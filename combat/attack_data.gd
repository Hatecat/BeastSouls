class_name AttackData
extends Resource
## Definición de un ataque. Todos los tiempos van en segundos desde que empieza el ataque
## (la animación se reproduce a `anim_speed`, así que se ajustan a ojo con F1 en la arena).
##
## Línea de tiempo:  0 ── anticipación ── active_start ══ golpe ══ active_end ── recuperación ── duration
##                                                         combo_start →  (encadenar el siguiente)
##                                                         cancel_start → (cancelar con esquiva)

@export var display_name := ""
## Acción lógica de CharacterVisual (attack_light_1, attack_heavy_1...).
@export var action: StringName = &""
@export var anim_speed := 1.0

@export_group("Tiempos")
@export var duration := 0.8
@export var active_start := 0.3
@export var active_end := 0.4
@export var combo_start := 0.4
@export var cancel_start := 0.5

@export_group("Daño")
@export var damage := 10.0
## Daño a la postura (poise): si la vacía, el rival queda aturdido.
@export var poise_damage := 15.0
## Estamina que pierde el rival si bloquea el golpe.
@export var guard_stamina_damage := 15.0
@export var stamina_cost := 15.0
## Segundos de aturdimiento del rival si rompe su postura.
@export var stagger_time := 0.45
## Velocidad (m/s) con la que empuja al rival.
@export var knockback := 3.0
## Congelado breve de atacante y víctima al impactar (sensación de golpe).
@export var hitstop := 0.07
## Atraviesa el bloqueo.
@export var unblockable := false
## Segundos de quemadura que aplica (0 = ninguna).
@export var burn_time := 0.0
## Calor que gana el atacante al acertar (la mitad si se lo bloquean).
@export var heat_gain := 8.0

@export_group("Hitbox")
## Esfera en coordenadas locales del personaje (adelante = -Z). Se desplaza de start a end
## durante la ventana activa, para barrer un arco.
@export var hitbox_offset_start := Vector3(0, 1.1, -1.0)
@export var hitbox_offset_end := Vector3(0, 1.1, -1.0)
@export var hitbox_radius := 0.7

@export_group("Movimiento")
## Avance (m/s) durante [lunge_start, lunge_end].
@export var lunge_speed := 3.0
@export var lunge_start := 0.1
@export var lunge_end := 0.3
## Giro máximo (rad/s) hacia el objetivo antes del golpe.
@export var tracking := 6.0
## Postura extra mientras dura el ataque (hasta active_end): "hiper armadura".
@export var hyper_armor := 0.0

@export_group("Carga")
@export var chargeable := false
## Instante en que se congela el ataque mientras se mantenga el botón.
@export var charge_point := 0.2
@export var max_charge := 0.8
## Multiplicador de daño y postura con la carga completa.
@export var charge_multiplier := 1.6


## Centro de la hitbox (local) en el instante `t`.
func hitbox_offset_at(t: float) -> Vector3:
	var k := 0.0
	if active_end > active_start:
		k = clampf((t - active_start) / (active_end - active_start), 0.0, 1.0)
	return hitbox_offset_start.lerp(hitbox_offset_end, k)


func is_active_at(t: float) -> bool:
	return t >= active_start and t <= active_end

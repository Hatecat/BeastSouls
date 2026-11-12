class_name AbilityData
extends Resource
## Habilidad base. Las subclases implementan `start`, `tick` y `finish`.
##
## El Resource se comparte entre todas las bestias que lo usan: el estado de cada lanzamiento va en
## el diccionario `cast` que reciben los métodos, nunca en el propio Resource.
## Lo que hace daño pasa siempre por `Beast.deal_hit` (en red, solo lo aplicará el host).

@export var display_name := ""
## Color del icono en el HUD.
@export var color := Color(1.0, 0.5, 0.15)
## Acción lógica de CharacterVisual (skill_flamethrower...).
@export var action: StringName = &""
@export var anim_speed := 1.0

@export_group("Coste")
@export var heat_cost := 30.0
@export var cooldown := 5.0

@export_group("Tiempos")
@export var duration := 1.2
## Desde aquí se puede cancelar con una esquiva.
@export var cancel_start := 1.0
## Giro máximo (rad/s) hacia el objetivo mientras dure la habilidad.
@export var tracking := 3.0
## Hasta cuándo sigue al objetivo (segundos); después queda fija la orientación.
@export var track_until := 0.3
## Fracción de la velocidad de trote con la que se puede andar mientras tanto (0 = quieto).
@export var move_factor := 0.0
## Si recibir un golpe corta el lanzamiento aunque no rompa la postura.
@export var interruptible := true


## Tipo de habilidad (para la IA y el selector): projectile, channel, area, buff, dash.
func kind() -> StringName:
	return &""


## Una línea para el selector: qué hace, con sus números.
func summary() -> String:
	return ""


## Distancia útil aproximada (m): la IA la usa para decidir cuándo lanzarla.
func reach() -> float:
	return 4.0


static func kind_label(k: StringName) -> String:
	return {&"projectile": "Distancia", &"channel": "Chorro", &"area": "Área", &"buff": "Mejora", &"dash": "Embestida"}.get(k, "Habilidad")


func start(_beast: Beast, _cast: Dictionary) -> void:
	pass


func tick(_beast: Beast, _cast: Dictionary, _t: float, _delta: float) -> void:
	pass


## Se llama al terminar o al ser interrumpida (aturdimiento, muerte, esquiva).
func finish(_beast: Beast, _cast: Dictionary) -> void:
	pass


## Ayuda: ¿ha cruzado `t` el instante `at` en este tick?
static func crossed(t: float, delta: float, at: float) -> bool:
	return t >= at and t - delta < at

class_name Moveset
extends Resource
## Repertorio de ataques de una bestia.

## Combo del ataque ligero (al terminar vuelve al primero).
@export var light_combo: Array[AttackData] = []
## Combo del ataque fuerte (cargable si el AttackData lo permite).
@export var heavy_combo: Array[AttackData] = []
## Ataque ligero mientras se corre.
@export var running_attack: AttackData
## Kit de habilidades (teclas 1-4 / cruceta), en orden de ranura.
@export var abilities: Array[AbilityData] = []

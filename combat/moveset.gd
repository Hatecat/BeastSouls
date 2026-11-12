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


## Índice estable de un ataque (para la red): ligeros, luego fuertes, luego el de carrera. -1 si no está.
func attack_index(atk: AttackData) -> int:
	if atk == null:
		return -1
	return all_attacks().find(atk)


func attack_by_index(i: int) -> AttackData:
	var list := all_attacks()
	return list[i] if i >= 0 and i < list.size() else null


func all_attacks() -> Array[AttackData]:
	var out: Array[AttackData] = []
	out.append_array(light_combo)
	out.append_array(heavy_combo)
	if running_attack:
		out.append(running_attack)
	return out

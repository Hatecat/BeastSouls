class_name Moveset
extends Resource
## Repertorio de ataques de una bestia.

## Combo del ataque ligero (al terminar vuelve al primero).
@export var light_combo: Array[AttackData] = []
## Combo del ataque fuerte (cargable si el AttackData lo permite).
@export var heavy_combo: Array[AttackData] = []
## Ataque ligero mientras se corre.
@export var running_attack: AttackData
## Combos mixtos: secuencia de botones desde el inicio de la cadena ("L" ligero, "H" fuerte; p. ej. "LLH") →
## ataque que sale en ese paso en lugar del que tocaría. Tras él, la cadena vuelve a empezar.
@export var combos: Dictionary[String, AttackData] = {}
## Catálogo de habilidades del personaje (hasta 10). El jugador equipa 4 antes del combate; las 4 primeras
## son la selección por defecto. Las equipadas están en `Beast.abilities`.
@export var abilities: Array[AbilityData] = []

const LOADOUT_SIZE := 4


## Deja `picks` (índices del catálogo) en una selección válida: sin repetidos, dentro del catálogo y completa.
func valid_loadout(picks: Array) -> Array[int]:
	var out: Array[int] = []
	for p: Variant in picks:
		var i := int(p)
		if i >= 0 and i < abilities.size() and i not in out and out.size() < LOADOUT_SIZE:
			out.append(i)
	var next := 0
	while out.size() < mini(LOADOUT_SIZE, abilities.size()):
		if next not in out:
			out.append(next)
		next += 1
	return out


func loadout_abilities(picks: Array) -> Array[AbilityData]:
	var out: Array[AbilityData] = []
	for i in valid_loadout(picks):
		out.append(abilities[i])
	return out


## Ataque de combo para la secuencia `seq`, o null si esa secuencia sigue la cadena normal.
func combo_attack(seq: String) -> AttackData:
	return combos.get(seq)


## Combos ordenados de corto a largo: [[secuencia, nombre], ...] (para la interfaz).
func combo_list() -> Array:
	var keys := combos.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return a.length() < b.length() if a.length() != b.length() else a > b)
	var out := []
	for k: String in keys:
		out.append([k, combos[k].display_name])
	return out


## Índice estable de un ataque (para la red): ligeros, fuertes, el de carrera y los combos (por secuencia).
## -1 si no está.
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
	var keys := combos.keys()
	keys.sort()
	for k: String in keys:
		out.append(combos[k])
	return out

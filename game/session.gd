extends Node
## Autoload "Session": lo que pasa de una escena a otra (personajes elegidos) y el estado del rival en el
## lobby online. Escucha los eventos de red siempre, así no se pierde nada aunque llegue mientras se cambia
## de escena (p. ej. el rival elige personaje antes de que nosotros salgamos de la arena).

signal rival_pick_changed
## El anfitrión ha arrancado la partida (llega al invitado; el anfitrión lo emite para sí mismo).
signal match_start
## El rival pide volver al selector de personaje.
signal to_select

const SETTINGS := "user://settings.cfg"
const SELECT := "res://ui/character_select.tscn"
const ARENA := "res://levels/arena_test/arena_test.tscn"
## Escenarios disponibles (id → escena). La arena carga `stage`.
const STAGES := {
	&"colosseum": "res://levels/colosseum/colosseum.tscn",
	&"test": "res://levels/arena_test/test_stage.tscn",
}

var my_character: StringName = &"charizard"
## Online: el personaje del rival. Práctica: el de la IA.
var rival_character: StringName = &"charizard"

## Lobby online: elección actual del rival y si ha pulsado "Listo".
var rival_pick: StringName = &""
var rival_ready := false
## El rival ha cargado la arena (el anfitrión espera a esto para empezar la primera ronda).
var rival_in_arena := false

var stage: StringName = &"colosseum"

## Habilidades equipadas (índices del catálogo del personaje). Vacío = las 4 primeras.
var my_loadout: Array = []
var rival_loadout: Array = []
## Lobby online: las que lleva la elección actual del rival.
var rival_pick_loadout: Array = []
## Última selección guardada por personaje (user://settings.cfg, sección "loadouts").
var _saved_loadouts := {}

## Argumentos de línea de comandos para pruebas: --char=ID --rival=ID --stage=ID --autoready.
var auto_ready := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--char="):
			my_character = StringName(a.trim_prefix("--char="))
		elif a.begins_with("--rival="):
			rival_character = StringName(a.trim_prefix("--rival="))
		elif a.begins_with("--stage="):
			stage = StringName(a.trim_prefix("--stage="))
		elif a == "--autoready":
			auto_ready = true
	Net.event_received.connect(_on_event)
	Net.connected.connect(_reset_lobby)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK and cfg.has_section("loadouts"):
		for id in cfg.get_section_keys("loadouts"):
			_saved_loadouts[StringName(id)] = cfg.get_value("loadouts", id)
	my_loadout = saved_loadout(my_character)
	rival_loadout = saved_loadout(rival_character)


## Selección guardada de `id`, ya validada contra su catálogo.
func saved_loadout(id: StringName) -> Array:
	var def := Roster.find(id)
	return def.moveset.valid_loadout(_saved_loadouts.get(id, []))


func save_loadout(id: StringName, picks: Array) -> void:
	_saved_loadouts[id] = picks.duplicate()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("loadouts", String(id), picks)
	cfg.save(SETTINGS)


func _reset_lobby() -> void:
	rival_pick = &""
	rival_ready = false
	rival_in_arena = false


func send_pick(ready: bool) -> void:
	Net.send_event({type = "pick", id = String(my_character), ready = ready, loadout = my_loadout})


## Anfitrión: arrancar cuando los dos estén listos.
func host_start() -> void:
	rival_character = rival_pick
	rival_loadout = rival_pick_loadout
	Net.send_event({type = "start", host = String(my_character), guest = String(rival_pick),
			host_loadout = my_loadout, guest_loadout = rival_pick_loadout})
	match_start.emit()


func request_select() -> void:
	Net.send_event({type = "to_select"})


## Lo que llega por red no es de fiar: solo una lista corta de enteros.
func _clean_loadout(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for x: Variant in (v as Array).slice(0, Moveset.LOADOUT_SIZE):
			if x is int or x is float:
				out.append(int(x))
	return out


func _on_event(e: Dictionary) -> void:
	match e.get("type", ""):
		"pick":
			rival_pick = StringName(e.get("id", ""))
			rival_ready = bool(e.get("ready", false))
			rival_pick_loadout = _clean_loadout(e.get("loadout", []))
			rival_in_arena = false
			rival_pick_changed.emit()
		"start":
			my_character = StringName(e.get("guest", my_character))
			rival_character = StringName(e.get("host", rival_character))
			my_loadout = _clean_loadout(e.get("guest_loadout", my_loadout))
			rival_loadout = _clean_loadout(e.get("host_loadout", []))
			match_start.emit()
		"arena_ready":
			rival_in_arena = true
		"to_select":
			to_select.emit()

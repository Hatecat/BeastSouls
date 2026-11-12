extends Node
## Autoload "Session": lo que pasa de una escena a otra (personajes elegidos) y el estado del rival en el
## lobby online. Escucha los eventos de red siempre, así no se pierde nada aunque llegue mientras se cambia
## de escena (p. ej. el rival elige personaje antes de que nosotros salgamos de la arena).

signal rival_pick_changed
## El anfitrión ha arrancado la partida (llega al invitado; el anfitrión lo emite para sí mismo).
signal match_start
## El rival pide volver al selector de personaje.
signal to_select

const SELECT := "res://ui/character_select.tscn"
const ARENA := "res://levels/arena_test/arena_test.tscn"

var my_character: StringName = &"charizard"
## Online: el personaje del rival. Práctica: el de la IA.
var rival_character: StringName = &"charizard"

## Lobby online: elección actual del rival y si ha pulsado "Listo".
var rival_pick: StringName = &""
var rival_ready := false
## El rival ha cargado la arena (el anfitrión espera a esto para empezar la primera ronda).
var rival_in_arena := false

## Argumentos de línea de comandos para pruebas: --char=ID --rival=ID --autoready.
var auto_ready := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--char="):
			my_character = StringName(a.trim_prefix("--char="))
		elif a.begins_with("--rival="):
			rival_character = StringName(a.trim_prefix("--rival="))
		elif a == "--autoready":
			auto_ready = true
	Net.event_received.connect(_on_event)
	Net.connected.connect(_reset_lobby)


func _reset_lobby() -> void:
	rival_pick = &""
	rival_ready = false
	rival_in_arena = false


func send_pick(ready: bool) -> void:
	Net.send_event({type = "pick", id = String(my_character), ready = ready})


## Anfitrión: arrancar cuando los dos estén listos.
func host_start() -> void:
	rival_character = rival_pick
	Net.send_event({type = "start", host = String(my_character), guest = String(rival_pick)})
	match_start.emit()


func request_select() -> void:
	Net.send_event({type = "to_select"})


func _on_event(e: Dictionary) -> void:
	match e.get("type", ""):
		"pick":
			rival_pick = StringName(e.get("id", ""))
			rival_ready = bool(e.get("ready", false))
			rival_in_arena = false
			rival_pick_changed.emit()
		"start":
			my_character = StringName(e.get("guest", my_character))
			rival_character = StringName(e.get("host", rival_character))
			match_start.emit()
		"arena_ready":
			rival_in_arena = true
		"to_select":
			to_select.emit()

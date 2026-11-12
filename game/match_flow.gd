class_name MatchFlow
extends Node
## Partida al mejor de N rondas: cuenta atrás, K.O., marcador, fin de partida y revancha.
##
## Decide la AUTORIDAD (en práctica, esta máquina; online, el anfitrión): ella cuenta las muertes y anuncia
## cada ronda ("round") y cada final de ronda ("round_over"). Cada máquina solo coloca/revive a SU Beast
## (el proxy del rival le sigue por las instantáneas). Las muertes llegan por NetMatch.remote_died.

signal match_finished(won: bool)

enum Phase { WAITING, COUNTDOWN, FIGHT, ROUND_OVER, MATCH_OVER }

@export var rounds_to_win := 2
@export var countdown := 3
@export var round_over_delay := 3.5

var local: Beast
var rival: Beast
var hud: Hud
## Para recolocarla detrás del jugador en cada ronda (opcional).
var camera: ThirdPersonCamera
## [posición, orientación] de cada lado (0 = anfitrión/jugador, 1 = invitado/IA).
var spawns: Array
var online := false
var phase := Phase.WAITING
var round_n := 0
## Victorias por LADO (0 = anfitrión/jugador, 1 = invitado/IA).
var wins := [0, 0]

var _me := 0
var _token := 0
var _rematch_me := false
var _rematch_them := false


func setup(local_beast: Beast, rival_beast: Beast, the_hud: Hud, spawn_points: Array, is_online: bool, net_match: NetMatch) -> void:
	local = local_beast
	rival = rival_beast
	hud = the_hud
	spawns = spawn_points
	online = is_online
	_me = Net.side if online else 0
	local.died.connect(_on_beast_died.bind(_me))
	if online:
		net_match.remote_died.connect(_on_beast_died.bind(1 - _me))
	else:
		rival.died.connect(_on_beast_died.bind(1))


func is_authority() -> bool:
	return not online or Net.mode == Net.Mode.HOST


func _ready() -> void:
	if online:
		Net.event_received.connect(_on_event)
	_update_score()
	_freeze(true)
	_place_mine()
	if not online:
		_start_match.call_deferred()
	elif is_authority():
		_host_wait_for_guest()
	else:
		Net.send_event({type = "arena_ready"})


func _exit_tree() -> void:
	_token += 1
	if Net.event_received.is_connected(_on_event):
		Net.event_received.disconnect(_on_event)


func _host_wait_for_guest() -> void:
	var token := _token
	hud.show_banner("ESPERANDO AL RIVAL…", Color(0.85, 0.85, 0.85), 30.0, 0.3)
	while not Session.rival_in_arena:
		await get_tree().process_frame
		if token != _token:
			return
	_start_match()


# --- Autoridad ------------------------------------------------------------------------

func _start_match() -> void:
	wins = [0, 0]
	_rematch_me = false
	_rematch_them = false
	_announce_round(1)


func _announce_round(n: int) -> void:
	if online:
		Net.send_event({type = "round", n = n, wins = wins})
	_begin_round(n, wins)


func _on_beast_died(side: int) -> void:
	if not is_authority() or phase != Phase.FIGHT:
		return
	var winner := 1 - side
	wins[winner] += 1
	var final: bool = wins[winner] >= rounds_to_win
	if online:
		Net.send_event({type = "round_over", winner = winner, wins = wins, final = final})
	_round_over(winner, wins, final)
	if not final:
		var token := _token
		await get_tree().create_timer(round_over_delay, false).timeout
		if token == _token and phase == Phase.ROUND_OVER:
			_announce_round(round_n + 1)


# --- Ambos lados ----------------------------------------------------------------------

func _begin_round(n: int, w: Array) -> void:
	_token += 1
	var token := _token
	round_n = n
	wins = w.duplicate()
	phase = Phase.COUNTDOWN
	hud.hide_match_over()
	_update_score()
	_freeze(true)
	_place_mine()
	local.revive()
	if not online:
		rival.revive()
	var final_round: bool = wins[0] == rounds_to_win - 1 and wins[1] == rounds_to_win - 1
	hud.show_banner("RONDA FINAL" if final_round else "RONDA %d" % n, Color(0.95, 0.85, 0.6), 0.6, 0.2)
	await get_tree().create_timer(1.3, false).timeout
	for i in range(countdown, 0, -1):
		if token != _token:
			return
		hud.show_banner(str(i), Color(1, 1, 1), 0.45, 0.05)
		Audio.play_ui("count", -2.0)
		await get_tree().create_timer(0.7, false).timeout
	if token != _token:
		return
	hud.show_banner("¡LUCHA!", Color(1.0, 0.55, 0.2), 0.5, 0.05)
	Audio.play_ui("fight", 0.0)
	Audio.music("combat")
	phase = Phase.FIGHT
	_freeze(false)


func _round_over(winner: int, w: Array, final: bool) -> void:
	_token += 1
	var token := _token
	wins = w.duplicate()
	phase = Phase.ROUND_OVER
	_update_score()
	hud.show_banner("K.O.", Color(0.9, 0.15, 0.1), 1.0, 0.1)
	Audio.play("guard_break", Vector3.INF, 0.0, 0.7, 0.0)
	await get_tree().create_timer(1.6, false).timeout
	if token != _token:
		return
	_freeze(true)
	var won := winner == _me
	if not final:
		var text := "GANAS LA RONDA" if won else "%s GANA LA RONDA" % _side_name(winner).to_upper()
		hud.show_banner(text, Color(0.95, 0.8, 0.35) if won else Color(0.8, 0.8, 0.85), 1.4, 0.3)
		return
	phase = Phase.MATCH_OVER
	await get_tree().create_timer(0.6, false).timeout
	if token != _token:
		return
	Audio.music("", 0.8)
	Audio.stinger("victory" if won else "defeat")
	_show_match_over(won)
	match_finished.emit(won)


func _show_match_over(won: bool) -> void:
	var score := "%d – %d" % [wins[_me], wins[1 - _me]]
	var buttons := [
		["Revancha", _on_rematch_pressed],
		["Elegir personaje", _on_select_pressed],
		["Salir al menú", _on_quit_pressed],
	]
	hud.show_match_over("VICTORIA" if won else "DERROTA", Color(0.95, 0.8, 0.35) if won else Color(0.75, 0.15, 0.1),
			"%s  %s  %s" % [_side_name(_me), score, _side_name(1 - _me)], buttons)


func _on_rematch_pressed() -> void:
	if not online:
		_start_match()
		return
	_rematch_me = true
	Net.send_event({type = "rematch"})
	hud.set_match_over_note("Esperando a que %s acepte la revancha…" % Net.remote_nick)
	_check_rematch()


func _check_rematch() -> void:
	if is_authority() and _rematch_me and _rematch_them and phase == Phase.MATCH_OVER:
		_start_match()


func _on_select_pressed() -> void:
	if online:
		Session.request_select()
	get_tree().change_scene_to_file(Session.SELECT)


func _on_quit_pressed() -> void:
	Net.close()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_event(e: Dictionary) -> void:
	match e.get("type", ""):
		"round":
			_begin_round(int(e.n), e.wins)
		"round_over":
			_round_over(int(e.winner), e.wins, bool(e.final))
		"rematch":
			_rematch_them = true
			if not _rematch_me:
				hud.set_match_over_note("%s quiere la revancha." % Net.remote_nick)
			_check_rematch()
		"to_select":
			get_tree().change_scene_to_file.call_deferred(Session.SELECT)


# --- Utilidades -----------------------------------------------------------------------

func _freeze(on: bool) -> void:
	local.frozen = on
	if not online:
		rival.frozen = on


## Coloca a los Beasts de esta máquina en su punto de aparición.
func _place_mine() -> void:
	_place(local, spawns[_me])
	if camera:
		camera.snap_behind()
	if not online:
		_place(rival, spawns[1])


func _place(b: Beast, spawn: Array) -> void:
	b.global_position = spawn[0]
	b.facing = spawn[1]
	b.velocity = Vector3.ZERO
	b.reset_physics_interpolation()


func _side_name(side: int) -> String:
	if side == _me:
		return Net.nick if online else "Tú"
	return Net.remote_nick if online else rival.name


func _update_score() -> void:
	var pips := func(n: int) -> String:
		var s := ""
		for i in rounds_to_win:
			s += "●" if i < n else "○"
		return s
	hud.set_score("%s  %s   %s  %s" % [_side_name(_me), pips.call(wins[_me]), pips.call(wins[1 - _me]), _side_name(1 - _me)])

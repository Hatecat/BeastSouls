extends Node3D
## Arena: práctica contra la IA o versus online (si Net está conectado al cargar la escena).
## Los personajes salen de Session; las rondas (al mejor de 3) las lleva MatchFlow.
##   F1: mostrar/ocultar hitboxes activas.
##   F2: cambiar el modo de la IA del rival (solo en práctica).

const MENU := "res://ui/main_menu.tscn"
## Puntos de aparición [posición, orientación]: 0 = anfitrión / jugador, 1 = invitado / rival.
const SPAWNS := [[Vector3(0, 0, 6), 0.0], [Vector3(0, 0, -4), PI]]

@onready var hud: Hud = $HUD
@onready var player: Beast = $Player
@onready var rival: Beast = $Rival
@onready var camera: ThirdPersonCamera = $Camera
@onready var dummy_brain: DummyBrain = $DummyBrain

var net_match: NetMatch
var match_flow: MatchFlow


func _ready() -> void:
	var mine := Roster.find(Session.my_character)
	var theirs := Roster.find(Session.rival_character)
	player.apply_character(mine)
	rival.apply_character(theirs)
	camera.fit_to_size(clampf(mine.body_height / 2.0, 0.85, 1.35))
	Fx.prewarm(self, _effect_colors([mine, theirs]))
	var online := Net.is_online()
	if online:
		dummy_brain.queue_free()
		dummy_brain = null
		hud.dummy_brain = null
		player.name = Net.nick.validate_node_name()
		rival.name = Net.remote_nick.validate_node_name()
		net_match = NetMatch.new()
		net_match.name = "NetMatch"
		net_match.setup(player, rival)  # antes de add_child: su _ready usa el proxy
		add_child(net_match)
		net_match.ended.connect(_on_net_ended)
	else:
		rival.name = theirs.display_name
	match_flow = MatchFlow.new()
	match_flow.name = "MatchFlow"
	match_flow.setup(player, rival, hud, SPAWNS, online, net_match)
	match_flow.camera = camera
	add_child(match_flow)


func _effect_colors(defs: Array[CharacterDef]) -> Array[Color]:
	var out: Array[Color] = []
	for d in defs:
		for a in d.moveset.abilities:
			if a.color not in out:
				out.append(a.color)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_hitboxes"):
		Beast.debug_hitboxes = not Beast.debug_hitboxes
	elif event.is_action_pressed("debug_ai") and dummy_brain:
		dummy_brain.next_mode()


func _on_net_ended(reason: String) -> void:
	match_flow.queue_free()
	hud.hide_match_over()
	hud.show_banner("RIVAL DESCONECTADO" if reason == "left" else "CONEXIÓN PERDIDA", Color(0.8, 0.8, 0.8))
	await get_tree().create_timer(3.0).timeout
	Net.close()
	get_tree().change_scene_to_file(MENU)

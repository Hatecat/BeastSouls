extends Node3D
## Arena: práctica contra la IA o versus online (si Net está conectado al cargar la escena).
##   F1: mostrar/ocultar hitboxes activas.
##   F2: cambiar el modo de la IA del rival (solo en práctica).

const MENU := "res://ui/main_menu.tscn"
## Puntos de aparición [posición, orientación]: 0 = anfitrión / jugador, 1 = invitado / rival.
const SPAWNS := [[Vector3(0, 0, 6), 0.0], [Vector3(0, 0, -4), PI]]

@export var respawn_delay := 3.0

@onready var hud: Hud = $HUD
@onready var player: Beast = $Player
@onready var rival: Beast = $Rival
@onready var camera: ThirdPersonCamera = $Camera
@onready var dummy_brain: DummyBrain = $DummyBrain

var net_match: NetMatch
var _spawns := {}


func _ready() -> void:
	Fx.prewarm(self)
	if Net.is_online():
		_setup_online()
	else:
		rival.died.connect(hud.show_banner.bind("VICTORIA", Color(0.95, 0.8, 0.35)))
		rival.died.connect(_on_died.bind(rival))
		_spawns[rival] = [rival.global_position, rival.facing]
	_spawns[player] = [player.global_position, player.facing]
	player.died.connect(_on_died.bind(player))


func _setup_online() -> void:
	dummy_brain.queue_free()
	dummy_brain = null
	hud.dummy_brain = null
	var mine: Array = SPAWNS[Net.side]
	var theirs: Array = SPAWNS[1 - Net.side]
	_place(player, mine)
	_place(rival, theirs)
	rival.name = Net.remote_nick.validate_node_name()
	camera.snap_behind()
	net_match = NetMatch.new()
	net_match.name = "NetMatch"
	net_match.setup(player, rival)  # antes de add_child: su _ready usa el proxy
	add_child(net_match)
	net_match.remote_died.connect(hud.show_banner.bind("VICTORIA", Color(0.95, 0.8, 0.35)))
	net_match.score_changed.connect(func(a: int, b: int) -> void: hud.set_score("%s  %d – %d  %s" % [Net.nick, a, b, Net.remote_nick]))
	net_match.ended.connect(_on_net_ended)
	hud.set_score("%s  0 – 0  %s" % [Net.nick, Net.remote_nick])


func _place(b: Beast, spawn: Array) -> void:
	b.global_position = spawn[0]
	b.facing = spawn[1]
	b.reset_physics_interpolation()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_hitboxes"):
		Beast.debug_hitboxes = not Beast.debug_hitboxes
	elif event.is_action_pressed("debug_ai") and dummy_brain:
		dummy_brain.next_mode()


func _on_died(b: Beast) -> void:
	await get_tree().create_timer(respawn_delay).timeout
	if not is_instance_valid(b):
		return
	_place(b, _spawns[b])
	b.revive()


func _on_net_ended(reason: String) -> void:
	hud.show_banner("RIVAL DESCONECTADO" if reason == "left" else "CONEXIÓN PERDIDA", Color(0.8, 0.8, 0.8))
	await get_tree().create_timer(3.0).timeout
	Net.close()
	get_tree().change_scene_to_file(MENU)

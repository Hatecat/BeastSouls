extends Node3D
## Arena de pruebas: reaparición tras morir y atajos de depuración.
##   F1: mostrar/ocultar hitboxes activas.
##   F2: cambiar el modo de la IA del rival.

@export var respawn_delay := 3.0

@onready var hud: Hud = $HUD
@onready var dummy_brain: DummyBrain = $DummyBrain

var _spawns := {}


func _ready() -> void:
	for b: Beast in get_tree().get_nodes_in_group(&"beasts"):
		_spawns[b] = [b.global_position, b.facing]
		b.died.connect(_on_died.bind(b))
	var dummy := dummy_brain.beast
	dummy.died.connect(hud.show_banner.bind("VICTORIA", Color(0.95, 0.8, 0.35)))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_hitboxes"):
		Beast.debug_hitboxes = not Beast.debug_hitboxes
	elif event.is_action_pressed("debug_ai"):
		dummy_brain.next_mode()


func _on_died(b: Beast) -> void:
	await get_tree().create_timer(respawn_delay).timeout
	if not is_instance_valid(b):
		return
	var spawn: Array = _spawns[b]
	b.global_position = spawn[0]
	b.facing = spawn[1]
	b.reset_physics_interpolation()
	b.revive()

class_name DummyBrain
extends Node
## IA de práctica: rodea al jugador y esquiva de vez en cuando, para probar el fijado de objetivo.
## Genera PlayerInput igual que un jugador, así que usa la misma simulación que él.

@export var beast: Beast
@export var target: Node3D
@export var active := true
## Distancia que intenta mantener respecto al objetivo.
@export var keep_distance := 6.0
@export var dodge_interval := Vector2(2.5, 5.0)

var _strafe_dir := 1.0
var _next_switch := 2.0
var _next_dodge := 3.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_physics_priority = -10
	_rng.seed = 1234


func _physics_process(delta: float) -> void:
	if beast == null or target == null or not active:
		return
	var frame := PlayerInput.new()
	frame.lock_target = target
	var to := target.global_position - beast.global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := to / maxf(dist, 0.001)
	var side := Vector3(-fwd.z, 0.0, fwd.x) * _strafe_dir
	var approach := clampf((dist - keep_distance) * 0.5, -1.0, 1.0)
	var m := (side + fwd * approach).limit_length(1.0) * 0.8
	frame.move = Vector2(m.x, m.z)

	_next_switch -= delta
	if _next_switch <= 0.0:
		_strafe_dir = -_strafe_dir
		_next_switch = _rng.randf_range(1.5, 3.5)
	_next_dodge -= delta
	if _next_dodge <= 0.0:
		frame.buttons |= PlayerInput.DODGE
		_next_dodge = _rng.randf_range(dodge_interval.x, dodge_interval.y)
	beast.input = frame

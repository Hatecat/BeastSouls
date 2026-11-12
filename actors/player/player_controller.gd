class_name PlayerController
extends Node
## Convierte el teclado/ratón/mando del jugador local en un PlayerInput por tick
## y se lo entrega a su Beast. También maneja la captura del ratón y el fijado de objetivo.

@export var beast: Beast
@export var camera: ThirdPersonCamera
## Mantener el botón de esquivar más de esto = correr; soltarlo antes = esquivar.
@export var sprint_hold_time := 0.28

var _dodge_down := false
var _dodge_held := 0.0
## Ticks en los que se ignoran los ataques (tras el clic que recaptura el ratón).
var _suppress_attacks := 0


func _ready() -> void:
	# Antes que el Beast, para que simule con el input de este mismo tick.
	process_physics_priority = -10
	if camera and beast:
		camera.follow = beast
		camera.snap_behind()
		beast.hit_landed.connect(_on_hit_landed)
		beast.hit_received.connect(_on_hit_received)
	_capture_mouse(true)


func _physics_process(delta: float) -> void:
	if beast == null:
		return
	var frame := PlayerInput.new()

	# Movimiento relativo a la cámara.
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var yaw := camera.yaw if camera else 0.0
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	frame.move = (right * raw.x + fwd * -raw.y).limit_length(1.0)

	# Esquivar (toque) / correr (mantener) en el mismo botón.
	if Input.is_action_just_pressed("dodge"):
		_dodge_down = true
		_dodge_held = 0.0
	if _dodge_down:
		if Input.is_action_pressed("dodge"):
			_dodge_held += delta
			if _dodge_held >= sprint_hold_time:
				frame.held |= PlayerInput.SPRINT
		else:
			if _dodge_held < sprint_hold_time:
				frame.buttons |= PlayerInput.DODGE
			_dodge_down = false

	if Input.is_action_pressed("block"):
		frame.held |= PlayerInput.BLOCK
	if _suppress_attacks > 0 or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_suppress_attacks -= 1
	else:
		if Input.is_action_just_pressed("attack_light"):
			frame.buttons |= PlayerInput.LIGHT
		if Input.is_action_just_pressed("attack_heavy"):
			frame.buttons |= PlayerInput.HEAVY
		if Input.is_action_pressed("attack_heavy"):
			frame.held |= PlayerInput.HEAVY_HELD
	for i in 4:
		if Input.is_action_just_pressed("ability_%d" % (i + 1)):
			frame.buttons |= PlayerInput.ABILITY_1 << i

	if camera:
		if Input.is_action_just_pressed("lock_on"):
			camera.toggle_lock()
		frame.lock_target = camera.lock_target

	beast.input = frame


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_capture_mouse(false)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# El clic que recaptura el ratón no debe contar como ataque.
		_capture_mouse(true)
		_suppress_attacks = 2
		get_viewport().set_input_as_handled()
	elif camera and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.is_action_pressed("target_prev"):
			camera.switch_target(-1)
		elif event.is_action_pressed("target_next"):
			camera.switch_target(1)


func _on_hit_landed(_target: Beast, result: Beast.HitResult) -> void:
	camera.add_shake(0.15 if result == Beast.HitResult.BLOCKED else 0.3)


func _on_hit_received(_attacker: Beast, result: Beast.HitResult, _damage: float) -> void:
	match result:
		Beast.HitResult.BLOCKED:
			camera.add_shake(0.25)
		Beast.HitResult.IGNORED:
			pass
		_:
			camera.add_shake(0.55)


func _capture_mouse(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

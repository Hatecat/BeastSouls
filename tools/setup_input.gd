extends SceneTree
## Escribe el InputMap por defecto en project.godot (teclado/ratón + mando).
## Uso: godot --headless --path . --script tools/setup_input.gd
## Es idempotente: reemplaza las acciones listadas y deja intactas las demás.


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.device = -1
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.device = -1
	return e


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = -1
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = -1
	return e


func _initialize() -> void:
	# acción -> [deadzone, eventos]
	var actions := {
		# Movimiento (WASD / stick izquierdo)
		"move_forward": [0.2, [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)]],
		"move_back": [0.2, [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)]],
		"move_left": [0.2, [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)]],
		"move_right": [0.2, [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)]],
		# Cámara con mando (el ratón se lee aparte como movimiento relativo)
		"camera_left": [0.15, [_axis(JOY_AXIS_RIGHT_X, -1.0)]],
		"camera_right": [0.15, [_axis(JOY_AXIS_RIGHT_X, 1.0)]],
		"camera_up": [0.15, [_axis(JOY_AXIS_RIGHT_Y, -1.0)]],
		"camera_down": [0.15, [_axis(JOY_AXIS_RIGHT_Y, 1.0)]],
		# Combate
		"attack_light": [0.5, [_mouse(MOUSE_BUTTON_LEFT), _joy(JOY_BUTTON_RIGHT_SHOULDER)]],
		"attack_heavy": [0.5, [_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]],
		"block": [0.5, [_key(KEY_SHIFT), _joy(JOY_BUTTON_LEFT_SHOULDER)]],
		"dodge": [0.5, [_key(KEY_SPACE), _joy(JOY_BUTTON_B)]],  # toque = esquivar, mantener = correr
		"lock_on": [0.5, [_mouse(MOUSE_BUTTON_MIDDLE), _key(KEY_TAB), _joy(JOY_BUTTON_RIGHT_STICK)]],
		"target_prev": [0.5, [_mouse(MOUSE_BUTTON_WHEEL_UP)]],
		"target_next": [0.5, [_mouse(MOUSE_BUTTON_WHEEL_DOWN)]],
		# Habilidades (1-4 / cruceta)
		"ability_1": [0.5, [_key(KEY_1), _joy(JOY_BUTTON_DPAD_UP)]],
		"ability_2": [0.5, [_key(KEY_2), _joy(JOY_BUTTON_DPAD_RIGHT)]],
		"ability_3": [0.5, [_key(KEY_3), _joy(JOY_BUTTON_DPAD_DOWN)]],
		"ability_4": [0.5, [_key(KEY_4), _joy(JOY_BUTTON_DPAD_LEFT)]],
		# Varios
		"interact": [0.5, [_key(KEY_E), _joy(JOY_BUTTON_A)]],
		"pause": [0.5, [_key(KEY_ESCAPE), _joy(JOY_BUTTON_START)]],
		# Depuración (visor de animaciones del sandbox)
		"debug_prev": [0.5, [_key(KEY_LEFT)]],
		"debug_next": [0.5, [_key(KEY_RIGHT)]],
		"debug_hitboxes": [0.5, [_key(KEY_F1)]],
		"debug_ai": [0.5, [_key(KEY_F2)]],
		"debug_quality": [0.5, [_key(KEY_F3)]],
	}
	for action: String in actions:
		var def: Array = actions[action]
		ProjectSettings.set_setting("input/" + action, {"deadzone": def[0], "events": def[1]})
	var err := ProjectSettings.save()
	print("InputMap: %d acciones escritas (err=%d)" % [actions.size(), err])
	quit(err)

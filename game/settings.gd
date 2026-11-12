extends Node
## Autoload "Settings": opciones del jugador (sonido, controles, pantalla, interfaz) y teclas reasignadas.
## Se guardan en user://settings.cfg (la calidad gráfica la guarda Graphics en el mismo archivo).

signal changed
## Cambió el dispositivo en uso (mando ↔ teclado/ratón): la ayuda se adapta.
signal device_changed(pad: bool)

const PATH := "user://settings.cfg"
## Acciones que se pueden reasignar (teclado/ratón), en el orden del menú.
const REBINDABLE := [
	["move_forward", "Avanzar"], ["move_back", "Retroceder"], ["move_left", "Izquierda"], ["move_right", "Derecha"],
	["attack_light", "Ataque ligero"], ["attack_heavy", "Ataque fuerte"], ["block", "Bloquear"],
	["dodge", "Esquivar / correr"], ["jump", "Saltar"], ["lock_on", "Fijar objetivo"],
	["ability_1", "Habilidad 1"], ["ability_2", "Habilidad 2"], ["ability_3", "Habilidad 3"], ["ability_4", "Habilidad 4"],
]
const KEY_NAMES := {"Space": "Espacio", "Shift": "Mayús", "Ctrl": "Ctrl", "Alt": "Alt", "Tab": "Tab",
	"Enter": "Intro", "Escape": "Esc", "Backspace": "Retroceso", "CapsLock": "Bloq Mayús", "Up": "↑", "Down": "↓",
	"Left": "←", "Right": "→"}
const BUSES := ["Music", "SFX", "Ambience", "UI"]

var master_volume := 0.8
var music_volume := 0.6
var sfx_volume := 0.9
var ambience_volume := 0.7
## Multiplicadores sobre la sensibilidad base de la cámara.
var mouse_sensitivity := 1.0
var stick_sensitivity := 1.0
var invert_y := false
var rumble := true
var fullscreen := false
var vsync := true
var show_debug := false
var show_help := true
## El último input fue de mando.
var using_pad := false

## Teclas por defecto (las del InputMap al arrancar) y las elegidas por el jugador: acción -> InputEvent.
var _defaults := {}
var _bindings := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiTheme.apply()
	_ensure_buses()
	_add_pad_ui_events()
	for pair in REBINDABLE:
		_defaults[pair[0]] = primary_event(pair[0])
	_load()
	apply()


## Las acciones de interfaz de Godot no traen botones de mando para aceptar/volver: A acepta, B vuelve.
func _add_pad_ui_events() -> void:
	for pair in [[&"ui_accept", JOY_BUTTON_A], [&"ui_cancel", JOY_BUTTON_B]]:
		var has := false
		for e in InputMap.action_get_events(pair[0]):
			if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == pair[1]:
				has = true
		if not has:
			var j := InputEventJoypadButton.new()
			j.button_index = pair[1]
			j.device = -1
			InputMap.action_add_event(pair[0], j)


func _input(event: InputEvent) -> void:
	var pad := using_pad
	if event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 4.0:
		pad = false
	if pad != using_pad:
		using_pad = pad
		device_changed.emit(pad)


func _ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, &"Master")


func apply() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("UI", sfx_volume)
	_set_bus("Ambience", ambience_volume)
	if not DisplayServer.get_name() == "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode and not (mode == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	for action: String in _bindings:
		_set_primary(action, _bindings[action])
	changed.emit()


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	apply()
	save()


func _set_bus(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(i, linear <= 0.001)


# --- Teclas -----------------------------------------------------------------------------

## Primer evento de teclado o ratón de la acción (el que se muestra y se reasigna).
func primary_event(action: String) -> InputEvent:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			return e
	return null


func rebind(action: String, event: InputEvent) -> void:
	var e := event.duplicate() as InputEvent
	e.device = -1
	if e is InputEventKey:
		(e as InputEventKey).pressed = false
	if e is InputEventMouseButton:
		(e as InputEventMouseButton).pressed = false
		(e as InputEventMouseButton).double_click = false
	# Si otra acción ya la usaba, se intercambian.
	var previous := primary_event(action)
	for pair in REBINDABLE:
		var other: String = pair[0]
		var cur := primary_event(other)
		if other != action and cur and _same(cur, e) and previous:
			_bindings[other] = previous.duplicate()
			_set_primary(other, _bindings[other])
	_bindings[action] = e
	_set_primary(action, e)
	save()
	changed.emit()


func reset_bindings() -> void:
	_bindings.clear()
	for action: String in _defaults:
		if _defaults[action]:
			_set_primary(action, _defaults[action])
	save()
	changed.emit()


func _set_primary(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action) or event == null:
		return
	var old := primary_event(action)
	if old:
		InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, event)


static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		return (ka.physical_keycode if ka.physical_keycode else ka.keycode) == (kb.physical_keycode if kb.physical_keycode else kb.keycode)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


static func event_text(e: InputEvent) -> String:
	if e == null:
		return "—"
	if e is InputEventMouseButton:
		match (e as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Clic izquierdo"
			MOUSE_BUTTON_RIGHT: return "Clic derecho"
			MOUSE_BUTTON_MIDDLE: return "Clic de rueda"
			MOUSE_BUTTON_XBUTTON1: return "Ratón 4"
			MOUSE_BUTTON_XBUTTON2: return "Ratón 5"
			_: return "Ratón %d" % (e as InputEventMouseButton).button_index
	if e is InputEventKey:
		var k := e as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		var layout := k.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless"
		var text := OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code) if layout else code)
		return KEY_NAMES.get(text, text)
	return e.as_text()


# --- Guardar ----------------------------------------------------------------------------

const KEYS := ["master_volume", "music_volume", "sfx_volume", "ambience_volume", "mouse_sensitivity",
	"stick_sensitivity", "invert_y", "rumble", "fullscreen", "vsync", "show_debug", "show_help"]


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for k: String in KEYS:
		cfg.set_value("options", k, get(k))
	if cfg.has_section("bindings"):
		cfg.erase_section("bindings")
	for action: String in _bindings:
		cfg.set_value("bindings", action, _bindings[action])
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k: String in KEYS:
		if cfg.has_section_key("options", k):
			set(k, cfg.get_value("options", k))
	if cfg.has_section("bindings"):
		for action in cfg.get_section_keys("bindings"):
			var e: Variant = cfg.get_value("bindings", action)
			if e is InputEvent:
				_bindings[action] = e

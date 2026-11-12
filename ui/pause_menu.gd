class_name PauseMenu
extends CanvasLayer
## Menú de pausa (Esc / Start). En práctica congela el juego; online no se puede pausar al rival, así que
## solo bloquea el input local (el Beast se queda quieto, pero puede recibir golpes).

const MENU := "res://ui/main_menu.tscn"

var online := false
var controller: PlayerController

var _root: Control
var _panel: PanelContainer
var _options: OptionsMenu
var _prev_mouse := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(380, 0)
	_root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "PAUSA" if not online else "MENÚ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiTheme.title_font())
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", UiTheme.AMBER)
	box.add_child(title)
	if online:
		var note := Label.new()
		note.text = "La partida sigue en marcha"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_color_override("font_color", UiTheme.DIM)
		note.add_theme_font_size_override("font_size", 14)
		box.add_child(note)
	box.add_child(HSeparator.new())
	_button(box, "Continuar", close)
	_button(box, "Guía de controles", _open_options.bind(OptionsMenu.TAB_GUIDE))
	_button(box, "Opciones", _open_options.bind(0))
	_button(box, "Abandonar partida" if online else "Salir al menú", _quit)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if is_open():
		return
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true
	_panel.visible = true
	if controller:
		controller.blocked = true
	if not online:
		get_tree().paused = true
	Audio.play_ui("ui_confirm", -6.0)
	(_panel.find_children("*", "Button", true, false)[0] as Button).grab_focus.call_deferred()


func close() -> void:
	if not is_open():
		return
	if _options:
		_options.queue_free()
		_options = null
	_root.visible = false
	get_tree().paused = false
	if controller:
		controller.blocked = false
		controller.ignore_attacks(3)
	Input.mouse_mode = _prev_mouse


func _open_options(tab: int) -> void:
	_panel.visible = false
	_options = OptionsMenu.new()
	_options.start_tab = tab
	_root.add_child(_options)
	_options.closed.connect(func() -> void:
		_options = null
		_panel.visible = true
		(_panel.find_children("*", "Button", true, false)[0] as Button).grab_focus.call_deferred())


func _quit() -> void:
	get_tree().paused = false
	Net.close()
	get_tree().change_scene_to_file(MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if is_open():
			if _options == null:
				close()
		else:
			open()
	elif is_open() and _options == null and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

class_name OptionsMenu
extends PanelContainer
## Opciones (gráficos, sonido, controles, interfaz). Se usa desde el menú principal y desde la pausa.
## Todo se aplica y se guarda al momento (Settings / Graphics).

signal closed

const TAB_GUIDE := 4
## Pestaña con la que se abre (p. ej. TAB_GUIDE desde «Controles» en la pausa).
var start_tab := 0

var _waiting_action := ""
var _bind_buttons := {}
var _tabs: TabContainer
var _guide_box: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(820, 600)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	var title := Label.new()
	title.text = "OPCIONES"
	title.add_theme_font_override("font", UiTheme.spaced_font(5))
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UiTheme.AMBER)
	root.add_child(title)
	root.add_child(UiTheme.ornament(700))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_build_graphics()
	_build_sound()
	_build_controls()
	_build_interface()
	_build_guide()
	_tabs.current_tab = start_tab
	var back := Button.new()
	back.text = "Volver"
	back.custom_minimum_size = Vector2(180, 42)
	back.pressed.connect(close)
	var foot := HBoxContainer.new()
	var hints := HintBar.make([["A", "Enter", "Elegir"], ["B", "Esc", "Volver"], ["◂ ▸", "← →", "Cambiar valor o pestaña"]])
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hints)
	foot.add_child(back)
	root.add_child(foot)
	Settings.changed.connect(_refresh_bindings)
	_tabs.get_tab_bar().grab_focus.call_deferred()


func close() -> void:
	Audio.play_ui("ui_back", -4.0)
	closed.emit()
	queue_free()


func _page(name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 18)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	return box


func _row(parent: Control, label: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.set_meta(&"focus_frame", true)  # el cursor de foco enmarca la fila entera
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 280
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	parent.add_child(row)
	return control


func _check(parent: Control, label: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = Settings.get(key)
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	_row(parent, label, c)
	return c


func _slider(parent: Control, label: String, key: String, lo: float, hi: float, step: float, percent := true) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = Settings.get(key)
	s.custom_minimum_size.x = 260
	var value := Label.new()
	value.custom_minimum_size.x = 64
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var fmt := func(v: float) -> String: return "%d %%" % roundi(v * 100.0) if percent else "%.2f×" % v
	value.text = fmt.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		value.text = fmt.call(v)
		Settings.set_value(key, v)
		if key.ends_with("volume") and key != "music_volume":
			Audio.play_ui("ui_hover", -2.0))
	var h := HBoxContainer.new()
	h.add_child(s)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(value)
	_row(parent, label, h)
	return s


func _build_graphics() -> void:
	var p := _page("Gráficos")
	var q := OptionButton.new()
	for n in Graphics.NAMES:
		q.add_item(n)
	q.selected = Graphics.quality
	q.item_selected.connect(Graphics.set_quality)
	_row(p, "Calidad", q)
	var hint := Label.new()
	hint.text = "Bajo ≈ 240 fps · Medio ≈ 145 · Alto ≈ 88 · Ultra ≈ 54 (RTX 3050, 1080p). F3 la cambia en partida."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UiTheme.DIM)
	hint.add_theme_font_size_override("font_size", 14)
	p.add_child(hint)
	_check(p, "Pantalla completa", "fullscreen")
	_check(p, "Sincronización vertical (VSync)", "vsync")


func _build_sound() -> void:
	var p := _page("Sonido")
	_slider(p, "Volumen general", "master_volume", 0.0, 1.0, 0.01)
	_slider(p, "Música", "music_volume", 0.0, 1.0, 0.01)
	_slider(p, "Efectos", "sfx_volume", 0.0, 1.0, 0.01)
	_slider(p, "Ambiente", "ambience_volume", 0.0, 1.0, 0.01)


func _build_controls() -> void:
	var p := _page("Controles")
	_slider(p, "Sensibilidad del ratón", "mouse_sensitivity", 0.2, 3.0, 0.05, false)
	_slider(p, "Sensibilidad del stick", "stick_sensitivity", 0.2, 3.0, 0.05, false)
	_check(p, "Invertir eje vertical", "invert_y")
	_check(p, "Vibración del mando", "rumble")
	p.add_child(HSeparator.new())
	var head := Label.new()
	head.text = "Teclado y ratón (pulsa un botón y luego la tecla nueva; Esc cancela)"
	head.add_theme_color_override("font_color", UiTheme.DIM)
	head.add_theme_font_size_override("font_size", 15)
	p.add_child(head)
	for pair in Settings.REBINDABLE:
		var b := Button.new()
		b.custom_minimum_size = Vector2(220, 34)
		b.pressed.connect(_start_rebind.bind(pair[0]))
		_bind_buttons[pair[0]] = b
		_row(p, pair[1], b)
	_refresh_bindings()
	var reset := Button.new()
	reset.text = "Restaurar teclas por defecto"
	reset.pressed.connect(Settings.reset_bindings)
	p.add_child(reset)
	var pad := Label.new()
	pad.text = "Mando: stick izq. mover · L3 correr · stick der. cámara · RB ligero · RT fuerte · LB bloquear · B esquivar · A saltar · R3 fijar · X / Y habilidades · LT + X / Y secundarias · Start pausa (detalles en «Guía de controles»)"
	pad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pad.add_theme_color_override("font_color", UiTheme.DIM)
	pad.add_theme_font_size_override("font_size", 14)
	p.add_child(pad)


func _build_guide() -> void:
	var p := _page("Guía de controles")
	_guide_box = p
	_fill_guide()
	Settings.device_changed.connect(func(_pad: bool) -> void: _fill_guide())


func _fill_guide() -> void:
	for c in _guide_box.get_children():
		c.queue_free()
	var intro := Label.new()
	intro.text = "Estamina (verde): la gastan ataques, bloqueos, esquivas y correr; se recupera sola. Postura: si la vacías a golpes, el rival queda aturdido. Cada golpe empuja al que lo recibe y le corta los ataques ligeros y casi todas las habilidades. PP (azul): pagan las habilidades y se regeneran solos poco a poco; además cada habilidad tiene su tiempo de recarga."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 15)
	_guide_box.add_child(intro)
	_guide_box.add_child(ControlsHelp.build_table(Settings.using_pad))


func _build_interface() -> void:
	var p := _page("Interfaz")
	_check(p, "Mostrar ayuda de controles en partida", "show_help")
	_check(p, "Mostrar panel de depuración (FPS, estado)", "show_debug")


func _refresh_bindings() -> void:
	for action: String in _bind_buttons:
		var b: Button = _bind_buttons[action]
		b.text = "Pulsa una tecla…" if action == _waiting_action else Settings.event_text(Settings.primary_event(action))


func _start_rebind(action: String) -> void:
	_waiting_action = action
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if _waiting_action != "":
		var done := false
		if event is InputEventKey and event.pressed and not event.echo:
			if (event as InputEventKey).keycode != KEY_ESCAPE:
				Settings.rebind(_waiting_action, event)
			done = true
		elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			Settings.rebind(_waiting_action, event)
			done = true
		if done:
			get_viewport().set_input_as_handled()
			_waiting_action = ""
			_refresh_bindings()
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

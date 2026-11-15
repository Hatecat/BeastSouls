extends Control
## Menú principal: el coliseo en 3D de fondo (cámara orbitando y un personaje al azar), y a la izquierda
## práctica, partida online (alojar / unirse), opciones y salir.
##
## Argumentos de línea de comandos (tras `--`), para pruebas automáticas o accesos directos:
##   --practice                 entra directo a la práctica (personajes: --char=ID --rival=ID)
##   --autoready                el selector elige solo (--char) y se marca listo: para pruebas automáticas
##   --host                     aloja y espera rival
##   --join=IP                  se une a IP
##   --relay=IP [--room=CÓDIGO]  entra por un servidor de retransmisión, en esa sala
##   --server [--port=N]        arranca como servidor de retransmisión (con --headless; net/relay_server.gd)
##   --port=N  --nick=NOMBRE
##   --latency=MS --jitter=MS --loss=0.05   simulación de red (lo que envía este lado)

const ARENA := "res://levels/arena_test/arena_test.tscn"
const SELECT := "res://ui/character_select.tscn"
const STAGE := "res://levels/colosseum/colosseum.tscn"
const SERVER := "res://net/relay_server.tscn"
const SETTINGS := "user://settings.cfg"

var _nick: LineEdit
var _address: LineEdit
var _room: LineEdit
var _port: SpinBox
var _latency: SpinBox
var _status: Label
var _main_box: VBoxContainer
var _online_box: VBoxContainer
var _online_buttons: Array[Button] = []
var _cancel: Button
var _back: Button
var _options: OptionsMenu
var _panel: PanelContainer
var _blurb: Label
var _hints: HintBar

var _cam: Camera3D
var _cam_angle := 0.0
var _hero: CharacterVisual
## Los argumentos de línea de comandos solo se aplican la primera vez (al volver al menú, no).
static var _args_done := false


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--server") and not _args_done:
		_args_done = true
		get_tree().change_scene_to_file.call_deferred(SERVER)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	var direct := OS.get_cmdline_user_args().has("--practice") and not _args_done
	if not direct:
		_build_scene()
	_build()
	Net.connected.connect(_on_connected)
	Net.failed.connect(_on_failed)
	Net.waiting.connect(_on_waiting)
	Audio.music("menu")
	Audio.ambience("wind", -10.0)
	_apply_args()


func _exit_tree() -> void:
	for pair in [[Net.connected, _on_connected], [Net.failed, _on_failed], [Net.waiting, _on_waiting]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


# --- Fondo 3D -------------------------------------------------------------------------------

func _build_scene() -> void:
	var world := Node3D.new()
	world.name = "Background"
	add_child(world)
	world.add_child(load(STAGE).instantiate())
	var def: CharacterDef = Roster.all().pick_random()
	_hero = def.visual.instantiate()
	world.add_child(_hero)
	_hero.rotation.y = deg_to_rad(200.0)
	_hero.play(&"idle")
	_hero.action_finished.connect(func(_a: StringName) -> void: _hero.play(&"idle", 0.3))
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.current = true
	world.add_child(_cam)
	_cam_angle = deg_to_rad(-25.0)
	_update_camera(0.0)
	# De vez en cuando, el personaje lanza su habilidad de mejora (la más vistosa sin rival).
	var t := Timer.new()
	t.wait_time = 7.0
	t.autostart = true
	t.timeout.connect(func() -> void:
		if def.moveset and not def.moveset.abilities.is_empty():
			_hero.play(def.moveset.abilities[mini(3, def.moveset.abilities.size() - 1)].action, 0.2))
	add_child(t)
	# Viñeta y grano, como en partida.
	var post := ColorRect.new()
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/post_fx.gdshader")
	post.material = mat
	add_child(post)


func _process(delta: float) -> void:
	if _cam:
		_update_camera(delta)


func _update_camera(delta: float) -> void:
	_cam_angle += delta * 0.035
	var dist := 7.5
	var target := Vector3(0, 1.3, 0)
	# El personaje queda a la derecha del encuadre; el panel ocupa la izquierda.
	var pos := Vector3(sin(_cam_angle) * dist, 2.1 + sin(_cam_angle * 1.7) * 0.25, cos(_cam_angle) * dist)
	_cam.look_at_from_position(pos, target)
	_cam.rotate_object_local(Vector3.UP, deg_to_rad(14.0))


# --- Interfaz -------------------------------------------------------------------------------

func _build() -> void:
	# Degradado oscuro a la izquierda para que el texto se lea sobre el coliseo.
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0.02, 0.015, 0.01, 0.88))
	grad.gradient.set_color(1, Color(0.02, 0.015, 0.01, 0.0))
	grad.fill_to = Vector2(1, 0)
	shade.texture = grad
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 900.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	margin.offset_right = 560.0
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_top", 110)
	margin.add_theme_constant_override("margin_bottom", 70)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var title := Label.new()
	title.text = "BEASTSOULS"
	title.add_theme_font_override("font", UiTheme.spaced_font(7))
	title.add_theme_font_size_override("font_size", 76)
	title.add_theme_color_override("font_color", Color(0.98, 0.68, 0.33))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.02, 0.9))
	title.add_theme_constant_override("outline_size", 6)
	col.add_child(title)
	col.add_child(UiTheme.ornament(470))
	var sub := Label.new()
	sub.text = "DUELOS DE BESTIAS EN LA ARENA"
	sub.add_theme_font_override("font", UiTheme.spaced_font(4, false))
	sub.add_theme_color_override("font_color", UiTheme.DIM.lightened(0.15))
	sub.add_theme_font_size_override("font_size", 16)
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 56
	col.add_child(gap)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 8)
	_main_box.custom_minimum_size.x = 400
	_main_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_main_box)
	_button(_main_box, "Práctica contra la IA", _on_practice, "Elige tu bestia y un rival y entrena sin prisa.")
	_button(_main_box, "Jugar online", _show_online.bind(true), "Duelo 1 contra 1 al mejor de tres asaltos.")
	_button(_main_box, "Opciones", _open_options, "Gráficos, sonido, controles e interfaz.")
	_button(_main_box, "Salir", get_tree().quit, "Cerrar el juego.")
	_blurb = Label.new()
	_blurb.add_theme_font_size_override("font_size", 15)
	_blurb.add_theme_color_override("font_color", UiTheme.DIM.lightened(0.2))
	var blurb_pad := MarginContainer.new()
	blurb_pad.add_theme_constant_override("margin_left", 26)
	blurb_pad.add_theme_constant_override("margin_top", 10)
	blurb_pad.add_child(_blurb)
	_main_box.add_child(blurb_pad)

	_build_online(col)

	_hints = HintBar.make([["A", "Enter", "Elegir"], ["B", "Esc", "Volver"]])
	_hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hints.offset_left = 90.0
	_hints.offset_bottom = -30.0
	add_child(_hints)

	var foot := Label.new()
	foot.text = "Prototipo · modelos provisionales"
	foot.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	foot.add_theme_font_size_override("font_size", 13)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	foot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_right = -24.0
	foot.offset_bottom = -16.0
	add_child(foot)
	(_main_box.get_child(0) as Button).grab_focus.call_deferred()


func _build_online(parent: Control) -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = 440
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.visible = false
	parent.add_child(_panel)
	_online_box = VBoxContainer.new()
	_online_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_online_box)
	var head := Label.new()
	head.text = "PARTIDA ONLINE"
	head.add_theme_font_override("font", UiTheme.spaced_font(3))
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", UiTheme.AMBER)
	_online_box.add_child(head)
	_online_box.add_child(UiTheme.ornament(380))
	_nick = _field(_online_box, "Nombre", "Jugador")
	_address = _field(_online_box, "IP o servidor", "127.0.0.1")
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = Net.DEFAULT_PORT
	_row(_online_box, "Puerto", _port)
	_latency = SpinBox.new()
	_latency.max_value = 500
	_latency.suffix = "ms"
	_row(_online_box, "Latencia simulada", _latency)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_online_box.add_child(row)
	for pair in [["Alojar partida", _on_host], ["Unirse", _on_join]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size.y = 42
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(pair[1])
		row.add_child(b)
		_online_buttons.append(b)
	# Por servidor: los dos escriben la dirección del servidor y la misma sala; nadie abre puertos.
	_room = _field(_online_box, "Sala (servidor)", "")
	_room.placeholder_text = "vacío = pública"
	_room.max_length = 16
	var via := Button.new()
	via.text = "Jugar por servidor"
	via.custom_minimum_size.y = 42
	via.pressed.connect(_on_relay)
	_online_box.add_child(via)
	_online_buttons.append(via)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		_nick.text = cfg.get_value("net", "nick", _nick.text)
		_address.text = cfg.get_value("net", "address", _address.text)
		_room.text = cfg.get_value("net", "room", "")
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
	_status.add_theme_font_size_override("font_size", 15)
	_online_box.add_child(_status)
	_cancel = Button.new()
	_cancel.text = "Cancelar"
	_cancel.visible = false
	_cancel.pressed.connect(_on_cancel)
	_online_box.add_child(_cancel)
	_back = Button.new()
	_back.text = "Volver"
	_back.pressed.connect(_show_online.bind(false))
	_online_box.add_child(_back)


func _show_online(on: bool) -> void:
	_main_box.visible = not on
	_panel.visible = on
	if on:
		_online_buttons[0].grab_focus.call_deferred()
	else:
		(_main_box.get_child(1) as Button).grab_focus.call_deferred()


func _open_options() -> void:
	_main_box.visible = false
	_hints.visible = false
	_options = OptionsMenu.new()
	add_child(_options)
	_options.closed.connect(func() -> void:
		_options = null
		_main_box.visible = true
		_hints.visible = true
		(_main_box.get_child(2) as Button).grab_focus.call_deferred())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _panel.visible and not _cancel.visible:
		get_viewport().set_input_as_handled()
		_show_online(false)


func _field(parent: Control, label: String, value: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	_row(parent, label, e)
	return e


func _row(parent: Control, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 170
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


func _button(parent: Control, text: String, cb: Callable, blurb := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 52
	UiTheme.menu_button(b, 24)
	b.pressed.connect(cb)
	b.focus_entered.connect(func() -> void: _blurb.text = blurb)
	b.mouse_entered.connect(func() -> void: _blurb.text = blurb)
	parent.add_child(b)
	return b


func _set_waiting(waiting: bool) -> void:
	for b in _online_buttons:
		b.disabled = waiting
	_cancel.visible = waiting
	_back.visible = not waiting


func _prepare() -> void:
	Net.nick = _nick.text.strip_edges().substr(0, 16) if not _nick.text.strip_edges().is_empty() else "Jugador"
	Net.sim_latency_ms = int(_latency.value)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("net", "nick", _nick.text.strip_edges())
	cfg.set_value("net", "address", _address.text.strip_edges())
	cfg.set_value("net", "room", _room.text.strip_edges())
	cfg.save(SETTINGS)


func _on_practice() -> void:
	Net.close()
	get_tree().change_scene_to_file(SELECT)


func _on_host() -> void:
	_prepare()
	var err := Net.host(int(_port.value))
	if err != OK:
		_status.text = "No se pudo abrir el puerto %d (¿ya está en uso?)." % int(_port.value)
		Audio.play_ui("ui_error")
		return
	var ips := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127."):
			ips.append(ip)
	_status.text = "Esperando rival en el puerto %d…\nTu IP local: %s\n(Por internet: abre el puerto UDP %d en el router o usad Tailscale/ZeroTier.)" % [
			int(_port.value), ", ".join(ips) if not ips.is_empty() else "—", int(_port.value)]
	_set_waiting(true)


func _on_join() -> void:
	_prepare()
	var err := Net.join(_address.text.strip_edges(), int(_port.value))
	if err != OK:
		_status.text = "Dirección no válida."
		Audio.play_ui("ui_error")
		return
	_status.text = "Conectando con %s:%d…" % [_address.text.strip_edges(), int(_port.value)]
	_set_waiting(true)


func _on_relay() -> void:
	_prepare()
	var err := Net.join_server(_address.text.strip_edges(), _room.text, int(_port.value))
	if err != OK:
		_status.text = "Dirección no válida."
		Audio.play_ui("ui_error")
		return
	_status.text = "Conectando con el servidor %s:%d…" % [_address.text.strip_edges(), int(_port.value)]
	_set_waiting(true)


func _on_waiting() -> void:
	var code := _room.text.strip_edges().to_upper()
	_status.text = "En la sala %s. Esperando rival…" % ("«%s»" % code if code != "" else "pública")


func _on_cancel() -> void:
	Net.close()
	_status.text = ""
	_set_waiting(false)


func _on_connected() -> void:
	_status.text = "¡Conectado con %s!" % Net.remote_nick
	Audio.play_ui("ui_confirm")
	get_tree().change_scene_to_file.call_deferred(SELECT)


func _on_failed(reason: String) -> void:
	var texts := {
		"unreachable": "No se pudo conectar: no hay nadie alojando en esa dirección.",
		"timeout": "El anfitrión no respondió a tiempo.",
		"version": "Versiones del juego distintas.",
		"host_left": "El anfitrión cerró la partida.",
		"server_left": "Se perdió la conexión con el servidor.",
		"left": "El rival se fue.",
	}
	_status.text = texts.get(reason, "Error de red (%s)." % reason)
	Audio.play_ui("ui_error")
	_set_waiting(false)


func _apply_args() -> void:
	if _args_done:
		return
	_args_done = true
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("nick"):
		_nick.text = args.nick
	if args.has("port"):
		_port.value = int(args.port)
	if args.has("latency"):
		_latency.value = int(args.latency)
	Net.sim_jitter_ms = int(args.get("jitter", "0"))
	Net.sim_loss = float(args.get("loss", "0"))
	if args.has("practice"):
		Net.close()
		get_tree().change_scene_to_file.call_deferred(ARENA)
	elif args.has("host"):
		_show_online(true)
		_on_host.call_deferred()
	elif args.has("relay"):
		if args.relay != "":
			_address.text = args.relay
		_room.text = args.get("room", "")
		_show_online(true)
		_on_relay.call_deferred()
	elif args.has("join"):
		if args.join != "":
			_address.text = args.join
		_show_online(true)
		_on_join.call_deferred()

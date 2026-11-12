extends Control
## Menú principal: práctica contra la IA, alojar o unirse a una partida online.
##
## Argumentos de línea de comandos (tras `--`), para pruebas automáticas o accesos directos:
##   --practice                 entra directo a la práctica (personajes: --char=ID --rival=ID)
##   --autoready                el selector elige solo (--char) y se marca listo: para pruebas automáticas
##   --host                     aloja y espera rival
##   --join=IP                  se une a IP
##   --port=N  --nick=NOMBRE
##   --latency=MS --jitter=MS --loss=0.05   simulación de red (lo que envía este lado)

const ARENA := "res://levels/arena_test/arena_test.tscn"
const SELECT := "res://ui/character_select.tscn"

var _nick: LineEdit
var _address: LineEdit
var _port: SpinBox
var _latency: SpinBox
var _status: Label
var _buttons: Array[Button] = []
var _cancel: Button


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	Net.connected.connect(_on_connected)
	Net.failed.connect(_on_failed)
	_apply_args()


func _exit_tree() -> void:
	Net.connected.disconnect(_on_connected)
	Net.failed.disconnect(_on_failed)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "BEASTSOULS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.95, 0.6, 0.25))
	box.add_child(title)
	box.add_child(HSeparator.new())

	_nick = _field(box, "Nombre", "Jugador")
	var practice := _button(box, "Práctica contra la IA")
	practice.pressed.connect(_on_practice)
	box.add_child(HSeparator.new())

	_address = _field(box, "IP del anfitrión", "127.0.0.1")
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = Net.DEFAULT_PORT
	_row(box, "Puerto", _port)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var host := _button(row, "Alojar partida")
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(_on_host)
	var join := _button(row, "Unirse")
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(_on_join)

	var quality := OptionButton.new()
	for n in Graphics.NAMES:
		quality.add_item(n)
	quality.selected = Graphics.quality
	quality.item_selected.connect(Graphics.set_quality)
	_row(box, "Calidad gráfica", quality)

	_latency = SpinBox.new()
	_latency.max_value = 500
	_latency.suffix = "ms"
	_row(box, "Latencia simulada (pruebas)", _latency)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	box.add_child(_status)
	_cancel = _button(box, "Cancelar")
	_cancel.visible = false
	_cancel.pressed.connect(_on_cancel)


func _field(parent: Control, label: String, value: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	_row(parent, label, e)
	return e


func _row(parent: Control, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 200
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 40
	parent.add_child(b)
	_buttons.append(b)
	return b


func _set_waiting(waiting: bool) -> void:
	for b in _buttons:
		b.disabled = waiting
	_cancel.visible = waiting
	_cancel.disabled = false


func _prepare() -> void:
	Net.nick = _nick.text.strip_edges().substr(0, 16) if not _nick.text.strip_edges().is_empty() else "Jugador"
	Net.sim_latency_ms = int(_latency.value)


func _on_practice() -> void:
	Net.close()
	get_tree().change_scene_to_file(SELECT)


func _on_host() -> void:
	_prepare()
	var err := Net.host(int(_port.value))
	if err != OK:
		_status.text = "No se pudo abrir el puerto %d (¿ya está en uso?)." % int(_port.value)
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
		return
	_status.text = "Conectando con %s:%d…" % [_address.text.strip_edges(), int(_port.value)]
	_set_waiting(true)


func _on_cancel() -> void:
	Net.close()
	_status.text = ""
	_set_waiting(false)


func _on_connected() -> void:
	_status.text = "¡Conectado con %s!" % Net.remote_nick
	get_tree().change_scene_to_file.call_deferred(SELECT)


func _on_failed(reason: String) -> void:
	var texts := {
		"unreachable": "No se pudo conectar: no hay nadie alojando en esa dirección.",
		"timeout": "El anfitrión no respondió a tiempo.",
		"version": "Versiones del juego distintas.",
		"host_left": "El anfitrión cerró la partida.",
	}
	_status.text = texts.get(reason, "Error de red (%s)." % reason)
	_set_waiting(false)


func _apply_args() -> void:
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
		_on_host.call_deferred()
	elif args.has("join"):
		if args.join != "":
			_address.text = args.join
		_on_join.call_deferred()

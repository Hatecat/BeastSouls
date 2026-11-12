extends Control
## Selector de personaje con vista previa 3D.
##   Práctica: eliges tu bestia y después la de la IA.
##   Online: cada uno elige la suya y pulsa "Listo"; el anfitrión arranca cuando los dos lo están.

const MENU := "res://ui/main_menu.tscn"

var _online := false
## Práctica: 0 = eligiendo la tuya, 1 = eligiendo la de la IA.
var _step := 0
var _is_ready := false
var _selected: CharacterDef

var _title: Label
var _list: VBoxContainer
var _buttons: Dictionary[StringName, Button] = {}
var _name: Label
var _role: Label
var _desc: Label
var _ratings: VBoxContainer
var _abilities: GridContainer
var _ab_title: Label
var _ab_detail: Label
var _ab_buttons: Array[Button] = []
## Habilidades elegidas para el personaje en pantalla (índices de su catálogo, en orden de ranura).
var _loadout: Array = []
## Práctica: lo elegido para la IA con cada personaje mientras dure esta pantalla (no se guarda en disco).
var _ai_loadouts := {}
var _status: Label
var _back: Button
var _next: Button

var _pivot: Node3D
var _cam: Camera3D
var _previews: Dictionary[StringName, CharacterVisual] = {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_online = Net.is_online()
	_build()
	Audio.music("menu")
	Audio.ambience("")
	if _online:
		Session.rival_pick_changed.connect(_refresh_status)
		Session.match_start.connect(_on_match_start)
		Net.disconnected.connect(_on_disconnected)
	_select(Roster.find(Session.my_character))
	_update_step()
	if _online:
		Session.send_pick(false)
	_focus_selected.call_deferred()
	if Session.auto_ready:
		_auto.call_deferred()


func _exit_tree() -> void:
	for pair in [[Session.rival_pick_changed, _refresh_status], [Session.match_start, _on_match_start], [Net.disconnected, _on_disconnected]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _process(delta: float) -> void:
	if _pivot:
		_pivot.rotate_y(delta * 0.5)


# --- Construcción ---------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Color(0.95, 0.6, 0.25))
	root.add_child(_title)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 24)
	root.add_child(main)

	# Lista de personajes.
	_list = VBoxContainer.new()
	_list.custom_minimum_size.x = 300
	_list.add_theme_constant_override("separation", 8)
	main.add_child(_list)
	var group := ButtonGroup.new()
	for def in Roster.all():
		var b := Button.new()
		b.text = "%s\n%s" % [def.display_name, def.role]
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 64
		b.add_theme_font_size_override("font_size", 18)
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, _card_style(def.color, st))
		b.pressed.connect(_on_pick.bind(def))
		b.pressed.connect(func() -> void:  # con mando: A elige y salta a sus habilidades
			if not _ab_buttons.is_empty():
				_ab_buttons[0].grab_focus())
		b.focus_entered.connect(func() -> void:
			if _selected != def and not b.disabled:
				_on_pick(def))
		_list.add_child(b)
		_buttons[def.id] = b

	# Vista previa 3D.
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 6)
	main.add_child(center)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	view.add_child(vp)
	_build_stage(vp)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 44)
	center.add_child(_name)
	_role = Label.new()
	_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role.add_theme_font_size_override("font_size", 20)
	_role.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	center.add_child(_role)

	# Detalles.
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 500
	right.add_theme_constant_override("separation", 10)
	main.add_child(right)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 17)
	right.add_child(_desc)
	right.add_child(HSeparator.new())
	_ratings = VBoxContainer.new()
	right.add_child(_ratings)
	right.add_child(HSeparator.new())
	_ab_title = Label.new()
	_ab_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	right.add_child(_ab_title)
	_abilities = GridContainer.new()
	_abilities.columns = 2
	_abilities.add_theme_constant_override("h_separation", 6)
	_abilities.add_theme_constant_override("v_separation", 6)
	right.add_child(_abilities)
	_ab_detail = Label.new()
	_ab_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ab_detail.custom_minimum_size.y = 50
	_ab_detail.add_theme_font_size_override("font_size", 15)
	_ab_detail.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	right.add_child(_ab_detail)
	Settings.device_changed.connect(func(_pad: bool) -> void: _refresh_abilities())

	# Barra inferior.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	root.add_child(bottom)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", 18)
	bottom.add_child(_status)
	_back = Button.new()
	_back.custom_minimum_size = Vector2(200, 50)
	_back.pressed.connect(_on_back)
	bottom.add_child(_back)
	_next = Button.new()
	_next.custom_minimum_size = Vector2(240, 50)
	_next.add_theme_font_size_override("font_size", 20)
	_next.pressed.connect(_on_next)
	bottom.add_child(_next)


func _card_style(color: Color, state: String) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var on := state in ["pressed", "hover_pressed"]
	s.bg_color = Color(color.r * 0.35, color.g * 0.35, color.b * 0.35, 0.95) if on else Color(0.12, 0.1, 0.1, 0.95)
	if state == "hover":
		s.bg_color = Color(0.18, 0.15, 0.14)
	s.border_color = color if on or state == "focus" else Color(color.r, color.g, color.b, 0.5)
	s.border_width_left = 8
	s.set_border_width(SIDE_TOP, 2 if on or state == "focus" else 0)
	s.set_border_width(SIDE_BOTTOM, 2 if on or state == "focus" else 0)
	s.set_border_width(SIDE_RIGHT, 2 if on or state == "focus" else 0)
	if state == "focus":
		s.draw_center = false
	s.set_content_margin_all(10)
	s.content_margin_left = 20
	s.set_corner_radius_all(4)
	return s


func _build_stage(vp: SubViewport) -> void:
	var env := WorldEnvironment.new()
	env.environment = load("res://levels/common/world_env.tres")
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	vp.add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.5, 3.0, -3.0)
	rim.light_color = Color(1.0, 0.65, 0.4)
	rim.light_energy = 2.0
	rim.omni_range = 9.0
	vp.add_child(rim)
	var floor := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.4
	disc.bottom_radius = 2.6
	disc.height = 0.2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.13, 0.12)
	m.roughness = 0.9
	disc.material = m
	floor.mesh = disc
	floor.position.y = -0.1
	vp.add_child(floor)
	_pivot = Node3D.new()
	_pivot.rotation.y = 0.5
	vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 38
	vp.add_child(_cam)


# --- Selección ------------------------------------------------------------------------

func _on_pick(def: CharacterDef) -> void:
	_select(def)
	_play_flourish()
	if _online:
		Session.my_character = def.id
		Session.send_pick(false)
	elif _step == 0:
		Session.my_character = def.id
	else:
		Session.rival_character = def.id


func _select(def: CharacterDef) -> void:
	_selected = def
	_buttons[def.id].button_pressed = true
	_name.text = def.display_name
	_name.add_theme_color_override("font_color", def.color)
	_role.text = def.role
	_desc.text = def.description
	for c in _ratings.get_children():
		c.queue_free()
	var health: float = def.stats.get(&"max_health", 100.0)
	_rating_row("Vida  (%d)" % health, def.rating_health, def.color)
	_rating_row("Velocidad", def.rating_speed, def.color)
	_rating_row("Poder", def.rating_power, def.color)
	_rating_row("Alcance", def.rating_range, def.color)
	_build_abilities(def)
	_show_preview(def)


# --- Habilidades: se equipan 4 de las del catálogo ------------------------------------

func _for_ai() -> bool:
	return not _online and _step == 1


func _build_abilities(def: CharacterDef) -> void:
	for c in _abilities.get_children():
		_abilities.remove_child(c)
		c.queue_free()
	_ab_buttons.clear()
	if _for_ai() and _ai_loadouts.has(def.id):
		_loadout = (_ai_loadouts[def.id] as Array).duplicate()
	else:
		_loadout = Array(Session.saved_loadout(def.id))
	for i in def.moveset.abilities.size():
		var ab := def.moveset.abilities[i]
		var b := Button.new()
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 50
		b.add_theme_font_size_override("font_size", 15)
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, _card_style(ab.color, st))
		b.pressed.connect(_on_ability.bind(i))
		b.focus_entered.connect(_describe.bind(i))
		b.mouse_entered.connect(_describe.bind(i))
		_abilities.add_child(b)
		_ab_buttons.append(b)
	_ab_detail.text = ""
	_store_loadout(false)
	_refresh_abilities()


func _on_ability(i: int) -> void:
	if i in _loadout:
		_loadout.erase(i)
	elif _loadout.size() < Moveset.LOADOUT_SIZE:
		_loadout.append(i)
		var v: CharacterVisual = _previews.get(_selected.id)
		if v:
			v.play(_selected.moveset.abilities[i].action, 0.15)
	else:
		Audio.play_ui("ui_error")
	_describe(i)
	_store_loadout(true)
	_refresh_abilities()


func _loadout_complete() -> bool:
	return _selected != null and _loadout.size() >= mini(Moveset.LOADOUT_SIZE, _selected.moveset.abilities.size())


## Pasa lo elegido a Session (y al rival online). Una selección incompleta no se guarda: Session conserva la
## última válida y «Siguiente» queda bloqueado hasta completarla.
func _store_loadout(save: bool) -> void:
	if not _loadout_complete():
		return
	if _for_ai():
		Session.rival_loadout = _loadout.duplicate()
		_ai_loadouts[_selected.id] = _loadout.duplicate()
		return
	Session.my_loadout = _loadout.duplicate()
	if save:
		Session.save_loadout(_selected.id, _loadout)
		if _online:
			Session.send_pick(false)


func _refresh_abilities() -> void:
	if _selected == null:
		return
	var locked := _online and _is_ready
	var full := _loadout.size() >= Moveset.LOADOUT_SIZE
	for i in _ab_buttons.size():
		var ab := _selected.moveset.abilities[i]
		var slot := _loadout.find(i)
		var b := _ab_buttons[i]
		b.set_pressed_no_signal(slot >= 0)
		b.disabled = locked
		var tag := "[%s] " % ControlsHelp.slot_key(slot, Settings.using_pad) if slot >= 0 else ""
		b.text = "%s%s\n%s · %d calor · %d s" % [tag, ab.display_name, AbilityData.kind_label(ab.kind()),
				ab.heat_cost, ab.cooldown]
		b.modulate = Color(1, 1, 1, 0.55) if full and slot < 0 else Color.WHITE
	_ab_title.text = "Habilidades: elige %d  (%d/%d)" % [Moveset.LOADOUT_SIZE, _loadout.size(), Moveset.LOADOUT_SIZE]
	_ab_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8) if _loadout_complete() else UiTheme.AMBER)
	if _next:
		_next.disabled = not _loadout_complete()


func _describe(i: int) -> void:
	if _selected == null or i >= _selected.moveset.abilities.size():
		return
	var ab := _selected.moveset.abilities[i]
	var note := ""
	if _loadout.size() >= Moveset.LOADOUT_SIZE and i not in _loadout:
		note = "\nYa llevas %d: quita una para cambiarla." % Moveset.LOADOUT_SIZE
	_ab_detail.text = "%s — %s%s" % [ab.display_name, ab.summary(), note]


func _rating_row(label: String, value: int, color: Color) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 150
	row.add_child(l)
	for k in 5:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(30, 12)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.color = color if k < value else Color(0.25, 0.22, 0.22)
		row.add_child(pip)
		var gap := Control.new()
		gap.custom_minimum_size.x = 4
		row.add_child(gap)
	_ratings.add_child(row)


func _show_preview(def: CharacterDef) -> void:
	for id in _previews:
		_previews[id].visible = id == def.id
	if not _previews.has(def.id):
		var v: CharacterVisual = def.visual.instantiate()
		_pivot.add_child(v)
		v.action_finished.connect(func(_a: StringName) -> void: v.play(&"idle", 0.25))
		_previews[def.id] = v
	var h: float = _previews[def.id].target_height
	var dist := 2.4 + h * 1.6
	var look := Vector3(0, h * 0.5, 0)
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var from := _cam.position if _cam.position != Vector3.ZERO else look + Vector3(0, h * 0.25, dist)
	_cam.position = from
	tw.tween_method(func(p: Vector3) -> void:
		_cam.position = p
		_cam.look_at(look), from, look + Vector3(0, h * 0.25, dist), 0.35)


func _play_flourish() -> void:
	var v: CharacterVisual = _previews.get(_selected.id)
	if v and not _selected.moveset.abilities.is_empty():
		v.play(_selected.moveset.abilities[mini(3, _selected.moveset.abilities.size() - 1)].action, 0.15)


# --- Flujo ----------------------------------------------------------------------------

func _update_step() -> void:
	for b in _buttons.values():
		b.disabled = _online and _is_ready
	if _online:
		_title.text = "ELIGE TU BESTIA"
		_back.text = "Salir"
		_next.text = "Cancelar" if _is_ready else "¡LISTO!"
		_refresh_status()
	elif _step == 0:
		_title.text = "ELIGE TU BESTIA"
		_back.text = "◂ Menú"
		_next.text = "Elegir rival ▸"
		_status.text = ""
		_select(Roster.find(Session.my_character))
	else:
		_title.text = "ELIGE AL RIVAL (IA)"
		_back.text = "◂ Atrás"
		_next.text = "¡LUCHAR!"
		_status.text = "Tú: %s" % Roster.find(Session.my_character).display_name
		_select(Roster.find(Session.rival_character))
	_refresh_abilities()


func _refresh_status() -> void:
	if not _online:
		return
	var who := Net.remote_nick
	if Session.rival_pick == &"":
		_status.text = "%s está entrando…" % who
	else:
		_status.text = "%s: %s · %s" % [who, Roster.find(Session.rival_pick).display_name,
				"✔ LISTO" if Session.rival_ready else "eligiendo…"]
	_status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if Session.rival_ready else Color(0.85, 0.85, 0.85))
	_try_start()


func _try_start() -> void:
	if _online and Net.mode == Net.Mode.HOST and _is_ready and Session.rival_ready and Session.rival_pick != &"":
		Session.host_start()


func _on_next() -> void:
	if not _loadout_complete():
		return
	if _online:
		_is_ready = not _is_ready
		Session.send_pick(_is_ready)
		_update_step()
	elif _step == 0:
		_step = 1
		_update_step()
		_focus_selected()
	else:
		get_tree().change_scene_to_file(Session.ARENA)


func _focus_selected() -> void:
	var b: Button = _buttons.get(_selected.id) if _selected else null
	if b and not b.disabled:
		b.grab_focus()
	else:
		_next.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _online and _is_ready:
			_on_next()  # B con «Listo» marcado: cancelar el listo
		else:
			_on_back()


func _on_back() -> void:
	if _online:
		Net.close()
		get_tree().change_scene_to_file(MENU)
	elif _step == 1:
		_step = 0
		_update_step()
		_focus_selected()
	else:
		get_tree().change_scene_to_file(MENU)


func _on_match_start() -> void:
	get_tree().change_scene_to_file.call_deferred(Session.ARENA)


func _on_disconnected(_reason: String) -> void:
	get_tree().change_scene_to_file.call_deferred(MENU)


## Pruebas automáticas (--autoready): elige lo que diga Session y entra.
func _auto() -> void:
	await get_tree().create_timer(0.5).timeout
	if _online:
		if not _is_ready:
			_on_next()
	else:
		get_tree().change_scene_to_file(Session.ARENA)

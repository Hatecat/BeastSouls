class_name Hud
extends CanvasLayer
## HUD mínimo al estilo souls: vida y estamina arriba a la izquierda (el ancho crece con el máximo),
## más un panel de depuración y la ayuda de controles.

@export var beast: Beast
@export var camera: ThirdPersonCamera
@export var show_debug := true
## IA del rival de práctica (para mostrar su modo en el panel de depuración).
@export var dummy_brain: DummyBrain
## Píxeles de barra por punto de vida/estamina.
@export var px_per_point := 3.2

var _health: Bar
var _stamina: Bar
var _heat: Bar
var _diamond: ActionDiamond
var _status: Label
var _debug: Label
var _target_box: VBoxContainer
var _target_name: Label
var _target_bar: Bar
## Daño acumulado al objetivo (como en Souls): se suma mientras sigas golpeando y se borra tras una pausa.
var _damage_label: Label
var _damage_total := 0.0
var _damage_timer := 0.0
var _damage_target: Beast
var _damage_last_health := 0.0
var _help: Label
var _banner: Label
var _score: Label
var _banner_tween: Tween
var _over: PanelContainer
var _over_title: Label
var _over_sub: Label
var _over_note: Label
var _over_buttons: HBoxContainer


class Bar extends Control:
	var fill_color := Color.WHITE
	var trail_color := Color(1.0, 0.85, 0.5)
	var value := 1.0  ## 0..1
	var _trail := 1.0  ## lo que se ha perdido hace poco, se vacía con retraso

	func _process(delta: float) -> void:
		_trail = value if value > _trail else move_toward(_trail, value, delta * 0.6)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6))
		draw_rect(r, Color(0.08, 0.07, 0.07, 0.85))
		draw_rect(Rect2(r.position, Vector2(r.size.x * _trail, r.size.y)), trail_color)
		draw_rect(Rect2(r.position, Vector2(r.size.x * value, r.size.y)), fill_color)
		draw_rect(Rect2(r.position, Vector2(r.size.x * value, r.size.y * 0.35)), Color(1, 1, 1, 0.12))


func _ready() -> void:
	var root := VBoxContainer.new()
	root.position = Vector2(40, 36)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	_health = _make_bar(Color(0.62, 0.08, 0.06), 14.0)
	_stamina = _make_bar(Color(0.18, 0.52, 0.22), 9.0)
	_heat = _make_bar(Color(0.95, 0.45, 0.08), 7.0)
	_heat.trail_color = Color(1.0, 0.9, 0.6)
	root.add_child(_health)
	root.add_child(_stamina)
	root.add_child(_heat)

	# Rombo de acciones y habilidades (abajo a la derecha).
	_diamond = ActionDiamond.new()
	_diamond.beast = beast
	_diamond.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_diamond.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_diamond.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_diamond.offset_right = -24.0
	_diamond.offset_bottom = -16.0
	add_child(_diamond)

	# Estados (quemadura, mejoras) bajo las barras.
	_status = Label.new()
	_status.position = Vector2(40, 92)
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	add_child(_status)

	_debug = Label.new()
	_debug.position = Vector2(40, 122)
	_debug.add_theme_font_size_override("font_size", 16)
	_debug.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_debug.visible = show_debug
	add_child(_debug)

	# Barra del objetivo fijado (abajo, centrada).
	_target_box = VBoxContainer.new()
	_target_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_target_box.offset_top = -120.0
	_target_box.offset_bottom = -90.0
	_target_box.offset_left = -300.0
	_target_box.offset_right = 300.0
	_target_box.add_theme_constant_override("separation", 4)
	add_child(_target_box)
	_target_name = Label.new()
	_target_name.add_theme_font_size_override("font_size", 20)
	_target_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	var name_row := HBoxContainer.new()
	_target_box.add_child(name_row)
	_target_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_target_name)
	_damage_label = Label.new()
	_damage_label.add_theme_font_size_override("font_size", 20)
	_damage_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_damage_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	name_row.add_child(_damage_label)
	_target_bar = _make_bar(Color(0.62, 0.08, 0.06), 10.0)
	_target_bar.custom_minimum_size.x = 600.0
	_target_box.add_child(_target_bar)
	_target_box.visible = false

	# Marcador (online), arriba al centro.
	_score = Label.new()
	_score.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score.offset_top = 30.0
	_score.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_font_size_override("font_size", 24)
	_score.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	add_child(_score)

	# Mensaje central (muerte / victoria).
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 72)
	_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("shadow_offset_y", 4)
	_banner.modulate.a = 0.0
	add_child(_banner)
	_build_match_over()

	var help := Label.new()
	_help = help
	help.text = _help_text()
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_color_override("font_color", Color(1, 0.95, 0.88, 0.9))
	help.add_theme_constant_override("outline_size", 4)
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_left = 40.0
	help.offset_bottom = -28.0
	add_child(help)
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	Settings.device_changed.connect(func(_pad: bool) -> void: _apply_settings())


func _help_text() -> String:
	return ControlsHelp.hud_text(Settings.using_pad)


func _apply_settings() -> void:
	_debug.visible = Settings.show_debug
	_help.visible = Settings.show_help
	_help.text = _help_text()


func set_score(text: String) -> void:
	_score.text = text


func show_banner(text: String, color: Color, hold := 1.6, fade_in := 0.6) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, fade_in)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, minf(0.8, hold * 0.6 + 0.15))


# --- Fin de partida -------------------------------------------------------------------

func _build_match_over() -> void:
	_over = PanelContainer.new()
	_over.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_over.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_over.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.03, 0.03, 0.88)
	style.border_color = Color(0.6, 0.4, 0.2, 0.8)
	style.set_border_width_all(2)
	style.set_content_margin_all(36)
	style.set_corner_radius_all(6)
	_over.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_over.add_child(box)
	_over_title = Label.new()
	_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_title.add_theme_font_size_override("font_size", 64)
	box.add_child(_over_title)
	_over_sub = Label.new()
	_over_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_sub.add_theme_font_size_override("font_size", 24)
	box.add_child(_over_sub)
	_over_note = Label.new()
	_over_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_note.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	box.add_child(_over_note)
	_over_buttons = HBoxContainer.new()
	_over_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_over_buttons.add_theme_constant_override("separation", 16)
	box.add_child(_over_buttons)
	_over.visible = false
	add_child(_over)


## Panel de fin de partida. `buttons`: [[texto, Callable], ...]. Suelta el ratón para poder pulsarlos.
func show_match_over(title: String, color: Color, subtitle: String, buttons: Array) -> void:
	_over_title.text = title
	_over_title.add_theme_color_override("font_color", color)
	_over_sub.text = subtitle
	_over_note.text = ""
	for c in _over_buttons.get_children():
		_over_buttons.remove_child(c)
		c.queue_free()
	for b: Array in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(200, 44)
		btn.pressed.connect(b[1])
		_over_buttons.add_child(btn)
	_over.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _over_buttons.get_child_count() > 0:
		(_over_buttons.get_child(0) as Button).grab_focus.call_deferred()


func set_match_over_note(text: String) -> void:
	_over_note.text = text


func hide_match_over() -> void:
	if _over.visible:
		_over.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _make_bar(color: Color, h: float) -> Bar:
	var b := Bar.new()
	b.fill_color = color
	b.custom_minimum_size = Vector2(300, h)
	return b


func _update_damage(t: Beast, delta: float) -> void:
	if t != _damage_target:
		_damage_target = t
		_damage_total = 0.0
		_damage_timer = 0.0
		_damage_last_health = t.health if t else 0.0
	if t == null:
		_damage_label.text = ""
		return
	var lost := _damage_last_health - t.health
	_damage_last_health = t.health
	if lost > 0.01:
		_damage_total += lost
		_damage_timer = 2.5
	elif lost < -0.01:
		_damage_total = 0.0  # se curó o empezó otra ronda
	_damage_timer -= delta
	if _damage_timer <= 0.0:
		_damage_total = 0.0
	_damage_label.text = str(roundi(_damage_total)) if _damage_total >= 0.5 else ""
	_damage_label.modulate.a = clampf(_damage_timer / 0.4, 0.0, 1.0)


func _process(_delta: float) -> void:
	if beast == null:
		return
	_health.custom_minimum_size.x = beast.max_health * px_per_point
	_stamina.custom_minimum_size.x = beast.max_stamina * px_per_point
	_health.value = beast.health / beast.max_health
	_stamina.value = beast.stamina / beast.max_stamina
	_heat.custom_minimum_size.x = beast.max_heat * px_per_point * 0.6
	_heat.value = beast.heat / beast.max_heat
	_diamond.beast = beast
	var status := PackedStringArray()
	if beast.burn_time > 0.0:
		status.append("Quemado %.0f s" % beast.burn_time)
	for b in beast.buffs:
		status.append("%s %.0f s" % [String(b.id).capitalize(), b.time])
	_status.text = "  ·  ".join(status)
	var t := camera.lock_target as Beast if camera else null
	_target_box.visible = t != null
	_update_damage(t, _delta)
	if t:
		_target_name.text = "%s · %s" % [t.name, t.character.display_name] if t.character and String(t.name) != t.character.display_name else String(t.name)
		_target_bar.value = t.health / t.max_health
	if _debug.visible:
		var target := "—"
		if camera and camera.lock_target:
			target = "%s (%.1f m)" % [camera.lock_target.name, beast.global_position.distance_to(camera.lock_target.global_position)]
		var atk := ""
		if beast.attack:
			atk = "  %s%s" % [beast.attack.display_name, "  carga x%.2f" % beast.charge_multiplier() if beast.charge > 0.0 else ""]
		elif beast.ability:
			atk = "  " + beast.ability.display_name
		_debug.text = "Estado: %s%s%s%s\nVelocidad: %.1f m/s\nVida: %d · Estamina: %d · Postura: %d · Calor: %d\nObjetivo: %s\n%s\nFPS: %d · Calidad: %s (F3)" % [
			Beast.State.keys()[beast.state], atk,
			"  [correr]" if beast.sprinting else "",
			"  [invulnerable]" if beast.is_invulnerable() else "",
			beast.horizontal_speed(), beast.health, beast.stamina, beast.poise, beast.heat, target,
			_net_or_ai_text(),
			Engine.get_frames_per_second(), Graphics.quality_name()]


func _net_or_ai_text() -> String:
	if Net.is_online():
		var sim := Net.sim_latency_ms + Net.sim_jitter_ms / 2
		return "Red: %s · ping %d ms%s" % ["anfitrión" if Net.mode == Net.Mode.HOST else "invitado", Net.rtt(),
				" (+%d simulado por lado)" % sim if sim > 0 else ""]
	if is_instance_valid(dummy_brain):
		return "IA rival: " + DummyBrain.Mode.keys()[dummy_brain.mode]
	return ""

class_name ActionDiamond
extends Control
## Rombo de acciones del HUD (abajo a la derecha): qué hace ahora mismo cada botón.
##   Mando: los cuatro botones frontales colocados como en el mando (Y arriba, X izquierda, B derecha, A abajo).
##     X / Y son las habilidades 1 y 2; con LT mantenido pasan a ser la 3 y la 4 (la otra pareja se ve en el
##     círculo pequeño pegado a cada botón). B esquiva y A salta.
##   Teclado: las cuatro habilidades en rombo con su tecla.
## Encima, dos líneas con el resto de acciones. Lo que no se puede usar ahora (sin PP, en recarga, sin
## estamina, en el aire) sale apagado; la recarga es un sector oscuro que se va cerrando.

const R := 34.0        ## radio de cada botón
const SPREAD := 74.0   ## distancia del centro del rombo a cada botón
const MINI := 14.0     ## radio del círculo de la pareja alternativa (LT)
const SIDE := 150.0    ## ancho reservado para los nombres a izquierda y derecha
const HINTS := 50.0    ## alto de las líneas de ayuda de encima
## Colores de los botones del mando (disposición Xbox).
const PAD_COLORS := {"X": Color(0.3, 0.55, 1.0), "Y": Color(1.0, 0.8, 0.2), "B": Color(0.95, 0.3, 0.25), "A": Color(0.4, 0.85, 0.35)}
const DIRS := [Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1)]  ## izquierda, arriba, derecha, abajo

var beast: Beast


func _init() -> void:
	custom_minimum_size = Vector2(SIDE * 2.0 + (SPREAD + R) * 2.0, HINTS + (SPREAD + R) * 2.0 + 44.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _center() -> Vector2:
	return Vector2(size.x * 0.5, HINTS + 20.0 + SPREAD + R)


func _draw() -> void:
	if beast == null:
		return
	var pad := Settings.using_pad
	var font := get_theme_default_font()
	var c := _center()
	# Rombo de fondo que une los cuatro botones.
	var pts := PackedVector2Array()
	for d: Vector2 in DIRS:
		pts.append(c + d * SPREAD)
	draw_colored_polygon(pts, Color(0, 0, 0, 0.28))
	pts.append(pts[0])
	draw_polyline(pts, Color(UiTheme.AMBER.r, UiTheme.AMBER.g, UiTheme.AMBER.b, 0.35), 2.0, true)

	if pad:
		var alt := PlayerController.secondary_held()
		_ability_node(font, c + DIRS[0] * SPREAD, DIRS[0], "X", 2 if alt else 0, 0 if alt else 2)
		_ability_node(font, c + DIRS[1] * SPREAD, DIRS[1], "Y", 3 if alt else 1, 1 if alt else 3)
		_action_node(font, c + DIRS[2] * SPREAD, DIRS[2], "B", "Esquivar", beast.stamina > 0.0)
		_action_node(font, c + DIRS[3] * SPREAD, DIRS[3], "A", "Saltar",
				not beast.is_airborne() and beast.stamina > 0.0)
		_hints(font, [
			"LB Bloquear  ·  RB Ligero  ·  RT Fuerte",
			("LT mantenido: suelta para X / Y principales" if alt else "LT + X / Y: otras dos habilidades") + "  ·  L3 Correr  ·  R3 Fijar",
		], alt)
	else:
		for i in 4:
			_ability_node(font, c + DIRS[i] * SPREAD, DIRS[i], ControlsHelp.slot_key(i, false), i, -1)
		_hints(font, [
			"%s Ligero  ·  %s Fuerte  ·  %s Bloquear" % [_k("attack_light"), _k("attack_heavy"), _k("block")],
			"%s Esquivar (mantener: correr)  ·  %s Saltar  ·  %s Fijar" % [_k("dodge"), _k("jump"), _k("lock_on")],
		], false)


static func _k(action: String) -> String:
	return Settings.event_text(Settings.primary_event(action))


func _hints(font: Font, lines: Array, highlight_second: bool) -> void:
	for i in lines.size():
		var col := UiTheme.AMBER if (i == 1 and highlight_second) else Color(1, 0.95, 0.88, 0.9)
		_text(font, Vector2(0, 16.0 + i * 20.0), lines[i], HORIZONTAL_ALIGNMENT_RIGHT, size.x, 15, col)


## Texto con sombra.
func _text(font: Font, pos: Vector2, text: String, align: HorizontalAlignment, width: float, fsize: int, col: Color) -> void:
	draw_string(font, pos + Vector2(1, 1), text, align, width, fsize, Color(0, 0, 0, 0.85 * col.a))
	draw_string(font, pos, text, align, width, fsize, col)


## Nombre junto al botón: a los lados en izquierda/derecha, encima o debajo en arriba/abajo.
func _label(font: Font, p: Vector2, dir: Vector2, text: String, sub: String, col: Color) -> void:
	var w := SIDE - 8.0
	if dir.x < 0.0:
		_text(font, p + Vector2(-R - 8.0 - w, -2.0), text, HORIZONTAL_ALIGNMENT_RIGHT, w, 15, col)
		_text(font, p + Vector2(-R - 8.0 - w, 15.0), sub, HORIZONTAL_ALIGNMENT_RIGHT, w, 12, Color(col.r, col.g, col.b, col.a * 0.75))
	elif dir.x > 0.0:
		_text(font, p + Vector2(R + 8.0, -2.0), text, HORIZONTAL_ALIGNMENT_LEFT, w, 15, col)
		_text(font, p + Vector2(R + 8.0, 15.0), sub, HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(col.r, col.g, col.b, col.a * 0.75))
	else:
		var line := text if sub == "" else "%s  ·  %s" % [text, sub]
		var y := -R - 8.0 if dir.y < 0.0 else R + 19.0
		_text(font, p + Vector2(-160.0, y), line, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 15, col)


func _disc(p: Vector2, fill: Color, lit: bool) -> void:
	draw_circle(p, R + 3.0, Color(0, 0, 0, 0.75))
	draw_circle(p, R, Color(fill.r * 0.22, fill.g * 0.22, fill.b * 0.22, 0.95))
	draw_circle(p, R - 5.0, Color(fill.r, fill.g, fill.b, 0.85) if lit else Color(fill.r * 0.45, fill.g * 0.45, fill.b * 0.45, 0.6))


## Sector oscuro de recarga (empieza arriba y se cierra en sentido horario).
func _pie(p: Vector2, radius: float, frac: float) -> void:
	if frac <= 0.0:
		return
	var pts := PackedVector2Array([p])
	var steps := maxi(3, int(40.0 * frac))
	for s in steps + 1:
		var a := -PI * 0.5 - TAU * frac * (1.0 - float(s) / steps)
		pts.append(p + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, Color(0, 0, 0, 0.7))


## Letra del botón: en mando, chapa de color en el centro del rombo; en teclado, dentro del círculo.
func _glyph(font: Font, p: Vector2, dir: Vector2, key: String) -> void:
	if PAD_COLORS.has(key):
		var g := p - dir * (SPREAD - 24.0)  # las cuatro chapas juntas en el centro, como en el mando
		draw_circle(g, 13.0, Color(0, 0, 0, 0.9))
		draw_circle(g, 11.0, PAD_COLORS[key])
		draw_string(font, g + Vector2(-11.0, 6.0), key, HORIZONTAL_ALIGNMENT_CENTER, 22.0, 16, Color(0.05, 0.05, 0.05))
	else:
		_text(font, p + Vector2(-R, -8.0), key, HORIZONTAL_ALIGNMENT_CENTER, R * 2.0, 15, Color(1, 1, 1, 0.95))


func _ability_node(font: Font, p: Vector2, dir: Vector2, key: String, slot: int, alt_slot: int) -> void:
	var ab: AbilityData = beast.abilities[slot] if slot < beast.abilities.size() else null
	if ab == null:
		_disc(p, Color(0.3, 0.3, 0.3), false)
		_glyph(font, p, dir, key)
		return
	var usable := beast.can_use_ability(slot)
	_disc(p, ab.color, usable)
	var cd := beast.cooldowns[slot]
	_pie(p, R - 5.0, clampf(cd / maxf(ab.cooldown, 0.001), 0.0, 1.0))
	if beast.ability_slot == slot and beast.ability == ab:
		draw_arc(p, R + 5.0, 0.0, TAU, 48, Color(1, 1, 1, 0.95), 3.0, true)
	_glyph(font, p, dir, key)
	# Dentro: segundos de recarga o coste de PP.
	var enough := beast.pp >= ab.pp_cost
	if cd > 0.05:
		_text(font, p + Vector2(-R, 14.0), "%.0f" % ceilf(cd), HORIZONTAL_ALIGNMENT_CENTER, R * 2.0, 20, Color(1, 1, 1, 0.95))
	else:
		_text(font, p + Vector2(-R, 14.0 if not PAD_COLORS.has(key) else 6.0), "%d" % ab.pp_cost, HORIZONTAL_ALIGNMENT_CENTER, R * 2.0, 14,
				Color(0.7, 0.86, 1.0) if enough else Color(1.0, 0.45, 0.4))
	var col := Color(1, 1, 1, 0.95) if usable else Color(1, 1, 1, 0.62)
	_label(font, p, dir, ab.display_name, AbilityData.kind_label(ab.kind()) if usable or cd > 0.05 else "Faltan PP", col)
	# Pareja alternativa (con LT): círculo pequeño hacia fuera del rombo.
	if alt_slot >= 0 and alt_slot < beast.abilities.size():
		var other := beast.abilities[alt_slot]
		var m := p + Vector2(1, 1) * (R * 0.78)
		var ok := beast.can_use_ability(alt_slot)
		draw_circle(m, MINI + 2.0, Color(0, 0, 0, 0.85))
		draw_circle(m, MINI, Color(other.color.r, other.color.g, other.color.b, 0.9) if ok else Color(other.color.r * 0.4, other.color.g * 0.4, other.color.b * 0.4, 0.8))
		_pie(m, MINI, clampf(beast.cooldowns[alt_slot] / maxf(other.cooldown, 0.001), 0.0, 1.0))
		draw_string(font, m + Vector2(-MINI, 4.0), "LT" if alt_slot >= 2 else "·", HORIZONTAL_ALIGNMENT_CENTER, MINI * 2.0, 11, Color(0.05, 0.05, 0.05))


func _action_node(font: Font, p: Vector2, dir: Vector2, key: String, text: String, available: bool) -> void:
	_disc(p, Color(0.75, 0.7, 0.62), available)
	_glyph(font, p, dir, key)
	_label(font, p, dir, text, "" if available else "Sin estamina" if beast.stamina <= 0.0 else "En el aire",
			Color(1, 1, 1, 0.95) if available else Color(1, 1, 1, 0.5))

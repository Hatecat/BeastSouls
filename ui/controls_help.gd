class_name ControlsHelp
extends RefCounted
## Textos de controles para teclado/ratón y mando (las teclas salen del InputMap actual, ya reasignadas).

## Nombres de la cruceta para cada ranura de habilidad.
const PAD_SLOTS := ["X", "Y", "LT+X", "LT+Y"]


static func _k(action: String) -> String:
	return Settings.event_text(Settings.primary_event(action))


## Filas de la guía: [acción, teclado y ratón, mando, explicación].
static func rows() -> Array:
	return [
		["Mover", "%s %s %s %s" % [_k("move_forward"), _k("move_left"), _k("move_back"), _k("move_right")], "Stick izquierdo", ""],
		["Cámara", "Ratón", "Stick derecho", ""],
		["Ataque ligero", _k("attack_light"), "RB / R1",
			"Combo de hasta 3 golpes: vuelve a pulsar cuando conecte el anterior. Rápido, pero cualquier golpe que recibas lo corta."],
		["Ataque fuerte", _k("attack_heavy"), "RT / R2",
			"Combo de 2 golpes lentos con armadura: aguanta golpes flojos sin cortarse. Mantén pulsado para cargarlo (más daño)."],
		["Ataque en carrera", "%s mientras corres" % _k("attack_light"), "RB mientras corres", "Embestida rápida para cerrar distancia."],
		["Bloquear", "%s (mantener)" % _k("block"), "LB / L1 (mantener)",
			"Para los golpes a cambio de estamina. Sin estamina te rompen la guardia y quedas aturdido."],
		["Esquivar", "%s (toque)" % _k("dodge"), "B / Círculo",
			"Rodada con un instante de invulnerabilidad. Gasta estamina. Sin dirección: paso atrás."],
		["Correr", "%s (mantener)" % _k("dodge"), "L3 (pulsar stick izq.)",
			"Con mando, corres hasta que sueltes el stick (o vuelves a pulsar L3). Gasta estamina."],
		["Saltar", _k("jump"), "A / Cruz", "Gasta un poco de estamina. Lo que pulses en el aire se hace al aterrizar."],
		["Fijar objetivo", _k("lock_on"), "R3 (pulsar stick der.)",
			"La cámara sigue al rival y te mueves a su alrededor. Cambia de objetivo con la rueda o moviendo el stick derecho."],
		["Habilidades 1 y 2", "%s · %s" % [_k("ability_1"), _k("ability_2")], "X / Cuadrado · Y / Triángulo",
			"Las principales: 1 a distancia, 2 de cerca. Gastan Calor (barra naranja), que se gana golpeando, y tienen recarga."],
		["Habilidades 3 y 4", "%s · %s" % [_k("ability_3"), _k("ability_4")], "LT / L2 (mantener) + X · Y",
			"Las secundarias: 3 de área, 4 de mejora. Con mando, mantén LT y el HUD resalta la segunda barra."],
		["Pausa y opciones", "Esc", "Start", ""],
	]


## Ayuda corta del HUD para el dispositivo en uso.
static func hud_text(pad: bool) -> String:
	if pad:
		return "RB ligero (combo) · RT fuerte (mantener: cargar) · LB bloquear · B esquivar · L3 correr · A saltar · R3 fijar\nX / Y habilidades · LT + X / Y habilidades secundarias (gastan Calor) · Start: pausa y guía de controles"
	return "%s ligero (combo) · %s fuerte (mantener: cargar) · %s bloquear · %s: toque esquivar, mantener correr · %s saltar · %s fijar\n%s-%s: habilidades (gastan Calor) · Esc: pausa y guía de controles · F1 hitboxes · F2 IA · F3 calidad" % [
		_k("attack_light"), _k("attack_heavy"), _k("block"), _k("dodge"), _k("jump"), _k("lock_on"), _k("ability_1"), _k("ability_4")]


## Etiqueta de la ranura de habilidad `i` en el HUD.
static func slot_key(i: int, pad: bool) -> String:
	return PAD_SLOTS[i] if pad else _k("ability_%d" % (i + 1))


## Tabla de la guía (para opciones y pausa).
static func build_table(pad_first := false) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	var heads := ["", "Mando", "Teclado y ratón"] if pad_first else ["", "Teclado y ratón", "Mando"]
	for h: String in heads:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", UiTheme.AMBER)
		grid.add_child(l)
	for r: Array in rows():
		var name := Label.new()
		name.text = r[0]
		name.custom_minimum_size.x = 170
		grid.add_child(name)
		for text: String in ([r[2], r[1]] if pad_first else [r[1], r[2]]):
			var l := Label.new()
			l.text = text
			l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.7))
			grid.add_child(l)
		if r[3] != "":
			grid.add_child(Control.new())
			var d := Label.new()
			d.text = r[3]
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size.x = 420
			d.add_theme_font_size_override("font_size", 14)
			d.add_theme_color_override("font_color", UiTheme.DIM)
			grid.add_child(d)
			grid.add_child(Control.new())
	return grid

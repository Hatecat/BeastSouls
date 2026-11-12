class_name ControlsHelp
extends RefCounted
## Textos de controles para teclado/ratón y mando (las teclas salen del InputMap actual, ya reasignadas).

## Nombres de la cruceta para cada ranura de habilidad.
const PAD_SLOTS := ["↑", "→", "↓", "←"]


static func _k(action: String) -> String:
	return Settings.event_text(Settings.primary_event(action))


## Filas de la guía: [acción, teclado y ratón, mando, explicación].
static func rows() -> Array:
	return [
		["Mover", "%s %s %s %s" % [_k("move_forward"), _k("move_left"), _k("move_back"), _k("move_right")], "Stick izquierdo", ""],
		["Cámara", "Ratón", "Stick derecho", ""],
		["Ataque ligero", _k("attack_light"), "RB / R1",
			"Combo de hasta 3 golpes: vuelve a pulsar cuando conecte el anterior. Rápido y gasta poca estamina."],
		["Ataque fuerte", _k("attack_heavy"), "RT / R2",
			"Combo de 2 golpes lentos que dañan mucho la postura. Mantén pulsado para cargarlo (más daño)."],
		["Ataque en carrera", "%s mientras corres" % _k("attack_light"), "RB mientras corres", "Embestida rápida para cerrar distancia."],
		["Bloquear", "%s (mantener)" % _k("block"), "LB / L1 (mantener)",
			"Para los golpes a cambio de estamina. Sin estamina te rompen la guardia y quedas aturdido."],
		["Esquivar", "%s (toque)" % _k("dodge"), "B / Círculo (toque)",
			"Rodada con un instante de invulnerabilidad. Gasta estamina."],
		["Correr", "%s (mantener)" % _k("dodge"), "B / Círculo (mantener)", "Gasta estamina mientras corres."],
		["Fijar objetivo", _k("lock_on"), "R3 (pulsar stick der.)",
			"La cámara sigue al rival y te mueves a su alrededor. Cambia de objetivo con la rueda o moviendo el stick derecho."],
		["Habilidades 1-4", "%s · %s · %s · %s" % [_k("ability_1"), _k("ability_2"), _k("ability_3"), _k("ability_4")], "Cruceta ↑ → ↓ ←",
			"Gastan Calor (barra naranja), que se gana golpeando. Cada una tiene recarga. 1 distancia · 2 cerca · 3 área · 4 mejora."],
		["Pausa y opciones", "Esc", "Start", ""],
	]


## Ayuda corta del HUD para el dispositivo en uso.
static func hud_text(pad: bool) -> String:
	if pad:
		return "RB ligero (combo) · RT fuerte (mantener: cargar) · LB bloquear · B: toque esquivar, mantener correr · R3 fijar\nCruceta ↑→↓←: habilidades (gastan Calor) · Start: pausa y guía de controles"
	return "%s ligero (combo) · %s fuerte (mantener: cargar) · %s bloquear · %s: toque esquivar, mantener correr · %s fijar\n%s-%s: habilidades (gastan Calor) · Esc: pausa y guía de controles · F1 hitboxes · F2 IA · F3 calidad" % [
		_k("attack_light"), _k("attack_heavy"), _k("block"), _k("dodge"), _k("lock_on"), _k("ability_1"), _k("ability_4")]


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

class_name UiTheme
extends RefCounted
## Tema común de la interfaz (piedra oscura y ámbar). Se fusiona con el tema por defecto al arrancar, así lo
## heredan todos los controles, también los que cuelgan de un CanvasLayer.

const AMBER := Color(0.95, 0.62, 0.28)
const TEXT := Color(0.9, 0.86, 0.8)
const DIM := Color(0.6, 0.57, 0.53)
const BG := Color(0.07, 0.06, 0.055, 0.92)
const EDGE := Color(0.42, 0.32, 0.22)

static var _applied := false


static func apply() -> void:
	if _applied:
		return
	_applied = true
	var base := ThemeDB.get_default_theme()
	base.merge_with(build())
	base.default_font = font()
	base.default_font_size = 18


static func font(bold := false) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Cinzel", "EB Garamond", "Cormorant Garamond", "Georgia", "Liberation Serif", "Noto Serif", "DejaVu Serif", "serif"])
	f.font_weight = 700 if bold else 400
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


static func title_font() -> SystemFont:
	return font(true)


## Fuente de títulos con las letras separadas (rótulos en mayúsculas).
static func spaced_font(spacing := 4, bold := true) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = font(bold)
	v.spacing_glyph = spacing
	return v


## Rótulo de sección: mayúsculas pequeñas en ámbar.
static func caption(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", spaced_font(2))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(AMBER.r, AMBER.g, AMBER.b, 0.85))
	return l


## Filete ornamental: rombo y línea que se desvanece. `centered` lo dibuja simétrico (títulos centrados).
static func ornament(width := 320.0, centered := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 14)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var y := c.size.y * 0.5
		var w := c.size.x
		var clear := Color(AMBER.r, AMBER.g, AMBER.b, 0.0)
		var x0 := w * 0.5 if centered else 7.0
		var d := 5.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(x0 - d, y), Vector2(x0, y - d), Vector2(x0 + d, y), Vector2(x0, y + d)]), AMBER)
		c.draw_polyline_colors(PackedVector2Array([Vector2(x0 + d + 5, y), Vector2(w, y)]), PackedColorArray([AMBER, clear]), 1.5, true)
		if centered:
			c.draw_polyline_colors(PackedVector2Array([Vector2(x0 - d - 5, y), Vector2(0, y)]), PackedColorArray([AMBER, clear]), 1.5, true))
	return c


## Fondo de pantalla completa: penumbra cálida en el centro que se cierra hacia los bordes.
static func backdrop() -> TextureRect:
	var t := TextureRect.new()
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color(0.17, 0.125, 0.09))
	g.gradient.set_color(1, Color(0.03, 0.026, 0.026))
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.42)
	g.fill_to = Vector2(1.05, 1.0)
	t.texture = g
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Botón principal de una pantalla («¡Luchar!», «Listo»): relleno ámbar.
static func primary_button(b: Button) -> void:
	b.add_theme_font_override("font", spaced_font(2))
	b.add_theme_stylebox_override("normal", box(Color(0.42, 0.22, 0.07, 0.95), AMBER, 1, 4))
	b.add_theme_stylebox_override("hover", box(Color(0.58, 0.31, 0.1, 0.98), AMBER.lightened(0.3), 1, 4))
	b.add_theme_stylebox_override("pressed", box(Color(0.7, 0.4, 0.14), AMBER.lightened(0.4), 1, 4))
	b.add_theme_color_override("font_color", Color(1.0, 0.92, 0.8))


## Botón de lista de menú: sin caja, con una barra a la izquierda; al pasar el ratón o enfocarlo se enciende
## una franja ámbar que se desvanece hacia la derecha y el texto se desplaza.
static func menu_button(b: Button, font_size := 22) -> void:
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", font_size)
	var idle := box(Color(0.05, 0.042, 0.036, 0.55), Color(EDGE.r, EDGE.g, EDGE.b, 0.8), 0, 2, Vector2(22, 10))
	idle.border_width_left = 3
	var hot := StyleBoxTexture.new()
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.offsets = PackedFloat32Array([0.0, 0.014, 0.0141, 1.0])
	g.gradient.colors = PackedColorArray([Color(1.0, 0.78, 0.45), Color(1.0, 0.78, 0.45), Color(0.8, 0.42, 0.12, 0.62), Color(0.5, 0.25, 0.06, 0.0)])
	g.width = 512
	g.height = 4
	hot.texture = g
	hot.content_margin_left = 34
	hot.content_margin_right = 22
	hot.content_margin_top = 10
	hot.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("pressed", hot)
	b.add_theme_stylebox_override("hover_pressed", hot)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.95, 0.85))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.85))
	b.focus_entered.connect(func() -> void: b.add_theme_stylebox_override("normal", hot))
	b.focus_exited.connect(func() -> void: b.add_theme_stylebox_override("normal", idle))


static func box(bg: Color, border: Color, width := 1, radius := 3, pad := Vector2(14, 8)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	s.anti_aliasing = true
	return s


static func build() -> Theme:
	var t := Theme.new()
	# Botones (también OptionButton, que hereda de Button).
	var normal := box(Color(0.12, 0.1, 0.085, 0.9), EDGE)
	var hover := box(Color(0.2, 0.14, 0.09, 0.95), AMBER)
	var pressed := box(Color(0.3, 0.17, 0.07, 0.95), AMBER.lightened(0.2))
	var disabled := box(Color(0.09, 0.08, 0.075, 0.6), Color(0.25, 0.22, 0.2))
	var focus := box(Color(0, 0, 0, 0), Color(1.0, 0.9, 0.72), 2)
	focus.draw_center = false
	focus.set_expand_margin_all(2)
	focus.shadow_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.45)
	focus.shadow_size = 6
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1.0, 0.9, 0.75))
		t.set_color("font_pressed_color", type, Color(1.0, 0.85, 0.6))
		t.set_color("font_hover_pressed_color", type, Color(1.0, 0.85, 0.6))
		t.set_color("font_focus_color", type, Color(1.0, 0.9, 0.75))
		t.set_color("font_disabled_color", type, Color(0.45, 0.42, 0.4))
	# Casillas: sin caja, solo el texto y la marca.
	for type in ["CheckBox", "CheckButton"]:
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 4
		empty.content_margin_right = 4
		for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			t.set_stylebox(s, type, empty)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1.0, 0.9, 0.75))
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, Color(1.0, 0.9, 0.75))
		t.set_color("font_focus_color", type, Color(1.0, 0.9, 0.75))
	# Paneles.
	var panel := box(BG, Color(0.5, 0.38, 0.25), 1, 6, Vector2(26, 22))
	panel.border_width_top = 2
	panel.shadow_color = Color(0, 0, 0, 0.55)
	panel.shadow_size = 22
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PopupMenu", box(Color(0.08, 0.07, 0.06, 0.98), EDGE, 1, 2, Vector2(6, 6)))
	t.set_stylebox("hover", "PopupMenu", box(Color(0.3, 0.17, 0.07), Color(0, 0, 0, 0), 0, 2, Vector2(6, 2)))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1.0, 0.9, 0.75))
	# Campos de texto.
	var field := box(Color(0.04, 0.035, 0.03, 0.9), Color(0.3, 0.25, 0.2), 1, 2, Vector2(10, 6))
	var field_focus := box(Color(0.05, 0.04, 0.035, 0.95), AMBER, 1, 2, Vector2(10, 6))
	for type in ["LineEdit", "SpinBox"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, field_focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("caret_color", type, AMBER)
		t.set_color("selection_color", type, Color(0.6, 0.35, 0.1, 0.5))
	# Deslizadores.
	var rail := box(Color(0.04, 0.035, 0.03), Color(0.3, 0.25, 0.2), 1, 2, Vector2(0, 3))
	var fill := box(Color(0.75, 0.42, 0.15), Color(0.95, 0.62, 0.28), 1, 2, Vector2(0, 3))
	t.set_stylebox("slider", "HSlider", rail)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	# Pestañas.
	var tab_sel := box(Color(0.2, 0.13, 0.07, 0.95), AMBER, 0, 0, Vector2(18, 8))
	tab_sel.border_width_bottom = 2
	var tab_off := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, Vector2(18, 8))
	var tab_hover := box(Color(0.14, 0.1, 0.07, 0.8), Color(0, 0, 0, 0), 0, 0, Vector2(18, 8))
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_off)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hover)
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TabContainer", box(Color(0, 0, 0, 0.25), Color(0.3, 0.24, 0.18), 1, 0, Vector2(18, 16)))
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabContainer", Color(1.0, 0.85, 0.6))
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	# Separadores y etiquetas.
	var line := StyleBoxLine.new()
	line.color = Color(0.42, 0.32, 0.22, 0.6)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 14)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	# Barras de desplazamiento finas.
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 0, 2, Vector2(4, 0)))
	t.set_stylebox("grabber", "VScrollBar", box(Color(0.4, 0.3, 0.2), Color(0, 0, 0, 0), 0, 2, Vector2(4, 0)))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(0.6, 0.4, 0.2), Color(0, 0, 0, 0), 0, 2, Vector2(4, 0)))
	return t

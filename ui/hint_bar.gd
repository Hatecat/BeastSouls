class_name HintBar
extends HBoxContainer
## Leyenda de botones al pie de los menús («Ⓐ Elegir   Ⓑ Volver»). Cambia sola entre mando y teclado según el
## último dispositivo usado. Cada entrada es [botón del mando, tecla, texto].

const PAD_COLORS := {
	"A": Color(0.45, 0.8, 0.4), "B": Color(0.9, 0.38, 0.33), "X": Color(0.4, 0.62, 0.95), "Y": Color(0.95, 0.8, 0.35),
}

var items: Array = []


static func make(entries: Array) -> HintBar:
	var bar := HintBar.new()
	bar.items = entries
	return bar


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Settings.device_changed.connect(_fill)
	_fill(Settings.using_pad)


func set_items(entries: Array) -> void:
	items = entries
	if is_inside_tree():
		_fill(Settings.using_pad)


func _fill(pad: bool) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for it: Array in items:
		var key: String = it[0] if pad else it[1]
		if key == "":
			continue
		add_child(_badge(key, pad))
		var l := Label.new()
		l.text = it[2]
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", UiTheme.DIM.lightened(0.25))
		add_child(l)
		var gap := Control.new()
		gap.custom_minimum_size.x = 14
		add_child(gap)


func _badge(key: String, pad: bool) -> Control:
	var p := PanelContainer.new()
	var round_btn := pad and key.length() == 1
	var col: Color = PAD_COLORS.get(key, UiTheme.TEXT) if pad else UiTheme.TEXT
	var s := UiTheme.box(Color(0.05, 0.045, 0.04, 0.9), Color(col.r, col.g, col.b, 0.85), 2 if round_btn else 1,
			13 if round_btn else 4, Vector2(0 if round_btn else 8, 0))
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(26, 26)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = key
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.font(true))
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	p.add_child(l)
	return p

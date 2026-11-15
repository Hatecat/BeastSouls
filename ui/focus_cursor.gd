class_name FocusCursor
extends Control
## Cursor de foco común a todos los menús: un marco brillante que late alrededor del control enfocado y una
## flecha a su izquierda. Sigue al foco deslizándose de un control a otro. Solo se muestra al navegar con
## mando o teclado (con el ratón basta el resaltado de «hover»). Lo crea `Settings` una sola vez, en un
## CanvasLayer por encima de todo, así sirve igual en el menú, el selector, las opciones y la pausa.

const GROW := 4.0
const FOLLOW := 24.0

var _rect := Rect2()
var _alpha := 0.0
var _nav := false
var _time := 0.0
var _frame: StyleBoxFlat


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = StyleBoxFlat.new()
	_frame.draw_center = false
	_frame.border_color = Color(1.0, 0.93, 0.78)
	_frame.set_border_width_all(2)
	_frame.set_corner_radius_all(6)
	_frame.shadow_color = Color(UiTheme.AMBER.r, UiTheme.AMBER.g, UiTheme.AMBER.b, 0.55)
	_frame.shadow_size = 10
	_frame.anti_aliasing = true


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventKey:
		_nav = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			_nav = true
	elif event is InputEventMouseButton:
		_nav = false
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 4.0:
		_nav = false


func _process(delta: float) -> void:
	var owner_c := get_viewport().gui_get_focus_owner()
	var show := _nav and owner_c != null and owner_c.is_visible_in_tree()
	if show:
		var target := _target(owner_c)
		if _alpha < 0.05:
			_rect = target
		else:
			var k := 1.0 - exp(-delta * FOLLOW)
			_rect = Rect2(_rect.position.lerp(target.position, k), _rect.size.lerp(target.size, k))
	_alpha = move_toward(_alpha, 1.0 if show else 0.0, delta * 9.0)
	modulate.a = _alpha
	_time += delta
	if _alpha > 0.0:
		queue_redraw()


## Rectángulo del control en pantalla; en una barra de pestañas, solo la pestaña activa. Si está dentro de un
## ScrollContainer se recorta a lo que se ve.
func _target(c: Control) -> Rect2:
	# Una fila marcada con el meta "focus_frame" (etiqueta + control, en Opciones) se enmarca entera.
	var holder: Node = c
	for i in 3:
		holder = holder.get_parent()
		if holder == null or not holder is Control:
			break
		if holder.has_meta(&"focus_frame"):
			c = holder as Control
			break
	var xf := c.get_global_transform_with_canvas()
	var r := Rect2(xf.origin, c.size * xf.get_scale())
	if c is TabBar and (c as TabBar).tab_count > 0:
		var tab := (c as TabBar).get_tab_rect((c as TabBar).current_tab)
		r = Rect2(xf.origin + tab.position * xf.get_scale(), tab.size * xf.get_scale())
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			var pxf := (p as Control).get_global_transform_with_canvas()
			var clip := Rect2(pxf.origin, (p as Control).size * pxf.get_scale()).grow(GROW)
			if r.intersects(clip):
				r = r.intersection(clip)
		p = p.get_parent()
	return r.grow(GROW)


func _draw() -> void:
	if _alpha <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 5.5)
	var r := _rect.grow(pulse * 2.0)
	_frame.shadow_size = 8 + int(pulse * 8.0)
	draw_style_box(_frame, r)
	# Esquinas reforzadas.
	var white := Color(1.0, 0.97, 0.9)
	var arm := minf(12.0, r.size.y * 0.35)
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var p := r.position + r.size * corner
		var dir := Vector2(1.0 - corner.x * 2.0, 1.0 - corner.y * 2.0)
		draw_line(p + Vector2(dir.x * 3.0, 0), p + Vector2(dir.x * arm, 0), white, 3.0, true)
		draw_line(p + Vector2(0, dir.y * 3.0), p + Vector2(0, dir.y * arm), white, 3.0, true)
	# Flecha a la izquierda.
	var tip := Vector2(r.position.x - 5.0 - pulse * 4.0, r.position.y + r.size.y * 0.5)
	var tri := PackedVector2Array([tip, tip + Vector2(-11, -8), tip + Vector2(-11, 8)])
	draw_colored_polygon(PackedVector2Array([tri[0] + Vector2(2, 0), tri[1] + Vector2(-2, -3), tri[2] + Vector2(-2, 3)]), Color(0, 0, 0, 0.6))
	draw_colored_polygon(tri, UiTheme.AMBER.lightened(0.35))

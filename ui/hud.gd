class_name Hud
extends CanvasLayer
## HUD mínimo al estilo souls: vida y estamina arriba a la izquierda (el ancho crece con el máximo),
## más un panel de depuración y la ayuda de controles.

@export var beast: Beast
@export var camera: ThirdPersonCamera
@export var show_debug := true
## Píxeles de barra por punto de vida/estamina.
@export var px_per_point := 3.2

var _health: Bar
var _stamina: Bar
var _debug: Label


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
	root.add_child(_health)
	root.add_child(_stamina)

	_debug = Label.new()
	_debug.position = Vector2(40, 110)
	_debug.add_theme_font_size_override("font_size", 16)
	_debug.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_debug.visible = show_debug
	add_child(_debug)

	var help := Label.new()
	help.text = "WASD mover · Ratón cámara · Espacio: toque esquivar / mantener correr\nClic de rueda o Tab: fijar objetivo · Gesto de ratón o girar la rueda: cambiar objetivo · Esc: soltar ratón"
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_left = 40.0
	help.offset_bottom = -28.0
	add_child(help)


func _make_bar(color: Color, h: float) -> Bar:
	var b := Bar.new()
	b.fill_color = color
	b.custom_minimum_size = Vector2(300, h)
	return b


func _process(_delta: float) -> void:
	if beast == null:
		return
	_health.custom_minimum_size.x = beast.max_health * px_per_point
	_stamina.custom_minimum_size.x = beast.max_stamina * px_per_point
	_health.value = beast.health / beast.max_health
	_stamina.value = beast.stamina / beast.max_stamina
	if _debug.visible:
		var target := "—"
		if camera and camera.lock_target:
			target = "%s (%.1f m)" % [camera.lock_target.name, beast.global_position.distance_to(camera.lock_target.global_position)]
		_debug.text = "Estado: %s%s%s\nVelocidad: %.1f m/s\nEstamina: %d / %d\nObjetivo: %s\nFPS: %d" % [
			Beast.State.keys()[beast.state],
			"  [correr]" if beast.sprinting else "",
			"  [invulnerable]" if beast.is_invulnerable() else "",
			beast.horizontal_speed(), beast.stamina, beast.max_stamina, target,
			Engine.get_frames_per_second()]

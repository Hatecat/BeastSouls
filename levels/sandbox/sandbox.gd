extends Node3D
## Sandbox de la Fase 0: comprueba modelo, iluminación y animaciones.
## ←/→ cambia de clip. La cámara orbita sola alrededor del personaje.

@export var orbit_speed := 0.25
@export var orbit_radius := 6.5
@export var orbit_height := 2.4

@onready var visual: CharacterVisual = $CharizardVisual
@onready var camera: Camera3D = $Camera3D
@onready var label: Label = $UI/Info

var _clips: PackedStringArray
var _index := 0
var _angle := PI - 0.6


func _ready() -> void:
	_clips = visual.get_clip_names()
	_index = maxi(0, _clips.find("idle"))
	_play_current()


func _process(delta: float) -> void:
	_angle += orbit_speed * delta
	var target := visual.global_position + Vector3.UP * 1.2
	camera.global_position = visual.global_position + Vector3(sin(_angle) * orbit_radius, orbit_height, cos(_angle) * orbit_radius)
	camera.look_at(target)


func _unhandled_input(event: InputEvent) -> void:
	if _clips.is_empty():
		return
	if event.is_action_pressed("debug_next"):
		_index = (_index + 1) % _clips.size()
		_play_current()
	elif event.is_action_pressed("debug_prev"):
		_index = (_index - 1 + _clips.size()) % _clips.size()
		_play_current()


func _play_current() -> void:
	var clip := _clips[_index]
	# En el visor se reproduce el clip directamente, en bucle.
	var anim := visual.anim_player.get_animation(clip)
	anim.loop_mode = Animation.LOOP_LINEAR
	visual.anim_player.play(clip, 0.2)
	label.text = "Clip %d/%d: %s  (%.2fs)\n← / → para cambiar" % [_index + 1, _clips.size(), clip, anim.length]

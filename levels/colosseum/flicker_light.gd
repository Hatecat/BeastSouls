class_name FlickerLight
extends OmniLight3D
## Luz de fuego que parpadea (braseros, antorchas). Solo presentación.

@export var base_energy := 2.5
@export var amount := 0.25
@export var speed := 7.0

var _t := randf() * 100.0


func _process(delta: float) -> void:
	_t += delta * speed
	var n := sin(_t) * 0.5 + sin(_t * 2.3 + 1.7) * 0.3 + sin(_t * 5.1 + 0.4) * 0.2
	light_energy = base_energy * (1.0 + n * amount)

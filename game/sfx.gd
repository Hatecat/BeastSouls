class_name Sfx
extends RefCounted
## Acceso estático al autoload Audio para las clases de simulación (Beast, habilidades, proyectiles), sin
## nombrar el autoload: así se pueden usar desde scripts que se compilan antes que los autoloads (pruebas).


static func _audio() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"Audio") if tree else null


static func play(name: String, pos := Vector3.INF, volume_db := 0.0, pitch := 1.0, pitch_random := 0.08) -> void:
	var a := _audio()
	if a:
		a.play(name, pos, volume_db, pitch, pitch_random)


static func attach_loop(name: String, parent: Node3D, volume_db := 0.0, bus := &"SFX") -> AudioStreamPlayer3D:
	var a := _audio()
	return a.attach_loop(name, parent, volume_db, bus) if a else null

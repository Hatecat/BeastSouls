class_name Projectile
extends Node3D
## Proyectil simulado en el tick de física: avanza, gira hacia su objetivo y explota al tocar
## una hurtbox ajena o el escenario. El daño pasa por `owner_beast.deal_hit`.

var owner_beast: Beast
var hit: AttackData
var target: Node3D
var speed := 18.0
var radius := 0.4
var lifetime := 2.0
var homing := 1.2
var explode_radius := 1.8
var color := Fx.FIRE
## Escala del efecto visual (no de la colisión).
var visual_scale := 1.0

var _age := 0.0
var _done := false
var _visual: Node3D


func _ready() -> void:
	_visual = Fx.fireball_visual(color)
	_visual.scale = Vector3.ONE * visual_scale
	add_child(_visual)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age >= lifetime or not is_instance_valid(owner_beast):
		_explode(global_position)
		return
	# Teledirigido suave hacia el objetivo.
	var dir := -global_basis.z
	if is_instance_valid(target) and target.has_method("get_lock_position"):
		var want: Vector3 = (target.get_lock_position() - global_position).normalized()
		var angle := dir.angle_to(want)
		if angle > 0.001:
			var axis := dir.cross(want).normalized()
			if axis.is_normalized():
				dir = dir.rotated(axis, minf(angle, homing * delta))
	var step := dir * speed * delta
	var from := global_position
	var to := from + step
	# Escenario.
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
	var wall := get_world_3d().direct_space_state.intersect_ray(ray)
	if not wall.is_empty():
		_explode(wall.position)
		return
	global_transform = Transform3D(Basis.looking_at(dir), to)
	# Bestias.
	for v in owner_beast.beasts_in_sphere(to, radius):
		_explode(to, v)
		return


func _explode(pos: Vector3, direct: Beast = null) -> void:
	_done = true
	if is_instance_valid(owner_beast):
		var victims: Array[Beast] = []
		if direct:
			victims.append(direct)
		if explode_radius > 0.0:
			for v in owner_beast.beasts_in_sphere(pos, explode_radius):
				if v not in victims:
					victims.append(v)
		for v in victims:
			owner_beast.deal_hit(v, hit, pos)
	Fx.explosion(get_parent(), pos, color, clampf(explode_radius / 1.8, 0.4, 1.5))
	queue_free()

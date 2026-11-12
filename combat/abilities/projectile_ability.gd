class_name ProjectileAbility
extends AbilityData
## Lanza un proyectil (bola de fuego) en `spawn_time`.

@export var hit: AttackData
@export var spawn_time := 0.3
## Punto de salida en coordenadas locales (adelante = -Z).
@export var spawn_offset := Vector3(0, 1.6, -1.1)
@export var speed := 18.0
@export var radius := 0.4
@export var lifetime := 2.0
## Giro máximo (rad/s) hacia el objetivo fijado.
@export var homing := 1.2
## Radio de la explosión al impactar (0 = solo el impacto directo).
@export var explode_radius := 1.8


func tick(beast: Beast, _cast: Dictionary, t: float, delta: float) -> void:
	if not crossed(t, delta, spawn_time):
		return
	var p := Projectile.new()
	p.owner_beast = beast
	p.hit = hit
	p.speed = speed
	p.radius = radius
	p.lifetime = lifetime
	p.homing = homing
	p.explode_radius = explode_radius
	p.target = beast.lock_target
	beast.get_parent().add_child(p)
	p.global_transform = Transform3D(Basis(Vector3.UP, beast.facing), beast.global_position + Basis(Vector3.UP, beast.facing) * spawn_offset)
	p.reset_physics_interpolation()

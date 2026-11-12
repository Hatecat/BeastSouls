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
## Escala del efecto visual del proyectil.
@export var visual_scale := 1.0
## Proyectiles por lanzamiento (ráfaga, p. ej. pin misil) y separación entre ellos (s).
@export var count := 1
@export var interval := 0.1


func tick(beast: Beast, _cast: Dictionary, t: float, delta: float) -> void:
	for i in count:
		if crossed(t, delta, spawn_time + i * interval):
			_spawn(beast, i)


func _spawn(beast: Beast, index: int) -> void:
	var p := Projectile.new()
	p.color = color
	p.visual_scale = visual_scale
	p.owner_beast = beast
	p.hit = hit
	p.speed = speed
	p.radius = radius
	p.lifetime = lifetime
	p.homing = homing
	p.explode_radius = explode_radius
	p.target = beast.lock_target
	beast.get_parent().add_child(p)
	# En ráfaga, cada proyectil sale un poco desplazado a un lado y a otro.
	var offset := spawn_offset + Vector3(0.25 * (1 if index % 2 else -1) if count > 1 else 0.0, 0, 0)
	p.global_transform = Transform3D(Basis(Vector3.UP, beast.facing), beast.global_position + Basis(Vector3.UP, beast.facing) * offset)
	p.reset_physics_interpolation()
	Sfx.play("cast_projectile", p.global_position, -2.0)

class_name DashAbility
extends AbilityData
## Embestida: el lanzador cruza una distancia a toda velocidad y golpea una vez a lo que toque por el camino.

@export var hit: AttackData
## Ventana de la embestida (s) y velocidad (m/s): distancia ≈ (dash_end - dash_start) * dash_speed.
@export var dash_start := 0.2
@export var dash_end := 0.5
@export var dash_speed := 18.0
## Esfera de golpeo delante del cuerpo.
@export var radius := 1.3
@export var offset := Vector3(0, 1.0, -0.8)


func kind() -> StringName:
	return &"dash"


func summary() -> String:
	return "Embestida de %d m · %d de daño" % [roundi((dash_end - dash_start) * dash_speed), hit.damage if hit else 0]


func reach() -> float:
	return (dash_end - dash_start) * dash_speed


func start(_beast: Beast, cast: Dictionary) -> void:
	cast.hit = []
	cast.started = false


func tick(beast: Beast, cast: Dictionary, t: float, _delta: float) -> void:
	if t < dash_start or t > dash_end:
		return
	if not cast.started:
		cast.started = true
		Fx.shockwave(beast.get_parent(), beast.global_position, 1.6, color)
		Sfx.play("dodge", beast.global_position + Vector3.UP, 0.0, 0.8)
	if not beast.is_remote:
		var f := beast.forward() * dash_speed
		beast.velocity.x = f.x
		beast.velocity.z = f.z
	var center := beast.global_position + Basis(Vector3.UP, beast.facing) * offset
	for v in beast.beasts_in_sphere(center, radius):
		if v not in cast.hit:
			cast.hit.append(v)
			beast.deal_hit(v, hit, beast.global_position)

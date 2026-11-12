class_name ChannelAbility
extends AbilityData
## Habilidad canalizada en cono (lanzallamas): golpea cada `tick_interval` a todo lo que hay delante.

@export var hit: AttackData
@export var channel_start := 0.3
@export var channel_end := 1.5
@export var tick_interval := 0.15
@export var cone_range := 5.5
@export var cone_angle_deg := 28.0
## Origen del cono en coordenadas locales (adelante = -Z), aprox. la boca.
@export var origin_offset := Vector3(0, 1.7, -0.7)
## Socket visual desde el que sale el efecto (solo presentación).
@export var fx_socket: StringName = &"mouth"


func start(beast: Beast, cast: Dictionary) -> void:
	cast.next_tick = channel_start
	var jet := Fx.flame_jet(color)
	jet.top_level = true
	beast.add_child(jet)
	cast.fx = jet
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = 7.0
	light.top_level = true
	beast.add_child(light)
	cast.light = light


func tick(beast: Beast, cast: Dictionary, t: float, _delta: float) -> void:
	var channeling := t >= channel_start and t <= channel_end
	var origin := beast.global_position + Basis(Vector3.UP, beast.facing) * origin_offset
	_update_fx(beast, cast, channeling, origin)
	while channeling and t >= cast.next_tick:
		cast.next_tick += tick_interval
		for v in beast.beasts_in_cone(origin, beast.forward(), cone_range, cone_angle_deg):
			beast.deal_hit(v, hit, origin)


func finish(_beast: Beast, cast: Dictionary) -> void:
	var jet: GPUParticles3D = cast.get("fx")
	if is_instance_valid(jet):
		jet.emitting = false
		jet.get_tree().create_timer(jet.lifetime + 0.1).timeout.connect(jet.queue_free)
	var light: OmniLight3D = cast.get("light")
	if is_instance_valid(light):
		light.queue_free()


func _update_fx(beast: Beast, cast: Dictionary, on: bool, origin: Vector3) -> void:
	var jet: GPUParticles3D = cast.fx
	var socket := beast.visual.get_socket(fx_socket)
	var pos := socket.global_position if socket != beast.visual else origin
	jet.global_transform = Transform3D(Basis(Vector3.UP, beast.facing), pos)
	jet.emitting = on
	var light: OmniLight3D = cast.light
	light.global_position = pos + beast.forward() * 2.0
	light.light_energy = randf_range(2.5, 3.5) if on else 0.0

class_name NetMatch
extends Node
## Partida online 1 contra 1: envía el estado del Beast local, alimenta el proxy del rival y gestiona los
## eventos (golpe confirmado, muerte) y el marcador.

signal score_changed(mine: int, theirs: int)
## El rival ha caído (lo decide su máquina).
signal remote_died
signal ended(reason: String)

## Instantáneas por segundo.
@export var send_rate := 30.0

var local: Beast
var remote: Beast
var proxy: NetProxy
var score_mine := 0
var score_theirs := 0

var _send_accum := 0.0


func setup(local_beast: Beast, remote_beast: Beast) -> void:
	local = local_beast
	remote = remote_beast
	proxy = NetProxy.new()
	proxy.name = "NetProxy"
	add_child(proxy)
	proxy.setup(remote, local)


func _ready() -> void:
	# Después de que el Beast local simule su tick, para mandar el estado recién calculado.
	process_physics_priority = 10
	Net.snapshot_received.connect(proxy.push)
	Net.event_received.connect(_on_event)
	Net.disconnected.connect(func(reason: String) -> void: ended.emit(reason))
	# El proxy golpeó al Beast local (decidido aquí): avisar al atacante.
	remote.hit_landed.connect(_on_remote_hit_local)
	local.died.connect(_on_local_died)


func _exit_tree() -> void:
	if Net.snapshot_received.is_connected(proxy.push):
		Net.snapshot_received.disconnect(proxy.push)
	if Net.event_received.is_connected(_on_event):
		Net.event_received.disconnect(_on_event)


func _physics_process(delta: float) -> void:
	_send_accum += delta
	if _send_accum >= 1.0 / send_rate:
		_send_accum = fmod(_send_accum, 1.0 / send_rate)
		Net.send_snapshot(local.net_snapshot())


func _on_remote_hit_local(target: Beast, result: Beast.HitResult, atk: AttackData) -> void:
	if target != local or atk == null:
		return
	Net.send_event({type = "hit", result = result, gain = atk.heat_gain, hitstop = atk.hitstop})


func _on_local_died() -> void:
	score_theirs += 1
	score_changed.emit(score_mine, score_theirs)
	Net.send_event({type = "died"})


func _on_event(e: Dictionary) -> void:
	match e.get("type", ""):
		"hit":
			local.confirm_remote_hit(remote, int(e.result) as Beast.HitResult, float(e.gain), float(e.hitstop))
		"died":
			score_mine += 1
			score_changed.emit(score_mine, score_theirs)
			remote_died.emit()

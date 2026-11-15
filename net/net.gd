extends Node
## Autoload "Net": conexión 1 contra 1 por ENet (UDP). Un PC aloja (`host`) y el otro se une (`join`).
##
## Modelo de red: cada jugador es dueño de su Beast (lo simula sin retardo) y envía instantáneas de su estado
## (`send_snapshot`, no fiable y ordenado, ~30 Hz). El rival se ve como un proxy interpolado (NetProxy).
## Los golpes los decide la VÍCTIMA en su máquina; los eventos (golpe confirmado, muerte...) van por el canal
## fiable (`send_event`). Ver net/net_match.gd.
##
## Dos formas de conectar, con el mismo modelo y los mismos mensajes:
##   - Directa: `host()` / `join(ip)`. Quien aloja necesita el puerto UDP abierto.
##   - Por servidor: los dos llaman a `join_server(dirección, sala)` contra un servidor de retransmisión
##     (`serve()`, ver net/relay_server.gd y docs/SERVIDOR.md) que los empareja por código de sala y reenvía sus
##     mensajes. El primero en llegar a la sala hace de anfitrión (`mode == HOST`, lleva las rondas), el segundo de
##     invitado. Nadie abre puertos; el servidor no simula nada.
##
## Para pruebas: `sim_latency_ms`, `sim_jitter_ms` y `sim_loss` retrasan/pierden lo que ESTE lado envía
## (latencia de ida; el ping total es la suma de ambos lados).

signal connected  ## Saludo completado: ya hay rival.
signal waiting  ## Por servidor: estamos en la sala y falta el rival.
signal disconnected(reason: String)
signal failed(reason: String)
signal snapshot_received(data: Array)
signal event_received(data: Dictionary)

const PROTOCOL_VERSION := 4
const DEFAULT_PORT := 24700
const HANDSHAKE_TIMEOUT_MS := 8000
const CHANNEL_EVENTS := 0
const CHANNEL_STATE := 1

## Salas y jugadores que admite un servidor a la vez.
const SERVER_MAX_CLIENTS := 64

enum Mode { OFF, HOST, JOIN, SERVER }

var mode := Mode.OFF
var nick := "Jugador"
var remote_nick := "Rival"
## 0 = anfitrión, 1 = invitado (elige el punto de aparición).
var side := 0
## La partida va a través de un servidor de retransmisión (no hay conexión directa con el rival).
var relay := false
var room := ""

@export var sim_latency_ms := 0
@export var sim_jitter_ms := 0
@export_range(0.0, 1.0) var sim_loss := 0.0

var _peer: ENetMultiplayerPeer
var _remote_id := 0
var _accepted := false
var _deadline := 0
## Envíos retrasados por la latencia simulada: [instante_ms, callable].
var _outbox: Array = []
var _rng := RandomNumberGenerator.new()

# Solo servidor.
## Recién conectados que aún no han saludado: id → instante límite (ms).
var _pending := {}
## Código de sala → id del jugador que espera rival.
var _rooms := {}
## id → id de su rival.
var _partner := {}
var _nicks := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Diferidos: cerrar el peer dentro de su propio sondeo (poll) hace que Godot se cuelgue.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected, CONNECT_DEFERRED)
	multiplayer.connection_failed.connect(func() -> void: _fail("unreachable"), CONNECT_DEFERRED)
	multiplayer.server_disconnected.connect(func() -> void: _drop("server_left" if relay else "host_left"), CONNECT_DEFERRED)


func host(port := DEFAULT_PORT) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, 1, 2)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = _peer
	mode = Mode.HOST
	side = 0
	return OK


func join(address: String, port := DEFAULT_PORT) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port, 2)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = _peer
	mode = Mode.JOIN
	side = 1
	_deadline = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS
	return OK


## Entra en la sala `room_code` del servidor de `address`. Vacío = sala pública (el primero que llegue).
func join_server(address: String, room_code := "", port := DEFAULT_PORT) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port, 2)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = _peer
	mode = Mode.JOIN
	relay = true
	room = room_code
	_deadline = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS
	return OK


## Arranca como servidor de retransmisión (sin juego): empareja jugadores por sala y reenvía sus mensajes.
func serve(port := DEFAULT_PORT) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, SERVER_MAX_CLIENTS, 2)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = _peer
	# Cada cliente solo conoce al servidor: no se anuncian unos a otros.
	(multiplayer as SceneMultiplayer).server_relay = false
	mode = Mode.SERVER
	return OK


func close() -> void:
	if _peer:
		_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	mode = Mode.OFF
	relay = false
	room = ""
	_pending.clear()
	_rooms.clear()
	_partner.clear()
	_nicks.clear()
	_remote_id = 0
	_accepted = false
	_outbox.clear()


func is_online() -> bool:
	return mode != Mode.OFF and _accepted


## Ida y vuelta medida por ENet (ms), sin contar la latencia simulada. Por servidor es solo nuestro tramo hasta él.
func rtt() -> int:
	if _peer == null or _remote_id == 0:
		return -1
	var p := _peer.get_peer(_remote_id)
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else -1


func send_snapshot(data: Array) -> void:
	if not _accepted:
		return
	if sim_loss > 0.0 and _rng.randf() < sim_loss:
		return
	_queue(func() -> void: _rx_snapshot.rpc_id(_remote_id, data))


func send_event(data: Dictionary) -> void:
	if not _accepted:
		return
	_queue(func() -> void: _rx_event.rpc_id(_remote_id, data))


func _queue(call: Callable) -> void:
	if sim_latency_ms <= 0 and sim_jitter_ms <= 0:
		call.call()
		return
	var delay := sim_latency_ms + _rng.randi_range(0, sim_jitter_ms)
	var at := Time.get_ticks_msec() + delay
	# Con jitter no se reordena: nunca antes que el último encolado (como un canal ordenado).
	if not _outbox.is_empty():
		at = maxi(at, _outbox[-1][0])
	_outbox.append([at, call])


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	while not _outbox.is_empty() and _outbox[0][0] <= now:
		var call: Callable = _outbox.pop_front()[1]
		if _peer and _remote_id != 0:
			call.call()
	if mode == Mode.JOIN and not _accepted and _deadline > 0 and now > _deadline:
		_fail("timeout")
	if mode == Mode.SERVER:
		for id: int in _pending.keys():
			if now > _pending[id]:
				_pending.erase(id)
				_kick(id)


# --- Saludo ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if mode == Mode.SERVER:
		_pending[id] = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS
		return
	if _remote_id != 0 or (relay and id != 1):
		return
	_remote_id = id
	if relay:
		_relay_hello.rpc_id(1, PROTOCOL_VERSION, nick, room)
	elif mode == Mode.JOIN:
		_hello.rpc_id(id, PROTOCOL_VERSION, nick)


@rpc("any_peer", "reliable", "call_remote", CHANNEL_EVENTS)
func _hello(version: int, their_nick: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	if mode != Mode.HOST or from != _remote_id:
		return
	if version != PROTOCOL_VERSION:
		_welcome.rpc_id(from, false, nick)
		_peer.get_peer(from).peer_disconnect_later()
		_remote_id = 0
		return
	remote_nick = their_nick.substr(0, 16)
	_welcome.rpc_id(from, true, nick)
	_accepted = true
	connected.emit()


@rpc("authority", "reliable", "call_remote", CHANNEL_EVENTS)
func _welcome(ok: bool, their_nick: String) -> void:
	if not ok:
		_fail.call_deferred("version")
		return
	remote_nick = their_nick.substr(0, 16)
	_accepted = true
	_deadline = 0
	connected.emit()


# --- Mensajes -------------------------------------------------------------------------

@rpc("any_peer", "unreliable_ordered", "call_remote", CHANNEL_STATE)
func _rx_snapshot(data: Array) -> void:
	if mode == Mode.SERVER:
		var to: int = _partner.get(multiplayer.get_remote_sender_id(), 0)
		if to != 0 and to in multiplayer.get_peers():  # puede haberse ido en este mismo sondeo
			_rx_snapshot.rpc_id(to, data)
		return
	if _accepted and multiplayer.get_remote_sender_id() == _remote_id:
		snapshot_received.emit(data)


@rpc("any_peer", "reliable", "call_remote", CHANNEL_EVENTS)
func _rx_event(data: Dictionary) -> void:
	if mode == Mode.SERVER:
		var to: int = _partner.get(multiplayer.get_remote_sender_id(), 0)
		if to != 0 and to in multiplayer.get_peers():  # puede haberse ido en este mismo sondeo
			_rx_event.rpc_id(to, data)
		return
	if _accepted and multiplayer.get_remote_sender_id() == _remote_id:
		event_received.emit(data)


# --- Servidor de retransmisión ----------------------------------------------------------

## Cliente → servidor: versión, nombre y sala.
@rpc("any_peer", "reliable", "call_remote", CHANNEL_EVENTS)
func _relay_hello(version: int, their_nick: String, room_code: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	if mode != Mode.SERVER or not _pending.has(from):
		return
	_pending.erase(from)
	if version != PROTOCOL_VERSION:
		_relay_reject.rpc_id(from, "version")
		_kick(from)
		return
	var code := room_code.strip_edges().to_upper().substr(0, 16)
	_nicks[from] = their_nick.strip_edges().substr(0, 16)
	var other: int = _rooms.get(code, 0)
	if other == 0:
		_rooms[code] = from
		_relay_wait.rpc_id(from)
		_log("%s (%d) espera en la sala «%s»" % [_nicks[from], from, code])
		return
	_rooms.erase(code)
	_partner[from] = other
	_partner[other] = from
	_relay_start.rpc_id(other, 0, _nicks[from])
	_relay_start.rpc_id(from, 1, _nicks[other])
	_log("sala «%s»: %s (%d) contra %s (%d) · %d partidas en curso" % [code, _nicks[other], other, _nicks[from], from,
			_partner.size() / 2])


@rpc("authority", "reliable", "call_remote", CHANNEL_EVENTS)
func _relay_wait() -> void:
	_deadline = 0
	waiting.emit()


## Servidor → cliente: ya hay rival. `my_side` 0 = anfitrión (lleva las rondas), 1 = invitado.
@rpc("authority", "reliable", "call_remote", CHANNEL_EVENTS)
func _relay_start(my_side: int, their_nick: String) -> void:
	if not relay:
		return
	side = clampi(my_side, 0, 1)
	mode = Mode.HOST if side == 0 else Mode.JOIN
	remote_nick = their_nick.substr(0, 16)
	_accepted = true
	_deadline = 0
	connected.emit()


@rpc("authority", "reliable", "call_remote", CHANNEL_EVENTS)
func _relay_reject(reason: String) -> void:
	if relay:
		_fail.call_deferred(reason)


## Servidor → cliente: el rival se ha ido.
@rpc("authority", "reliable", "call_remote", CHANNEL_EVENTS)
func _relay_left() -> void:
	if relay:
		_drop.call_deferred("left")


func _server_peer_left(id: int) -> void:
	_pending.erase(id)
	for code: String in _rooms.keys():
		if _rooms[code] == id:
			_rooms.erase(code)
	var other: int = _partner.get(id, 0)
	if other != 0:
		_partner.erase(id)
		_partner.erase(other)
		_relay_left.rpc_id(other)
		_log("%s (%d) se fue; aviso a %s (%d) · %d partidas en curso" % [_nicks.get(id, "?"), id,
				_nicks.get(other, "?"), other, _partner.size() / 2])
	_nicks.erase(id)


func _kick(id: int) -> void:
	if _peer:
		var p := _peer.get_peer(id)
		if p:
			p.peer_disconnect_later()


func _log(text: String) -> void:
	print("[%s] %s" % [Time.get_datetime_string_from_system(false, true), text])


func _on_peer_disconnected(id: int) -> void:
	if mode == Mode.SERVER:
		_server_peer_left(id)
	elif id == _remote_id:
		_drop("left")


func _drop(reason: String) -> void:
	var was := _accepted
	close()
	if was:
		disconnected.emit(reason)
	else:
		failed.emit(reason)


func _fail(reason: String) -> void:
	close()
	failed.emit(reason)

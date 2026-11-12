extends Node
## Servidor de retransmisión para desplegar en una VPS: empareja jugadores por código de sala y reenvía sus
## mensajes (ver `Net.serve()`). No carga el juego. Arranque (docs/SERVIDOR.md):
##   BeastSoulsServer.x86_64 --headless [-- --port=24700]
## La compilación «Servidor» (dedicated_server) arranca directamente en esta escena y no incluye modelos, texturas
## ni audio. Desde el proyecto: `godot --headless --path . -- --server`.

func _ready() -> void:
	var port: int = Net.DEFAULT_PORT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))
	# Sin ventana no hay sincronía vertical: sin límite, el bucle se comería un núcleo entero.
	Engine.max_fps = 120
	Engine.physics_ticks_per_second = 10
	var err := Net.serve(port)
	if err != OK:
		printerr("No se pudo abrir el puerto UDP %d (error %d)." % [port, err])
		get_tree().quit(1)
		return
	print("BeastSouls · servidor de retransmisión · puerto UDP %d · protocolo %d · hasta %d jugadores" % [
			port, Net.PROTOCOL_VERSION, Net.SERVER_MAX_CLIENTS])

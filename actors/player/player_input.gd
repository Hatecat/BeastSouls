class_name PlayerInput
extends RefCounted
## Un "fotograma de input": todo lo que un Beast necesita para simular un tick.
##
## Lo genera PlayerController (jugador local) y, en la Fase 5, llegará también por la red.
## Por eso es plano y serializable: nada de leer `Input` dentro de la simulación.

## Bits de `buttons` (pulsaciones de un solo tick).
const DODGE := 1        ## Esquivar (se emite al SOLTAR el botón tras un toque corto, como en Dark Souls).
const LIGHT := 2        ## Ataque ligero (Fase 2).
const HEAVY := 4        ## Ataque fuerte (Fase 2).
const ABILITY_1 := 8
const ABILITY_2 := 16
const ABILITY_3 := 32
const ABILITY_4 := 64
## Bits de `held` (botones mantenidos).
const SPRINT := 1
const BLOCK := 2

## Dirección de movimiento en el MUNDO (XZ), longitud 0..1. Ya viene relativa a la cámara.
var move := Vector2.ZERO
var buttons := 0
var held := 0
## Objetivo fijado (null = libre). En red se enviará como id de jugador, no como referencia.
var lock_target: Node3D = null


func pressed(bit: int) -> bool:
	return buttons & bit != 0


func is_held(bit: int) -> bool:
	return held & bit != 0


func move_3d() -> Vector3:
	return Vector3(move.x, 0.0, move.y)


## Para la red (Fase 5): movimiento cuantizado a bytes + botones.
func to_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b[0] = int(round((clampf(move.x, -1.0, 1.0) + 1.0) * 127.0))
	b[1] = int(round((clampf(move.y, -1.0, 1.0) + 1.0) * 127.0))
	b[2] = buttons & 0xFF
	b[3] = held & 0xFF
	return b


static func from_bytes(b: PackedByteArray) -> PlayerInput:
	var i := PlayerInput.new()
	i.move = Vector2(b[0] / 127.0 - 1.0, b[1] / 127.0 - 1.0)
	i.buttons = b[2]
	i.held = b[3]
	return i

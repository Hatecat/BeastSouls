class_name Roster
extends RefCounted
## Lista de personajes jugables. El orden es el del selector.

const PATHS := [
	"res://actors/characters/charizard.tres",
	"res://actors/characters/scyther.tres",
	"res://actors/characters/gengar.tres",
	"res://actors/characters/snorlax.tres",
	"res://actors/characters/beedrill.tres",
	"res://actors/characters/vaporeon.tres",
]

static var _all: Array[CharacterDef] = []


static func all() -> Array[CharacterDef]:
	if _all.is_empty():
		for p: String in PATHS:
			_all.append(load(p))
	return _all


static func find(id: StringName) -> CharacterDef:
	for c in all():
		if c.id == id:
			return c
	return all()[0]


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for c in all():
		out.append(c.id)
	return out

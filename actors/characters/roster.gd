class_name Roster
extends RefCounted
## Lista de personajes jugables. El orden es el del selector: primero los de PATHS y después cualquier otro
## CharacterDef que haya en actors/characters/ (los que crea tools/new_character.py), por orden alfabético.

const DIR := "res://actors/characters/"
const PATHS := [
	"res://actors/characters/charizard.tres",
	"res://actors/characters/scyther.tres",
	"res://actors/characters/gengar.tres",
	"res://actors/characters/snorlax.tres",
	"res://actors/characters/beedrill.tres",
	"res://actors/characters/vaporeon.tres",
	"res://actors/characters/machop.tres",
	"res://actors/characters/poliwrath.tres",
	"res://actors/characters/golem.tres",
	"res://actors/characters/mewtwo.tres",
	"res://actors/characters/ninetales.tres",
	"res://actors/characters/mrmime.tres",
]

static var _all: Array[CharacterDef] = []


static func all() -> Array[CharacterDef]:
	if _all.is_empty():
		var paths: Array[String] = []
		paths.assign(PATHS)
		var extra: Array[String] = []
		for f in ResourceLoader.list_directory(DIR):
			if f.ends_with(".tres") and DIR + f not in paths:
				extra.append(DIR + f)
		extra.sort()
		for p: String in paths + extra:
			var def := load(p) as CharacterDef
			if def and def.visual and def.moveset:
				_all.append(def)
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

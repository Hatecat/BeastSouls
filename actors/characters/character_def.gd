class_name CharacterDef
extends Resource
## Un personaje jugable: modelo, moveset, estadísticas y datos para el selector.
## Beast.apply_character() lo aplica en tiempo de ejecución.

@export var id: StringName = &""
@export var display_name := ""
## Papel en una línea ("Equilibrado", "Tanque"...).
@export var role := ""
@export_multiline var description := ""
## Color de acento en menús y HUD.
@export var color := Color(1.0, 0.55, 0.2)

@export var visual: PackedScene
@export var moveset: Moveset

@export_group("Estadísticas")
## Propiedades del Beast que se sobrescriben: {"max_health": 120.0, "jog_speed": 4.0, ...}.
@export var stats: Dictionary[StringName, Variant] = {}

@export_group("Cuerpo")
## Cápsula de colisión (la hurtbox es un poco mayor).
@export var body_radius := 0.55
@export var body_height := 2.0
## Altura del punto al que apunta la cámara al fijar objetivo.
@export var lock_height := 1.3

@export_group("Selector")
## Valoraciones 1..5 para el selector.
@export_range(1, 5) var rating_health := 3
@export_range(1, 5) var rating_speed := 3
@export_range(1, 5) var rating_power := 3
@export_range(1, 5) var rating_range := 3

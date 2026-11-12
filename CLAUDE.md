# BeastSouls

Souls-like 3D en tercera persona con versus online 1v1. Godot 4.7.2, Forward+, Jolt Physics, todo en GDScript.
Charizard (`assets/models/placeholder/`) es un modelo TEMPORAL de uso privado: no se distribuye.

## Comandos

```bash
G=~/Godot_v4.7.2-stable_linux.x86_64
$G --path .                                       # jugar (arena de pruebas)
$G -e --path .                                    # editor
$G --headless --path . --import                   # registrar clases nuevas (class_name) e importar assets
$G --headless --path . --script tools/setup_input.gd   # regenerar el InputMap por defecto
```

Probar en partida: script `extends SceneTree` fuera del proyecto pasado con `--script`, que cambia de escena y guarda
capturas con `root.get_texture().get_image().save_png(...)`.

## Estructura

- `actors/visuals/` — `CharacterVisual` (character_visual.gd): única capa que conoce el modelo. El juego usa nombres
  LÓGICOS de acción (`idle`, `walk`, `run`, `dodge`, `attack_light_1..3`, `attack_heavy_1..2`, `block`, `hit`,
  `death`, `skill_*`) y de socket (`mouth`, `head`, `hand_l/r`, `foot_l/r`, `chest`, `tail_tip`). Cada modelo es una
  escena (p. ej. `charizard_visual.tscn`) con `action_map`, `action_speed` y `sockets`. Cambiar de modelo = otra escena.
- `actors/player/` — `Beast` (beast.gd/.tscn): CharacterBody3D con la simulación (estados LOCOMOTION/DODGE/DEAD,
  estamina, esquiva con i-frames, input buffer). `simulate(PlayerInput, delta)` es la única entrada de la lógica.
  `PlayerInput`: fotograma de input serializable (move en mundo, bits `buttons` de un tick y `held`).
  `PlayerController`: lee Input + yaw de cámara → PlayerInput (Espacio: toque = esquivar al soltar, mantener = correr).
  Corre con `process_physics_priority = -10` para ir antes que el Beast. El Beast reinicia su input cada tick.
- `actors/dummy/` — `DummyBrain`: IA de práctica que rodea al jugador generando PlayerInput.
- `camera/` — `ThirdPersonCamera`: rig top_level (yaw) → Pitch → SpringArm3D (máscara solo "world") → Camera3D,
  movida en `_process` con la posición interpolada. Fijar objetivo: grupo "lockable" + `get_lock_position()`;
  cambia con gesto de ratón/stick o rueda; se suelta por distancia, muerte u oclusión > 2 s. Si la pared empuja la
  cámara hasta el personaje, lo desvanece (`CharacterVisual.set_fade`).
- `ui/` — `Hud`: barras de vida/estamina (con rastro de pérdida) y panel de depuración.
- `combat/attacks/`, `combat/abilities/` — Resources `AttackData` / `AbilityData` (Fases 2-3).
- `net/` — multijugador ENet host-autoritativo (Fase 5).
- `levels/` — `arena_test/` (escena principal: arena con pilares, rampa, muros y un rival de práctica),
  `sandbox/` (visor de modelo, ←/→ cambian de clip), `common/world_env.tres` (Environment compartido).
- `art/` — fuentes (.blend); tiene `.gdignore`, Godot no lo importa.
- `tools/` — scripts de utilidad.

## Convenciones

- Separar siempre input → estado → presentación (preparado para red desde el principio): la lógica no lee
  `Input` directamente, recibe un "frame de input".
- Capas físicas: 1 world, 2 beasts, 3 hitboxes, 4 hurtboxes. Interpolación física activada (60 Hz).
- Yaw: adelante = -Z girado `yaw` → dirección (-sin, 0, -cos); `Beast.yaw_of(dir)` hace la inversa.
- El modelo glTF mira a +Z; `CharacterVisual.model_yaw_offset = 180` lo gira para que "adelante" sea -Z.
- Controles por defecto (tools/setup_input.gd): WASD/stick izq., ratón/stick der., LMB/R1 ligero, RMB/R2 fuerte,
  Shift/L1 bloquear, Espacio/B esquivar (mantener = correr), MMB/Tab/R3 fijar objetivo, 1-4/cruceta habilidades.
- Objetivo de rendimiento: 60 fps a 1080p en una RTX 3050 (FSR2 al 80 %).

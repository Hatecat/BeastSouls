# BeastSouls

Souls-like 3D en tercera persona con versus online 1v1. Godot 4.7.2, Forward+, Jolt Physics, todo en GDScript.
Los modelos de `assets/models/placeholder/` (Charizard, Scyther, Gengar, Snorlax, Beedrill, Vaporeon, sacados de
poke-tactics) son TEMPORALES y de uso privado: no se distribuyen. Se sustituirán por personajes propios.

## Comandos

```bash
G=~/Godot_v4.7.2-stable_linux.x86_64
$G --path .                                       # jugar (menú principal)
$G --path . -- --practice --char=gengar --rival=snorlax   # directo a la arena contra la IA
$G --path . -- --host --nick=A --latency=60       # alojar (otra ventana: -- --join=127.0.0.1 --nick=B)
                                                  # --char=ID --autoready: el selector elige y se marca listo solo
python3 tools/gen_characters.py                   # regenerar kits de los personajes provisionales
python3 tools/gen_textures.py                     # regenerar texturas procedurales del coliseo (numpy + Pillow)
$G --path . -- --practice --stage=test --quality=2   # escenario de pruebas; calidad 0..3
$G -e --path .                                    # editor
$G --headless --path . --import                   # registrar clases nuevas (class_name) e importar assets
$G --headless --path . --script tools/setup_input.gd   # regenerar el InputMap por defecto
```

Probar en partida: script `extends SceneTree` fuera del proyecto pasado con `--script`, que cambia de escena y guarda
capturas con `root.get_texture().get_image().save_png(...)`. Para no depender del ratón real: poner el ratón en
`MOUSE_MODE_VISIBLE`, desactivar `PlayerController` y asignar `beast.input` tras cada `await physics_frame`. Si se
inyecta input al rival, desactivar también su `DummyBrain` (si no, lo sobrescribe). Los Beasts están congelados (`frozen`) durante la
cuenta atrás: esperar a `match_flow.phase == 2` (FIGHT). No tipar con clases que usen autoloads (MatchFlow, NetMatch)
en el script de prueba: se compilan antes de que existan y fallan. En esos scripts los autoload no son identificadores:
usar `root.get_node("Net")`. Red: lanzar dos instancias (`-- --host` / `-- --join=127.0.0.1`) con el mismo script.

## Estructura

- `actors/visuals/` — `CharacterVisual` (character_visual.gd): única capa que conoce el modelo. El juego usa nombres
  LÓGICOS de acción (`idle`, `walk`, `run`, `dodge`, `attack_light_1..3`, `attack_heavy_1..2`, `block`, `hit`,
  `death`, `skill_*`) y de socket (`mouth`, `head`, `hand_l/r`, `foot_l/r`, `chest`, `tail_tip`). Cada modelo es una
  escena (p. ej. `charizard_visual.tscn`) con `action_map`, `action_speed` y `sockets`. Cambiar de modelo = otra escena.
- `actors/player/` — `Beast` (beast.gd/.tscn): CharacterBody3D con la simulación (estados LOCOMOTION, BLOCK, DODGE,
  ATTACK, ABILITY, STAGGER, DEAD; estamina, postura, Calor, recargas, mejoras, quemadura, esquiva con i-frames,
  input buffer, hitstop). `simulate(PlayerInput, delta)` es la única entrada de la lógica. Todo daño pasa por
  `deal_hit()` → `receive_hit()` (en red: solo el host). Consultas: `beasts_in_sphere()`, `beasts_in_cone()`.
  `PlayerInput`: fotograma de input serializable (move en mundo, bits `buttons` de un tick y `held`).
  `PlayerController`: lee Input + yaw de cámara → PlayerInput (Espacio: toque = esquivar al soltar, mantener = correr).
  Corre con `process_physics_priority = -10` para ir antes que el Beast. El Beast reinicia su input cada tick.
- `actors/characters/` — `CharacterDef` (.tres por personaje: escena visual, moveset, `stats` que sobrescriben
  exports del Beast, tamaño de cápsula, altura de fijado, valoraciones del selector) y `Roster` (lista ordenada).
  `Beast.apply_character(def)` cambia todo en tiempo de ejecución (restaura las estadísticas del anterior). Los kits
  provisionales los genera `tools/gen_characters.py` (ataques = plantillas de Charizard escaladas; habilidades
  con las 4 clases genéricas; ranuras: 1 distancia, 2 cerca, 3 área, 4 mejora → lo que espera `DummyBrain`).
  Los efectos (`Fx`) toman el color de la habilidad (`AbilityData.color`).
- `game/graphics.gd` — autoload `Graphics`: calidad Bajo/Medio/Alto/Ultra (user://settings.cfg, menú principal, F3,
  `--quality=N`). Ajusta escala FSR2, SDFGI, SSIL, SSAO, niebla volumétrica y sombras; se aplica sola a cada
  WorldEnvironment que entra en el árbol y a los grupos "brazier_lights" (sombras de luces puntuales) y
  "optional_fx" (polvo). Medido en la RTX 3050 a 1080p en combate: Bajo ~240, Medio ~145, Alto ~88, Ultra ~54 fps.
- `game/` — `Session` (autoload: personajes elegidos y estado del rival en el lobby; escucha la red siempre para
  no perder eventos entre escenas) y `MatchFlow` (al mejor de 3: cuenta atrás con `Beast.frozen`, K.O., marcador,
  panel de fin, revancha, volver al selector). Online manda el anfitrión (eventos "round", "round_over"); cada
  máquina solo coloca/revive a SU Beast.
- `actors/dummy/` — `DummyBrain`: IA de práctica (PASSIVE / STRAFE / AGGRESSIVE / GUARD) que genera PlayerInput.
- `camera/` — `ThirdPersonCamera`: rig top_level (yaw) → Pitch → SpringArm3D (máscara solo "world") → Camera3D,
  movida en `_process` con la posición interpolada. Fijar objetivo: grupo "lockable" + `get_lock_position()`;
  cambia con gesto de ratón/stick o rueda; se suelta por distancia, muerte u oclusión > 2 s. Si la pared empuja la
  cámara hasta el personaje, o si este tapa al objetivo fijado, lo desvanece (`CharacterVisual.set_fade`).
  Al fijar, la cámara sube y se desplaza al hombro derecho. `add_shake()` para vibración.
- `ui/` — `Hud`: barras de vida/estamina (con rastro de pérdida) y panel de depuración.
- `combat/` — `AttackData` (tiempos activo/combo/cancelación, daño, postura, hitbox local que barre de start a
  end, embestida, seguimiento, hiper armadura, carga) y `Moveset` (combo ligero, combo fuerte, ataque corriendo).
  Los de Charizard están en `combat/attacks/charizard/*.tres` (se editan en el inspector; F1 en la arena muestra
  las hitboxes). Hitboxes = consulta de esfera en el tick contra las `Hurtbox` (Area3D, capa 4): deterministas,
  no dependen de los huesos. `HitFx`: chispas y destello (solo presentación).
- `combat/abilities/` — `AbilityData` (base: coste de Calor, recarga, tiempos, seguimiento) con `start/tick/finish`;
  el estado de cada lanzamiento va en el diccionario `cast`, NUNCA en el Resource (se comparte). Subclases:
  `ChannelAbility` (cono por ticks), `ProjectileAbility` (→ `combat/projectile.gd`), `AreaAbility`, `BuffAbility`.
  Kit de Charizard en `combat/abilities/charizard/` (ranuras 1-4 en `moveset.tres`: bola de fuego, lanzallamas,
  rugido, danza dragón). AttackData tiene además `unblockable`, `burn_time` y `heat_gain`.
- `combat/fx.gd` — constructores de efectos (chorro de fuego, ascuas, bola, onda, explosión). REGLA: cachear
  materiales/mallas con `Fx._cached()`; crear recursos nuevos por efecto costaba ~40 ms por fotograma en partida.
  `Fx.prewarm()` (en el `_ready` del nivel) compila los shaders al cargar.
- `net/` — versus online 1v1 por ENet (UDP, puerto 24700). NO es host-autoritativo: cada jugador simula su
  propio Beast sin retardo y manda instantáneas (`Beast.net_snapshot()`, 30 Hz, canal no fiable ordenado). El rival
  es un proxy (`Beast.is_remote`, no simula) que `NetProxy` interpola 100 ms en el pasado y que reproduce sus
  ataques/habilidades contra el Beast LOCAL: la VÍCTIMA decide los golpes y los confirma al atacante con un evento
  fiable (`NetMatch`: "hit", "died", marcador). `deal_hit()` ignora víctimas remotas. `Net` (autoload): host/join,
  saludo con versión de protocolo, simulación de latencia/jitter/pérdida en el emisor (`--latency= --jitter=
  --loss=`). Al cambiar de modelo, el visual viejo se esconde y se libera 0.5 s después (liberarlo en el mismo fotograma deja
  materiales colgando en el renderizador). Las señales de desconexión de `multiplayer` se conectan DIFERIDAS (cerrar el peer dentro de su poll
  cuelga Godot). `NetMatch.setup()` va antes de `add_child`.
- `ui/main_menu` — escena inicial: práctica, alojar, unirse; acepta argumentos tras `--` (ver main_menu.gd).
  Después va a `ui/character_select` (vista previa 3D en SubViewport; práctica: tú y luego la IA; online: cada uno
  elige, "Listo", y el anfitrión arranca).
- `levels/` — `arena_test/arena_test.tscn` es la escena de COMBATE (jugadores, cámara, HUD, IA; F1 hitboxes,
  F2 modo de la IA, F3 calidad gráfica) y carga como hijo el escenario de `Session.stage` (`Session.STAGES`):
  `colosseum/` (por defecto) o `arena_test/test_stage.tscn` (cajas grises). Añade también la viñeta/grano
  (`ui/post_fx.gdshader`, CanvasLayer 0, por debajo del HUD).
  `colosseum/colosseum.gd` (@tool) construye TODO por código al cargar: entorno (cielo de atardecer, SDFGI,
  niebla volumétrica, AgX), suelo, muro con pilastras y portones, columnata y gradas con un tramo derrumbado hacia
  el sol, columnas rotas, escombros (MultiMesh), braseros (`FlickerLight`, `Fx.fire`), estandartes, polvo y
  cordilleras. Shaders en `colosseum/shaders/`: `floor` (losas en XZ de mundo + arena + emblema), `stone`
  (triplanar de mundo, sin UVs, suciedad abajo y polvo encima), `banner` (tela con viento). Texturas en
  `colosseum/textures/` (generadas; ORM empaquetado: R rugosidad, G altura, B oclusión).
  `sandbox/` (visor de modelo, ←/→ cambian de clip), `common/world_env.tres` (Environment del selector/sandbox).
- `art/` — fuentes (.blend); tiene `.gdignore`, Godot no lo importa.
- `tools/` — scripts de utilidad.

## Convenciones

- Separar siempre input → estado → presentación (preparado para red desde el principio): la lógica no lee
  `Input` directamente, recibe un "frame de input".
- Capas físicas: 1 world, 2 beasts, 3 hitboxes (reservada), 4 hurtboxes. Interpolación física activada (60 Hz).
- Yaw: adelante = -Z girado `yaw` → dirección (-sin, 0, -cos); `Beast.yaw_of(dir)` hace la inversa.
- El modelo glTF mira a +Z; `CharacterVisual.model_yaw_offset = 180` lo gira para que "adelante" sea -Z.
- Controles por defecto (tools/setup_input.gd): WASD/stick izq., ratón/stick der., LMB/R1 ligero, RMB/R2 fuerte,
  Shift/L1 bloquear, Espacio/B esquivar (mantener = correr), MMB/Tab/R3 fijar objetivo, 1-4/cruceta habilidades.
- Objetivo de rendimiento: 60 fps a 1080p en una RTX 3050 (FSR2 al 80 %).

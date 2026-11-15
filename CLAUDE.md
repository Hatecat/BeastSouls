# BeastSouls

Souls-like 3D en tercera persona con versus online 1v1. Godot 4.7.2, Forward+, Jolt Physics, todo en GDScript.
Los modelos de `assets/models/placeholder/` (Charizard, Scyther, Gengar, Snorlax, Beedrill, Vaporeon, Machop,
Poliwrath, Golem, Mewtwo, Ninetales, Mr. Mime, sacados de poke-tactics; Feraligatr, Bayleef, Forretress, Aipom,
Hitmontop, Houndoom, Raikou, Blaziken, Lucario, Zoroark, de ~/Documentos/modelos-desc/regular/<nº pokédex>.glb) son TEMPORALES y de uso privado: no se distribuyen. Se sustituirán por personajes propios.

## Comandos

```bash
G=~/Godot_v4.7.2-stable_linux.x86_64
$G --path .                                       # jugar (menú principal)
$G --path . -- --practice --char=gengar --rival=snorlax   # directo a la arena contra la IA
$G --path . -- --host --nick=A --latency=60       # alojar (otra ventana: -- --join=127.0.0.1 --nick=B)
                                                  # --char=ID --autoready: el selector elige y se marca listo solo
python3 tools/gen_characters.py                   # regenerar kits de los personajes provisionales
python3 tools/new_character.py --id=ID --model=X.glb   # personaje nuevo desde un modelo (docs/NUEVO_PERSONAJE.md)
python3 tools/animate_models.py lucario:448 forretress:205:generic   # animar un rip sin clips (Blender + poke-tactics)
python3 tools/gen_textures.py                     # regenerar texturas procedurales del coliseo (numpy + Pillow)
python3 tools/gen_character_textures.py            # regenerar el microdetalle de piel de los personajes
python3 tools/gen_music.py                        # regenerar música y ambiente (numpy + ffmpeg/libvorbis)
$G --path . -- --practice --stage=test --quality=2   # escenario de pruebas; calidad 0..3
$G -e --path .                                    # editor
$G --headless --path . --import                   # registrar clases nuevas (class_name) e importar assets
$G --headless --path . --script tools/setup_input.gd   # regenerar el InputMap por defecto
$G --headless --path . -- --server                # servidor de retransmisión (clientes: -- --relay=IP --room=X)
$G --headless --path . --export-release "Servidor" builds/server/BeastSoulsServer.x86_64   # también "Linux", "Windows"
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
  Encima de los clips hay una capa procedural (solo presentación, igual para el Beast local y el proxy remoto):
  - `_process`: inclinación del cuerpo con la aceleración y los giros y aplastar/estirar (salto, aterrizaje,
    golpes), sobre un nodo `Pivot` entre el visual y el modelo; se calcula del propio movimiento del nodo.
  - `PoseModifier` (SkeletonModifier3D): la cabeza mira al rival fijado (`look_at_point`) y el torso se dobla al
    recibir un golpe (`flinch`); rota en el espacio del visual, no depende de los ejes de los huesos.
  - `SpringBoneSimulator3D` en las cadenas cuyo nombre contiene `spring_patterns` (colas, antenas, orejas).
    OJO: el simulador parte del reposo del hueso y DESCARTA lo que anima el clip en esos huesos; por eso su
    `influence` baja a 0 durante las acciones `attack*` / `skill*` (si no, los coletazos no mueven la cola). Un
    personaje cuya cola va posada o animada siempre (Aipom) la saca de `spring_patterns`.
  - `face_surface`: superficie para mallas llamadas "Eye" que en realidad son la cara entera (Aipom).
  - `bone_scale` ({"Tail": 0.55}): encoge cadenas enteras desde su primer hueso (lo aplica `PoseModifier`); las
    colas de Ninetales tapaban la cámara.
  - Ataques: `drive(action, clip_time, rate)` clava el clip al `state_time` de la simulación.
    `_analyze_attacks()` busca en cada clip de ataque el instante de máximo avance (impacto) y
    `Beast._attack_clip_time()` lo hace caer en la ventana activa (anticipación que acelera, golpe seco,
    recuperación que frena). `AttackTrail`: estela que barre el mismo arco que la hitbox (`Beast._update_trail`).
  - Materiales: `character.gdshader` + `surface` (skin/scales/chitin/ghost/fur/wet → `SURFACES`): microdetalle
    repetido de `assets/textures/characters/` (RG normal, B altura; `tools/gen_character_textures.py`), barniz,
    contorno, luz que atraviesa y brillo de borde. Ojos y piezas con recorte conservan su material.
  Probado y descartado: subdividir las mallas en Blender (saca costuras y no mejora la silueta).
- `actors/player/` — `Beast` (beast.gd/.tscn): CharacterBody3D con la simulación (estados LOCOMOTION, BLOCK, DODGE,
  ATTACK, ABILITY, STAGGER, DEAD; estamina, postura, PP (`pp`: empiezan llenos y se regeneran solos, `pp_regen` por segundo; no se ganan golpeando), recargas, mejoras, quemadura, esquiva con i-frames,
  input buffer, hitstop). `simulate(PlayerInput, delta)` es la única entrada de la lógica.
  Golpes recibidos (`receive_hit`): todo golpe empuja (`_knock`: `AttackData.knockback` × `knockback_distance`
  metros en `knockback_time`; la mitad al bloquear). Si rompe la postura → STAGGER (`stagger_time`). Si no la
  rompe: corta la acción en curso cuando es interrumpible (`AttackData.interruptible` y sin `hyper_armor`;
  `AbilityData.interruptible`, falso en las de área y en las de Snorlax) con un STAGGER corto (`flinch_time`); si
  no, el Beast sigue a lo suyo pero se desliza (`_push`). Todo daño pasa por
  `deal_hit()` → `receive_hit()` (en red: solo el host). Consultas: `beasts_in_sphere()`, `beasts_in_cone()`.
  `PlayerInput`: fotograma de input serializable (move en mundo, bits `buttons` de un tick y `held`).
  `PlayerController`: lee Input + yaw de cámara → PlayerInput (Espacio: toque = esquivar al soltar, mantener = correr).
  Corre con `process_physics_priority = -10` para ir antes que el Beast. El Beast reinicia su input cada tick.
- `actors/characters/` — `CharacterDef` (.tres por personaje: escena visual, moveset, `stats` que sobrescriben
  exports del Beast, tamaño de cápsula, altura de fijado, valoraciones del selector) y `Roster` (lista ordenada).
  `Beast.apply_character(def)` cambia todo en tiempo de ejecución (restaura las estadísticas del anterior). Los kits
  provisionales los genera `tools/gen_characters.py` (ataques = plantillas de Charizard escaladas; habilidades
  con las clases genéricas). Cada personaje tiene un CATÁLOGO de 10 habilidades (`Moveset.abilities`: las 4
  primeras son la selección por defecto; las 6 extra salen de `EXTRA_KITS` en el generador, también las de
  Charizard) y se equipan 4 antes del combate: `Beast.abilities` (ranuras 1-4) lo rellena
  `apply_character(def, loadout)` con índices del catálogo (`Moveset.valid_loadout` corrige los inválidos).
  `Session.my_loadout` / `rival_loadout`; la última selección de cada personaje se guarda en
  user://settings.cfg (sección "loadouts"). Online viaja en los eventos "pick" y "start".
  Los efectos (`Fx`) toman el color de la habilidad (`AbilityData.color`).
  Segunda tanda (Machop, Poliwrath, Golem, Mewtwo, Ninetales, Mr. Mime): sus 10 habilidades están todas en
  `EXTRA_KITS` y sus visuales usan acciones comunes (`skill_shot/roar/boost/cast/punch/kick/body/claw/tail/mind`),
  que también usan los remates de combo para no repetir el clip de la cadena. Mewtwo trae otro juego de clips
  (`pm0150_…`, largos): guardia = `rangeattack02_start` con `block_pose` 0.9 en sus `stats`.
  Tercera tanda (Feraligatr … Zoroark): los rips de modelos-desc vienen SIN animaciones (salvo Feraligatr, que
  trae los clips `pm0160_…`) y tres sin esqueleto (Aipom, Hitmontop, Forretress). `tools/animate_models.py` los
  pasa por las herramientas de Blender de poke-tactics (setup_animations → animate_pokemon/animate_generic →
  animate_status → export) en una carpeta temporal y deja el .glb con clips `fight_b_*`/`fight_d_*`;
  `tools/anim_extras.py` lleva lo propio de BeastSouls que se inyecta en la copia temporal de esos
  animadores: poses fijas (la cola curvada de Aipom; Zoroark encorvado con la melena por la espalda), clips nuevos o
  rehechos (coletazo de Aipom; giros de Forretress `spin_ram/_b`, `spin_heavy`, `spin_multi`, `spin_drop`;
  Hitmontop de cabeza girando como peonza: `top_walk`, `top_kick`, `top_spin`, `top_dash`). Un clip nuevo no
  puede llevar "hit" ni "ko" en el nombre (animate_status lo toma por variante y no crea el clip base) y el soldado de mallas que vienen como
  triángulos sueltos (se veían facetadas y con costuras). `tools/rig_templates_extra.py` lleva los esqueletos de plantilla (la cabeza de Hitmontop va fijada entera a
  `Head` con `_props`). Forretress tiene un solo hueso: todos sus ataques usan `fight_b`. Sus kits se escriben
  con los preajustes `_MULTI`, `_BIG`, `_MELEE`, `_QUICK` y `_stun()` del generador.
  `Roster` carga los de `PATHS` y después cualquier otro `.tres` de la carpeta. `tools/new_character.py` crea un
  personaje desde un .glb: lo importa, lee clips y huesos (`tools/inspect_model.gd`), adivina `action_map` y
  sockets, y genera visual, kit por arquetipo (acciones `skill_1..4`) y CharacterDef. Guía: docs/NUEVO_PERSONAJE.md.
- `game/graphics.gd` — autoload `Graphics`: calidad Bajo/Medio/Alto/Ultra (user://settings.cfg, menú principal, F3,
  `--quality=N`). Ajusta escala FSR2, SDFGI, SSIL, SSAO, niebla volumétrica y sombras; se aplica sola a cada
  WorldEnvironment que entra en el árbol y a los grupos "brazier_lights" (sombras de luces puntuales) y
  "optional_fx" (polvo). Medido en la RTX 3050 a 1080p en combate: Bajo ~240, Medio ~145, Alto ~88, Ultra ~54 fps.
- `game/settings.gd` — autoload `Settings`: volúmenes (buses Music/SFX/Ambience/UI), sensibilidad (multiplica la
  base de la cámara), invertir Y, vibración, pantalla completa, VSync, panel de depuración, ayuda y teclas
  reasignadas (solo el primer evento de teclado/ratón de cada acción; si choca con otra, se intercambian). Guarda
  en user://settings.cfg (secciones "options" y "bindings"); señal `changed`. Aplica también el tema (`UiTheme`).
- `game/audio.gd` — autoload `Audio`: efectos de `assets/audio/sfx/` agrupados por nombre base (`hit_light_0..4` →
  `play("hit_light", pos)` elige variante), reservas de reproductores 2D/3D, `attach_loop` (bucle pegado a un nodo),
  `music(name)` con fundido cruzado, `stinger`, `ambience`, y clic/hover automático en todos los botones.
  Las clases de simulación (Beast, habilidades, proyectil, coliseo) usan `Sfx` (game/sfx.gd, estático, busca el
  autoload en tiempo de ejecución) para no depender del autoload al compilar (los scripts de prueba tipan Beast).
  Audio en `assets/audio/` (CREDITS.txt: efectos Kenney CC0; música y ambiente generados por tools/gen_music.py,
  los .import de los bucles llevan loop=true).
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
- `ui/` — `Hud`: barras de vida/estamina (con rastro de pérdida), daño acumulado sobre la barra del objetivo
  (estilo Souls, se borra tras 2.5 s sin golpear), ayuda y panel de depuración (según Settings).
  `ActionDiamond` (action_diamond.gd): rombo abajo a la derecha con lo que hace cada botón ahora mismo. Mando: X / Y
  habilidades (con LT pasan a la 3 y la 4; la otra pareja va en un círculo pequeño), B esquivar, A saltar. Teclado:
  las 4 habilidades con su tecla. Recarga en sector, coste de PP, apagado si no se puede usar; encima, el
  resto de acciones en dos líneas.
  `UiTheme` (ui_theme.gd): tema común (fuente serif del sistema, piedra oscura y ámbar) fusionado con el tema por
  defecto, así lo heredan también los controles de los CanvasLayer. Ayudas de estilo: `menu_button` (lista
  con franja ámbar), `primary_button`, `ornament` (filete con rombo), `caption`, `spaced_font`, `backdrop`.
  `FocusCursor` (focus_cursor.gd): marco que late + flecha sobre el control enfocado; lo crea `Settings` una vez
  en un CanvasLayer 100 y vale para todos los menús. Solo se ve navegando con mando/teclado. Un contenedor con el
  meta `focus_frame` (filas de Opciones) se enmarca entero. En las tarjetas del selector, «elegida» usa el color
  propio y el foco un marco claro: no reutilizar el color de selección para el foco.
  `HintBar` (hint_bar.gd): leyenda de botones al pie (A/B o Enter/Esc según el dispositivo). `OptionsMenu` (pestañas Gráficos/Sonido/
  Controles/Interfaz, se aplica y guarda al momento; se usa en el menú y en la pausa). `PauseMenu` (Esc/Start):
  en práctica pausa el árbol (los temporizadores de MatchFlow son pausables); online no pausa, solo pone
  `PlayerController.blocked` (input vacío). Vibración del mando en `PlayerController._rumble`.
  `ControlsHelp` (controls_help.gd): textos de controles para teclado y mando (ayuda del HUD, pestaña «Guía de
  controles» de Opciones, accesible desde la pausa). `Settings.using_pad` / `device_changed`: la ayuda y las
  etiquetas de las ranuras cambian según el último dispositivo usado. Settings añade el botón A a `ui_accept` y B a
  `ui_cancel` (Godot no los trae): todos los menús se manejan con mando (foco inicial con `grab_focus`).
- `combat/` — `AttackData` (tiempos activo/combo/cancelación, daño, postura, hitbox local que barre de start a
  end, embestida, seguimiento, hiper armadura, carga) y `Moveset` (combo ligero, combo fuerte, ataque corriendo).
  Combos mixtos: `Moveset.combos` ("LH", "LLH", "LLLH", "HL" → AttackData; L ligero, H fuerte). `Beast._combo_seq`
  guarda los botones de la cadena; si la secuencia está en `combos` sale ese ataque y la cadena vuelve a empezar.
  Los genera `make_combo` en `tools/gen_characters.py` (`combo_<sec>.tres`, también los de Charizard) y el
  selector los lista. Van al final de `all_attacks()` (índices de red).
  Los de Charizard están en `combat/attacks/charizard/*.tres` (se editan en el inspector; F1 en la arena muestra
  las hitboxes). Hitboxes = consulta de esfera en el tick contra las `Hurtbox` (Area3D, capa 4): deterministas,
  no dependen de los huesos. `HitFx`: chispas y destello (solo presentación).
- `combat/abilities/` — `AbilityData` (base: coste de PP `pp_cost`, recarga `cooldown` por ranura, tiempos, seguimiento) con `start/tick/finish`;
  el estado de cada lanzamiento va en el diccionario `cast`, NUNCA en el Resource (se comparte). Subclases:
  `ChannelAbility` (cono por ticks), `ProjectileAbility` (→ `combat/projectile.gd`), `AreaAbility`, `BuffAbility`,
  `DashAbility` (embestida: fija la velocidad del lanzador y golpea una vez). Cada una define `kind()`,
  `summary()` (texto del selector) y `reach()`; `DummyBrain` decide por `kind()`, no por ranura.
  Kit de Charizard en `combat/abilities/charizard/` (ranuras 1-4 en `moveset.tres`: bola de fuego, lanzallamas,
  rugido, danza dragón). AttackData tiene además `unblockable` y `burn_time`.
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
  Servidor de retransmisión (docs/SERVIDOR.md, `deploy/`): `Net.serve()` empareja por código de sala y reenvía
  instantáneas y eventos; los clientes entran con `Net.join_server(dirección, sala)` y el servidor les asigna
  papel (`mode` HOST el primero, JOIN el segundo; `Net.relay = true`), así el resto del juego no distingue. La
  compilación «Servidor» (dedicated_server, sin modelos ni audio) arranca en `net/relay_server.tscn`; `Session`
  no hace nada ahí. `builds/` lleva `.gdignore` (sin él la importación se cuelga con los ejecutables).
- `ui/main_menu` — escena inicial: coliseo en 3D de fondo (cámara orbitando, personaje al azar), práctica, jugar
  online (subpanel alojar/unirse), opciones, salir; acepta argumentos tras `--` solo la primera vez (ver main_menu.gd).
  Después va a `ui/character_select` (vista previa 3D en SubViewport; práctica: tú y luego la IA; online: cada uno
  elige, "Listo", y el anfitrión arranca). Ahí se eligen también las 4 habilidades (rejilla de 10 botones; el
  orden en que se marcan es la ranura; no deja continuar con menos de 4).
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
- Controles por defecto (tools/setup_input.gd). Teclado: WASD, ratón, LMB ligero, RMB fuerte, Shift bloquear,
  Espacio esquivar (mantener = correr), F saltar, MMB/Tab fijar, 1-4 habilidades, Esc pausa. Mando: stick izq.
  mover, L3 alterna correr (se corta al soltar el stick), B esquivar (al pulsar), A saltar, RB ligero, RT fuerte,
  LB bloquear, R3 fijar, X / Y habilidades 1 y 2, LT mantenido + X / Y habilidades 3 y 4 (el HUD resalta la barra
  secundaria; `PlayerController.secondary_held()`), la cruceta sigue lanzando 1-4, Start pausa. Salto:
  `PlayerInput.JUMP`, `Beast.jump_velocity`/`jump_cost`; en el aire solo hay control de dirección y lo pulsado
  queda en el buffer para el aterrizaje (los modelos no tienen clip de salto: pose fija de `run`).
- Objetivo de rendimiento: 60 fps a 1080p en una RTX 3050 (FSR2 al 80 %).

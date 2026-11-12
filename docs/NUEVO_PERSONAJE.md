# Añadir un personaje propio

## 1. Qué necesita el modelo

Un `.glb` (glTF binario) con **malla, esqueleto y animaciones dentro del mismo archivo**.

- **Orientación y escala:** mirando a +Z (lo normal al exportar de Blender con "+Y Up"). La altura da igual:
  se ajusta con `--height`.
- **Clips.** El juego funciona con nombres lógicos; la herramienta los empareja por el nombre del clip:

  | Acción | Para qué | Palabras que reconoce |
  |---|---|---|
  | `idle` | Quieto (bucle) | idle, stand, wait |
  | `walk` | Andar (bucle) | walk, jog |
  | `run` | Correr (bucle) | run, sprint |
  | `dodge` | Esquiva (~0,5 s) | dodge, roll, evade, dash |
  | `block` | Guardia (se congela en una pose) | block, guard, defend |
  | `hit` | Recibir golpe | hit, hurt, damage, stagger |
  | `death` | Muerte | death, die, ko |
  | `jump` | Salto (opcional) | jump, leap |
  | ataques (hasta 6) | 3 ligeros, 2 fuertes, 1 en carrera | attack, slash, punch, kick, bite, claw… |
  | habilidades (hasta 4) | 1 distancia, 2 cerca, 3 área, 4 mejora | skill, cast, spell, roar, breath… |

  Lo que falte se sustituye por otro clip (y se avisa), así que se puede empezar con pocos.
- **Ataques:** que el golpe llegue claramente **hacia delante**. El juego busca solo el instante de máximo
  avance de cada clip y lo hace coincidir con el momento en que el ataque pega; la anticipación y la
  recuperación se estiran alrededor.
- **Huesos** con nombres reconocibles para los puntos de anclaje: cabeza (`head`), boca (`jaw`/`mouth`), pecho
  (`spine`/`chest`), manos y pies con lado (`LHand`, `hand_r`, `LeftFoot`…), cola (`tail…`).
  Las cadenas cuyo nombre contenga `Tail`, `Feeler`, `Ear` o `Tongue` reciben física de muelle automáticamente
  (se cambia en `spring_patterns` del visual).
- **Materiales:** textura de color en el material base. El relieve fino lo pone el juego según `--surface`.
  Los materiales con "eye"/"iris" en el nombre se dejan brillantes, como ojos.

## 2. Crear el personaje

```bash
python3 tools/new_character.py --id=lobo --name="Lobo" --model=/ruta/lobo.glb \
    --archetype=fast --surface=fur --height=1.8 --color=0.6,0.7,1
```

- `--archetype`: `balanced`, `fast` (frágil y rápido), `tank` (lento, mucha vida y armadura), `ranged`.
- `--surface`: `skin`, `scales`, `chitin`, `ghost`, `fur`, `wet`.
- `--force` para regenerar uno que ya existe (pisa el kit y el visual).

Al terminar lista qué clip ha asignado a cada acción y qué ha tenido que sustituir. El personaje aparece
solo en el selector.

## 3. Ajustarlo

Probar: `godot --path . -- --practice --char=lobo` (F1 muestra las hitboxes, F2 cambia la IA).

| Qué | Dónde |
|---|---|
| Clip de cada acción, velocidad, sockets, altura, superficie, muelles | `actors/visuals/<id>_visual.tscn` |
| Tiempos, daño y hitbox de cada ataque | `combat/attacks/<id>/*.tres` |
| Habilidades (coste, recarga, daño, alcance, color) | `combat/abilities/<id>/*.tres` |
| Vida, velocidad, postura, esquiva, tamaño del cuerpo, texto del selector | `actors/characters/<id>.tres` |

Todo se edita en el inspector de Godot. Orden en el selector: los de `Roster.PATHS` primero y después el
resto por orden alfabético; para fijar la posición de uno nuevo, añádelo a `PATHS` (`actors/characters/roster.gd`).

Para una habilidad con comportamiento propio, crea una subclase de `AbilityData`
(`combat/abilities/`) con `start/tick/finish`; el estado de cada lanzamiento va en el diccionario `cast`.

## 4. Retirar los provisionales

Cuando haya personajes propios: borrar su `.tres` de `actors/characters/` y quitarlo de `Roster.PATHS`,
y cambiar los valores por defecto de `Session.my_character` / `rival_character`.

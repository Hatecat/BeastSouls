"""Ajustes propios de BeastSouls sobre los animadores de poke-tactics. `tools/animate_models.py` los inyecta
en la copia temporal de las herramientas (poke-tactics no se toca):

- POKEMON_TWEAKS: entradas extra para el dict TWEAKS de animate_pokemon.py (pose fija de huesos, brazos...).
- POKEMON_ACTIONS: código que se ejecuta tras definir ACTIONS en animate_pokemon.py (clips nuevos o rehechos).
- GENERIC_ACTIONS: lo mismo para animate_generic.py (cuerpos sin patas).
- FIX_MESH: script de Blender que suelda y suaviza las mallas que vienen como triángulos sueltos (cada cara con
  sus propios vértices y normales: se ven facetadas y con costuras).
"""

POKEMON_TWEAKS = '''
    # Zoroark: encorvado y al acecho, con las garras colgando por delante, las rodillas flexionadas y la melena
    # cayendo por la espalda (en el rip sale tiesa hacia atrás y con los brazos en cruz).
    "zoroark": {"arm_drop": 66, "arm_fwd": 26, "elbow": 38, "crouch": 15, "legs_in": 7, "idle_arms": 1.8,
                "hold": {"Spine1": [("PITCH", 15)], "Spine2": [("PITCH", 9)], "Neck": [("PITCH", -9)],
                         "Head": [("PITCH", -11)], "Jaw": [("PITCH", -9)],
                         # La punta de la melena no baja de los pies: el juego apoya en el suelo el punto más bajo.
                         "Hair01": [("PITCH", -26)], "Hair02": [("PITCH", -12)], "Hair03": [("PITCH", -8)],
                         "Hair07": [("PITCH", 8)], "Hair09": [("PITCH", 12)], "Hair11": [("PITCH", 14)],
                         "Hair13": [("PITCH", 10)]}},
    # Aipom: la cola sube por detrás de la espalda y se curva hacia delante por encima de la cabeza.
    "aipom": {"arm_drop": 55, "hold": {"Tail1": [("PITCH", 58)], "Tail2": [("PITCH", 24)], "Tail3": [("PITCH", 14)],
                                       "Tail4": [("PITCH", 16)], "Tail5": [("PITCH", 20)], "Tail6": [("PITCH", 22)]}},
'''

POKEMON_ACTIONS = '''
if Path(bpy.data.filepath).stem == "hitmontop":
    # Hitmontop pelea de cabeza, girando como una peonza: se da la vuelta sobre la cadera y se sube lo justo
    # para apoyar la punta de la cabeza en el suelo.
    _zs = [co.dot(UP) for _g, co in _mesh_verts()]
    # (El 6 % de menos: en reposo el juego lo apoya algo más bajo que en la pose de montaje y quedaba flotando.)
    _TOP_LIFT = (min(_zs) + max(_zs) - 2 * _pos("Hips").dot(UP) - 0.06 * (max(_zs) - min(_zs))) / SCALE

    def _top(yaw, tilt=0.0, spread=72, lift=0.0, fwd=0.0, arms_up=30, knee=10):
        """De cabeza, girado `yaw` grados sobre la vertical; tilt: inclinación hacia delante; spread: apertura
        de las piernas (90 = en horizontal, como aspas)."""
        p = pose(arms(up=arms_up, bend=10), root=(0, -fwd, _TOP_LIFT + lift))
        p["Hips"] = [(PITCH, tilt), (YAW, yaw), (ROLL, 180)]
        for side, k in (("L", 1), ("R", -1)):
            p[side + "Thigh"] = [(ROLL, -k * SIDE * spread)]
            p[side + "Leg"] = [(PITCH, knee)]
            p[side + "Foot"] = [(PITCH, -20)]
        return p

    def _top_spin(first, last, turns, start=0.0, **kw):
        n = last - first
        return [(first + i, _top(start + 360.0 * turns * i / n,
                                 **{k: (v(i / n) if callable(v) else v) for k, v in kw.items()})) for i in range(n + 1)]

    _bump = lambda peak, at=0.5, w=0.35: (lambda k: peak * max(0.0, 1 - abs(k - at) / w))
    # Desplazarse: gira sin parar, algo inclinado hacia delante (dos vueltas por ciclo: enlaza sin salto).
    ACTIONS["top_walk"] = lambda: _top_spin(1, 25, 2, tilt=9, spread=62)
    # Patada giratoria: una vuelta y media abriendo las piernas; a mitad se vuelca hacia delante y barre.
    ACTIONS["top_kick"] = lambda: [
        (1, BASE()),
        *_top_spin(5, 20, 2, tilt=_bump(26, 0.55), spread=lambda k: 55 + 35 * min(1.0, k * 2), fwd=_bump(0.02, 0.55)),
        (28, BASE()),
    ]
    # Peonza: tres vueltas rápidas en el sitio con las piernas en horizontal.
    ACTIONS["top_spin"] = lambda: [
        (1, BASE()),
        *_top_spin(5, 21, 3, spread=88, tilt=_bump(10, 0.5), lift=_bump(0.01, 0.5)),
        (28, BASE()),
    ]
    # Embestida: se lanza girando muy volcado hacia delante.
    ACTIONS["top_dash"] = lambda: [
        (1, BASE()),
        *_top_spin(5, 21, 3, tilt=lambda k: 12 + 22 * max(0.0, 1 - abs(k - 0.5) / 0.4), spread=70,
                   fwd=_bump(0.035, 0.5, 0.45)),
        (28, BASE()),
    ]

if Path(bpy.data.filepath).stem == "aipom":
    def _aipom_idle(t):
        p = idle_pose(t)
        p.update(tail_wave(t, amp=34, pitch_amp=16, step=0.55))  # cola suelta: se mece mucho más
        return p

    def _aipom_walk(t):
        p = walk_pose(t)
        p.update(tail_wave(t, amp=30, pitch_amp=20, step=0.6))
        return p

    ACTIONS["idle"] = lambda: cycle(_aipom_idle, 24)
    ACTIONS["walk"] = lambda: cycle(_aipom_walk, 24)
    def _whip(yaw1, yaw_rest, pitch1, pitch_rest=0):
        """Cola estirada (deshace la curva fija de TWEAKS["hold"]) y girada desde la base: yaw1/pitch1 en el
        primer hueso, yaw_rest/pitch_rest en cada uno de los demás (la enrosca)."""
        d = {}
        for i, n in enumerate(TAIL):
            undo = [(ax, -deg) for ax, deg in reversed(BASE_ROTS.get(n, []))]
            d[n] = undo + [(YAW, yaw1 if i == 0 else yaw_rest), (PITCH, pitch1 if i == 0 else pitch_rest)]
        return d

    # Golpe de cola: se recoge girando y la cola se estira y barre por el costado hasta delante, como un látigo
    # con la mano en la punta.
    ACTIONS["fight_b_tail"] = lambda: [
        (1, BASE()),
        (8, pose(arms(up=18, bend=35), crouch(18), spine(-6, yaw=28), hips(yaw=38), head(-4, yaw=-40, lean=-4),
                 _whip(40, 10, 20), root=(0, 0.012, -0.012))),
        (12, pose(arms(fwd=-25, up=28, bend=15), crouch(10), spine(16, yaw=-30), hips(yaw=-62),
                  head(6, yaw=55, lean=10), _whip(-20, 8, 15), root=(0, -0.02, -0.008))),
        (14, pose(arms(fwd=-30, up=30, bend=10), crouch(14), spine(24, yaw=-34), hips(yaw=-78),
                  head(8, yaw=60, lean=14), _whip(-75, -7, 12), root=(0, -0.03, -0.012))),
        (18, pose(arms(fwd=-22, up=24, bend=14), crouch(13), spine(20, yaw=-30), hips(yaw=-70),
                  head(8, yaw=55, lean=12), _whip(-85, -10, 10), root=(0, -0.026, -0.011))),
        (30, BASE()),
    ]
'''

GENERIC_ACTIONS = '''
if bpy.path.basename(bpy.data.filepath) == "forretress.blend":
    def _spin(first, last, turns, **kw):
        """Giros enteros sobre el eje vertical entre dos fotogramas, una clave por fotograma (entre claves
        gira menos de 70 grados: con más, la interpolación tomaría el camino corto)."""
        n = last - first
        return [(first + i, P(yaw=360.0 * turns * i / n, **{k: (v(i / n) if callable(v) else v) for k, v in kw.items()}))
                for i in range(n + 1)]

    def _ram(turns, back=0):
        """Embestida girando: se recoge, gira `turns` vueltas mientras se lanza y llega delante al acabarlas."""
        end = 360.0 * turns
        keys = _spin(6, 14, turns, up=0.02, pitch=lambda k: -8 + 22 * k)
        return [
            (1, P()),
            (5, P(fwd=-0.07, up=0.02, pitch=-12)),
            *[(f, dict(p, root=(-0.07 + 0.25 * (i / 8) ** 1.5, 0.02))) for i, (f, p) in enumerate(keys)],
            (17, P(fwd=0.14, pitch=10, yaw=end)),
            (26, P(yaw=end)),
        ]

    # (Sin "hit" ni "ko" en el nombre: animate_status los tomaría por variantes de esos clips y no los crearía.)
    ACTIONS["spin_ram"] = lambda: _ram(1)
    ACTIONS["spin_ram_b"] = lambda: _ram(-1)
    ACTIONS["spin_heavy"] = lambda: _ram(2)
    # Giro bola: se recoge, da tres vueltas inclinado hacia delante mientras embiste y frena con rebote.
    ACTIONS["spin_multi"] = lambda: [
        (1, P()),
        (5, P(fwd=-0.05, up=-0.03, pitch=-10)),
        *[(f, dict(p, root=(0.05, 0.05), pitch=14)) for f, p in _spin(6, 22, 3)],
        (25, P(fwd=0.06, up=0.0, pitch=-8, yaw=1080)),
        (30, P(yaw=1080)),
    ]
    # Púas tóxicas: se agacha, da una vuelta elevándose y cae de golpe soltándolas.
    ACTIONS["spin_drop"] = lambda: [
        (1, P()),
        (4, P(up=-0.04, pitch=6)),
        *_spin(5, 15, 1, up=lambda k: -0.04 + 0.2 * k),
        (17, P(up=0.17, yaw=360)),
        (19, P(up=-0.05, pitch=4, yaw=360)),
        (21, P(up=0.03, yaw=360)),
        (23, P(up=-0.015, yaw=360)),
        (28, P(yaw=360)),
    ]
'''

FIX_MESH = '''
import bmesh
import bpy

for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    me = obj.data
    if len(me.vertices) < 0.8 * len(me.loops):
        continue  # ya comparte vértices
    size = max(obj.dimensions) or 1.0
    bm = bmesh.new()
    bm.from_mesh(me)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=size * 1e-4)
    bm.normal_update()
    bm.to_mesh(me)
    after = len(bm.verts)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    me.update()
    print(f"Malla soldada: {obj.name} {before} -> {after} vértices")
bpy.ops.wm.save_mainfile()
'''

"""Esqueletos de plantilla para los rips que vienen sin huesos (Aipom, Hitmontop, Forretress).

Mismo formato que tools/blender/rig_templates.py de poke-tactics (posiciones en alturas del modelo: u a lo
ancho, v de delante (-) a atrás (+), h desde el suelo). tools/animate_models.py los añade a RIGS antes de animar.
"""

RIGS_EXTRA = {
    "aipom": {  # pose T, cola recta hacia atrás acabada en mano
        "Hips": ((0, -0.48, 0.17), (0, -0.48, 0.32), None),
        "Spine": ((0, -0.48, 0.32), (0, -0.48, 0.45), "Hips"),
        "Head": ((0, -0.48, 0.45), (0, -0.5, 0.8), "Spine"),
        "LEar": ((0.15, -0.48, 0.62), (0.4, -0.48, 0.72), "Head"),
        "LThigh": ((0.06, -0.48, 0.17), (0.06, -0.5, 0.05), "Hips"),
        "LFoot": ((0.06, -0.5, 0.05), (0.06, -0.6, 0.02), "LThigh"),
        "LToe": ((0.06, -0.6, 0.02), (0.06, -0.66, 0.01), "LFoot"),
        "LArm": ((0.1, -0.48, 0.4), (0.19, -0.48, 0.4), "Spine"),
        "LForeArm": ((0.19, -0.48, 0.4), (0.28, -0.48, 0.4), "LArm"),
        "LHand": ((0.28, -0.48, 0.4), (0.36, -0.48, 0.4), "LForeArm"),
        "Tail1": ((0, -0.38, 0.2), (0, -0.1, 0.2), "Hips"),
        "Tail2": ((0, -0.1, 0.2), (0, 0.15, 0.2), "Tail1"),
        "Tail3": ((0, 0.15, 0.2), (0, 0.36, 0.2), "Tail2"),
        "Tail4": ((0, 0.36, 0.2), (0, 0.68, 0.2), "Tail3"),
    },
    "hitmontop": {  # pose T, ala ancha en la cabeza, cola con bola
        "Hips": ((0, -0.1, 0.27), (0, -0.1, 0.4), None),
        "Spine": ((0, -0.1, 0.4), (0, -0.1, 0.5), "Hips"),
        "Head": ((0, -0.1, 0.5), (0, -0.1, 0.9), "Spine"),
        "LThigh": ((0.04, -0.1, 0.27), (0.1, -0.1, 0.15), "Hips"),
        "LLeg": ((0.1, -0.1, 0.15), (0.15, -0.1, 0.06), "LThigh"),
        "LFoot": ((0.15, -0.1, 0.06), (0.15, -0.25, 0.02), "LLeg"),
        "LToe": ((0.15, -0.25, 0.02), (0.15, -0.32, 0.01), "LFoot"),
        "LArm": ((0.12, -0.1, 0.43), (0.24, -0.1, 0.43), "Spine"),
        "LForeArm": ((0.24, -0.1, 0.43), (0.35, -0.1, 0.43), "LArm"),
        "LHand": ((0.35, -0.1, 0.43), (0.47, -0.1, 0.43), "LForeArm"),
        "Tail1": ((0, -0.02, 0.27), (0, 0.15, 0.26), "Hips"),
        "Tail2": ((0, 0.15, 0.26), (0, 0.36, 0.26), "Tail1"),
        # La cabeza (con su ala ancha) es una pieza suelta: entera al hueso Head, sin moverla.
        "_props": [{"box": ((-0.6, -0.6, 0.49), (0.6, 0.6, 1.05)), "pivot": (0, -0.1, 0.5), "pitch": 0,
                    "to": (0, -0.1, 0.5), "bone": "Head"}],
    },
    "forretress": {
        "Hips": ((0, 0, 0.5), (0, 0, 0.8), None),
    },
}

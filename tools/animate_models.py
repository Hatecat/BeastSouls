#!/usr/bin/env python3
"""Pone animaciones a modelos que vienen sin ellas, con las herramientas de Blender de poke-tactics.

    python3 tools/animate_models.py lucario:448 houndoom:229 forretress:205:generic
        [--src ~/Documentos/modelos-desc/regular] [--poke-tactics ~/Documentos/poke-tactics]

Cada argumento es nombre:número_de_pokédex (el modelo es <src>/<número>.glb). Con ":generic" se anima con
animate_generic.py (cuerpos sin patas: bolas, peces); si no, con animate_pokemon.py (bípedos y cuadrúpedos con
la convención de huesos Hips/LThigh/LFoot...). Los modelos sin esqueleto necesitan una plantilla en
tools/rig_templates_extra.py.

Trabaja en una carpeta temporal (no toca poke-tactics) y deja el resultado en assets/models/placeholder/<nombre>.glb
con los clips idle, walk, fight_b, fight_b_<variante>, fight_d, fight_d_<variante>, hit y ko. Después:
`godot --headless --path . --import` y crear el visual (actors/visuals/<nombre>_visual.tscn).
Necesita `blender` en el PATH (probado con 5.2).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VARIANTS = ["punch", "kick", "claw", "bite", "body", "tail", "horn", "breath", "sound", "boost", "mind"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("models", nargs="+")
    ap.add_argument("--src", default=os.path.expanduser("~/Documentos/modelos-desc/regular"))
    ap.add_argument("--poke-tactics", default=os.path.expanduser("~/Documentos/poke-tactics"))
    a = ap.parse_args()
    work = tempfile.mkdtemp(prefix="beastsouls_anim_")
    shutil.copytree(os.path.join(a.poke_tactics, "tools", "blender"), os.path.join(work, "tools", "blender"),
                    ignore=shutil.ignore_patterns("__pycache__"))
    for d in ("assets/models/pokemon", "art/blender"):
        os.makedirs(os.path.join(work, d))
    extra = open(os.path.join(ROOT, "tools", "rig_templates_extra.py"), encoding="utf-8").read()
    with open(os.path.join(work, "tools", "blender", "rig_templates.py"), "a", encoding="utf-8") as f:
        f.write("\n\n" + extra[extra.index("RIGS_EXTRA = {"):] + "\nRIGS.update(RIGS_EXTRA)\n")

    def blender(*args):
        r = subprocess.run(["blender", "--background", *args], cwd=work, capture_output=True, text=True, timeout=1200)
        return r.stdout + r.stderr

    for spec in a.models:
        parts = spec.split(":")
        name, dex, generic = parts[0], parts[1], len(parts) > 2 and parts[2] == "generic"
        shutil.copyfile(os.path.join(a.src, dex + ".glb"), os.path.join(work, "assets/models/pokemon", name + ".glb"))
        blend = f"art/blender/{name}.blend"
        out = blender("--python", "tools/blender/setup_animations.py", "--", name, *VARIANTS)
        if "Listo" not in out:
            print(f"{name}: no se pudo preparar\n{out[-600:]}")
            continue
        if generic:
            out = blender(blend, "--python", "tools/blender/animate_generic.py")
        else:
            # Las acciones válidas dependen del cuerpo (bípedo/cuadrúpedo, con o sin cola): se le preguntan.
            out = blender(blend, "--python", "tools/blender/animate_pokemon.py", "--", "?")
            m = re.search(r"Válidas: (.*)", out)
            if not m:
                print(f"{name}: el animador no reconoce el esqueleto\n{out[-800:]}")
                continue
            out = blender(blend, "--python", "tools/blender/animate_pokemon.py", "--", *[x.strip() for x in m.group(1).split(",")])
        print(name, "|", (re.search(r"Animadas:.*", out) or [out[-400:]])[0])
        blender(blend, "--python", "tools/blender/animate_status.py", "--", "hit", "ko")
        out = blender(blend, "--python", "tools/blender/export_animations.py")
        m = re.search(r"con (\d+ acciones.*)", out)
        if not m:
            print(f"{name}: no se pudo exportar\n{out[-600:]}")
            continue
        shutil.copyfile(os.path.join(work, "assets/models/pokemon", name + ".glb"),
                        os.path.join(ROOT, "assets/models/placeholder", name + ".glb"))
        print(name, "|", m.group(1))
    shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())

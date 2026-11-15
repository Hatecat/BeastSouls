"""Rehace feraligatr.glb desde el rip original: sus mallas vienen sin normales (material sin iluminación) y el
shader de personaje necesita normales y tangentes. De paso deja solo los clips que usa el visual (113 → 14).

    blender --background --python tools/fix_feraligatr.py -- ~/Documentos/modelos-desc/regular/160.glb
"""
import re
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[1]
src = sys.argv[sys.argv.index("--") + 1]
visual = (ROOT / "actors/visuals/feraligatr_visual.tscn").read_text(encoding="utf-8")
keep = set(re.findall(r'&"(pm0160_[^"]+)"', visual))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src, guess_original_bind_pose=False)
for obj in list(bpy.data.objects):
    if obj.type == "MESH" and obj.name.startswith("Icosphere"):
        bpy.data.objects.remove(obj)  # esferas con las que el importador dibuja los huesos
for obj in bpy.context.scene.objects:
    if obj.type == "MESH":
        obj.data.shade_smooth()
for action in list(bpy.data.actions):
    if action.name.removesuffix("_loop") in keep:  # Godot quita "_loop" al importar (marca de bucle)
        action.use_fake_user = True
    else:
        bpy.data.actions.remove(action)
missing = keep - {a.name.removesuffix("_loop") for a in bpy.data.actions}
if missing:
    raise SystemExit(f"Faltan clips: {sorted(missing)}")
out = ROOT / "assets/models/placeholder/feraligatr.glb"
bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", export_animations=True, export_animation_mode="ACTIONS",
                          export_force_sampling=True, export_frame_range=False, export_draco_mesh_compression_enable=False,
                          export_apply=False, export_normals=True, export_tangents=True)
print(f"Exportado {out} con {len(bpy.data.actions)} clips")

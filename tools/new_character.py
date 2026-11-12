#!/usr/bin/env python3
"""Crea un personaje jugable a partir de un modelo (.glb con esqueleto y animaciones).

    python3 tools/new_character.py --id=lobo --name="Lobo" --model=/ruta/lobo.glb
        [--archetype=balanced|fast|tank|ranged] [--surface=skin|scales|chitin|ghost|fur|wet]
        [--height=2.0] [--color=1,0.5,0.2] [--role="Texto"] [--desc="Texto"] [--force]

Qué hace:
  1. Copia el modelo a assets/models/characters/<id>/ y lo importa con Godot.
  2. Lee sus clips y huesos y adivina por nombre el mapa de acciones y los sockets
     → actors/visuals/<id>_visual.tscn (revísalo: es lo único que conoce el modelo).
  3. Genera un kit de partida según el arquetipo (ataques = plantillas de Charizard escaladas; 4 habilidades
     genéricas: 1 distancia, 2 cerca, 3 área, 4 mejora) → combat/attacks/<id>/, combat/abilities/<id>/.
  4. Escribe actors/characters/<id>.tres. El selector lo recoge solo (Roster busca en esa carpeta).

Después: abre el juego, prueba con `-- --practice --char=<id>`, ajusta tiempos y hitboxes en el inspector (F1 en
la arena las muestra). Godot: variable de entorno GODOT o ~/Godot_v4.7.2-stable_linux.x86_64.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_characters as kit  # noqa: E402

ROOT = kit.ROOT
GODOT = os.environ.get("GODOT", os.path.expanduser("~/Godot_v4.7.2-stable_linux.x86_64"))

# Acción lógica -> palabras que suelen llevar los clips (por orden de preferencia).
CLIP_HINTS = {
    "idle": ["idle", "stand", "wait", "breath"],
    "walk": ["walk", "jog", "move"],
    "run": ["run", "sprint", "dash", "gallop"],
    "dodge": ["dodge", "roll", "evade", "dash", "step", "jump"],
    "block": ["block", "guard", "defend", "shield", "parry"],
    "hit": ["hit", "hurt", "damage", "flinch", "stagger", "impact"],
    "death": ["death", "die", "dead", "ko", "defeat", "faint"],
    "jump": ["jump", "leap"],
}
ATTACK_WORDS = ["attack", "slash", "punch", "kick", "bite", "claw", "swipe", "strike", "stab", "smash", "tail",
                "combo", "melee", "fight_b_"]
SKILL_WORDS = ["skill", "cast", "spell", "magic", "special", "roar", "breath", "shoot", "buff", "power", "fight_d_"]
# Socket lógico -> palabras del hueso. `side`: prefijos/sufijos de lado que debe llevar.
SOCKET_HINTS = {
    "head": (["head"], None), "mouth": (["jaw", "mouth", "head"], None), "chest": (["spine2", "chest", "spine", "torso", "hips"], None),
    "hand_l": (["hand", "forearm", "arm", "wrist"], "l"), "hand_r": (["hand", "forearm", "arm", "wrist"], "r"),
    "foot_l": (["foot", "ankle", "toe", "leg"], "l"), "foot_r": (["foot", "ankle", "toe", "leg"], "r"),
    "tail_tip": (["tail"], None),
}
ARCHETYPES = {
    #            t     daño  alcance  estadísticas
    "balanced": (1.0, 1.0, 1.0, {}),
    "fast": (0.82, 0.85, 1.05, {"max_health": 85.0, "jog_speed": 5.2, "sprint_speed": 8.6, "strafe_speed": 3.8,
                                "max_poise": 5.0, "max_stamina": 110.0, "dodge_distance": 5.2}),
    "tank": (1.15, 1.3, 1.25, {"max_health": 150.0, "jog_speed": 3.6, "sprint_speed": 6.0, "strafe_speed": 2.6,
                               "max_poise": 30.0, "max_stamina": 120.0, "dodge_distance": 3.4, "turn_speed": 9.0}),
    "ranged": (1.0, 0.9, 1.0, {"max_health": 95.0, "jog_speed": 4.6, "max_poise": 8.0, "dodge_distance": 5.5}),
}
RATINGS = {"balanced": (3, 3, 3, 3), "fast": (2, 5, 3, 2), "tank": (5, 1, 5, 2), "ranged": (3, 4, 3, 5)}


def godot(*args):
    return subprocess.run([GODOT, "--headless", "--path", ROOT, *args], capture_output=True, text=True, timeout=600)


def side_of(name):
    n = name.lower()
    if re.search(r"(^|[^a-z])l(eft)?([^a-z]|$)|^l[A-Z_]|left", name) or n.startswith("l_") or re.match(r"^L[A-Z]", name):
        return "l"
    if re.search(r"(^|[^a-z])r(ight)?([^a-z]|$)|right", name) or n.startswith("r_") or re.match(r"^R[A-Z]", name):
        return "r"
    return None


def pick_clip(clips, words, used=()):
    for w in words:
        for c in sorted(clips, key=len):
            if w in c.lower() and c not in used:
                return c
    return None


def guess_actions(clips):
    amap, missing = {}, []
    for action, words in CLIP_HINTS.items():
        c = pick_clip(clips, words)
        if c and not (action == "hit" and any(w in c.lower() for w in ATTACK_WORDS if w != "fight_b_")):
            amap[action] = c
        elif action != "jump":
            missing.append(action)
    reserved = {amap.get(k) for k in ("idle", "walk", "run", "block", "hit", "death")}
    attacks = [c for c in sorted(clips) if any(w in c.lower() for w in ATTACK_WORDS) and c not in reserved
               and not any(w in c.lower() for w in SKILL_WORDS)]
    skills = [c for c in sorted(clips) if any(w in c.lower() for w in SKILL_WORDS) and c not in reserved]
    if not attacks:
        missing.append("attack_* (ningún clip de ataque reconocido)")
        attacks = [amap.get("idle", next(iter(clips), "idle"))]
    slots = ["attack_light_1", "attack_light_2", "attack_light_3", "attack_heavy_1", "attack_heavy_2", "attack_running"]
    for i, s in enumerate(slots):
        amap[s] = attacks[i % len(attacks)]
    if not skills:
        missing.append("skill_* (se usan clips de ataque)")
        skills = attacks
    for i in range(4):
        amap["skill_%d" % (i + 1)] = skills[i % len(skills)]
    for a in list(missing):
        if a in CLIP_HINTS:  # sin clip: que al menos no rompa (idle; correr = andar; esquivar = un ataque)
            amap[a] = {"run": amap.get("walk"), "walk": amap.get("run"), "dodge": attacks[-1]}.get(a) or amap.get("idle", attacks[0])
    return amap, missing


def guess_sockets(bones):
    names = [b[0] for b in bones]
    depth = {}
    for b in bones:  # los padres van antes que los hijos
        depth[b[0]] = depth[bones[b[1]][0]] + 1 if b[1] >= 0 else 0
    out, missing = {}, []
    for socket, (words, side) in SOCKET_HINTS.items():
        found = None
        for w in words:
            cands = [n for n in names if w in n.lower() and (side is None or side_of(n) == side)
                     and not re.search(r"end|camera|skin", n.lower())]
            if cands:
                # Cola: el hueso más profundo de la cadena; el resto: el nombre más corto (el hueso principal).
                found = max(cands, key=lambda n: depth[n]) if socket == "tail_tip" else sorted(cands, key=len)[0]
                break
        if found:
            out[socket] = found
        elif socket != "tail_tip":
            missing.append(socket)
    return out, missing


def write_visual(cid, model_res, height, surface, amap, sockets, clips):
    lines = ['[gd_scene load_steps=3 format=3]\n',
             '[ext_resource type="Script" path="res://actors/visuals/character_visual.gd" id="1_script"]',
             f'[ext_resource type="PackedScene" path="{model_res}" id="2_model"]\n',
             f'[node name="{cid.capitalize()}Visual" type="Node3D"]', 'script = ExtResource("1_script")',
             'model_scene = ExtResource("2_model")', f"target_height = {height}", f'surface = &"{surface}"',
             "action_map = Dictionary[StringName, StringName]({"]
    lines.append(",\n".join(f'&"{k}": &"{v}"' for k, v in sorted(amap.items())))
    lines.append("})")
    speeds = {}
    if amap.get("run") == amap.get("walk"):
        speeds["run"] = 1.7  # sin clip de carrera: el de andar acelerado
    if amap.get("dodge") and clips.get(amap["dodge"], 0.5) > 0.7:
        speeds["dodge"] = round(clips[amap["dodge"]] / 0.6, 2)
    if speeds:
        lines.append("action_speed = Dictionary[StringName, float]({")
        lines.append(",\n".join(f'&"{k}": {v}' for k, v in sorted(speeds.items())))
        lines.append("})")
    lines.append("sockets = Dictionary[StringName, StringName]({")
    lines.append(",\n".join(f'&"{k}": &"{v}"' for k, v in sorted(sockets.items())))
    lines.append("})")
    with open(os.path.join(ROOT, f"actors/visuals/{cid}_visual.tscn"), "w") as f:
        f.write("\n".join(lines) + "\n")


def write_kit(cid, a, col, h):
    t, dmg, reach, stats = ARCHETYPES[a.archetype]
    reach *= h / 2.0
    names = {"light_1": "Golpe", "light_2": "Revés", "light_3": "Remate", "heavy_1": "Golpe fuerte",
             "heavy_2": "Golpe demoledor", "running": "Embestida"}
    armor = {"hyper_armor": 40} if a.archetype == "tank" else None
    attacks = {k: kit.make_attack(k, n, t=t, dmg=dmg, reach=reach, extra=armor) for k, n in names.items()}
    ranged = a.archetype == "ranged"
    s = h / 2.0
    abilities = [
        kit.make_ability(cid, "ability_1", "projectile", "Proyectil", col, "skill_1",
                         hit=dict(damage=22 if ranged else 16, poise_damage=30, guard_stamina_damage=22, knockback=4),
                         anim_speed=1.6, heat_cost=20, cooldown=3 if ranged else 4, duration=0.85, cancel_start=0.65,
                         tracking=6, track_until=0.3, spawn_time=0.3, spawn_offset=(0, 1.3 * s, -1.0 * s), speed=18,
                         radius=0.45, lifetime=2.2, homing=1.5 if ranged else 0.8, explode_radius=1.8, visual_scale=1.0),
        kit.make_ability(cid, "ability_2", "channel", "Ráfaga", col, "skill_2",
                         hit=dict(damage=3.6, poise_damage=6, guard_stamina_damage=8, stagger_time=0.3, knockback=0.8),
                         heat_cost=35, cooldown=8, duration=1.6, cancel_start=1.4, tracking=2, track_until=1.35,
                         channel_start=0.3, channel_end=1.35, tick_interval=0.15, cone_range=6.0 if ranged else 4.5,
                         cone_angle_deg=24, origin_offset=(0, 1.5 * s, -0.7 * s)),
        kit.make_ability(cid, "ability_3", "area", "Onda", col, "skill_3",
                         hit=dict(damage=18, poise_damage=60, guard_stamina_damage=40, stagger_time=0.8, knockback=6, hitstop=0.1),
                         heat_cost=40, cooldown=12, duration=1.2, cancel_start=0.95, tracking=4, track_until=0.35,
                         trigger_time=0.45, radius=4.5 * max(s, 0.8), caster_shake=0.4),
        kit.make_ability(cid, "ability_4", "buff", "Furia", tuple(min(1.0, c * 0.5 + 0.5) for c in col), "skill_4",
                         heat_cost=45, cooldown=20, duration=1.1, cancel_start=0.9, tracking=0, track_until=0,
                         buff_id=f'&"furia_{cid}"', trigger_time=0.4, buff_duration=9, damage_multiplier=1.3,
                         speed_multiplier=1.1, action_speed_multiplier=1.1),
    ]
    kit.make_moveset(cid, attacks, abilities)
    return stats


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--id", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--name")
    ap.add_argument("--archetype", default="balanced", choices=sorted(ARCHETYPES))
    ap.add_argument("--surface", default="skin", choices=["skin", "scales", "chitin", "ghost", "fur", "wet"])
    ap.add_argument("--height", type=float, default=2.0)
    ap.add_argument("--color", default="1,0.6,0.25")
    ap.add_argument("--role", default="")
    ap.add_argument("--desc", default="")
    ap.add_argument("--force", action="store_true", help="sobrescribe un personaje que ya existe")
    a = ap.parse_args()
    cid = a.id.lower()
    if not re.fullmatch(r"[a-z][a-z0-9_]*", cid):
        sys.exit("El id debe ser minúsculas, números y _ (p. ej. lobo_gris).")
    def_path = os.path.join(ROOT, f"actors/characters/{cid}.tres")
    if os.path.exists(def_path) and not a.force:
        sys.exit(f"Ya existe {def_path}. Usa --force para regenerarlo (pisa el kit y el visual).")
    src = os.path.abspath(a.model)
    if not os.path.isfile(src):
        sys.exit(f"No existe el modelo: {src}")
    if src.startswith(ROOT + os.sep):
        model_res = "res://" + os.path.relpath(src, ROOT)
    else:
        dst_dir = os.path.join(ROOT, "assets", "models", "characters", cid)
        os.makedirs(dst_dir, exist_ok=True)
        dst = os.path.join(dst_dir, cid + os.path.splitext(src)[1].lower())
        shutil.copyfile(src, dst)
        model_res = "res://" + os.path.relpath(dst, ROOT)
    print(f"[1/4] Importando {model_res} …")
    godot("--import")
    r = godot("--script", "tools/inspect_model.gd", "--", model_res)
    m = re.search(r"MODEL_JSON_BEGIN(.*?)MODEL_JSON_END", r.stdout, re.S)
    info = json.loads(m.group(1)) if m else {"error": r.stdout[-400:] + r.stderr[-400:]}
    if "error" in info:
        sys.exit("No se pudo leer el modelo: %s" % info["error"])
    if not info["bones"] or not info["clips"]:
        sys.exit("El modelo necesita esqueleto y animaciones (clips: %d, huesos: %d)." % (len(info["clips"]), len(info["bones"])))
    print(f"      {len(info['clips'])} clips, {len(info['bones'])} huesos, {info['triangles']} triángulos")
    amap, miss_a = guess_actions(info["clips"])
    sockets, miss_s = guess_sockets(info["bones"])
    print("[2/4] Visual: actors/visuals/%s_visual.tscn" % cid)
    write_visual(cid, model_res, a.height, a.surface, amap, sockets, info["clips"])
    col = tuple(float(x) for x in a.color.split(","))
    print("[3/4] Kit (%s): combat/attacks/%s/, combat/abilities/%s/" % (a.archetype, cid, cid))
    stats = write_kit(cid, a, col, a.height)
    name = a.name or cid.replace("_", " ").title()
    radius = round(max(0.4, min(0.9, a.height * 0.28)), 2)
    kit.make_def(cid, name, a.role or a.archetype.capitalize(), a.desc or "Personaje nuevo: ajusta su kit.", col, stats,
                 (radius, a.height, round(a.height * 0.65, 2)), RATINGS[a.archetype])
    print("[4/4] Registrando clases y recursos …")
    godot("--import")
    print("\nListo: %s (%s)." % (name, cid))
    print("  Acciones → clips:")
    for k, v in sorted(amap.items()):
        print("    %-16s %s" % (k, v))
    print("  Sockets → huesos: " + ", ".join(f"{k}={v}" for k, v in sorted(sockets.items())))
    if miss_a:
        print("  SIN CLIP PROPIO (se ha puesto un sustituto): " + ", ".join(miss_a))
    if miss_s:
        print("  SIN HUESO para los sockets: " + ", ".join(miss_s) + " (los efectos saldrán del centro del personaje)")
    print(f"\nPruébalo:  {GODOT} --path {ROOT} -- --practice --char={cid}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Genera los kits de los personajes provisionales (ataques, habilidades, moveset y CharacterDef).

Los ataques parten de las plantillas de Charizard (combat/attacks/charizard/*.tres) escaladas por personaje.
Volver a ejecutarlo SOBRESCRIBE los .tres generados (no los de Charizard salvo su CharacterDef).
Uso: python3 tools/gen_characters.py
Las funciones make_* las reutiliza tools/new_character.py para crear personajes nuevos.
"""
import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIME_KEYS = ["duration", "active_start", "active_end", "combo_start", "cancel_start", "lunge_start", "lunge_end", "charge_point"]


def read_props(path):
    props, on = {}, False
    for line in open(os.path.join(ROOT, path)):
        line = line.rstrip("\n")
        if line == "[resource]":
            on = True
            continue
        if on and " = " in line and not line.startswith("script"):
            k, v = line.split(" = ", 1)
            props[k] = v
    return props


def num(v):
    return float(v)


def vec(v):
    return [float(x) for x in re.findall(r"-?[\d.]+", v.split("(", 1)[1])]


def fvec(xs):
    return "Vector3(%s)" % ", ".join("%g" % x for x in xs)


def color(c):
    return "Color(%g, %g, %g, 1)" % c


def write(path, header_ext, body, script="res://combat/attack_data.gd", cls="AttackData", subs=""):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(f'[gd_resource type="Resource" script_class="{cls}" format=3]\n\n')
        f.write(f'[ext_resource type="Script" path="{script}" id="1_script"]\n')
        f.write(header_ext)
        f.write("\n" + subs)
        f.write("[resource]\nscript = ExtResource(\"1_script\")\n" + body)


def props_text(p):
    return "".join(f"{k} = {v}\n" for k, v in p.items())


def make_attack(template, name, t=1.0, dmg=1.0, reach=1.0, extra=None, poise=None):
    # poise: escala de postura y desgaste de guardia (por defecto, la misma que el daño).
    poise = dmg if poise is None else poise
    p = dict(read_props(f"combat/attacks/charizard/{template}.tres"))
    p["display_name"] = f'"{name}"'
    for k in TIME_KEYS:
        if k in p:
            p[k] = "%g" % round(num(p[k]) * t, 3)
    p["anim_speed"] = "%g" % round(num(p.get("anim_speed", "1")) / t, 3)
    for k in ["damage", "poise_damage", "guard_stamina_damage"]:
        if k in p:
            p[k] = "%g" % round(num(p[k]) * (dmg if k == "damage" else poise), 1)
    for k in ["hitbox_offset_start", "hitbox_offset_end"]:
        if k in p:
            x, y, z = vec(p[k])
            p[k] = fvec([x * reach, y * reach, z * reach])
    if "hitbox_radius" in p:
        p["hitbox_radius"] = "%g" % round(num(p["hitbox_radius"]) * reach, 2)
    for k, v in (extra or {}).items():
        p[k] = v if isinstance(v, str) else "%g" % v
    return p


def make_combo(template, name, action=None, **kw):
    """Ataque de combo mixto (Moveset.combos): como make_attack, pero nunca cargable y con la animación que se pida."""
    extra = dict(kw.pop("extra", None) or {})
    p = make_attack(template, name, extra=extra, **kw)
    for k in ["chargeable", "charge_point", "max_charge", "charge_multiplier"]:
        p.pop(k, None)
    if action:
        p["action"] = f'&"{action}"'
    return p


def hit_sub(name, **kw):
    d = dict(damage=10, poise_damage=20, guard_stamina_damage=15, stamina_cost=0, stagger_time=0.5,
             knockback=3, hitstop=0.05, heat_gain=0)
    d.update(kw)
    lines = [f'display_name = "{name}"']
    for k, v in d.items():
        lines.append(f"{k} = {str(v).lower() if isinstance(v, bool) else ('%g' % v)}")
    return '[sub_resource type="Resource" id="hit"]\nscript = ExtResource("2_attack")\n' + "\n".join(lines) + "\n\n"


ABILITY_SCRIPTS = {
    "projectile": ("ProjectileAbility", "res://combat/abilities/projectile_ability.gd"),
    "channel": ("ChannelAbility", "res://combat/abilities/channel_ability.gd"),
    "area": ("AreaAbility", "res://combat/abilities/area_ability.gd"),
    "buff": ("BuffAbility", "res://combat/abilities/buff_ability.gd"),
    "dash": ("DashAbility", "res://combat/abilities/dash_ability.gd"),
}


def make_ability(cid, file, kind, name, col, action, hit=None, **kw):
    cls, script = ABILITY_SCRIPTS[kind]
    body = {"display_name": f'"{name}"', "color": color(col), "action": f'&"{action}"'}
    for k, v in kw.items():
        if isinstance(v, tuple):
            body[k] = fvec(v)
        elif isinstance(v, str):
            body[k] = v
        elif isinstance(v, bool):
            body[k] = str(v).lower()
        else:
            body[k] = "%g" % v
    ext = ""
    subs = ""
    if hit is not None:
        ext = '[ext_resource type="Script" path="res://combat/attack_data.gd" id="2_attack"]\n'
        subs = hit_sub(name, **hit)
        body = {"hit": 'SubResource("hit")', **body}
    write(f"combat/abilities/{cid}/{file}.tres", ext, props_text(body), script, cls, subs)
    return f"res://combat/abilities/{cid}/{file}.tres"


def make_moveset(cid, attacks, abilities, combos=None):
    """`abilities`: las 4 por defecto (ranuras 1 distancia, 2 cerca, 3 área, 4 mejora). Se completa el catálogo
    hasta 10 con las de EXTRA_KITS[cid] si existen."""
    abilities = list(abilities) + [f(cid) for f in EXTRA_KITS.get(cid, [])]
    ext = ['[ext_resource type="Script" path="res://combat/attack_data.gd" id="2_attack"]',
           '[ext_resource type="Script" path="res://combat/abilities/ability_data.gd" id="3_ability"]']
    for i, a in enumerate(abilities):
        ext.append(f'[ext_resource type="Resource" path="{a}" id="ab{i}"]')
    for k in ["light_1", "light_2", "light_3", "heavy_1", "heavy_2", "running"]:
        ext.append(f'[ext_resource type="Resource" path="res://combat/attacks/{cid}/{k}.tres" id="{k}"]')
    combos = combos or {}
    for seq in combos:
        ext.append(f'[ext_resource type="Resource" path="res://combat/attacks/{cid}/combo_{seq.lower()}.tres" id="combo_{seq.lower()}"]')
    combo_body = ""
    if combos:
        combo_body = 'combos = Dictionary[String, ExtResource("2_attack")]({\n%s\n})\n' % ",\n".join(
            f'"{seq}": ExtResource("combo_{seq.lower()}")' for seq in combos)
    body = ('light_combo = Array[ExtResource("2_attack")]([ExtResource("light_1"), ExtResource("light_2"), ExtResource("light_3")])\n'
            'heavy_combo = Array[ExtResource("2_attack")]([ExtResource("heavy_1"), ExtResource("heavy_2")])\n'
            'running_attack = ExtResource("running")\n' + combo_body +
            'abilities = Array[ExtResource("3_ability")]([%s])\n' % ", ".join(f'ExtResource("ab{i}")' for i in range(len(abilities))))
    write(f"combat/attacks/{cid}/moveset.tres", "\n".join(ext) + "\n", body, "res://combat/moveset.gd", "Moveset")
    for k, p in attacks.items():
        write(f"combat/attacks/{cid}/{k}.tres", "", props_text(p))
    for seq, p in combos.items():
        write(f"combat/attacks/{cid}/combo_{seq.lower()}.tres", "", props_text(p))


def make_def(cid, name, role, desc, col, stats, body, ratings):
    ext = ('[ext_resource type="PackedScene" path="res://actors/visuals/%s_visual.tscn" id="2_visual"]\n'
           '[ext_resource type="Resource" path="res://combat/attacks/%s/moveset.tres" id="3_moveset"]\n') % (cid, cid)
    st = ",\n".join(f'&"{k}": {v if isinstance(v, str) else ("%g" % v if isinstance(v, (int, float)) and not isinstance(v, bool) else v)}' for k, v in stats.items())
    b = (f'id = &"{cid}"\ndisplay_name = "{name}"\nrole = "{role}"\ndescription = "{desc}"\ncolor = {color(col)}\n'
         'visual = ExtResource("2_visual")\nmoveset = ExtResource("3_moveset")\n'
         f'stats = Dictionary[StringName, Variant]({{\n{st}\n}})\n'
         f'body_radius = {body[0]}\nbody_height = {body[1]}\nlock_height = {body[2]}\n'
         f'rating_health = {ratings[0]}\nrating_speed = {ratings[1]}\nrating_power = {ratings[2]}\nrating_range = {ratings[3]}\n')
    write(f"actors/characters/{cid}.tres", ext, b, "res://actors/characters/character_def.gd", "CharacterDef")


# --- Habilidades extra del catálogo (cada personaje equipa 4 de 10) -----------------------------------
# Atajos con valores por defecto razonables; cualquier campo se puede sobrescribir con **kw.

def x_proj(file, name, col, action, dmg, heat, cd, hit=None, **kw):
    h = dict(damage=dmg, poise_damage=dmg * 1.4, guard_stamina_damage=dmg * 1.1, knockback=3)
    h.update(hit or {})
    d = dict(anim_speed=1.7, heat_cost=heat, cooldown=cd, duration=0.8, cancel_start=0.62, tracking=6, track_until=0.3,
             spawn_time=0.3, spawn_offset=(0, 1.3, -1.0), speed=20, radius=0.4, lifetime=2.0, homing=1.0,
             explode_radius=1.6, visual_scale=1.0)
    d.update(kw)
    return lambda cid: make_ability(cid, file, "projectile", name, col, action, hit=h, **d)


def x_channel(file, name, col, action, dmg, heat, cd, hit=None, **kw):
    h = dict(damage=dmg, poise_damage=dmg * 1.6, guard_stamina_damage=dmg * 2, stagger_time=0.3, knockback=0.8)
    h.update(hit or {})
    d = dict(heat_cost=heat, cooldown=cd, duration=1.5, cancel_start=1.3, tracking=2.0, track_until=1.25,
             channel_start=0.3, channel_end=1.25, tick_interval=0.15, cone_range=5.0, cone_angle_deg=25,
             origin_offset=(0, 1.2, -0.6))
    d.update(kw)
    return lambda cid: make_ability(cid, file, "channel", name, col, action, hit=h, **d)


def x_area(file, name, col, action, dmg, heat, cd, radius, hit=None, **kw):
    h = dict(damage=dmg, poise_damage=55, guard_stamina_damage=35, stagger_time=0.8, knockback=6, hitstop=0.1)
    h.update(hit or {})
    d = dict(heat_cost=heat, cooldown=cd, duration=1.2, cancel_start=0.95, tracking=4, track_until=0.35,
             trigger_time=0.45, radius=radius, caster_shake=0.4)
    d.update(kw)
    return lambda cid: make_ability(cid, file, "area", name, col, action, hit=h, **d)


def x_buff(file, name, col, action, heat, cd, time, dmg=1.0, speed=1.0, rate=1.0, heal=0.0, **kw):
    d = dict(heat_cost=heat, cooldown=cd, duration=1.2, cancel_start=0.95, tracking=0, track_until=0,
             buff_id=f'&"{file}"', trigger_time=0.45, buff_duration=time, damage_multiplier=dmg,
             speed_multiplier=speed, action_speed_multiplier=rate, heal=heal)
    d.update(kw)
    return lambda cid: make_ability(cid, file, "buff", name, col, action, **d)


def x_dash(file, name, col, dmg, heat, cd, meters, hit=None, action="attack_running", **kw):
    h = dict(damage=dmg, poise_damage=dmg * 2, guard_stamina_damage=dmg * 1.5, stagger_time=0.6, knockback=5, hitstop=0.09)
    h.update(hit or {})
    d = dict(heat_cost=heat, cooldown=cd, duration=0.85, cancel_start=0.7, tracking=7, track_until=0.2,
             dash_start=0.2, dash_end=0.5, radius=1.3, offset=(0, 1.0, -0.8))
    d.update(kw)
    d["dash_speed"] = round(meters / (d["dash_end"] - d["dash_start"]), 1)
    return lambda cid: make_ability(cid, file, "dash", name, col, action, hit=h, **d)


_FIRE = (1.0, 0.55, 0.2)
_G = (0.55, 1.0, 0.4)
_P = (0.62, 0.3, 1.0)
_N = (1.0, 0.92, 0.65)
_E = (0.75, 0.55, 0.3)
_Y = (0.85, 1.0, 0.25)
_T = (0.7, 0.3, 1.0)
_W = (0.3, 0.62, 1.0)
_ICE = (0.7, 0.95, 1.0)
_F = (1.0, 0.55, 0.35)
_PSY = (0.8, 0.45, 1.0)
_MIME = (1.0, 0.55, 0.8)
_NI = dict(interruptible=False)  # Snorlax no se corta

# Preajustes de la tercera tanda (se mezclan con ** en los atajos x_*).
_GR = (0.5, 0.9, 0.35)
_ST = (0.75, 0.8, 0.9)
_EL = (1.0, 0.9, 0.3)
_AU = (0.4, 0.7, 1.0)
_DK = (0.9, 0.25, 0.35)
_AP = (0.75, 0.55, 1.0)
_MULTI = dict(duration=1.0, cancel_start=0.85, track_until=0.7, spawn_time=0.26, radius=0.32, lifetime=2.2,
              explode_radius=0.0, visual_scale=0.55, interval=0.13)
_MULTI_HIT = dict(stagger_time=0.2, knockback=1)
_BIG = dict(anim_speed=1.1, duration=1.2, cancel_start=1.0, spawn_time=0.55, speed=13, radius=0.7, lifetime=2.6,
            homing=0.6, explode_radius=3.2, visual_scale=1.9)
_BIG_HIT = dict(stagger_time=0.8, knockback=7, hitstop=0.12)
_MELEE = dict(anim_speed=1.7, duration=1.2, cancel_start=1.0, tracking=5, track_until=1.0, move_factor=0.5,
              channel_start=0.15, channel_end=1.0, tick_interval=0.14, cone_range=3.0, cone_angle_deg=50,
              fx_socket='&"hand_r"')
_QUICK = dict(anim_speed=1.4, trigger_time=0.3, duration=0.85, cancel_start=0.68, caster_shake=0.2)


def _stun(t):
    return dict(poise_damage=100, guard_stamina_damage=0, stagger_time=t, knockback=1, unblockable=True)


EXTRA_KITS = {
    "charizard": [
        x_proj("ember", "Ascuas", _FIRE, "skill_fireball", 7, 15, 3, hit=dict(stagger_time=0.25, knockback=1, burn_time=1.5),
               spawn_time=0.22, duration=0.9, cancel_start=0.72, track_until=0.6, speed=28, radius=0.28, lifetime=1.2,
               homing=1.6, explode_radius=0.0, visual_scale=0.5, count=3, interval=0.13, spawn_offset=(0, 1.6, -1.1)),
        x_dash("flare_blitz", "Envite ígneo", _FIRE, 24, 30, 9, 8.0, hit=dict(burn_time=3.0)),
        x_area("heat_wave", "Onda ígnea", (1.0, 0.4, 0.15), "skill_roar", 20, 35, 11, 4.5, hit=dict(burn_time=3.0)),
        x_channel("fire_spin", "Giro fuego", _FIRE, "skill_flamethrower", 3.0, 25, 6, hit=dict(burn_time=1.0),
                  duration=1.3, cancel_start=1.1, tracking=5, track_until=1.05, move_factor=0.6, channel_start=0.2,
                  channel_end=1.05, tick_interval=0.13, cone_range=3.4, cone_angle_deg=60, origin_offset=(0, 1.7, -0.7)),
        x_buff("roost", "Respiro", (1.0, 0.9, 0.7), "skill_dragon_dance", 50, 24, 5, heal=0.25, speed=0.8),
        x_proj("fire_blast", "Llamarada", (1.0, 0.35, 0.1), "skill_fireball", 34, 45, 10,
               hit=dict(stagger_time=0.8, knockback=7, hitstop=0.12, burn_time=4.0), anim_speed=1.1, duration=1.2,
               cancel_start=1.0, spawn_time=0.55, speed=13, radius=0.7, lifetime=2.6, homing=0.6, explode_radius=3.2,
               visual_scale=1.9, spawn_offset=(0, 1.6, -1.1)),
    ],
    "scyther": [
        x_proj("razor_leaf", "Viento cortante", _G, "skill_air_slash", 6, 20, 4, hit=dict(stagger_time=0.25, knockback=1),
               anim_speed=2.0, spawn_time=0.2, duration=0.85, cancel_start=0.7, track_until=0.6, speed=32, radius=0.25,
               lifetime=1.0, homing=1.2, explode_radius=0.0, visual_scale=0.45, count=4, interval=0.1),
        x_dash("quick_attack", "Ataque rápido", _G, 13, 15, 3.5, 6.5, dash_start=0.12, dash_end=0.34, duration=0.6,
               cancel_start=0.48, track_until=0.12),
        x_dash("night_slash", "Tajo umbrío", (0.35, 0.8, 0.5), 26, 35, 10, 10.0, hit=dict(stagger_time=0.8, knockback=6),
               dash_start=0.3, dash_end=0.6, duration=1.0, cancel_start=0.85, track_until=0.3, radius=1.5,
               action="attack_heavy_1"),
        x_area("blade_cyclone", "Ciclón de cuchillas", _G, "skill_x_scissor", 13, 20, 5, 2.8,
               hit=dict(poise_damage=35, stagger_time=0.5, knockback=4, hitstop=0.07), duration=0.75, cancel_start=0.6,
               trigger_time=0.2, caster_shake=0.2),
        x_channel("razor_wind", "Vendaval", (0.75, 1.0, 0.8), "skill_air_slash", 3.4, 35, 9, anim_speed=0.8,
                  cone_range=6.5, cone_angle_deg=16, origin_offset=(0, 1.3, -0.6), fx_socket='&"hand_r"'),
        x_buff("focus_energy", "Foco energía", (1.0, 1.0, 0.6), "skill_swords_dance", 40, 18, 10, rate=1.25, speed=1.15),
    ],
    "gengar": [
        x_channel("lick", "Lengüetazo", (0.9, 0.4, 0.7), "skill_dark_pulse", 3.6, 25, 6, hit=dict(poise_damage=9),
                  duration=1.2, cancel_start=1.0, tracking=5, track_until=0.95, move_factor=0.5, channel_start=0.2,
                  channel_end=0.95, tick_interval=0.13, cone_range=3.2, cone_angle_deg=50, origin_offset=(0, 1.0, -0.5)),
        x_proj("sludge_bomb", "Bomba lodo", (0.6, 0.25, 0.75), "skill_shadow_ball", 16, 35, 8,
               hit=dict(stagger_time=0.6, knockback=4, burn_time=6.0), anim_speed=1.3, duration=1.0, cancel_start=0.8,
               spawn_time=0.4, speed=12, radius=0.55, lifetime=2.6, homing=0.8, explode_radius=3.4, visual_scale=1.5,
               spawn_offset=(0, 1.2, -1.0)),
        x_proj("night_shade", "Tinieblas", (0.45, 0.2, 0.8), "skill_shadow_ball", 7, 30, 7,
               hit=dict(stagger_time=0.3, knockback=1.5), duration=1.0, cancel_start=0.85, track_until=0.7, spawn_time=0.25,
               speed=11, radius=0.32, lifetime=3.0, homing=3.5, explode_radius=0.0, visual_scale=0.7, count=3,
               interval=0.2, spawn_offset=(0, 1.2, -1.0)),
        x_dash("phantom_force", "Golpe fantasma", _P, 22, 30, 9, 9.0, dash_start=0.28, dash_end=0.55, duration=0.95,
               cancel_start=0.8, track_until=0.28),
        x_area("curse", "Maldición", (0.5, 0.15, 0.6), "skill_hypnosis", 8, 40, 14, 6.0,
               hit=dict(poise_damage=30, stagger_time=0.5, knockback=2, burn_time=7.0), trigger_time=0.5, duration=1.3,
               cancel_start=1.0),
        x_buff("dream_eater", "Comesueños", (0.85, 0.5, 1.0), "skill_nasty_plot", 55, 26, 6, heal=0.22, dmg=1.1),
    ],
    "snorlax": [
        x_proj("rock_throw", "Lanzarrocas", _E, "skill_hyper_beam", 28, 30, 7,
               hit=dict(poise_damage=60, stagger_time=0.8, knockback=7, hitstop=0.12), anim_speed=1.0, duration=1.2,
               cancel_start=1.0, spawn_time=0.55, speed=16, radius=0.65, lifetime=2.2, homing=0.4, explode_radius=2.4,
               visual_scale=1.7, spawn_offset=(0, 2.0, -1.2), **_NI),
        x_dash("rollout", "Rodada", _E, 30, 35, 10, 9.0, hit=dict(poise_damage=80, stagger_time=0.9, knockback=9, hitstop=0.14),
               dash_start=0.4, dash_end=0.8, duration=1.25, cancel_start=1.1, track_until=0.4, tracking=4, radius=1.9,
               offset=(0, 1.3, -1.0), action="attack_heavy_1", **_NI),
        x_area("yawn", "Bostezo", (0.8, 0.85, 1.0), "skill_rest", 0, 40, 16, 4.5,
               hit=dict(poise_damage=100, guard_stamina_damage=0, stagger_time=1.7, knockback=1, unblockable=True),
               trigger_time=0.6, duration=1.4, cancel_start=1.1, caster_shake=0.0),
        x_buff("belly_drum", "Tambor", (1.0, 0.6, 0.4), "skill_rest", 55, 26, 10, dmg=1.5, speed=0.9, duration=1.5,
               cancel_start=1.3, trigger_time=0.6, **_NI),
        x_channel("hyper_voice", "Vozarrón", _N, "skill_earthquake", 3.6, 30, 8, hit=dict(knockback=2.0, poise_damage=8),
                  cone_range=5.0, cone_angle_deg=42, origin_offset=(0, 2.0, -0.8), duration=1.6, cancel_start=1.4,
                  channel_start=0.4, channel_end=1.35, track_until=1.35, **_NI),
        x_buff("stockpile", "Reserva", (0.7, 1.0, 0.7), "skill_rest", 40, 20, 8, heal=0.18, dmg=1.15, duration=1.4,
               cancel_start=1.2, trigger_time=0.55, **_NI),
    ],
    "beedrill": [
        x_proj("poison_sting", "Picotazo veneno", _T, "skill_pin_missile", 12, 20, 4, hit=dict(burn_time=8.0), anim_speed=1.8,
               spawn_time=0.22, speed=26, radius=0.3, lifetime=1.5, homing=1.4, explode_radius=0.0, visual_scale=0.6,
               spawn_offset=(0, 1.4, -1.0)),
        x_dash("pursuit", "Persecución", _Y, 18, 25, 6, 8.5, hit=dict(burn_time=2.0), dash_start=0.16, dash_end=0.42,
               duration=0.7, cancel_start=0.58, track_until=0.16),
        x_area("bug_buzz", "Zumbido", _Y, "skill_toxic_burst", 16, 30, 9, 4.0, trigger_time=0.35, duration=1.0,
               cancel_start=0.8),
        x_channel("acid", "Ácido", _T, "skill_pin_missile", 2.8, 35, 9, hit=dict(burn_time=2.5), anim_speed=0.9,
                  cone_range=6.0, cone_angle_deg=18, origin_offset=(0, 1.3, -0.6), fx_socket='&"hand_r"'),
        x_buff("hone_claws", "Afilagarras", (1.0, 0.8, 0.3), "skill_agility", 45, 20, 9, dmg=1.35),
        x_area("toxic", "Tóxico", _T, "skill_toxic_burst", 4, 45, 16, 3.6,
               hit=dict(poise_damage=20, guard_stamina_damage=0, stagger_time=0.4, knockback=2, burn_time=9.0, unblockable=True),
               trigger_time=0.4),
    ],
    "vaporeon": [
        x_proj("bubble", "Burbujas", (0.55, 0.8, 1.0), "skill_water_pulse", 6, 20, 4, hit=dict(stagger_time=0.25, knockback=2),
               duration=1.0, cancel_start=0.85, track_until=0.75, spawn_time=0.25, speed=15, radius=0.35, lifetime=2.2,
               homing=2.4, explode_radius=0.0, visual_scale=0.6, count=4, interval=0.14, spawn_offset=(0, 1.0, -1.2)),
        x_dash("aqua_jet", "Acua jet", _W, 17, 25, 6, 9.0, hit=dict(knockback=7)),
        x_channel("ice_beam", "Rayo hielo", _ICE, "skill_hydro_pump", 3.6, 40, 10, cone_range=9.0, cone_angle_deg=10,
                  origin_offset=(0, 1.0, -0.9), tracking=1.4),
        x_area("whirlpool", "Torbellino", _W, "skill_surf", 15, 25, 7, 3.6, hit=dict(knockback=10), trigger_time=0.3,
               duration=0.95, cancel_start=0.75),
        x_buff("rain_dance", "Danza lluvia", (0.45, 0.7, 1.0), "skill_aqua_ring", 40, 20, 10, speed=1.25, rate=1.12),
        x_proj("scald", "Escaldar", (0.75, 0.85, 1.0), "skill_water_pulse", 18, 30, 6, hit=dict(burn_time=4.0, knockback=4),
               speed=22, explode_radius=1.8, spawn_offset=(0, 1.0, -1.2)),
    ],
    # --- Segunda tanda (catálogo completo aquí: las 4 primeras son la selección por defecto) ---------
    "machop": [
        x_proj("vacuum_wave", "Onda vacío", _F, "skill_shot", 15, 20, 4, speed=24, radius=0.35, explode_radius=1.2,
               visual_scale=0.8, spawn_offset=(0, 1.0, -0.8)),
        x_dash("mach_punch", "Ultrapuño", _F, 16, 15, 4, 6.0, action="skill_punch", anim_speed=1.5, duration=0.7,
               cancel_start=0.55, dash_start=0.12, dash_end=0.36, radius=1.1, offset=(0, 0.9, -0.7)),
        x_area("seismic_toss", "Sísmico", _F, "skill_body", 20, 35, 10, 3.5, anim_speed=1.2, trigger_time=0.42),
        x_buff("bulk_up", "Corpulencia", (1.0, 0.75, 0.6), "skill_boost", 45, 20, 9, dmg=1.3, rate=1.1),
        x_channel("close_combat", "A bocajarro", _F, "skill_punch", 3.4, 30, 7, anim_speed=1.8, duration=1.2,
                  cancel_start=1.0, tracking=5, track_until=1.0, move_factor=0.5, channel_start=0.15, channel_end=1.0,
                  tick_interval=0.14, cone_range=2.6, cone_angle_deg=50, origin_offset=(0, 1.0, -0.4), fx_socket='&"hand_r"'),
        x_dash("jump_kick", "Patada salto", _F, 22, 30, 9, 8.0, action="skill_kick", anim_speed=1.4,
               hit=dict(knockback=7), offset=(0, 0.9, -0.7)),
        x_area("rock_smash", "Golpe roca", _E, "skill_punch", 14, 20, 5, 2.8, hit=dict(poise_damage=40, knockback=4),
               anim_speed=1.3, trigger_time=0.34, duration=0.9, cancel_start=0.7, caster_shake=0.25),
        x_proj("focus_blast", "Onda certera", (1.0, 0.7, 0.4), "skill_shot", 30, 45, 11,
               hit=dict(stagger_time=0.8, knockback=7, hitstop=0.12), anim_speed=1.2, duration=1.15, cancel_start=0.95,
               spawn_time=0.55, speed=15, radius=0.6, lifetime=2.4, homing=0.6, explode_radius=2.6, visual_scale=1.6,
               spawn_offset=(0, 1.0, -0.9)),
        x_buff("focus_energy", "Concentración", (0.8, 0.9, 1.0), "skill_cast", 40, 18, 8, speed=1.2, rate=1.25),
        x_area("scary_face", "Grito de guerra", (1.0, 0.85, 0.5), "skill_roar", 6, 45, 16, 4.0,
               hit=dict(poise_damage=100, guard_stamina_damage=0, stagger_time=1.3, knockback=1, unblockable=True)),
    ],
    "poliwrath": [
        x_proj("water_gun", "Pistola agua", _W, "skill_shot", 16, 20, 3.5, hit=dict(knockback=5), speed=22,
               spawn_offset=(0, 1.2, -1.0)),
        x_dash("dynamic_punch", "Puño dinámico", _F, 26, 35, 10, 7.0, action="skill_punch", anim_speed=1.3,
               hit=dict(stagger_time=0.9, knockback=7, hitstop=0.13)),
        x_area("sea_wave", "Onda marina", _W, "skill_roar", 18, 40, 12, 4.8, hit=dict(knockback=9)),
        x_buff("belly_drum_p", "Corpulencia", (0.6, 0.8, 1.0), "skill_boost", 50, 22, 10, dmg=1.3, heal=0.1),
        x_channel("bubble_beam", "Rayo burbuja", (0.55, 0.8, 1.0), "skill_shot", 3.8, 35, 8, cone_range=7.0,
                  cone_angle_deg=14, origin_offset=(0, 1.2, -0.8), fx_socket='&"chest"'),
        x_dash("waterfall", "Cascada", _W, 18, 25, 6, 9.0, action="skill_body", hit=dict(knockback=8)),
        x_area("hypnosis_p", "Hipnosis", (0.75, 0.6, 1.0), "skill_cast", 2, 45, 16, 4.0,
               hit=dict(poise_damage=100, guard_stamina_damage=0, stagger_time=1.6, knockback=1, unblockable=True),
               trigger_time=0.5),
        x_proj("bubbles", "Burbujas", (0.6, 0.85, 1.0), "skill_shot", 6, 20, 4, hit=dict(stagger_time=0.25, knockback=2),
               duration=1.0, cancel_start=0.85, track_until=0.75, spawn_time=0.25, speed=15, radius=0.35, lifetime=2.2,
               homing=2.4, explode_radius=0.0, visual_scale=0.6, count=4, interval=0.14, spawn_offset=(0, 1.2, -1.0)),
        x_channel("submission", "Sumisión", _F, "skill_body", 4.5, 30, 8, anim_speed=1.4, duration=1.1, cancel_start=0.95,
                  tracking=5, track_until=0.9, move_factor=0.4, channel_start=0.2, channel_end=0.9, tick_interval=0.14,
                  cone_range=2.8, cone_angle_deg=50, origin_offset=(0, 1.2, -0.4), fx_socket='&"hand_r"'),
        x_buff("rest_p", "Descanso", (0.6, 0.8, 1.0), "skill_cast", 55, 28, 4, heal=0.28, speed=0.6, rate=0.85),
    ],
    "golem": [
        x_proj("rock_throw", "Lanzarrocas", _E, "skill_shot", 26, 30, 6, hit=dict(stagger_time=0.8, knockback=7, hitstop=0.12),
               anim_speed=1.0, duration=1.2, cancel_start=1.0, spawn_time=0.5, speed=15, radius=0.6, lifetime=2.4,
               homing=0.4, explode_radius=2.2, visual_scale=1.7, spawn_offset=(0, 1.5, -1.3), **_NI),
        x_dash("rollout_g", "Rodar", _E, 28, 35, 9, 9.0, action="skill_body",
               hit=dict(poise_damage=80, stagger_time=0.9, knockback=9, hitstop=0.14), dash_start=0.25, dash_end=0.7,
               duration=1.05, cancel_start=0.9, radius=1.6, **_NI),
        x_area("magnitude", "Magnitud", _E, "skill_roar", 20, 45, 13, 6.5, hit=dict(poise_damage=70, stagger_time=0.9),
               trigger_time=0.55, duration=1.35, cancel_start=1.1, tracking=0, track_until=0, caster_shake=0.8, **_NI),
        x_buff("iron_defense", "Fortaleza", (0.85, 0.8, 0.7), "skill_boost", 50, 24, 10, dmg=1.2, speed=0.9, heal=0.15,
               duration=1.4, **_NI),
        x_area("explosion", "Explosión", (1.0, 0.5, 0.15), "skill_cast", 40, 70, 30, 5.0,
               hit=dict(poise_damage=120, guard_stamina_damage=70, stagger_time=1.1, knockback=11, hitstop=0.16),
               anim_speed=0.7, trigger_time=0.95, duration=1.7, cancel_start=1.5, tracking=0, track_until=0,
               caster_shake=1.0, **_NI),
        x_channel("rock_tomb", "Tumba rocas", _E, "skill_shot", 4.5, 35, 9, hit=dict(poise_damage=9, knockback=1.5),
                  cone_range=5.0, cone_angle_deg=28, origin_offset=(0, 1.3, -0.9), fx_socket='&"chest"', **_NI),
        x_proj("rock_blast", "Pedrada", _E, "skill_shot", 8, 25, 5, hit=dict(stagger_time=0.3, knockback=2.5),
               duration=1.05, cancel_start=0.9, track_until=0.8, spawn_time=0.28, speed=19, radius=0.4, lifetime=2.0,
               homing=0.8, explode_radius=0.0, visual_scale=0.8, count=3, interval=0.18, spawn_offset=(0, 1.5, -1.3), **_NI),
        x_area("stomp", "Pisotón", _E, "skill_kick", 16, 20, 6, 3.2, hit=dict(poise_damage=45), anim_speed=1.3,
               trigger_time=0.38, duration=0.95, cancel_start=0.78, **_NI),
        x_area("rock_slide", "Avalancha", (0.9, 0.8, 0.55), "skill_claw", 12, 45, 15, 4.5,
               hit=dict(poise_damage=100, guard_stamina_damage=0, stagger_time=1.0, knockback=4, unblockable=True),
               trigger_time=0.55, duration=1.3, cancel_start=1.05, **_NI),
        x_buff("rock_polish", "Pulimento", (0.8, 0.9, 1.0), "skill_boost", 40, 20, 8, speed=1.35, rate=1.15, duration=1.3, **_NI),
    ],
    "mewtwo": [
        x_proj("aura_sphere", "Esfera aural", _PSY, "skill_shot", 20, 25, 4, hit=dict(knockback=4, hitstop=0.06),
               anim_speed=2.3, speed=18, radius=0.5, lifetime=2.6, homing=3.0, explode_radius=1.8, visual_scale=1.2,
               spawn_offset=(0, 1.6, -1.1)),
        x_channel("psybeam", "Psicorrayo", _PSY, "skill_shot", 3.6, 35, 8, anim_speed=0.9, tracking=1.6, cone_range=9.0,
                  cone_angle_deg=9, channel_start=0.45, origin_offset=(0, 1.6, -0.9), fx_socket='&"hand_r"'),
        x_area("psychic", "Psíquico", _PSY, "skill_roar", 18, 40, 12, 6.0, hit=dict(knockback=9), anim_speed=1.6),
        x_buff("calm_mind", "Paz mental", (0.9, 0.75, 1.0), "skill_boost", 50, 20, 10, dmg=1.3, rate=1.1, anim_speed=1.7),
        x_proj("psystrike", "Onda mental", (0.95, 0.4, 1.0), "skill_shot", 34, 45, 10,
               hit=dict(stagger_time=0.8, knockback=8, hitstop=0.13), anim_speed=1.3, duration=1.2, cancel_start=1.0,
               spawn_time=0.55, speed=14, radius=0.75, lifetime=2.6, homing=0.8, explode_radius=3.2, visual_scale=2.0,
               spawn_offset=(0, 1.6, -1.2)),
        x_dash("teleport", "Teletransporte", (0.8, 0.7, 1.0), 10, 20, 5, 10.0, action="dodge", anim_speed=1.0,
               hit=dict(poise_damage=15, knockback=2), duration=0.55, cancel_start=0.4, dash_start=0.08, dash_end=0.26,
               tracking=10, track_until=0.08),
        x_area("disable", "Anulación", (0.75, 0.6, 1.0), "skill_cast", 3, 45, 16, 5.0,
               hit=dict(poise_damage=100, guard_stamina_damage=0, stagger_time=1.5, knockback=1, unblockable=True),
               anim_speed=1.3, trigger_time=0.5),
        x_proj("swift", "Rapidez", (1.0, 0.9, 0.5), "skill_shot", 5, 20, 4, hit=dict(stagger_time=0.2, knockback=1),
               anim_speed=2.3, duration=1.05, cancel_start=0.9, track_until=0.8, spawn_time=0.3, speed=22, radius=0.3,
               lifetime=1.8, homing=3.2, explode_radius=0.0, visual_scale=0.5, count=5, interval=0.1,
               spawn_offset=(0, 1.6, -1.1)),
        x_buff("recover", "Recuperación", (0.8, 1.0, 0.85), "skill_boost", 55, 26, 5, heal=0.3, speed=0.75, anim_speed=1.7),
        x_area("repulse", "Repulsión", _PSY, "skill_cast", 12, 20, 6, 3.2, hit=dict(poise_damage=45, knockback=11),
               anim_speed=1.6, trigger_time=0.3, duration=0.85, cancel_start=0.68, caster_shake=0.2),
    ],
    "ninetales": [
        x_proj("will_o_wisp", "Fuego fatuo", (0.55, 0.75, 1.0), "skill_shot", 5, 20, 4,
               hit=dict(stagger_time=0.2, knockback=1, burn_time=4.0), duration=1.0, cancel_start=0.85, track_until=0.7,
               spawn_time=0.26, speed=13, radius=0.32, lifetime=3.0, homing=3.4, explode_radius=0.0, visual_scale=0.6,
               count=3, interval=0.16, spawn_offset=(0, 1.1, -1.0)),
        x_channel("fire_breath", "Aliento ígneo", _FIRE, "skill_shot", 3.4, 35, 7, hit=dict(burn_time=1.0), cone_range=6.0,
                  cone_angle_deg=22, origin_offset=(0, 1.1, -0.8)),
        x_area("fire_ring", "Anillo ígneo", (1.0, 0.45, 0.15), "skill_tail", 16, 35, 11, 5.0, hit=dict(burn_time=3.0),
               anim_speed=1.5, trigger_time=0.5),
        x_buff("sunny_day", "Día soleado", (1.0, 0.9, 0.5), "skill_boost", 50, 20, 10, dmg=1.3, speed=1.1),
        x_proj("inferno", "Infierno", (1.0, 0.35, 0.1), "skill_shot", 32, 45, 10,
               hit=dict(stagger_time=0.8, knockback=7, hitstop=0.12, burn_time=5.0), anim_speed=1.1, duration=1.2,
               cancel_start=1.0, spawn_time=0.55, speed=13, radius=0.7, lifetime=2.6, homing=0.6, explode_radius=3.2,
               visual_scale=1.9, spawn_offset=(0, 1.1, -1.0)),
        x_dash("flame_charge", "Nitrocarga", _FIRE, 18, 25, 6, 8.0, action="skill_body", hit=dict(burn_time=2.0),
               offset=(0, 0.8, -0.8)),
        x_area("confuse_ray", "Rayo confuso", (0.8, 0.6, 1.0), "skill_mind", 2, 45, 16, 5.0,
               hit=dict(poise_damage=100, guard_stamina_damage=0, stagger_time=1.6, knockback=1, unblockable=True),
               trigger_time=0.5),
        x_proj("extrasensory", "Paranormal", (0.9, 0.6, 1.0), "skill_mind", 16, 25, 5, hit=dict(knockback=3),
               anim_speed=1.8, speed=26, radius=0.4, lifetime=1.8, homing=2.2, explode_radius=0.0, visual_scale=0.9,
               spawn_offset=(0, 1.1, -1.0)),
        x_channel("fire_spin_n", "Giro fuego", _FIRE, "skill_tail", 3.0, 25, 6, hit=dict(burn_time=1.0), anim_speed=1.3,
                  duration=1.3, cancel_start=1.1, tracking=5, track_until=1.05, move_factor=0.6, channel_start=0.2,
                  channel_end=1.05, tick_interval=0.13, cone_range=3.4, cone_angle_deg=60, origin_offset=(0, 1.0, -0.6)),
        x_buff("safeguard", "Velo sagrado", (1.0, 0.95, 0.8), "skill_cast", 50, 24, 6, heal=0.22, speed=0.85),
    ],
    "mrmime": [
        x_proj("magical_leaf", "Hoja mágica", (0.6, 1.0, 0.6), "skill_shot", 6, 18, 3.5, hit=dict(stagger_time=0.2, knockback=1),
               duration=1.0, cancel_start=0.85, track_until=0.7, spawn_time=0.26, speed=20, radius=0.3, lifetime=2.0,
               homing=3.0, explode_radius=0.0, visual_scale=0.55, count=3, interval=0.13, spawn_offset=(0, 1.2, -0.9)),
        x_channel("double_slap", "Doble bofetón", _MIME, "skill_punch", 3.2, 28, 6, anim_speed=1.7, duration=1.2,
                  cancel_start=1.0, tracking=5, track_until=1.0, move_factor=0.5, channel_start=0.15, channel_end=1.0,
                  tick_interval=0.14, cone_range=3.0, cone_angle_deg=50, origin_offset=(0, 1.2, -0.4), fx_socket='&"hand_r"'),
        x_area("barrier", "Barrera", (0.7, 0.9, 1.0), "skill_cast", 14, 35, 10, 4.0, hit=dict(knockback=11),
               trigger_time=0.38, duration=1.0, cancel_start=0.8),
        x_buff("mimic", "Mímica", (1.0, 0.8, 0.9), "skill_boost", 45, 20, 9, dmg=1.25, speed=1.15, rate=1.15),
        x_proj("psywave", "Psicoonda", _PSY, "skill_shot", 22, 30, 6, hit=dict(knockback=5, hitstop=0.06), speed=17,
               radius=0.5, homing=1.6, explode_radius=2.0, visual_scale=1.2, spawn_offset=(0, 1.2, -0.9)),
        x_dash("drain_punch", "Puño drenaje", _F, 20, 30, 8, 7.0, action="skill_punch", anim_speed=1.3),
        x_area("teeter_dance", "Danza caos", (1.0, 0.7, 0.9), "skill_roar", 3, 45, 16, 4.5,
               hit=dict(poise_damage=100, guard_stamina_damage=0, stagger_time=1.5, knockback=1, unblockable=True),
               trigger_time=0.5),
        x_channel("dazzling_gleam", "Brillo mágico", (1.0, 0.75, 0.95), "skill_shot", 3.4, 35, 9, cone_range=6.0,
                  cone_angle_deg=20, origin_offset=(0, 1.2, -0.7), fx_socket='&"hand_r"'),
        x_buff("wish", "Deseo", (1.0, 0.95, 0.75), "skill_cast", 50, 25, 6, heal=0.25),
        x_area("fake_out", "Sorpresa", _MIME, "skill_claw", 13, 20, 5, 3.0, hit=dict(poise_damage=45, knockback=5),
               anim_speed=1.4, trigger_time=0.3, duration=0.85, cancel_start=0.68, caster_shake=0.2),
    ],
    # --- Tercera tanda (2.ª generación en adelante; animaciones generadas con las herramientas de poke-tactics) ---
    "feraligatr": [
        x_proj("hydro_cannon", "Hidrocañón", _W, "skill_shot", 24, 30, 6, hit=dict(knockback=6, hitstop=0.08), anim_speed=2.0,
               speed=20, radius=0.55, explode_radius=2.2, visual_scale=1.4, spawn_offset=(0, 1.5, -1.3)),
        x_dash("aqua_tail", "Acua cola", _W, 24, 30, 8, 8.0, action="skill_body", anim_speed=1.6, hit=dict(knockback=8),
               radius=1.6, offset=(0, 1.1, -1.0)),
        x_area("tidal_wave", "Maremoto", _W, "skill_roar", 20, 40, 12, 5.5, hit=dict(knockback=9), anim_speed=1.6),
        x_buff("dragon_dance_f", "Danza dragón", (0.6, 0.8, 1.0), "skill_boost", 50, 20, 10, dmg=1.25, speed=1.2, rate=1.1,
               anim_speed=1.4),
        x_channel("crunch", "Triturar", _DK, "skill_bite", 5.0, 30, 8, **dict(_MELEE, cone_range=3.4, fx_socket='&"mouth"',
                  origin_offset=(0, 1.4, -0.6))),
        x_area("scary_face_f", "Cara susto", (0.7, 0.75, 1.0), "skill_roar", 4, 45, 16, 5.0, hit=_stun(1.2), anim_speed=1.6),
        x_proj("icicle", "Carámbano", _ICE, "skill_shot", 8, 25, 5, hit=_MULTI_HIT, anim_speed=2.0, speed=24, homing=1.4,
               count=3, spawn_offset=(0, 1.5, -1.3), **_MULTI),
        x_dash("superpower", "Fuerza bruta", _F, 30, 40, 11, 6.0, action="skill_body", anim_speed=1.5,
               hit=dict(poise_damage=80, stagger_time=0.9, knockback=9, hitstop=0.14), radius=1.7, offset=(0, 1.1, -1.0)),
        x_buff("rage", "Rabia", (1.0, 0.6, 0.5), "skill_boost", 45, 22, 8, dmg=1.15, heal=0.15, anim_speed=1.4),
        x_area("tail_sweep", "Barrido de cola", _W, "skill_tail", 15, 20, 6, 3.6, hit=dict(poise_damage=45, knockback=8), **_QUICK),
    ],
    "bayleef": [
        x_proj("razor_leaf", "Hoja afilada", _GR, "skill_shot", 9, 18, 3.5, hit=_MULTI_HIT, speed=26, homing=1.0, count=2,
               spawn_offset=(0, 1.1, -0.9), **_MULTI),
        x_channel("vine_whip", "Látigo cepa", _GR, "skill_shot", 3.4, 30, 7, cone_range=5.0, cone_angle_deg=16,
                  origin_offset=(0, 1.0, -0.7)),
        x_area("petal_dance", "Danza pétalo", (1.0, 0.6, 0.75), "skill_roar", 16, 35, 10, 4.5),
        x_buff("synthesis", "Síntesis", (0.7, 1.0, 0.6), "skill_boost", 50, 24, 5, heal=0.28, speed=0.8),
        x_proj("energy_ball", "Energibola", _GR, "skill_shot", 22, 30, 6, hit=dict(knockback=5, hitstop=0.06), speed=17,
               radius=0.5, homing=1.6, explode_radius=2.0, visual_scale=1.2, spawn_offset=(0, 1.1, -0.9)),
        x_dash("headbutt", "Golpe cabeza", _N, 18, 25, 7, 7.0, action="skill_horn", offset=(0, 0.9, -0.8)),
        x_area("sleep_powder", "Somnífero", (0.6, 0.9, 0.8), "skill_mind", 2, 45, 16, 4.0, hit=_stun(1.6), trigger_time=0.5),
        x_channel("poison_powder", "Polvo veneno", _T, "skill_shot", 2.5, 30, 9, hit=dict(burn_time=3.0), cone_range=4.0,
                  cone_angle_deg=40, origin_offset=(0, 1.0, -0.6)),
        x_buff("aromatherapy", "Aromaterapia", (0.9, 1.0, 0.7), "skill_cast", 45, 20, 10, dmg=1.2, speed=1.15, rate=1.1),
        x_area("frenzy_plant", "Planta feroz", (0.35, 0.8, 0.25), "skill_roar", 30, 60, 22, 5.5,
               hit=dict(poise_damage=90, stagger_time=1.0, knockback=8, hitstop=0.14), anim_speed=0.8, trigger_time=0.8,
               duration=1.5, cancel_start=1.3, caster_shake=0.8),
    ],
    "forretress": [
        x_proj("spikes", "Púas", _ST, "skill_shot", 8, 20, 4, hit=_MULTI_HIT, speed=24, homing=1.2, count=3,
               spawn_offset=(0, 0.8, -1.0), **_MULTI, **_NI),
        x_dash("gyro_ball", "Giro bola", _ST, 26, 35, 9, 9.0, action="skill_body",
               hit=dict(poise_damage=80, stagger_time=0.9, knockback=9, hitstop=0.14), dash_start=0.25, dash_end=0.7,
               duration=1.05, cancel_start=0.9, radius=1.4, offset=(0, 0.7, -0.6), **_NI),
        x_area("rapid_spin", "Giro rápido", _ST, "skill_body", 16, 25, 7, 3.5, hit=dict(poise_damage=45), **_QUICK, **_NI),
        x_buff("iron_defense_f", "Defensa férrea", (0.85, 0.9, 1.0), "skill_boost", 50, 24, 10, dmg=1.15, speed=0.9, heal=0.12, **_NI),
        x_area("self_destruct", "Autodestrucción", (1.0, 0.5, 0.15), "skill_cast", 38, 70, 30, 5.0,
               hit=dict(poise_damage=120, guard_stamina_damage=70, stagger_time=1.1, knockback=11, hitstop=0.16),
               anim_speed=0.7, trigger_time=0.95, duration=1.7, cancel_start=1.5, tracking=0, track_until=0,
               caster_shake=1.0, **_NI),
        x_proj("flash_cannon", "Foco resplandor", (0.9, 0.95, 1.0), "skill_shot", 22, 30, 6, hit=dict(knockback=5, hitstop=0.07),
               speed=30, radius=0.45, homing=0.5, explode_radius=1.6, visual_scale=1.1, spawn_offset=(0, 0.8, -1.0), **_NI),
        x_channel("mirror_shot", "Disparo espejo", (0.8, 0.9, 1.0), "skill_shot", 3.6, 35, 9, cone_range=6.0, cone_angle_deg=18,
                  origin_offset=(0, 0.8, -0.8), fx_socket='&"chest"', **_NI),
        x_area("toxic_spikes", "Púas tóxicas", _T, "skill_cast", 8, 30, 12, 4.0, hit=dict(burn_time=6.0, poise_damage=30), **_NI),
        x_area("gravity", "Gravedad", (0.7, 0.6, 1.0), "skill_cast", 4, 45, 16, 4.5, hit=_stun(1.2), trigger_time=0.5, **_NI),
        x_buff("autotomize", "Aligerar", (0.8, 0.95, 1.0), "skill_boost", 40, 20, 8, speed=1.4, rate=1.15, **_NI),
    ],
    "aipom": [
        x_proj("swift_a", "Meteoros", (1.0, 0.9, 0.5), "skill_shot", 5, 18, 3.5, hit=_MULTI_HIT, speed=22, homing=3.2, count=4,
               spawn_offset=(0, 0.8, -0.6), **_MULTI),
        x_channel("double_hit", "Doble golpe", _AP, "skill_tail", 3.0, 25, 6, **dict(_MELEE, move_factor=0.6,
                  origin_offset=(0, 0.7, -0.3))),
        x_area("tail_slap", "Golpe cola", _AP, "skill_tail", 14, 20, 6, 3.2, hit=dict(poise_damage=40, knockback=6), **_QUICK),
        x_buff("baton_pass", "Relevo", (0.9, 0.8, 1.0), "skill_boost", 40, 18, 8, speed=1.35, rate=1.2),
        x_dash("fake_out_a", "As oculto", _AP, 16, 15, 4, 7.0, action="skill_punch", anim_speed=1.5, duration=0.7,
               cancel_start=0.55, dash_start=0.12, dash_end=0.36, radius=1.0, offset=(0, 0.7, -0.6)),
        x_area("screech", "Chirrido", (1.0, 0.85, 0.5), "skill_roar", 3, 45, 16, 4.0, hit=_stun(1.2)),
        x_proj("fling", "Lanzamiento", (1.0, 0.7, 0.4), "skill_shot", 18, 25, 5, hit=dict(knockback=4), speed=20, radius=0.4,
               explode_radius=1.6, spawn_offset=(0, 0.8, -0.6)),
        x_dash("sucker_punch", "Golpe bajo", _DK, 24, 30, 9, 9.0, action="skill_tail", anim_speed=1.3, hit=dict(knockback=6),
               radius=1.1, offset=(0, 0.7, -0.6)),
        x_buff("pickup", "Recogida", (1.0, 0.95, 0.7), "skill_cast", 45, 22, 6, heal=0.2),
        x_channel("fury_swipes", "Golpes furia", _N, "skill_claw", 3.0, 28, 7, **dict(_MELEE, channel_end=1.05, cone_range=2.6,
                  origin_offset=(0, 0.7, -0.3))),
    ],
    "hitmontop": [
        x_proj("triple_wave", "Triple onda", _F, "skill_shot", 6, 20, 4, hit=_MULTI_HIT, speed=24, homing=1.4, count=3,
               spawn_offset=(0, 0.9, -0.7), **_MULTI),
        x_channel("rapid_spin_h", "Giro rápido", _F, "skill_kick", 3.2, 28, 6, **dict(_MELEE, move_factor=0.7, cone_angle_deg=90,
                  origin_offset=(0, 0.8, -0.3), fx_socket='&"foot_r"')),
        x_area("rolling_kick", "Patada giro", _F, "skill_kick", 18, 30, 9, 3.8, anim_speed=1.3, trigger_time=0.4),
        x_buff("endeavor", "Esfuerzo", (1.0, 0.8, 0.6), "skill_boost", 45, 20, 9, dmg=1.25, rate=1.15),
        x_dash("high_jump_kick", "Patada salto alta", _F, 26, 35, 10, 9.0, action="skill_kick", anim_speed=1.3,
               hit=dict(stagger_time=0.9, knockback=8, hitstop=0.13), offset=(0, 0.9, -0.7)),
        x_dash("bullet_punch", "Puño bala", _ST, 15, 15, 4, 6.0, action="skill_punch", anim_speed=1.5, duration=0.7,
               cancel_start=0.55, dash_start=0.12, dash_end=0.36, radius=1.1, offset=(0, 0.9, -0.7)),
        x_area("counter", "Contraataque", _F, "skill_body", 14, 20, 5, 2.8, hit=dict(poise_damage=45, knockback=9), **_QUICK),
        x_area("feint", "Finta", (0.9, 0.8, 1.0), "skill_cast", 6, 45, 16, 3.5, hit=_stun(1.2)),
        x_buff("agility_h", "Agilidad", (0.8, 0.95, 1.0), "skill_cast", 40, 18, 8, speed=1.3, rate=1.2),
        x_proj("shock_wave", "Onda de choque", (1.0, 0.7, 0.4), "skill_shot", 26, 40, 10, hit=_BIG_HIT,
               spawn_offset=(0, 0.9, -0.8), **dict(_BIG, explode_radius=2.6, visual_scale=1.5)),
    ],
    "houndoom": [
        x_proj("hellfire", "Fuego infernal", (1.0, 0.4, 0.2), "skill_shot", 18, 22, 4, hit=dict(burn_time=3.0, knockback=4),
               speed=22, spawn_offset=(0, 1.1, -1.0)),
        x_channel("flamethrower_h", "Lanzallamas", _FIRE, "skill_shot", 3.4, 35, 7, hit=dict(burn_time=1.0), cone_range=6.0,
                  cone_angle_deg=22, origin_offset=(0, 1.1, -0.9)),
        x_area("smog", "Humareda", (0.6, 0.35, 0.3), "skill_roar", 16, 35, 11, 4.5, hit=dict(burn_time=3.0)),
        x_buff("howl", "Aullido", (1.0, 0.6, 0.5), "skill_roar", 45, 20, 9, dmg=1.35),
        x_dash("crunch_h", "Triturar", _DK, 22, 28, 7, 8.0, action="skill_bite", hit=dict(knockback=4), offset=(0, 0.9, -0.9)),
        x_proj("overheat", "Sofoco", (1.0, 0.3, 0.1), "skill_shot", 34, 50, 11, hit=dict(_BIG_HIT, burn_time=5.0),
               spawn_offset=(0, 1.1, -1.0), **_BIG),
        x_area("mean_look", "Mal de ojo", (0.7, 0.4, 0.8), "skill_mind", 3, 45, 16, 4.5, hit=_stun(1.4), trigger_time=0.5),
        x_proj("dark_pulse_h", "Pulso oscuro", (0.55, 0.3, 0.7), "skill_shot", 7, 22, 5, hit=_MULTI_HIT, speed=16, homing=3.2,
               count=3, spawn_offset=(0, 1.1, -1.0), **dict(_MULTI, lifetime=2.8, interval=0.16)),
        x_dash("fire_fang", "Colmillo ígneo", _FIRE, 14, 15, 4, 5.0, action="skill_bite", anim_speed=1.5, duration=0.7,
               cancel_start=0.55, dash_start=0.12, dash_end=0.36, hit=dict(burn_time=3.0, knockback=3), offset=(0, 0.9, -0.9)),
        x_buff("frenzy", "Frenesí", (1.0, 0.5, 0.4), "skill_boost", 40, 18, 8, speed=1.25, rate=1.2),
    ],
    "raikou": [
        x_proj("thunderbolt", "Rayo", _EL, "skill_shot", 22, 25, 4, hit=dict(knockback=4, hitstop=0.07), speed=34, radius=0.4,
               homing=0.4, explode_radius=1.2, visual_scale=0.9, lifetime=1.2, spawn_offset=(0, 1.4, -1.3)),
        x_channel("charge_beam", "Rayo carga", _EL, "skill_shot", 3.6, 35, 8, tracking=1.6, cone_range=7.5, cone_angle_deg=10,
                  origin_offset=(0, 1.4, -1.1)),
        x_area("thunder", "Trueno", _EL, "skill_roar", 22, 45, 12, 5.5, hit=dict(hitstop=0.13, stagger_time=0.9), caster_shake=0.7),
        x_buff("charge", "Carga", (1.0, 0.95, 0.6), "skill_boost", 50, 20, 10, dmg=1.3, rate=1.1),
        x_dash("wild_charge", "Voltio cruel", _EL, 26, 35, 10, 9.0, action="skill_body",
               hit=dict(stagger_time=0.9, knockback=8, hitstop=0.13), radius=1.5, offset=(0, 1.1, -1.1)),
        x_area("thunder_wave", "Onda trueno", (1.0, 1.0, 0.6), "skill_mind", 2, 45, 16, 5.0, hit=_stun(1.6), trigger_time=0.5),
        x_proj("electro_ball", "Bola voltio", _EL, "skill_shot", 7, 22, 5, hit=_MULTI_HIT, speed=17, homing=3.2, count=3,
               spawn_offset=(0, 1.4, -1.3), **dict(_MULTI, lifetime=2.8, interval=0.16)),
        x_dash("extreme_speed", "Velocidad extrema", (1.0, 1.0, 0.8), 12, 20, 5, 11.0, action="skill_body", anim_speed=1.6,
               hit=dict(poise_damage=18, knockback=3), duration=0.6, cancel_start=0.45, dash_start=0.08, dash_end=0.3,
               radius=1.4, offset=(0, 1.1, -1.1)),
        x_area("spark", "Chispa", _EL, "skill_claw", 13, 20, 5, 3.2, hit=dict(poise_damage=45, knockback=5), **_QUICK),
        x_buff("electrify", "Electrizar", (1.0, 1.0, 0.7), "skill_cast", 40, 18, 8, speed=1.3, rate=1.15),
    ],
    "blaziken": [
        x_proj("flame_burst", "Pirotecnia", _FIRE, "skill_shot", 18, 22, 4, hit=dict(burn_time=3.0, knockback=4), speed=22,
               spawn_offset=(0, 1.5, -1.0)),
        x_dash("blaze_kick", "Patada ígnea", _FIRE, 22, 28, 7, 7.0, action="skill_kick", anim_speed=1.3,
               hit=dict(burn_time=3.0, knockback=6), offset=(0, 1.1, -0.9)),
        x_area("eruption", "Erupción", (1.0, 0.4, 0.15), "skill_roar", 20, 38, 11, 4.5, hit=dict(burn_time=3.0)),
        x_buff("speed_boost", "Impulso", (1.0, 0.8, 0.5), "skill_boost", 50, 20, 10, dmg=1.15, speed=1.25, rate=1.2),
        x_dash("brave_bird", "Pájaro osado", (1.0, 0.75, 0.5), 32, 45, 12, 10.0, action="skill_body",
               hit=dict(poise_damage=80, stagger_time=0.9, knockback=9, hitstop=0.14), radius=1.5, offset=(0, 1.2, -0.9)),
        x_channel("fire_punch", "Puño fuego", _FIRE, "skill_punch", 3.6, 30, 7, hit=dict(burn_time=1.0),
                  **dict(_MELEE, cone_range=2.8, origin_offset=(0, 1.4, -0.4))),
        x_proj("fire_blast_b", "Llamarada", (1.0, 0.35, 0.1), "skill_shot", 34, 45, 10, hit=dict(_BIG_HIT, burn_time=4.0),
               spawn_offset=(0, 1.5, -1.1), **_BIG),
        x_area("sky_uppercut", "Gancho alto", _F, "skill_punch", 15, 20, 5, 3.0, hit=dict(poise_damage=45, knockback=8), **_QUICK),
        x_area("blaze_cry", "Grito ígneo", (1.0, 0.7, 0.4), "skill_roar", 5, 45, 16, 4.5, hit=_stun(1.3)),
        x_buff("morning_sun", "Sol matinal", (1.0, 0.95, 0.7), "skill_cast", 50, 24, 6, heal=0.22, speed=0.85),
    ],
    "lucario": [
        x_proj("aura_sphere_l", "Esfera aural", _AU, "skill_shot", 20, 25, 4, hit=dict(knockback=4, hitstop=0.06), speed=18,
               radius=0.5, lifetime=2.6, homing=3.0, explode_radius=1.8, visual_scale=1.2, spawn_offset=(0, 1.3, -0.9)),
        x_channel("dragon_pulse", "Pulso dragón", _AU, "skill_shot", 3.6, 35, 8, tracking=1.6, cone_range=8.0, cone_angle_deg=10,
                  origin_offset=(0, 1.3, -0.8), fx_socket='&"hand_r"'),
        x_area("aura_burst", "Estallido aural", _AU, "skill_roar", 18, 38, 11, 4.8, hit=dict(knockback=8)),
        x_buff("swords_dance_l", "Danza espada", (0.85, 0.9, 1.0), "skill_boost", 45, 20, 8, dmg=1.4, rate=1.05),
        x_dash("extreme_speed_l", "Velocidad extrema", (0.8, 0.9, 1.0), 14, 20, 5, 10.0, action="skill_punch", anim_speed=1.6,
               hit=dict(poise_damage=20, knockback=3), duration=0.6, cancel_start=0.45, dash_start=0.08, dash_end=0.3),
        x_channel("bone_rush", "Ataque óseo", (0.9, 0.85, 0.7), "skill_punch", 3.4, 30, 7, **dict(_MELEE, origin_offset=(0, 1.2, -0.4))),
        x_area("detect", "Detección", (0.7, 0.85, 1.0), "skill_cast", 4, 45, 16, 4.5, hit=_stun(1.4), trigger_time=0.5),
        x_proj("focus_blast_l", "Onda certera", (0.6, 0.85, 1.0), "skill_shot", 32, 45, 10, hit=_BIG_HIT,
               spawn_offset=(0, 1.3, -1.0), **dict(_BIG, explode_radius=2.8, visual_scale=1.7)),
        x_dash("power_up_punch", "Puño incremento", _F, 24, 30, 8, 7.0, action="skill_punch", anim_speed=1.3, hit=dict(knockback=6)),
        x_buff("meditate", "Meditación", (0.75, 0.9, 1.0), "skill_cast", 50, 24, 8, dmg=1.15, rate=1.1, heal=0.15),
    ],
    "zoroark": [
        x_proj("dark_pulse_z", "Pulso umbrío", _DK, "skill_shot", 20, 25, 4, hit=dict(knockback=4, hitstop=0.06), speed=20,
               radius=0.5, explode_radius=1.8, visual_scale=1.2, spawn_offset=(0, 1.3, -0.9)),
        x_channel("shadow_claw", "Garra umbría", _DK, "skill_claw", 3.4, 28, 6, **dict(_MELEE, origin_offset=(0, 1.2, -0.4))),
        x_area("night_daze", "Pulso noche", (0.7, 0.15, 0.3), "skill_roar", 18, 38, 11, 5.0, hit=dict(knockback=7)),
        x_buff("illusion", "Ilusión", (1.0, 0.6, 0.7), "skill_boost", 50, 20, 10, dmg=1.3, speed=1.15),
        x_dash("foul_play", "Juego sucio", _DK, 22, 28, 8, 9.0, action="skill_claw", anim_speed=1.3, hit=dict(knockback=5)),
        x_proj("grudge", "Rencor", (0.6, 0.3, 0.7), "skill_shot", 7, 22, 5, hit=_MULTI_HIT, speed=15, homing=3.4, count=3,
               spawn_offset=(0, 1.3, -0.9), **dict(_MULTI, lifetime=2.8, interval=0.16)),
        x_area("taunt", "Mofa", (1.0, 0.5, 0.6), "skill_cast", 3, 45, 16, 4.5, hit=_stun(1.4), trigger_time=0.5),
        x_dash("feint_attack", "Finta", (0.8, 0.4, 0.5), 12, 15, 3.5, 6.0, action="skill_kick", anim_speed=1.5, duration=0.65,
               cancel_start=0.5, dash_start=0.1, dash_end=0.32, hit=dict(poise_damage=18, knockback=3)),
        x_proj("night_slash", "Corte vacío", (0.9, 0.2, 0.4), "skill_shot", 28, 40, 9, hit=_BIG_HIT, spawn_offset=(0, 1.3, -1.0),
               **dict(_BIG, speed=22, anim_speed=1.3, spawn_time=0.45, duration=1.05, cancel_start=0.88, explode_radius=2.2,
                      visual_scale=1.4)),
        x_buff("snatch", "Robo", (1.0, 0.7, 0.8), "skill_cast", 45, 22, 6, heal=0.2, speed=1.1),
    ],
}


def v2(x, y):
    return f"Vector2({x}, {y})"


# ---------------------------------------------------------------------------------------------------
def main():
    # Charizard: solo su CharacterDef (su kit está hecho a mano).
    make_def("charizard", "Charizard", "Equilibrado",
             "Dragón de fuego versátil. Quema a distancia y aguanta bien el cuerpo a cuerpo.",
             (1.0, 0.55, 0.2), {}, (0.55, 2.0, 1.3), (3, 3, 3, 4))
    # Su moveset reutiliza los ataques y las 4 habilidades hechas a mano; solo se añaden las extra del catálogo.
    make_moveset("charizard", {}, [f"res://combat/abilities/charizard/{n}.tres"
                                   for n in ["fireball", "flamethrower", "roar", "dragon_dance"]], {
        "LH": make_combo("running", "Cabezazo", dmg=0.8, extra={"lunge_speed": 6, "knockback": 7}),
        "LLH": make_combo("heavy_1", "Garra dragón", t=0.85, dmg=1.0, extra={"burn_time": 2.0}),
        "LLLH": make_combo("heavy_2", "Picado", t=0.9, dmg=1.05),
        "HL": make_combo("light_3", "Coletazo de remate", t=0.9, dmg=1.0),
    })

    # Scyther: rápido, frágil, combos cortos.
    G = (0.55, 1.0, 0.4)
    make_moveset("scyther", {
        "light_1": make_attack("light_1", "Tajo", t=0.8, dmg=0.85, reach=1.1),
        "light_2": make_attack("light_2", "Corte cruzado", t=0.8, dmg=0.85, reach=1.1),
        "light_3": make_attack("light_3", "Tajo giratorio", t=0.85, dmg=0.85, reach=0.9),
        "heavy_1": make_attack("heavy_1", "Guillotina", t=0.85, dmg=0.9, reach=1.15),
        "heavy_2": make_attack("heavy_2", "Tijera", t=0.85, dmg=0.9, reach=1.15),
        "running": make_attack("running", "Ataque rápido", t=0.8, dmg=0.85, extra={"lunge_speed": 10}),
    }, [
        make_ability("scyther", "air_slash", "projectile", "Aire afilado", G, "skill_air_slash",
                     hit=dict(damage=14, poise_damage=20, guard_stamina_damage=18, knockback=2.5),
                     anim_speed=2.0, heat_cost=15, cooldown=2.5, duration=0.6, cancel_start=0.45, tracking=8, track_until=0.25,
                     spawn_time=0.22, spawn_offset=(0, 1.4, -1.0), speed=28, radius=0.35, lifetime=1.2, homing=0.5,
                     explode_radius=0.9, visual_scale=0.7),
        make_ability("scyther", "fury_cutter", "channel", "Corte furia", G, "skill_fury_cutter",
                     hit=dict(damage=3.2, poise_damage=7, guard_stamina_damage=8, stagger_time=0.3, knockback=0.5),
                     anim_speed=1.6, heat_cost=30, cooldown=6, duration=1.2, cancel_start=1.0, tracking=5, track_until=1.0,
                     move_factor=0.5, channel_start=0.15, channel_end=1.0, tick_interval=0.12, cone_range=3.0,
                     cone_angle_deg=45, origin_offset=(0, 1.3, -0.5), fx_socket='&"hand_r"'),
        make_ability("scyther", "x_scissor", "area", "Tijera X", G, "skill_x_scissor",
                     hit=dict(damage=18, poise_damage=60, guard_stamina_damage=40, stagger_time=0.8, knockback=6, hitstop=0.1),
                     heat_cost=35, cooldown=10, duration=1.0, cancel_start=0.8, tracking=6, track_until=0.3,
                     trigger_time=0.35, radius=3.5, caster_shake=0.3),
        make_ability("scyther", "swords_dance", "buff", "Danza espadas", (0.85, 1.0, 0.85), "skill_swords_dance",
                     heat_cost=45, cooldown=20, duration=1.1, cancel_start=0.9, tracking=0, track_until=0,
                     buff_id='&"danza_espadas"', trigger_time=0.4, buff_duration=8, damage_multiplier=1.4,
                     speed_multiplier=1.0, action_speed_multiplier=1.05),
    ], {
        "LH": make_combo("running", "Tajo relámpago", t=0.75, dmg=0.75, extra={"lunge_speed": 11}),
        "LLH": make_combo("heavy_2", "Corte doble", t=0.7, dmg=0.8, reach=1.15),
        "LLLH": make_combo("heavy_1", "Ejecución", t=0.8, dmg=1.3, poise=1.3, reach=1.15),
        "HL": make_combo("light_3", "Contratajo", t=0.7, dmg=0.9, reach=0.9),
    })
    make_def("scyther", "Scyther", "Asesino veloz",
             "Cuchillas rapidísimas y gran movilidad, pero poca vida y postura. Golpea y sal.",
             G, {"max_health": 95.0, "jog_speed": 5.2, "sprint_speed": 8.6, "strafe_speed": 3.8, "max_poise": 5.0,
                 "max_stamina": 110.0, "dodge_distance": 5.2},
             (0.5, 2.0, 1.3), (2, 5, 3, 2))

    # Gengar: esquivo, control con hipnosis.
    P = (0.62, 0.3, 1.0)
    make_moveset("gengar", {
        "light_1": make_attack("light_1", "Arañazo", dmg=0.9),
        "light_2": make_attack("light_2", "Puño sombra", dmg=0.9),
        "light_3": make_attack("light_3", "Lengüetazo", dmg=0.95, extra={"heat_gain": 12}),
        "heavy_1": make_attack("heavy_1", "Mordisco fantasma", dmg=0.95),
        "heavy_2": make_attack("heavy_2", "Golpe umbrío", dmg=0.95),
        "running": make_attack("running", "Sombra vil", dmg=0.9, extra={"lunge_speed": 9}),
    }, [
        make_ability("gengar", "shadow_ball", "projectile", "Bola sombra", P, "skill_shadow_ball",
                     hit=dict(damage=22, poise_damage=30, guard_stamina_damage=25, knockback=4.5, hitstop=0.06),
                     anim_speed=1.6, heat_cost=25, cooldown=4, duration=0.85, cancel_start=0.65, tracking=6, track_until=0.3,
                     spawn_time=0.32, spawn_offset=(0, 1.2, -1.0), speed=14, radius=0.5, lifetime=2.5, homing=2.0,
                     explode_radius=2.2, visual_scale=1.3),
        make_ability("gengar", "dark_pulse", "channel", "Pulso umbrío", P, "skill_dark_pulse",
                     hit=dict(damage=3.2, poise_damage=4, guard_stamina_damage=6, stagger_time=0.3, knockback=0.8),
                     heat_cost=35, cooldown=8, duration=1.6, cancel_start=1.4, tracking=1.8, track_until=1.35,
                     channel_start=0.3, channel_end=1.35, tick_interval=0.15, cone_range=6.5, cone_angle_deg=22,
                     origin_offset=(0, 1.0, -0.6)),
        make_ability("gengar", "hypnosis", "area", "Hipnosis", (0.9, 0.5, 1.0), "skill_hypnosis",
                     hit=dict(damage=2, poise_damage=100, guard_stamina_damage=0, stagger_time=1.8, knockback=1, hitstop=0.1, unblockable=True),
                     heat_cost=45, cooldown=16, duration=1.3, cancel_start=1.0, tracking=4, track_until=0.4,
                     trigger_time=0.5, radius=5.0, caster_shake=0.3),
        make_ability("gengar", "nasty_plot", "buff", "Maquinación", (0.75, 0.35, 1.0), "skill_nasty_plot",
                     heat_cost=50, cooldown=20, duration=1.3, cancel_start=1.0, tracking=0, track_until=0,
                     buff_id='&"maquinacion"', trigger_time=0.5, buff_duration=10, damage_multiplier=1.35,
                     speed_multiplier=1.1, action_speed_multiplier=1.15),
    ], {
        "LH": make_combo("light_3", "Zarpazo espectral", t=0.9, dmg=1.0, extra={"heat_gain": 14}),
        "LLH": make_combo("heavy_2", "Doble puño sombra", t=0.9, dmg=0.95, extra={"heat_gain": 20}),
        "LLLH": make_combo("heavy_1", "Garra umbría", t=0.9, dmg=1.05, extra={"knockback": 7}),
        "HL": make_combo("running", "Finta sombría", t=0.9, dmg=0.8, extra={"lunge_speed": 9}),
    })
    make_def("gengar", "Gengar", "Embaucador",
             "Esquivas largas con mucha invulnerabilidad. Proyectiles teledirigidos e hipnosis que aturde.",
             P, {"max_health": 95.0, "jog_speed": 4.6, "max_poise": 8.0, "dodge_distance": 5.5,
                 "dodge_iframes": v2(0.02, 0.46)},
             (0.6, 1.8, 1.1), (3, 4, 3, 4))

    # Snorlax: tanque lento, golpes enormes.
    N = (1.0, 0.92, 0.65)
    E_ = (0.75, 0.55, 0.3)
    make_moveset("snorlax", {
        "light_1": make_attack("light_1", "Manotazo", t=1.15, dmg=1.1, poise=1.3, reach=1.25, extra={"hyper_armor": 20}),
        "light_2": make_attack("light_2", "Pisotón", t=1.15, dmg=1.1, poise=1.3, reach=1.25, extra={"hyper_armor": 20}),
        "light_3": make_attack("light_3", "Panzazo", t=1.15, dmg=1.1, poise=1.3, reach=1.25, extra={"hyper_armor": 30}),
        "heavy_1": make_attack("heavy_1", "Golpe cuerpo", t=1.2, dmg=1.15, poise=1.35, reach=1.3, extra={"hyper_armor": 80}),
        "heavy_2": make_attack("heavy_2", "Mordisco voraz", t=1.2, dmg=1.15, poise=1.35, reach=1.3, extra={"hyper_armor": 80}),
        "running": make_attack("running", "Avalancha", t=1.1, dmg=1.1, poise=1.3, reach=1.25, extra={"hyper_armor": 60}),
    }, [
        make_ability("snorlax", "hyper_beam", "channel", "Hiperrayo", N, "skill_hyper_beam",
                     hit=dict(damage=4.5, poise_damage=8, guard_stamina_damage=10, stagger_time=0.35, knockback=1.2),
                     interruptible=False, anim_speed=0.75, heat_cost=45, cooldown=12, duration=2.2, cancel_start=2.0, tracking=1.2, track_until=1.9,
                     channel_start=0.6, channel_end=1.9, tick_interval=0.12, cone_range=10.0, cone_angle_deg=8,
                     origin_offset=(0, 2.0, -0.8)),
        make_ability("snorlax", "body_slam", "area", "Golpe cuerpo", E_, "skill_body_slam",
                     hit=dict(damage=30, poise_damage=70, guard_stamina_damage=50, stagger_time=0.9, knockback=8, hitstop=0.14),
                     interruptible=False, heat_cost=30, cooldown=8, duration=1.1, cancel_start=0.9, tracking=5, track_until=0.35,
                     trigger_time=0.45, radius=3.2, caster_shake=0.5),
        make_ability("snorlax", "earthquake", "area", "Terremoto", E_, "skill_earthquake",
                     hit=dict(damage=15, poise_damage=70, guard_stamina_damage=0, stagger_time=1.0, knockback=5, hitstop=0.1, unblockable=True),
                     interruptible=False, heat_cost=45, cooldown=15, duration=1.4, cancel_start=1.1, tracking=0, track_until=0,
                     trigger_time=0.55, radius=8.0, caster_shake=0.8),
        make_ability("snorlax", "rest", "buff", "Descanso", (0.6, 0.8, 1.0), "skill_rest",
                     interruptible=False, heat_cost=60, cooldown=30, duration=1.6, cancel_start=1.4, tracking=0, track_until=0,
                     buff_id='&"descanso"', trigger_time=0.6, buff_duration=4, damage_multiplier=1.0,
                     speed_multiplier=0.6, action_speed_multiplier=0.85, heal=0.35),
    ], {
        "LH": make_combo("running", "Empujón", t=1.0, dmg=0.9, poise=1.3, reach=1.25, extra={"hyper_armor": 40, "knockback": 9}),
        "LLH": make_combo("heavy_2", "Plancha", t=1.05, dmg=1.1, poise=1.5, reach=1.3, extra={"hyper_armor": 80, "knockback": 8}),
        "LLLH": make_combo("heavy_1", "Mazazo", t=1.15, dmg=1.2, poise=1.6, reach=1.3, extra={"hyper_armor": 80}),
        "HL": make_combo("light_3", "Bofetón", t=1.0, dmg=1.1, poise=1.3, reach=1.25, extra={"hyper_armor": 30}),
    })
    make_def("snorlax", "Snorlax", "Tanque",
             "Enorme y lento. Mucha vida y armadura en casi todos sus golpes; el Terremoto no se puede bloquear.",
             N, {"max_health": 150.0, "jog_speed": 3.6, "sprint_speed": 6.0, "strafe_speed": 2.6, "max_poise": 30.0,
                 "max_stamina": 120.0, "dodge_distance": 3.4, "turn_speed": 9.0, "walk_anim_speed": 2.0},
             (0.85, 2.6, 1.6), (5, 1, 5, 3))

    # Beedrill: agresivo, veneno (usa la quemadura como daño en el tiempo).
    Y = (0.85, 1.0, 0.25)
    T = (0.7, 0.3, 1.0)
    make_moveset("beedrill", {
        "light_1": make_attack("light_1", "Picotazo", t=0.85, dmg=0.85, reach=1.15, extra={"burn_time": 1.0}),
        "light_2": make_attack("light_2", "Aguijón", t=0.85, dmg=0.85, reach=1.15, extra={"burn_time": 1.0}),
        "light_3": make_attack("light_3", "Doble ataque", t=0.85, dmg=0.85, reach=1.0, extra={"burn_time": 1.5}),
        "heavy_1": make_attack("heavy_1", "Puya nociva", t=0.9, dmg=0.9, reach=1.2, extra={"burn_time": 3.0}),
        "heavy_2": make_attack("heavy_2", "Embestida venenosa", t=0.9, dmg=0.9, reach=1.2, extra={"burn_time": 3.0}),
        "running": make_attack("running", "Ida y vuelta", t=0.85, dmg=0.85, extra={"lunge_speed": 10, "burn_time": 2.0}),
    }, [
        make_ability("beedrill", "pin_missile", "projectile", "Pin misil", Y, "skill_pin_missile",
                     hit=dict(damage=6, poise_damage=8, guard_stamina_damage=8, stagger_time=0.25, knockback=1, hitstop=0.02, burn_time=1.5),
                     anim_speed=1.8, heat_cost=15, cooldown=2.5, duration=0.85, cancel_start=0.7, tracking=8, track_until=0.6,
                     spawn_time=0.2, spawn_offset=(0, 1.4, -1.0), speed=30, radius=0.25, lifetime=1.2, homing=2.0,
                     explode_radius=0.0, visual_scale=0.45, count=3, interval=0.12),
        make_ability("beedrill", "twineedle", "channel", "Pin furia", Y, "skill_twineedle",
                     hit=dict(damage=4, poise_damage=6, guard_stamina_damage=8, stagger_time=0.3, knockback=0.5, burn_time=2.0),
                     anim_speed=1.5, heat_cost=30, cooldown=7, duration=1.2, cancel_start=1.0, tracking=5, track_until=1.0,
                     move_factor=0.6, channel_start=0.15, channel_end=1.0, tick_interval=0.16, cone_range=3.2,
                     cone_angle_deg=35, origin_offset=(0, 1.3, -0.6), fx_socket='&"hand_r"'),
        make_ability("beedrill", "toxic_burst", "area", "Bomba tóxica", T, "skill_toxic_burst",
                     hit=dict(damage=10, poise_damage=50, guard_stamina_damage=30, stagger_time=0.7, knockback=4, hitstop=0.08, burn_time=5.0),
                     heat_cost=40, cooldown=14, duration=1.2, cancel_start=0.9, tracking=3, track_until=0.4,
                     trigger_time=0.45, radius=5.0, caster_shake=0.4),
        make_ability("beedrill", "agility", "buff", "Agilidad", (0.95, 0.95, 0.4), "skill_agility",
                     heat_cost=40, cooldown=18, duration=0.9, cancel_start=0.7, tracking=0, track_until=0,
                     buff_id='&"agilidad"', trigger_time=0.3, buff_duration=8, damage_multiplier=1.0,
                     speed_multiplier=1.4, action_speed_multiplier=1.2),
    ], {
        "LH": make_combo("running", "Pin misil", t=0.8, dmg=0.75, extra={"lunge_speed": 10, "burn_time": 2.0}),
        "LLH": make_combo("heavy_1", "Aguijón letal", t=0.8, dmg=0.9, reach=1.2, extra={"burn_time": 4.0}),
        "LLLH": make_combo("heavy_2", "Estocada tóxica", t=0.85, dmg=1.0, reach=1.2, extra={"burn_time": 5.0}),
        "HL": make_combo("light_3", "Doble picotazo", t=0.75, dmg=0.85, extra={"burn_time": 2.0}),
    })
    make_def("beedrill", "Beedrill", "Hostigador",
             "Rápido y venenoso: casi todos sus golpes envenenan. Presiona sin parar.",
             Y, {"max_health": 95.0, "jog_speed": 5.0, "sprint_speed": 8.5, "strafe_speed": 3.6, "max_poise": 6.0},
             (0.5, 2.0, 1.4), (2, 4, 3, 3))

    # Vaporeon: control a media distancia con agua, se cura.
    W = (0.3, 0.62, 1.0)
    make_moveset("vaporeon", {
        "light_1": make_attack("light_1", "Mordisco", dmg=0.95),
        "light_2": make_attack("light_2", "Patada", dmg=0.95),
        "light_3": make_attack("light_3", "Cola férrea", dmg=1.0),
        "heavy_1": make_attack("heavy_1", "Placaje", dmg=0.95),
        "heavy_2": make_attack("heavy_2", "Golpe de agua", dmg=0.95),
        "running": make_attack("running", "Acua jet", dmg=0.9, extra={"lunge_speed": 10}),
    }, [
        make_ability("vaporeon", "water_pulse", "projectile", "Hidropulso", W, "skill_water_pulse",
                     hit=dict(damage=16, poise_damage=40, guard_stamina_damage=25, stagger_time=0.6, knockback=6, hitstop=0.06),
                     anim_speed=1.8, heat_cost=20, cooldown=3, duration=0.8, cancel_start=0.6, tracking=6, track_until=0.3,
                     spawn_time=0.3, spawn_offset=(0, 1.0, -1.2), speed=20, radius=0.45, lifetime=2.0, homing=1.0,
                     explode_radius=2.0, visual_scale=1.1),
        make_ability("vaporeon", "hydro_pump", "channel", "Hidrobomba", W, "skill_hydro_pump",
                     hit=dict(damage=4, poise_damage=6, guard_stamina_damage=8, stagger_time=0.3, knockback=1.5),
                     heat_cost=40, cooldown=9, duration=1.7, cancel_start=1.5, tracking=1.8, track_until=1.45,
                     channel_start=0.35, channel_end=1.45, tick_interval=0.15, cone_range=7.5, cone_angle_deg=18,
                     origin_offset=(0, 1.0, -0.9)),
        make_ability("vaporeon", "surf", "area", "Surf", (0.4, 0.75, 1.0), "skill_surf",
                     hit=dict(damage=14, poise_damage=60, guard_stamina_damage=35, stagger_time=0.8, knockback=9, hitstop=0.1),
                     heat_cost=45, cooldown=14, duration=1.4, cancel_start=1.1, tracking=3, track_until=0.4,
                     trigger_time=0.55, radius=7.0, caster_shake=0.5),
        make_ability("vaporeon", "aqua_ring", "buff", "Acua aro", (0.5, 0.85, 1.0), "skill_aqua_ring",
                     heat_cost=50, cooldown=25, duration=1.3, cancel_start=1.0, tracking=0, track_until=0,
                     buff_id='&"acua_aro"', trigger_time=0.5, buff_duration=12, damage_multiplier=1.1,
                     speed_multiplier=1.0, action_speed_multiplier=1.0, heal=0.25),
    ], {
        "LH": make_combo("running", "Acometida", dmg=0.8, extra={"lunge_speed": 9}),
        "LLH": make_combo("heavy_2", "Coletazo acuático", t=0.9, dmg=0.95, extra={"knockback": 8}),
        "LLLH": make_combo("heavy_1", "Cascada", t=0.9, dmg=1.0),
        "HL": make_combo("light_3", "Giro de cola", dmg=1.0, extra={"knockback": 6}),
    })
    make_def("vaporeon", "Vaporeon", "Controlador",
             "Mucho aguante y control a media distancia: empuja con agua y se cura.",
             W, {"max_health": 120.0, "jog_speed": 4.4, "max_poise": 12.0},
             (0.6, 1.5, 1.0), (4, 3, 2, 5))
    # ---------------------------------------------------------------------------------------------
    # Segunda tanda. Sus 10 habilidades están en EXTRA_KITS; los remates usan clips distintos a los
    # de la cadena normal (acciones skill_punch/kick/body... del visual).

    # Machop: luchador pequeño y rápido, cadenas largas y poco alcance.
    make_moveset("machop", {
        "light_1": make_attack("light_1", "Golpe kárate", t=0.8, dmg=0.85, reach=0.85),
        "light_2": make_attack("light_2", "Puño certero", t=0.8, dmg=0.85, reach=0.85),
        "light_3": make_attack("light_3", "Patada baja", t=0.85, dmg=0.9, reach=0.75),
        "heavy_1": make_attack("heavy_1", "Patada giro", t=0.85, dmg=0.9, reach=0.9),
        "heavy_2": make_attack("heavy_2", "Tacleada", t=0.85, dmg=0.9, reach=0.9),
        "running": make_attack("running", "Golpe bajo", t=0.8, dmg=0.85, reach=0.9, extra={"lunge_speed": 10}),
    }, [], {
        "LH": make_combo("light_3", "Gancho", "skill_kick", t=0.75, dmg=0.9, reach=0.8, extra={"knockback": 6}),
        "LLH": make_combo("heavy_2", "Tajo cruzado", "skill_punch", t=0.75, dmg=0.85, reach=0.9),
        "LLLH": make_combo("heavy_1", "Demolición", "skill_body", t=0.85, dmg=1.15, poise=1.4, reach=0.95, extra={"knockback": 8}),
        "HL": make_combo("light_1", "Puño bala", "skill_punch", t=0.7, dmg=1.0, reach=0.9, extra={"lunge_speed": 7}),
    })
    make_def("machop", "Machop", "Luchador",
             "Pequeño, rápido y con cadenas largas. Tiene que pegarse al rival: casi no tiene alcance.",
             _F, {"max_health": 100.0, "jog_speed": 5.0, "sprint_speed": 8.2, "strafe_speed": 3.6, "max_poise": 9.0,
                  "max_stamina": 115.0},
             (0.45, 1.5, 1.0), (3, 4, 3, 1))

    # Poliwrath: fajador con armadura en los fuertes y agua para empujar.
    make_moveset("poliwrath", {
        "light_1": make_attack("light_1", "Puñetazo", dmg=1.0, reach=1.0),
        "light_2": make_attack("light_2", "Patada", dmg=1.0, reach=1.0),
        "light_3": make_attack("light_3", "Gancho alto", dmg=1.05, reach=0.9),
        "heavy_1": make_attack("heavy_1", "Golpe cuerpo", t=1.05, dmg=1.05, reach=1.05, extra={"hyper_armor": 60}),
        "heavy_2": make_attack("heavy_2", "Machada", t=1.05, dmg=1.05, reach=1.05, extra={"hyper_armor": 60}),
        "running": make_attack("running", "Placaje", dmg=1.0, extra={"lunge_speed": 9, "hyper_armor": 30}),
    }, [], {
        "LH": make_combo("running", "Empellón", "skill_body", dmg=0.85, extra={"knockback": 8, "hyper_armor": 30}),
        "LLH": make_combo("heavy_1", "Gancho hidráulico", "skill_punch", t=0.9, dmg=1.0, extra={"hyper_armor": 60}),
        "LLLH": make_combo("heavy_2", "Puño certero", "skill_punch", t=0.95, dmg=1.15, poise=1.4, extra={"hyper_armor": 60}),
        "HL": make_combo("light_3", "Patada circular", "skill_kick", t=0.9, dmg=1.05, extra={"knockback": 6}),
    })
    make_def("poliwrath", "Poliwrath", "Fajador",
             "Aguanta el intercambio: armadura en sus golpes fuertes, mucha vida y agua para apartar al rival.",
             _W, {"max_health": 125.0, "jog_speed": 4.3, "sprint_speed": 7.0, "max_poise": 16.0, "max_stamina": 110.0},
             (0.6, 1.9, 1.25), (4, 2, 4, 2))

    # Golem: coloso de roca; lentísimo, armadura en todo y área enorme.
    make_moveset("golem", {
        "light_1": make_attack("light_1", "Puño roca", t=1.2, dmg=1.1, poise=1.4, reach=1.2, extra={"hyper_armor": 25}),
        "light_2": make_attack("light_2", "Zarpa pétrea", t=1.2, dmg=1.1, poise=1.4, reach=1.2, extra={"hyper_armor": 25}),
        "light_3": make_attack("light_3", "Pisotón", t=1.2, dmg=1.1, poise=1.4, reach=1.2, extra={"hyper_armor": 35}),
        "heavy_1": make_attack("heavy_1", "Embate", t=1.25, dmg=1.12, poise=1.5, reach=1.25, extra={"hyper_armor": 90}),
        "heavy_2": make_attack("heavy_2", "Machacar", t=1.25, dmg=1.12, poise=1.5, reach=1.25, extra={"hyper_armor": 90}),
        "running": make_attack("running", "Desenrollar", t=1.1, dmg=1.15, poise=1.4, reach=1.2, extra={"hyper_armor": 70}),
    }, [], {
        "LH": make_combo("running", "Cabezazo", "skill_body", t=1.05, dmg=0.95, poise=1.4, reach=1.2, extra={"hyper_armor": 50, "knockback": 9}),
        "LLH": make_combo("heavy_2", "Roca afilada", "skill_claw", t=1.1, dmg=1.15, poise=1.6, reach=1.25, extra={"hyper_armor": 90}),
        "LLLH": make_combo("heavy_1", "Martillazo", "skill_punch", t=1.2, dmg=1.15, poise=1.8, reach=1.3, extra={"hyper_armor": 90, "knockback": 8}),
        "HL": make_combo("light_3", "Patada sísmica", "skill_kick", t=1.05, dmg=1.15, poise=1.4, reach=1.2, extra={"hyper_armor": 35}),
    })
    make_def("golem", "Golem", "Coloso",
             "El más duro y el más lento. Nada lo interrumpe y sus áreas son enormes, pero cada golpe se ve venir.",
             _E, {"max_health": 160.0, "jog_speed": 3.4, "sprint_speed": 5.8, "strafe_speed": 2.4, "max_poise": 34.0,
                  "max_stamina": 120.0, "dodge_distance": 3.2, "turn_speed": 8.0, "walk_anim_speed": 2.0},
             (0.85, 2.0, 1.3), (5, 1, 5, 3))

    # Mewtwo: psíquico de largo alcance; pega fuerte con habilidades caras.
    make_moveset("mewtwo", {
        "light_1": make_attack("light_1", "Palma psíquica", dmg=0.95, reach=1.25),
        "light_2": make_attack("light_2", "Barrido", dmg=0.95, reach=1.25),
        "light_3": make_attack("light_3", "Coletazo", dmg=1.0, reach=1.15),
        "heavy_1": make_attack("heavy_1", "Corte psíquico", dmg=1.0, reach=1.3),
        "heavy_2": make_attack("heavy_2", "Látigo", dmg=1.0, reach=1.3),
        "running": make_attack("running", "Acometida mental", dmg=0.95, reach=1.2, extra={"lunge_speed": 10}),
    }, [], {
        "LH": make_combo("light_3", "Golpe cinético", "attack_heavy_2", t=0.9, dmg=1.0, reach=1.2, extra={"knockback": 8}),
        "LLH": make_combo("heavy_1", "Psicocorte", "attack_light_1", t=0.85, dmg=0.95, reach=1.35, extra={"heat_gain": 20}),
        "LLLH": make_combo("heavy_2", "Colapso", "attack_heavy_1", t=0.95, dmg=1.15, poise=1.4, reach=1.35, extra={"knockback": 8}),
        "HL": make_combo("running", "Destello", "attack_light_1", t=0.85, dmg=0.85, reach=1.2, extra={"lunge_speed": 9}),
    })
    make_def("mewtwo", "Mewtwo", "Psíquico",
             "Domina la media y larga distancia con psíquicos potentes y un teletransporte. Sus habilidades cuestan mucho Calor.",
             _PSY, {"max_health": 100.0, "jog_speed": 4.8, "sprint_speed": 7.8, "max_poise": 10.0, "dodge_distance": 5.4,
                    "block_pose": 0.9},
             (0.55, 2.3, 1.55), (3, 4, 4, 5))

    # Ninetales: zorra de fuego; quema, hostiga a distancia y se mueve mucho.
    make_moveset("ninetales", {
        "light_1": make_attack("light_1", "Mordisco", t=0.9, dmg=0.85),
        "light_2": make_attack("light_2", "Coletazo", t=0.9, dmg=0.85, reach=1.1),
        "light_3": make_attack("light_3", "Colmillo ígneo", t=0.9, dmg=0.85, extra={"burn_time": 2.0}),
        "heavy_1": make_attack("heavy_1", "Abanico de colas", t=0.95, dmg=0.9, reach=1.2, extra={"burn_time": 2.0}),
        "heavy_2": make_attack("heavy_2", "Embestida", t=0.95, dmg=0.9, reach=1.1),
        "running": make_attack("running", "Ataque rápido", t=0.85, dmg=0.9, extra={"lunge_speed": 10}),
    }, [], {
        "LH": make_combo("running", "Pirueta", "skill_tail", t=0.85, dmg=0.8, reach=1.1, extra={"lunge_speed": 8, "burn_time": 2.0}),
        "LLH": make_combo("heavy_1", "Rueda de fuego", "skill_tail", t=0.85, dmg=0.9, reach=1.2, extra={"burn_time": 2.0}),
        "LLLH": make_combo("heavy_2", "Estallido", "skill_body", t=0.9, dmg=1.0, reach=1.15, extra={"burn_time": 3.0, "knockback": 7}),
        "HL": make_combo("light_3", "Dentellada", "skill_body", t=0.8, dmg=0.95, extra={"burn_time": 2.0}),
    })
    make_def("ninetales", "Ninetales", "Hechicera",
             "Rápida y frágil. Casi todo lo que hace quema: desgasta desde lejos y remata con las colas.",
             _FIRE, {"max_health": 95.0, "jog_speed": 5.0, "sprint_speed": 8.4, "strafe_speed": 3.6, "max_poise": 7.0,
                     "dodge_distance": 5.2},
             (0.5, 1.5, 1.0), (2, 4, 3, 4))

    # Mr. Mime: ilusionista; control del espacio con barreras y empujones.
    make_moveset("mrmime", {
        "light_1": make_attack("light_1", "Bofetón", t=0.95, dmg=0.9, reach=1.05),
        "light_2": make_attack("light_2", "Palmada", t=0.95, dmg=0.9, reach=1.05),
        "light_3": make_attack("light_3", "Patada cómica", t=0.95, dmg=0.95),
        "heavy_1": make_attack("heavy_1", "Muro invisible", t=0.95, dmg=0.95, reach=1.15, extra={"knockback": 7}),
        "heavy_2": make_attack("heavy_2", "Empujón", t=0.95, dmg=0.95, reach=1.15, extra={"knockback": 8}),
        "running": make_attack("running", "Tropezón", t=0.9, dmg=0.9, extra={"lunge_speed": 9}),
    }, [], {
        "LH": make_combo("light_3", "Guantazo", "skill_claw", t=0.85, dmg=1.0, reach=1.05, extra={"knockback": 7}),
        "LLH": make_combo("heavy_2", "Pared móvil", "skill_body", t=0.85, dmg=0.9, reach=1.2, extra={"knockback": 10}),
        "LLLH": make_combo("heavy_1", "Gran final", "skill_kick", t=0.9, dmg=1.15, poise=1.4, reach=1.15, extra={"knockback": 8}),
        "HL": make_combo("light_1", "Réplica", "skill_punch", t=0.8, dmg=1.0, reach=1.1),
    })
    make_def("mrmime", "Mr. Mime", "Ilusionista",
             "Controla el espacio: barreras que empujan, aturdimientos y proyectiles teledirigidos. Aguanta poco de cerca.",
             _MIME, {"max_health": 100.0, "jog_speed": 4.6, "max_poise": 9.0, "dodge_distance": 5.4},
             (0.5, 1.8, 1.2), (3, 3, 2, 4))
    # ---------------------------------------------------------------------------------------------
    # Tercera tanda. Habilidades en EXTRA_KITS.
    # Feraligatr: depredador pesado (clips propios del juego, como Mewtwo).
    make_moveset("feraligatr", {
        "light_1": make_attack("light_1", "Zarpazo", t=1.1, dmg=1.03, reach=1.3, poise=1.25),
        "light_2": make_attack("light_2", "Mordisco", t=1.1, dmg=1.03, reach=1.3, poise=1.25),
        "light_3": make_attack("light_3", "Coletazo", t=1.1, dmg=1.09, reach=1.3, poise=1.25),
        "heavy_1": make_attack("heavy_1", "Triturar", t=1.16, dmg=1.03, reach=1.3, poise=1.25, extra={'hyper_armor': 70}),
        "heavy_2": make_attack("heavy_2", "Embestida feroz", t=1.16, dmg=1.03, reach=1.3, poise=1.25, extra={'hyper_armor': 70}),
        "running": make_attack("running", "Acometida", t=1.1, dmg=1.03, reach=1.3, poise=1.25, extra={'hyper_armor': 40, 'lunge_speed': 9}),
    }, [], {
        "LH": make_combo("running", "Cabezazo", "skill_body", t=1.04, dmg=0.88, reach=1.3, poise=1.38, extra={'hyper_armor': 40, 'knockback': 8}),
        "LLH": make_combo("heavy_1", "Dentellada", "skill_bite", t=0.99, dmg=1.03, reach=1.3, poise=1.38, extra={'hyper_armor': 70}),
        "LLLH": make_combo("heavy_2", "Giro mortal", "skill_tail", t=1.04, dmg=1.14, reach=1.3, poise=1.38, extra={'hyper_armor': 70, 'knockback': 8}),
        "HL": make_combo("light_3", "Garra dragón", "skill_claw", t=0.99, dmg=1.03, reach=1.3, poise=1.38),
    })
    make_def("feraligatr", "Feraligatr", "Depredador",
             "Mandíbulas enormes y armadura en los golpes fuertes. Lento de arrancar, pero castiga durísimo de cerca.",
             _W, {"max_health": 140.0, "jog_speed": 4.0, "sprint_speed": 6.6, "strafe_speed": 2.9, "max_poise": 24.0, "max_stamina": 115.0, "dodge_distance": 3.8, "block_pose": 0.9},
             (0.8, 2.3, 1.5), (5, 2, 5, 2))
    # Bayleef: aguante y curas.
    make_moveset("bayleef", {
        "light_1": make_attack("light_1", "Mordisco", t=1.0, dmg=0.9, reach=1.0),
        "light_2": make_attack("light_2", "Cabezazo", t=1.0, dmg=0.9, reach=1.0),
        "light_3": make_attack("light_3", "Latigazo", t=1.0, dmg=0.95, reach=1.0),
        "heavy_1": make_attack("heavy_1", "Placaje", t=1.05, dmg=0.9, reach=1.0),
        "heavy_2": make_attack("heavy_2", "Pisotón", t=1.05, dmg=0.9, reach=1.0),
        "running": make_attack("running", "Embestida", t=1.0, dmg=0.9, reach=1.0, extra={'lunge_speed': 9}),
    }, [], {
        "LH": make_combo("running", "Empujón", "skill_body", t=0.95, dmg=0.77, reach=1.0, extra={'knockback': 7}),
        "LLH": make_combo("heavy_1", "Hoja aguda", "skill_tail", t=0.9, dmg=0.9, reach=1.0),
        "LLLH": make_combo("heavy_2", "Cornada", "skill_horn", t=0.95, dmg=1.03, reach=1.0, extra={'knockback': 7}),
        "HL": make_combo("light_3", "Coz", "skill_kick", t=0.9, dmg=0.9, reach=1.0),
    })
    make_def("bayleef", "Bayleef", "Sanadora",
             "Aguanta mucho y se cura: desgasta con hojas y polvos mientras recupera vida. Pega poco.",
             _GR, {"max_health": 120.0, "jog_speed": 4.4, "max_poise": 12.0},
             (0.55, 1.5, 1.0), (4, 3, 2, 4))
    # Forretress: bola blindada (un solo hueso: todos sus golpes son embestidas).
    make_moveset("forretress", {
        "light_1": make_attack("light_1", "Embate", t=1.15, dmg=1.0, reach=1.1, poise=1.4, extra={'hyper_armor': 30}),
        "light_2": make_attack("light_2", "Giro", t=1.15, dmg=1.0, reach=1.1, poise=1.4, extra={'hyper_armor': 30}),
        "light_3": make_attack("light_3", "Pinchazo", t=1.15, dmg=1.04, reach=1.1, poise=1.4, extra={'hyper_armor': 30}),
        "heavy_1": make_attack("heavy_1", "Giro bola", t=1.21, dmg=1.0, reach=1.1, poise=1.4, extra={'hyper_armor': 80}),
        "heavy_2": make_attack("heavy_2", "Cuerpo pesado", t=1.21, dmg=1.0, reach=1.1, poise=1.4, extra={'hyper_armor': 80}),
        "running": make_attack("running", "Rodada", t=1.15, dmg=1.0, reach=1.1, poise=1.4, extra={'hyper_armor': 60, 'lunge_speed': 9}),
    }, [], {
        "LH": make_combo("running", "Rebote", "skill_body", t=1.09, dmg=0.9, reach=1.1, poise=1.54, extra={'hyper_armor': 60, 'knockback': 9}),
        "LLH": make_combo("heavy_1", "Taladro", "skill_body", t=1.03, dmg=1.0, reach=1.1, poise=1.54, extra={'hyper_armor': 80}),
        "LLLH": make_combo("heavy_2", "Bomba imán", "skill_body", t=1.15, dmg=1.15, reach=1.1, poise=1.54, extra={'hyper_armor': 80, 'knockback': 8}),
        "HL": make_combo("light_3", "Púa", "skill_body", t=1.03, dmg=1.0, reach=1.1, poise=1.54, extra={'hyper_armor': 30}),
    })
    make_def("forretress", "Forretress", "Fortaleza",
             "Una bola blindada: nada la interrumpe y explota. Lentísima y sin alcance fuera de sus embestidas.",
             _ST, {"max_health": 150.0, "jog_speed": 3.5, "sprint_speed": 6.0, "strafe_speed": 2.5, "max_poise": 40.0, "max_stamina": 120.0, "dodge_distance": 3.6, "turn_speed": 9.0, "walk_anim_speed": 2.0},
             (0.75, 1.4, 0.8), (5, 1, 4, 2))
    # Aipom: pequeño y rápido (esqueleto de plantilla).
    make_moveset("aipom", {
        "light_1": make_attack("light_1", "Arañazo", t=0.78, dmg=0.8, reach=0.9),
        "light_2": make_attack("light_2", "Coletazo", t=0.78, dmg=0.8, reach=0.9),
        "light_3": make_attack("light_3", "Patada", t=0.78, dmg=0.84, reach=0.9),
        "heavy_1": make_attack("heavy_1", "Golpe cola", t=0.82, dmg=0.8, reach=0.9),
        "heavy_2": make_attack("heavy_2", "Placaje", t=0.82, dmg=0.8, reach=0.9),
        "running": make_attack("running", "Persecución", t=0.78, dmg=0.8, reach=0.9, extra={'lunge_speed': 10}),
    }, [], {
        "LH": make_combo("running", "Voltereta", "skill_kick", t=0.74, dmg=0.64, reach=0.9, extra={'lunge_speed': 10}),
        "LLH": make_combo("heavy_2", "Doble cola", "skill_tail", t=0.7, dmg=0.72, reach=0.9),
        "LLLH": make_combo("heavy_1", "Mano cola", "skill_tail", t=0.78, dmg=1.0, reach=0.9, extra={'knockback': 8}),
        "HL": make_combo("light_3", "Burla", "skill_punch", t=0.7, dmg=0.8, reach=0.9),
    })
    make_def("aipom", "Aipom", "Travieso",
             "El más pequeño y escurridizo. Golpea con la cola, entra y sale; un par de golpes lo tumban.",
             _AP, {"max_health": 85.0, "jog_speed": 5.4, "sprint_speed": 8.8, "strafe_speed": 3.9, "max_poise": 5.0, "max_stamina": 115.0, "dodge_distance": 5.2},
             (0.4, 1.2, 0.8), (2, 5, 2, 2))
    # Hitmontop: patadas giratorias (esqueleto de plantilla).
    make_moveset("hitmontop", {
        "light_1": make_attack("light_1", "Triple patada", t=0.85, dmg=0.9, reach=0.95),
        "light_2": make_attack("light_2", "Puño", t=0.85, dmg=0.9, reach=0.95),
        "light_3": make_attack("light_3", "Coletazo", t=0.85, dmg=0.95, reach=0.95),
        "heavy_1": make_attack("heavy_1", "Patada giro", t=0.89, dmg=0.9, reach=0.95),
        "heavy_2": make_attack("heavy_2", "Placaje", t=0.89, dmg=0.9, reach=0.95),
        "running": make_attack("running", "Giro rápido", t=0.85, dmg=0.9, reach=0.95, extra={'lunge_speed': 10}),
    }, [], {
        "LH": make_combo("light_3", "Barrido", "skill_tail", t=0.77, dmg=0.85, reach=0.95, extra={'knockback': 6}),
        "LLH": make_combo("heavy_2", "Patada doble", "skill_kick", t=0.77, dmg=0.81, reach=0.95),
        "LLLH": make_combo("heavy_1", "Peonza", "skill_kick", t=0.85, dmg=1.08, reach=0.95, extra={'knockback': 8}),
        "HL": make_combo("light_1", "Directo", "skill_punch", t=0.72, dmg=0.95, reach=0.95, extra={'lunge_speed': 7}),
    })
    make_def("hitmontop", "Hitmontop", "Peonza",
             "Gira sin parar: patadas en abanico, mucha movilidad y buen aguante para su tamaño.",
             _F, {"max_health": 105.0, "jog_speed": 4.8, "sprint_speed": 8.0, "max_poise": 12.0, "max_stamina": 110.0},
             (0.45, 1.5, 1.0), (3, 4, 3, 2))
    # Houndoom: presión con fuego.
    make_moveset("houndoom", {
        "light_1": make_attack("light_1", "Mordisco", t=0.88, dmg=0.92, reach=1.0, extra={'burn_time': 1.0}),
        "light_2": make_attack("light_2", "Zarpazo", t=0.88, dmg=0.92, reach=1.0),
        "light_3": make_attack("light_3", "Cornada", t=0.88, dmg=0.97, reach=1.0, extra={'burn_time': 2.0}),
        "heavy_1": make_attack("heavy_1", "Embestida", t=0.92, dmg=0.92, reach=1.0),
        "heavy_2": make_attack("heavy_2", "Coz", t=0.92, dmg=0.92, reach=1.0),
        "running": make_attack("running", "Persecución", t=0.88, dmg=0.92, reach=1.0, extra={'lunge_speed': 10}),
    }, [], {
        "LH": make_combo("running", "Salto", "skill_body", t=0.84, dmg=0.78, reach=1.0, extra={'lunge_speed': 9}),
        "LLH": make_combo("heavy_1", "Colmillo ígneo", "skill_bite", t=0.79, dmg=0.87, reach=1.0, extra={'burn_time': 3.0}),
        "LLLH": make_combo("heavy_2", "Degüello", "skill_bite", t=0.84, dmg=0.95, reach=1.0, extra={'burn_time': 3.0, 'knockback': 7}),
        "HL": make_combo("light_3", "Zarpa oscura", "skill_claw", t=0.79, dmg=0.92, reach=1.0),
    })
    make_def("houndoom", "Houndoom", "Cazador",
             "Perro infernal agresivo: persigue, muerde y quema. Frágil si lo frenan.",
             (1.0, 0.4, 0.2), {"max_health": 100.0, "jog_speed": 5.0, "sprint_speed": 8.6, "strafe_speed": 3.6, "max_poise": 9.0},
             (0.55, 1.6, 1.1), (3, 5, 3, 3))
    # Raikou: velocidad y rayos.
    make_moveset("raikou", {
        "light_1": make_attack("light_1", "Zarpazo", t=0.95, dmg=1.0, reach=1.15),
        "light_2": make_attack("light_2", "Colmillo rayo", t=0.95, dmg=1.0, reach=1.15),
        "light_3": make_attack("light_3", "Pisotón", t=0.95, dmg=1.05, reach=1.15),
        "heavy_1": make_attack("heavy_1", "Embestida", t=1.0, dmg=1.0, reach=1.15),
        "heavy_2": make_attack("heavy_2", "Coletazo", t=1.0, dmg=1.0, reach=1.15),
        "running": make_attack("running", "Carrera", t=0.95, dmg=1.0, reach=1.15, extra={'lunge_speed': 10}),
    }, [], {
        "LH": make_combo("running", "Chispazo", "skill_body", t=0.9, dmg=0.85, reach=1.15, extra={'knockback': 7}),
        "LLH": make_combo("heavy_1", "Garra voltio", "skill_claw", t=0.85, dmg=1.0, reach=1.15),
        "LLLH": make_combo("heavy_2", "Descarga", "skill_horn", t=0.9, dmg=1.15, reach=1.15, extra={'knockback': 8}),
        "HL": make_combo("light_3", "Dentellada", "skill_bite", t=0.85, dmg=1.0, reach=1.15),
    })
    make_def("raikou", "Raikou", "Bestia del trueno",
             "Grande y veloz. Rayos rapidísimos a distancia y embestidas largas; sus habilidades cuestan mucho Calor.",
             _EL, {"max_health": 120.0, "jog_speed": 4.8, "sprint_speed": 8.4, "max_poise": 16.0},
             (0.7, 2.0, 1.4), (4, 4, 4, 4))
    # Blaziken: patadas de fuego.
    make_moveset("blaziken", {
        "light_1": make_attack("light_1", "Puño fuego", t=0.9, dmg=0.94, reach=1.1),
        "light_2": make_attack("light_2", "Patada baja", t=0.9, dmg=0.94, reach=1.1),
        "light_3": make_attack("light_3", "Zarpazo", t=0.9, dmg=0.99, reach=1.1),
        "heavy_1": make_attack("heavy_1", "Patada ígnea", t=0.95, dmg=0.94, reach=1.1, extra={'burn_time': 2.0}),
        "heavy_2": make_attack("heavy_2", "Embate", t=0.95, dmg=0.94, reach=1.1),
        "running": make_attack("running", "Rodillazo", t=0.9, dmg=0.94, reach=1.1, extra={'lunge_speed': 10}),
    }, [], {
        "LH": make_combo("light_3", "Rodilla", "skill_kick", t=0.81, dmg=0.89, reach=1.1, extra={'knockback': 6}),
        "LLH": make_combo("heavy_1", "Doble patada", "skill_kick", t=0.81, dmg=0.89, reach=1.1, extra={'burn_time': 2.0}),
        "LLLH": make_combo("heavy_2", "Patada hacha", "skill_kick", t=0.9, dmg=1.08, reach=1.1, extra={'burn_time': 3.0, 'knockback': 8}),
        "HL": make_combo("light_1", "Directo ígneo", "skill_punch", t=0.77, dmg=0.99, reach=1.1, extra={'burn_time': 1.0}),
    })
    make_def("blaziken", "Blaziken", "Kickboxer",
             "Patadas de fuego encadenadas y embestidas largas. Mucho daño cuerpo a cuerpo, defensa justa.",
             _FIRE, {"max_health": 105.0, "jog_speed": 4.9, "sprint_speed": 8.3, "max_poise": 12.0, "max_stamina": 110.0},
             (0.55, 2.1, 1.45), (3, 4, 4, 2))
    # Lucario: equilibrado, aura a distancia.
    make_moveset("lucario", {
        "light_1": make_attack("light_1", "Palmeo", t=0.9, dmg=0.95, reach=1.05),
        "light_2": make_attack("light_2", "Garra metal", t=0.9, dmg=0.95, reach=1.05),
        "light_3": make_attack("light_3", "Patada", t=0.9, dmg=1.0, reach=1.05),
        "heavy_1": make_attack("heavy_1", "Patada alta", t=0.95, dmg=0.95, reach=1.05),
        "heavy_2": make_attack("heavy_2", "Embate", t=0.95, dmg=0.95, reach=1.05),
        "running": make_attack("running", "Ataque óseo", t=0.9, dmg=0.95, reach=1.05, extra={'lunge_speed': 10}),
    }, [], {
        "LH": make_combo("light_3", "Palma fuerza", "skill_punch", t=0.81, dmg=0.95, reach=1.05, extra={'knockback': 7}),
        "LLH": make_combo("heavy_1", "Tajo cruzado", "skill_claw", t=0.81, dmg=0.9, reach=1.05, extra={'heat_gain': 20}),
        "LLLH": make_combo("heavy_2", "A bocajarro", "skill_kick", t=0.85, dmg=1.09, reach=1.05, extra={'knockback': 8}),
        "HL": make_combo("light_1", "Puño bala", "skill_punch", t=0.77, dmg=1.0, reach=1.05, extra={'lunge_speed': 7}),
    })
    make_def("lucario", "Lucario", "Guerrero del aura",
             "Equilibrado y técnico: buen cuerpo a cuerpo y esferas de aura teledirigidas.",
             _AU, {"max_health": 100.0, "jog_speed": 4.8, "sprint_speed": 8.0, "max_poise": 11.0},
             (0.5, 1.9, 1.3), (3, 4, 3, 4))
    # Zoroark: rápido y esquivo.
    make_moveset("zoroark", {
        "light_1": make_attack("light_1", "Garra umbría", t=0.85, dmg=0.9, reach=1.1),
        "light_2": make_attack("light_2", "Zarpazo", t=0.85, dmg=0.9, reach=1.1),
        "light_3": make_attack("light_3", "Patada", t=0.85, dmg=0.95, reach=1.1),
        "heavy_1": make_attack("heavy_1", "Mordisco", t=0.89, dmg=0.9, reach=1.1),
        "heavy_2": make_attack("heavy_2", "Embate", t=0.89, dmg=0.9, reach=1.1),
        "running": make_attack("running", "Acometida", t=0.85, dmg=0.9, reach=1.1, extra={'lunge_speed': 10}),
    }, [], {
        "LH": make_combo("running", "Sombra vil", "skill_kick", t=0.81, dmg=0.77, reach=1.1, extra={'lunge_speed': 10}),
        "LLH": make_combo("heavy_1", "Tajo umbrío", "skill_claw", t=0.75, dmg=0.85, reach=1.1),
        "LLLH": make_combo("heavy_2", "Desgarro", "skill_claw", t=0.81, dmg=1.08, reach=1.1, extra={'knockback': 7}),
        "HL": make_combo("light_3", "Zarpa traidora", "skill_punch", t=0.72, dmg=0.9, reach=1.1),
    })
    make_def("zoroark", "Zoroark", "Embaucador oscuro",
             "Garras rápidas, esquivas largas y trucos sucios. Castiga errores, pero aguanta poco.",
             _DK, {"max_health": 95.0, "jog_speed": 5.0, "sprint_speed": 8.5, "strafe_speed": 3.6, "max_poise": 8.0, "dodge_distance": 5.6, "dodge_iframes": v2(0.02, 0.42)},
             (0.5, 1.9, 1.3), (2, 5, 3, 3))
    print("ok")


if __name__ == "__main__":
    main()

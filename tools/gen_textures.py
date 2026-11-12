#!/usr/bin/env python3
"""Genera las texturas procedurales del coliseo (periódicas, sin costuras) en levels/colosseum/textures/.

  floor_albedo.png / floor_normal.png / floor_orm.png   losas irregulares (una tesela = 4 m)
  stone_albedo.png / stone_normal.png / stone_orm.png   sillares de muro (una tesela = 4 m)
  macro.png                                             ruido de baja frecuencia para romper la repetición

ORM empaquetado a nuestra manera: R = rugosidad, G = altura, B = oclusión.
Uso: python3 tools/gen_textures.py   (necesita numpy y Pillow)
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "levels/colosseum/textures")
S = 1024
rng = np.random.default_rng(7)
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S  # coordenadas 0..1


def value_noise(freq, seed):
    """Ruido de valor periódico (frecuencia entera = celdas por tesela)."""
    g = np.random.default_rng(seed).random((freq, freq)).astype(np.float32)
    fx, fy = xx * freq, yy * freq
    x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
    tx, ty = fx - x0, fy - y0
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    x0 %= freq; y0 %= freq
    x1, y1 = (x0 + 1) % freq, (y0 + 1) % freq
    a = g[y0, x0] * (1 - tx) + g[y0, x1] * tx
    b = g[y1, x0] * (1 - tx) + g[y1, x1] * tx
    return a * (1 - ty) + b * ty


def fbm(freq, octaves, seed, gain=0.5):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + value_noise(freq * 2 ** o, seed + o) * amp
        norm += amp
        amp *= gain
    return total / norm


def voronoi(n, seed, jitter=0.85):
    """Voronoi periódico de n×n celdas: (F1, F2, id de celda)."""
    r = np.random.default_rng(seed)
    pts = 0.5 + (r.random((n, n, 2)) - 0.5) * jitter
    fx, fy = xx * n, yy * n
    cx, cy = np.floor(fx).astype(int), np.floor(fy).astype(int)
    f1 = np.full((S, S), 9.0, np.float32); f2 = f1.copy(); cid = np.zeros((S, S), int)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            nx, ny = cx + dx, cy + dy
            p = pts[ny % n, nx % n]
            d = np.hypot(nx + p[..., 0] - fx, ny + p[..., 1] - fy)
            idx = (ny % n) * n + (nx % n)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            cid = np.where(closer, idx, cid)
            f1 = np.where(closer, d, f1)
    return f1 / n, f2 / n, cid


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def normal_from_height(h, strength):
    """Normal en convención OpenGL (la de Godot): +Y hacia arriba en la imagen."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * S
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * S
    n = np.stack([-dx * strength, dy * strength, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save_rgb(name, rgb):
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, name))


def to_srgb(lin):
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(np.clip(lin, 0, 1), 1 / 2.4) - 0.055)


def tint_per_cell(cid, count, seed, base, spread):
    r = np.random.default_rng(seed)
    lum = 1 + (r.random(count) - 0.5) * 2 * spread
    hue = (r.random((count, 3)) - 0.5) * 0.08
    cols = np.clip(np.array(base)[None, :] * lum[:, None] * (1 + hue), 0, 1)
    return cols[cid]


# ---------------------------------------------------------------------------------- Suelo: losas
def floor():
    n = 7
    warp = (fbm(6, 3, 11) - 0.5) * 0.03  # bordes irregulares
    f1, f2, cid = voronoi(n, 3)
    edge = (f2 - f1) + warp  # ~distancia al borde de la losa (en teselas)
    chips = fbm(32, 3, 21)
    mortar = 0.004 + 0.005 * chips
    stone = smoothstep(mortar, mortar + 0.008, edge)
    detail = fbm(16, 5, 31)
    fine = fbm(64, 3, 41)
    # Altura: losas con borde biselado, superficie algo irregular, juntas hundidas.
    h = stone * (0.6 + 0.3 * detail + 0.1 * fine) * (0.85 + 0.15 * smoothstep(0.0, 0.03, edge))
    # Grietas orgánicas: crestas de un ruido, solo en algunas zonas.
    ridge = np.abs(fbm(10, 4, 5) - 0.5)
    crack = (1 - smoothstep(0.0, 0.006, ridge)) * smoothstep(0.55, 0.65, fbm(3, 2, 6)) * stone
    h = h - crack * 0.3
    base = tint_per_cell(cid, n * n, 13, (0.26, 0.22, 0.18), 0.22)
    stain = 0.8 + 0.3 * detail[..., None]
    col = base * stain * (0.92 + 0.12 * fine[..., None])
    grout = np.array([0.07, 0.06, 0.05]) * (0.8 + 0.5 * chips[..., None])
    col = col * stone[..., None] + grout * (1 - stone[..., None])
    col *= (1 - 0.55 * crack[..., None])
    col *= (0.82 + 0.18 * smoothstep(0.0, 0.05, edge))[..., None]  # bordes desgastados más oscuros
    save_rgb("floor_albedo.png", to_srgb(col ** 1.0))
    save_rgb("floor_normal.png", normal_from_height(h, 0.02))
    rough = np.clip(0.72 + 0.16 * detail - 0.08 * fine, 0, 1) * stone + 0.95 * (1 - stone)
    ao = np.clip(0.55 + 0.45 * smoothstep(0.0, 0.04, edge), 0, 1) * (1 - 0.5 * crack)
    save_rgb("floor_orm.png", np.stack([rough, np.clip(h, 0, 1), ao], -1))


# ---------------------------------------------------------------------------------- Muro: sillares
def stone():
    rows = 8  # 0.5 m por hilada
    r = np.random.default_rng(17)
    row = np.floor(yy * rows).astype(int)
    v = yy * rows - row  # 0..1 dentro de la hilada
    cid = np.zeros((S, S), int)
    dist_x = np.zeros((S, S), np.float32)
    for k in range(rows):
        widths = []
        while sum(widths) < 1.0:
            widths.append(r.uniform(0.18, 0.34))
        widths = np.array(widths) / sum(widths)
        cuts = np.concatenate([[0], np.cumsum(widths)])
        off = r.random()
        m = row == k
        u = (xx[m] + off) % 1.0
        j = np.searchsorted(cuts, u, side="right") - 1
        j = np.clip(j, 0, len(widths) - 1)
        left = u - cuts[j]; right = cuts[j + 1] - u
        dist_x[m] = np.minimum(left, right)
        cid[m] = k * 16 + j
    dist_y = np.minimum(v, 1 - v) / rows
    warp = (fbm(8, 4, 51) - 0.5) * 0.012
    edge = np.minimum(dist_x, dist_y) + warp
    chips = fbm(40, 3, 61)
    mortar = 0.003 + 0.004 * chips
    blk = smoothstep(mortar, mortar + 0.007, edge)
    detail = fbm(12, 5, 71)
    fine = fbm(80, 3, 81)
    erosion = smoothstep(0.55, 0.8, fbm(24, 4, 91))  # picaduras
    h = blk * (0.6 + 0.3 * detail + 0.1 * fine) * (0.8 + 0.2 * smoothstep(0.0, 0.02, edge)) - erosion * 0.2 * blk
    base = tint_per_cell(cid, rows * 16, 23, (0.30, 0.26, 0.21), 0.2)
    col = base * (0.7 + 0.45 * detail[..., None]) * (0.9 + 0.15 * fine[..., None])
    col *= (1 - 0.35 * erosion[..., None])
    mortar_col = np.array([0.10, 0.09, 0.075]) * (0.8 + 0.4 * chips[..., None])
    col = col * blk[..., None] + mortar_col * (1 - blk[..., None])
    col *= (0.8 + 0.2 * smoothstep(0.0, 0.03, edge))[..., None]
    save_rgb("stone_albedo.png", to_srgb(col))
    save_rgb("stone_normal.png", normal_from_height(h, 0.018))
    rough = np.clip(0.78 + 0.14 * detail + 0.08 * erosion, 0, 1) * blk + 0.92 * (1 - blk)
    ao = np.clip(0.6 + 0.4 * smoothstep(0.0, 0.03, edge), 0, 1) * (1 - 0.3 * erosion)
    save_rgb("stone_orm.png", np.stack([rough, np.clip(h, 0, 1), ao], -1))


def macro():
    m = fbm(4, 6, 101, 0.55)
    m = (m - m.min()) / (m.max() - m.min())
    save_rgb("macro.png", np.stack([m, fbm(8, 4, 111), fbm(3, 3, 121)], -1))


IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://levels/colosseum/textures/{name}"

[params]

compress/mode=2
compress/high_quality=false
mipmaps/generate=true
detect_3d/compress_to=0
"""

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    floor(); stone(); macro()
    for f in os.listdir(OUT):
        if f.endswith(".png") and not os.path.exists(os.path.join(OUT, f + ".import")):
            open(os.path.join(OUT, f + ".import"), "w").write(IMPORT.format(name=f))
    print("ok:", sorted(f for f in os.listdir(OUT) if f.endswith(".png")))

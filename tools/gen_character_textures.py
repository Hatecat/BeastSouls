"""Microdetalle de superficie para los personajes (escamas, quitina, pelaje, piel). numpy + Pillow.

    python3 tools/gen_character_textures.py

Escribe assets/textures/characters/<tipo>.png, repetibles sin costura: R,G = normal (XY, convención OpenGL),
B = altura (0 hueco .. 1 cresta; el shader la usa para oscurecer huecos y variar la rugosidad).
"""
import os

import numpy as np
from PIL import Image

N = 512
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures", "characters")
rng = np.random.default_rng(7)


def blur(img, sx, sy):
    """Desenfoque gaussiano periódico (por FFT): el resultado sigue siendo repetible."""
    fy = np.fft.fftfreq(img.shape[0])[:, None]
    fx = np.fft.fftfreq(img.shape[1])[None, :]
    k = np.exp(-2.0 * np.pi ** 2 * ((fx * sx) ** 2 + (fy * sy) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(img) * k))


def norm01(h):
    h = h - h.min()
    return h / max(h.max(), 1e-9)


def noise(sx, sy=None):
    return norm01(blur(rng.standard_normal((N, N)), sx, sx if sy is None else sy))


def voronoi(cells, jitter=0.85):
    """Distancias al punto más cercano y al segundo (F1, F2) y un valor aleatorio por celda. Repetible."""
    pts = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells), indexing="ij"), -1)
           + 0.5 + (rng.random((cells, cells, 2)) - 0.5) * jitter)
    val = rng.random((cells, cells))
    y, x = np.mgrid[0:N, 0:N] / N * cells
    cy, cx = np.floor(y).astype(int), np.floor(x).astype(int)
    f1 = np.full((N, N), 1e9)
    f2 = np.full((N, N), 1e9)
    v = np.zeros((N, N))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            iy, ix = (cy + dy) % cells, (cx + dx) % cells
            p = pts[iy, ix]
            d = np.hypot(y - (cy + dy + p[..., 0] - iy), x - (cx + dx + p[..., 1] - ix))
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            v = np.where(closer, val[iy, ix], v)
            f1 = np.where(closer, d, f1)
    return f1, f2, v


def save(name, height, strength):
    h = norm01(height)
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * N / 64.0 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * N / 64.0 * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)  # +Y hacia arriba de la imagen
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    rgb = np.stack([n[..., 0] * 0.5 + 0.5, n[..., 1] * 0.5 + 0.5, h], -1)
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name + ".png"))
    print(name, "ok")


def scales():
    f1, f2, v = voronoi(18)
    edge = np.clip((f2 - f1) / 0.22, 0, 1)            # 0 en la junta, 1 dentro de la escama
    dome = 1.0 - np.clip(f1 / 0.75, 0, 1) ** 2         # cada escama abombada
    h = edge ** 0.6 * (0.55 + 0.45 * dome) * (0.8 + 0.2 * v)
    return blur(h, 1.2, 1.2) + noise(1.5) * 0.06


def chitin():
    f1, f2, _ = voronoi(40, 1.0)
    pits = np.clip(1.0 - f1 / 0.28, 0, 1) ** 2         # poros dispersos
    return noise(40) * 0.5 + noise(6) * 0.2 - blur(pits, 1.0, 1.0) * 0.35 + noise(1.2) * 0.05


def fur():
    strands = noise(1.0, 22.0)                          # mechones alargados en vertical
    clumps = noise(14.0, 40.0)
    return strands * 0.65 + clumps * 0.35 + noise(0.8) * 0.08


def skin():
    f1, f2, _ = voronoi(56, 1.0)
    wrinkles = np.clip((f2 - f1) / 0.18, 0, 1) ** 0.5  # red fina de pliegues
    return blur(wrinkles, 1.0, 1.0) * 0.6 + noise(10) * 0.3 + noise(1.0) * 0.1


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("scales", scales(), 3.0)
    save("chitin", chitin(), 2.2)
    save("fur", fur(), 2.6)
    save("skin", skin(), 2.0)

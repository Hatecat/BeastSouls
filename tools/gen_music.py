#!/usr/bin/env python3
"""Compone por código la música y los ambientes de BeastSouls (numpy + ffmpeg). Sin derechos de terceros.

  assets/audio/music/menu.ogg      ambiente oscuro: coro, bordón y campanas (bucle)
  assets/audio/music/combat.ogg    combate: cuerdas graves en ostinato, taikos, metales y coro (bucle)
  assets/audio/music/victory.ogg   fanfarria corta        assets/audio/music/defeat.ogg   golpe y coro grave
  assets/audio/ambience/wind.ogg   viento (bucle)         assets/audio/ambience/fire.ogg  crepitar de brasero (bucle)

Los bucles se calculan circularmente (la reverb de la cola entra por el principio): empalman sin corte.
Uso: python3 tools/gen_music.py
"""
import subprocess
from pathlib import Path

import numpy as np

SR = 32000
OUT = Path(__file__).resolve().parent.parent / "assets/audio"
rng = np.random.default_rng(5)
NOTE = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def m(name):
    """'D3' -> número MIDI."""
    return NOTE[name[:-1]] + 12 * (int(name[-1]) + 1)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def env(n, attack, release, curve=1.0):
    e = np.ones(n)
    a = min(int(attack * SR), n)
    r = min(int(release * SR), n - a)
    if a:
        e[:a] = np.linspace(0, 1, a) ** curve
    if r:
        e[n - r:] *= np.linspace(1, 0, r) ** curve
    return e


def t_of(n):
    return np.arange(n) / SR


# --- Instrumentos -------------------------------------------------------------------------

def pad(midi, dur, harmonics=8, tilt=1.4, voices=3, vib=0.0):
    n = int(dur * SR)
    t = t_of(n)
    out = np.zeros(n)
    f0 = hz(midi)
    for v in range(voices):
        det = 2 ** (((v - (voices - 1) / 2) * 7) / 1200)  # ±7 cents
        ph = rng.random() * 6.28
        fm = 1 + vib * np.sin(2 * np.pi * (4.5 + v * 0.3) * t)
        for k in range(1, harmonics + 1):
            f = f0 * k * det
            if f > SR / 2.2:
                break
            out += np.sin(2 * np.pi * f * np.cumsum(fm) / SR + ph * k) / k ** tilt
    return out / voices


def choir(midi, dur):
    """'Aah': armónicos pesados por formantes de la vocal a."""
    n = int(dur * SR)
    t = t_of(n)
    f0 = hz(midi)
    out = np.zeros(n)
    formants = [(730, 90, 1.0), (1090, 110, 0.5), (2440, 160, 0.25)]
    for v in range(4):
        det = 2 ** ((rng.normal() * 9) / 1200)
        fm = 1 + 0.006 * np.sin(2 * np.pi * (5.0 + rng.random()) * t + rng.random() * 6)
        phase = 2 * np.pi * f0 * det * np.cumsum(fm) / SR
        for k in range(1, 40):
            f = f0 * k
            if f > 4000:
                break
            a = sum(g * np.exp(-((f - c) / w) ** 2) for c, w, g in formants) + 0.04 / k
            out += a * np.sin(k * phase)
    return out / 4


def string_hit(midi, dur):
    n = int(dur * SR)
    t = t_of(n)
    f0 = hz(midi)
    out = np.zeros(n)
    for k in range(1, 18):
        out += np.sin(2 * np.pi * f0 * k * t * (1 + 0.0015 * k)) / k
    return out * np.exp(-t * 5.5) * env(n, 0.008, 0.03)


def taiko(dur=1.2, pitch=58.0, amount=1.0):
    n = int(dur * SR)
    t = t_of(n)
    f = pitch * (1 + 0.6 * np.exp(-t * 18))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 4.0)
    noise = rng.normal(size=n)
    noise = np.convolve(noise, np.ones(12) / 12, "same") * np.exp(-t * 40)
    return (body + 0.5 * noise) * amount


def rim(dur=0.15):
    n = int(dur * SR)
    t = t_of(n)
    x = rng.normal(size=n)
    x = x - np.convolve(x, np.ones(6) / 6, "same")  # paso alto burdo
    return x * np.exp(-t * 60) * 0.5


def bell(midi, dur=4.0):
    n = int(dur * SR)
    t = t_of(n)
    f0 = hz(midi)
    out = np.zeros(n)
    for ratio, amp, dec in [(1, 1, 1.2), (2.76, 0.5, 2.0), (5.4, 0.25, 3.5), (8.93, 0.12, 5)]:
        out += amp * np.sin(2 * np.pi * f0 * ratio * t) * np.exp(-t * dec)
    return out * env(n, 0.002, 0.2)


def brass(midi, dur):
    n = int(dur * SR)
    x = pad(midi, dur, harmonics=14, tilt=1.0, voices=2, vib=0.003)
    swell = np.linspace(0.35, 1.0, n) ** 1.5
    return x * swell * env(n, 0.25, 0.4)


# --- Mezcla -------------------------------------------------------------------------------

class Track:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.buses = {}

    def add(self, bus, start, sound, gain=1.0):
        buf = self.buses.setdefault(bus, np.zeros(self.n))
        i = int(start * SR) % self.n
        # Circular: lo que se sale por el final entra por el principio (bucle perfecto).
        end = i + len(sound)
        if end <= self.n:
            buf[i:end] += sound * gain
        else:
            k = self.n - i
            buf[i:] += sound[:k] * gain
            rest = sound[k:]
            while len(rest):
                c = min(len(rest), self.n)
                buf[:c] += rest[:c] * gain
                rest = rest[c:]

    def mix(self, sends, loop=True):
        dry = sum(self.buses.values())
        wet_in = sum(self.buses[b] * s for b, s in sends.items() if b in self.buses)
        left = dry + reverb(wet_in, 2.6, 1, loop)
        right = dry + reverb(wet_in, 2.6, 2, loop)
        st = np.stack([left, right], 1)
        st /= np.max(np.abs(st)) + 1e-9
        return np.tanh(st * 1.4) / np.tanh(1.4)


def reverb(x, seconds, seed, loop):
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = t_of(n)
    ir = r.normal(size=n) * np.exp(-t * 6.9 / seconds)
    ir = np.convolve(ir, np.ones(8) / 8, "same")  # algo más oscura
    ir[0] = 0
    ir /= np.sqrt(np.sum(ir ** 2))
    if loop:
        L = len(x)
        irl = np.zeros(L)
        irl[:min(n, L)] = ir[:L]
        return np.real(np.fft.ifft(np.fft.fft(x) * np.fft.fft(irl))) * 0.9
    y = np.convolve(x, ir)[:len(x)]
    return y * 0.9


def write(path, stereo, volume=0.85):
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(stereo * volume, -1, 1) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", str(path)], input=pcm, check=True)
    print("  ", path.relative_to(OUT.parent.parent), f"{len(stereo) / SR:.1f} s")


# --- Piezas -------------------------------------------------------------------------------

DM = ["D3", "F3", "A3"]
BB = ["A#2", "D3", "F3"]
GM = ["G2", "A#2", "D3"]
AM = ["A2", "C#3", "E3"]
CM = ["C3", "E3", "G3"]


def menu():
    chord_len = 8.0
    prog = [DM, BB, GM, AM, DM, BB, GM, AM]
    tr = Track(chord_len * len(prog))
    for i, ch in enumerate(prog):
        s = i * chord_len
        for note in ch:
            tr.add("choir", s, choir(m(note) + 12, chord_len + 1.5) * env(int((chord_len + 1.5) * SR), 2.0, 2.5), 0.5)
        tr.add("pad", s, pad(m(ch[0]) - 12, chord_len + 1.0, 6, 1.6) * env(int((chord_len + 1) * SR), 1.5, 2.0), 0.6)
        tr.add("drum", s, taiko(2.0, 48, 0.9), 0.7)
    drone = pad(m("D2"), tr.n / SR, 5, 1.8, 3) + pad(m("A2"), tr.n / SR, 4, 1.8, 2) * 0.5
    tr.add("pad", 0, drone, 0.35)
    scale = [m(x) for x in ["D5", "F5", "G5", "A5", "C6", "D6", "A4"]]
    for k in range(18):
        tr.add("bell", rng.uniform(0, tr.n / SR), bell(int(rng.choice(scale)), 5.0), 0.16)
    return tr.mix({"choir": 1.0, "pad": 0.6, "bell": 1.4, "drum": 0.8})


def combat():
    bpm = 108
    beat = 60 / bpm
    bar = beat * 4
    prog = [DM, DM, BB, CM, DM, DM, GM, AM] * 2
    tr = Track(bar * len(prog))
    pattern = [0, 0, 12, 0, 7, 0, 12, 5]
    for b, ch in enumerate(prog):
        s = b * bar
        root = m(ch[0]) - 12
        for i, off in enumerate(pattern):
            tr.add("str", s + i * beat / 2, string_hit(root + off, beat * 0.9), 0.5 if i % 2 else 0.65)
        # Taikos: 1, 2y, 3, (4y en compases impares) y redoble cada 4 compases.
        for pos, amt in [(0, 1.0), (1.5, 0.6), (2, 0.85)] + ([(3.5, 0.5)] if b % 2 else []):
            tr.add("drum", s + pos * beat, taiko(1.0, 56, amt), 0.9)
        if b % 4 == 3:
            for k in range(4):
                tr.add("drum", s + (3 + k * 0.25) * beat, taiko(0.6, 70, 0.45 + k * 0.1), 0.8)
        for k in range(4):
            tr.add("perc", s + (k + 0.5) * beat, rim(), 0.18)
        # Metales en la segunda mitad; coro siempre, más fuerte al final.
        if b >= 8:
            for note in ch:
                tr.add("brass", s, brass(m(note), bar * 1.02), 0.28)
        for note in ch:
            tr.add("choir", s, choir(m(note) + 12, bar + 0.6) * env(int((bar + 0.6) * SR), 0.4, 0.6), 0.22 if b < 8 else 0.38)
    tr.add("str", 0, pad(m("D1"), tr.n / SR, 6, 1.6, 2), 0.25)
    return tr.mix({"str": 0.35, "drum": 0.45, "brass": 0.8, "choir": 1.0, "perc": 0.3})


def victory():
    tr = Track(5.0)
    for note in ["D3", "F#3", "A3", "D4"]:
        tr.add("brass", 0.0, brass(m(note), 3.5), 0.4)
    for note in ["D4", "F#4", "A4"]:
        tr.add("choir", 0.2, choir(m(note), 3.6) * env(int(3.6 * SR), 0.3, 1.5), 0.4)
    tr.add("drum", 0.0, taiko(2.0, 50, 1.0), 1.0)
    tr.add("bell", 0.3, bell(m("D6"), 4.0), 0.3)
    return tr.mix({"brass": 0.6, "choir": 1.0, "bell": 1.0, "drum": 0.5}, loop=False) * env(tr.n, 0.005, 1.2)[:, None]


def defeat():
    tr = Track(5.0)
    tr.add("drum", 0.0, taiko(3.0, 40, 1.2), 1.0)
    for note in ["D3", "F3", "G#3"]:
        tr.add("choir", 0.1, choir(m(note), 4.0) * env(int(4.0 * SR), 0.6, 2.0), 0.45)
    tr.add("pad", 0.0, pad(m("D1"), 4.5, 6, 1.5) * env(int(4.5 * SR), 0.05, 2.0), 0.6)
    return tr.mix({"choir": 1.0, "pad": 0.5, "drum": 0.6}, loop=False) * env(tr.n, 0.005, 1.5)[:, None]


def shaped_noise(seconds, shape):
    """Ruido periódico con espectro dado (bucle perfecto por construcción)."""
    n = int(seconds * SR)
    spec = np.fft.rfft(rng.normal(size=n))
    f = np.fft.rfftfreq(n, 1 / SR)
    return np.fft.irfft(spec * shape(f), n)


def wind():
    secs = 24.0
    n = int(secs * SR)
    t = t_of(n)
    chans = []
    for c in range(2):
        x = shaped_noise(secs, lambda f: 1 / (1 + (f / 350) ** 2) + 0.4 * np.exp(-((f - 520) / 160) ** 2))
        # Rachas: modulación lenta con periodos que dividen el bucle.
        gust = 0.55 + 0.25 * np.sin(2 * np.pi * t / 12 + c) + 0.15 * np.sin(2 * np.pi * t / 4.8 + 2 * c) + 0.05 * np.sin(2 * np.pi * t / 2.4)
        chans.append(x * gust)
    st = np.stack(chans, 1)
    return st / np.max(np.abs(st))


def fire():
    secs = 8.0
    n = int(secs * SR)
    rumble = shaped_noise(secs, lambda f: 1 / (1 + (f / 180) ** 2))
    rumble /= np.max(np.abs(rumble))
    crack = np.zeros(n)
    for k in range(int(secs * 22)):
        i = rng.integers(0, n)
        length = rng.integers(40, 400)
        burst = rng.normal(size=length) * np.exp(-np.arange(length) / (length / 5)) * rng.uniform(0.2, 1.0)
        end = min(n, i + length)
        crack[i:end] += burst[:end - i]
    crack = crack - np.convolve(crack, np.ones(4) / 4, "same") * 0.7
    x = rumble * 0.5 + crack * 0.6
    st = np.stack([x, np.roll(x, 900)], 1)
    return st / np.max(np.abs(st))


IMPORT = """[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"

[deps]

source_file="res://assets/audio/{dir}/{name}"

[params]

loop={loop}
loop_offset=0
bpm=0
beat_count=0
bar_beats=4
"""


def import_file(path, loop):
    imp = Path(str(path) + ".import")
    imp.write_text(IMPORT.format(dir=path.parent.name, name=path.name, loop="true" if loop else "false"))


if __name__ == "__main__":
    for name, fn, folder, loop, vol in [("menu", menu, "music", True, 0.8), ("combat", combat, "music", True, 0.85),
                                        ("victory", victory, "music", False, 0.85), ("defeat", defeat, "music", False, 0.85),
                                        ("wind", wind, "ambience", True, 0.7), ("fire", fire, "ambience", True, 0.7)]:
        p = OUT / folder / f"{name}.ogg"
        write(p, fn(), vol)
        import_file(p, loop)

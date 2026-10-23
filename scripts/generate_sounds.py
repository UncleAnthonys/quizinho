"""Generate Quizinho's original sound effects.

Every sound here is synthesised from scratch (sine/square/saw waves and
filtered noise), so there are no licensing questions. Re-run any time:

    python3 scripts/generate_sounds.py

Output: assets/sounds/*.wav (44.1 kHz, 16-bit mono).
"""

from __future__ import annotations

import pathlib
import wave

import numpy as np

SR = 44_100
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "sounds"
rng = np.random.default_rng(7)


def t(seconds: float) -> np.ndarray:
    return np.linspace(0, seconds, int(SR * seconds), endpoint=False)


def env(n: int, attack: float = 0.005, release: float = 0.08) -> np.ndarray:
    e = np.ones(n)
    a = max(1, int(SR * attack))
    r = max(1, int(SR * release))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    # one-pole low-pass; cutoff may be an array for sweeps
    cutoff = np.broadcast_to(cutoff, x.shape)
    alpha = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i, (v, a) in enumerate(zip(x, alpha)):
        acc += a * (v - acc)
        y[i] = acc
    return y


def bandpass(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return lowpass(x, hi) - lowpass(x, lo)


def save(name: str, x: np.ndarray, gain: float = 0.9) -> None:
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    data = (x * 32767).astype(np.int16)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def tone(freq, seconds, shape="sine"):
    tt = t(seconds)
    phase = 2 * np.pi * np.cumsum(np.broadcast_to(freq, tt.shape)) / SR
    if shape == "square":
        return np.sign(np.sin(phase))
    if shape == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1) - 1
    return np.sin(phase)


def click(freq: float, seconds: float = 0.035) -> np.ndarray:
    tt = t(seconds)
    return np.sin(2 * np.pi * freq * tt) * np.exp(-tt * 140)


def main() -> None:
    # Bomb ticks (normal + urgent) and wheel ratchet
    save("tick", click(1800), 0.6)
    save("tick_fast", click(2600, 0.03), 0.7)
    save("spin_tick", click(1100, 0.025) + 0.3 * rng.normal(size=int(SR * 0.025)) * np.exp(-t(0.025) * 300), 0.5)
    save("countdown_beep", tone(880, 0.12) * env(int(SR * 0.12), 0.003, 0.04), 0.6)

    # Referee whistle: two pea-whistle blasts
    def blast(sec):
        tt = t(sec)
        trill = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * 34 * tt))
        f = 3150 + 60 * np.sin(2 * np.pi * 34 * tt)
        x = tone(f, sec) * trill + 0.08 * rng.normal(size=len(tt))
        return x * env(len(tt), 0.01, 0.05)

    save("whistle", np.concatenate([blast(0.22), np.zeros(int(SR * 0.08)), blast(0.55)]), 0.75)

    # Buzz-in: bright two-note boop
    save("buzz_in", np.concatenate([tone(660, 0.07, "square"), tone(990, 0.12, "square")]) * env(int(SR * 0.19)), 0.5)

    # Wrong answer: low game-show buzzer
    wr = tone(110, 0.55, "square") + 0.6 * tone(116, 0.55, "square")
    save("wrong", lowpass(wr, 1400) * env(len(wr), 0.005, 0.1), 0.7)

    # Correct: rising arpeggio
    notes = [1046.5, 1318.5, 1568.0, 2093.0]
    parts = [tone(f, 0.09) * np.exp(-t(0.09) * 8) for f in notes[:-1]]
    parts.append(tone(notes[-1], 0.45) * np.exp(-t(0.45) * 5))
    save("correct", np.concatenate(parts), 0.7)

    # Explosion: sub thump + decaying low-passed noise
    n = int(SR * 1.4)
    noise = rng.normal(size=n)
    sweep = 2500 * np.exp(-np.linspace(0, 6, n)) + 80
    boom = lowpass(noise, sweep) * np.exp(-np.linspace(0, 5, n))
    thump = np.sin(2 * np.pi * np.cumsum(np.linspace(90, 30, n)) / SR) * np.exp(-np.linspace(0, 7, n))
    save("boom", boom * 1.6 + thump, 0.95)

    # Crowd cheer: swelling band-passed noise with fluttering "voices"
    n = int(SR * 2.6)
    base = bandpass(rng.normal(size=n), 300, 3200)
    flutter = 0.7 + 0.3 * lowpass(rng.normal(size=n), 6) * 8
    swell = np.minimum(1, np.linspace(0, 3, n)) * np.minimum(1, np.linspace(4, 0, n))
    whoo = sum(
        np.sin(2 * np.pi * np.cumsum(np.full(n, f) + 40 * np.sin(np.linspace(0, 3 + i, n))) / SR) * 0.04
        for i, f in enumerate([520, 640, 760, 900])
    )
    save("cheer", (base * flutter + whoo) * swell, 0.8)

    # Crowd groan: noise with falling filter
    n = int(SR * 1.6)
    g = lowpass(rng.normal(size=n), np.linspace(1200, 250, n))
    vow = tone(np.linspace(240, 150, n), 1.6, "saw") * 0.25
    save("groan", (g + lowpass(vow, 900)) * env(n, 0.15, 0.6), 0.7)

    # Reveal: whoosh into a hit
    n = int(SR * 0.5)
    whoosh = bandpass(rng.normal(size=n), 400, 4000) * np.linspace(0, 1, n) ** 2
    hit = tone(196, 0.5, "saw") + tone(293.7, 0.5, "saw") + tone(392, 0.5, "saw")
    hit = lowpass(hit, 2200) * np.exp(-t(0.5) * 5)
    save("reveal", np.concatenate([whoosh * 0.6, hit]), 0.85)

    # Fanfare: brassy C major arpeggio + final chord
    seq = [(523.3, 0.16), (659.3, 0.16), (784.0, 0.16)]
    parts = [lowpass(tone(f, d, "saw"), 2500) * env(int(SR * d), 0.01, 0.03) for f, d in seq]
    chord = sum(tone(f, 1.1, "saw") for f in (523.3, 659.3, 784.0, 1046.5))
    parts.append(lowpass(chord, 2600) * env(int(SR * 1.1), 0.02, 0.5))
    save("fanfare", np.concatenate(parts), 0.85)

    print("Wrote", sorted(p.name for p in OUT.glob("*.wav")))


if __name__ == "__main__":
    main()

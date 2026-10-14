"""Generate the synthesized source loops for the procedural suction events.

Every loop is built on a circular buffer (noise shaped in the frequency domain,
tones and modulators with a whole number of cycles, grains wrapped around the
end), so it loops seamlessly in FMOD. Output: 48 kHz mono 16-bit WAV in
sources/. The seed is fixed, so rerunning gives identical files.

Run: python3 tools/fmod_procedural/generate_sources.py
"""

from pathlib import Path

import numpy as np
from scipy.io import wavfile

RATE = 48_000
LOOP_SECONDS = 6.0
N = int(RATE * LOOP_SECONDS)
OUT = Path(__file__).resolve().parent / "sources"
rng = np.random.default_rng(20261013)
t = np.arange(N) / RATE


def loop_hz(hz: float) -> float:
    """Nearest frequency with a whole number of cycles in the loop."""
    return max(1, round(hz * LOOP_SECONDS)) / LOOP_SECONDS


def shaped_noise(gain_for_freq, length: int = N) -> np.ndarray:
    """Periodic noise whose magnitude spectrum follows gain_for_freq(freqs)."""
    freqs = np.fft.rfftfreq(length, 1 / RATE)
    spectrum = rng.normal(size=freqs.size) + 1j * rng.normal(size=freqs.size)
    spectrum *= gain_for_freq(np.maximum(freqs, 1.0))
    spectrum[0] = 0.0
    return np.fft.irfft(spectrum, length)


def band(freqs, low: float, high: float, slope: float = 2.0) -> np.ndarray:
    """Soft band-pass magnitude curve."""
    return 1 / (1 + (low / freqs) ** (2 * slope)) / (1 + (freqs / high) ** (2 * slope))


def slow_envelope(max_hz: float, low: float, high: float) -> np.ndarray:
    """Smooth periodic random envelope between low and high."""
    env = shaped_noise(lambda f: (f < max_hz).astype(float))
    env = (env - env.min()) / (env.max() - env.min())
    return low + (high - low) * env


def place_grains(grain_maker, per_second: float) -> np.ndarray:
    """Scatter grains at random times, wrapping past the loop end."""
    out = np.zeros(N)
    count = int(per_second * LOOP_SECONDS)
    for start in rng.integers(0, N, count):
        grain = grain_maker()
        idx = (start + np.arange(grain.size)) % N
        np.add.at(out, idx, grain)
    return out


def squelch_grain(scale: float = 1.0) -> np.ndarray:
    """A wet 'blop': a pitch-falling sine plus a short dull noise burst."""
    length = int(RATE * rng.uniform(0.05, 0.14))
    gt = np.arange(length) / RATE
    f_start = rng.uniform(220, 650)
    glide = f_start * np.exp(-gt * rng.uniform(6, 14))
    phase = 2 * np.pi * np.cumsum(glide) / RATE
    decay = np.exp(-gt / rng.uniform(0.02, 0.05))
    attack = np.minimum(1.0, gt / 0.004)
    bloop = np.sin(phase) * decay * attack
    burst = shaped_noise(lambda f: band(f, 120, 1400), length)
    burst = burst / (np.abs(burst).max() + 1e-9) * np.exp(-gt / 0.018) * attack
    return (bloop * 0.8 + burst * 0.35) * rng.uniform(0.4, 1.0) * scale


def saw(hz: float, harmonics: int = 40) -> np.ndarray:
    hz = loop_hz(hz)
    wave = np.zeros(N)
    for k in range(1, harmonics + 1):
        if hz * k > RATE / 2.2:
            break
        wave += np.sin(2 * np.pi * hz * k * t) / k
    return wave


def normalize(signal: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    return signal / (np.abs(signal).max() + 1e-12) * 10 ** (peak_db / 20)


def write(name: str, signal: np.ndarray, peak_db: float = -1.0) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    data = np.clip(normalize(signal, peak_db), -1, 1)
    wavfile.write(OUT / name, RATE, (data * 32767).astype(np.int16))
    print(f"{name}: {data.size / RATE:.2f} s")


# --- Suck: air stream, motor whine, gurgle ---------------------------------

air = shaped_noise(lambda f: f ** -0.5 * band(f, 90, 9000, 1.0))
write("suck_air_loop.wav", air, -3.0)

motor = saw(98) + 0.6 * saw(98 * 1.007) + 0.25 * saw(196.5, 20)
motor_spectrum = np.fft.rfft(motor)
motor_spectrum *= band(np.maximum(np.fft.rfftfreq(N, 1 / RATE), 1.0), 60, 2600, 1.0)
motor = np.fft.irfft(motor_spectrum, N) * (1 + 0.08 * np.sin(2 * np.pi * loop_hz(7) * t))
write("suck_motor_loop.wav", motor, -3.0)

flutter = (0.55 + 0.45 * np.sin(2 * np.pi * loop_hz(13) * t)) ** 2
gurgle = shaped_noise(lambda f: band(f, 400, 2500)) * flutter
gurgle = normalize(gurgle) + 0.7 * normalize(place_grains(lambda: squelch_grain(0.7), 10))
write("suck_gurgle_loop.wav", gurgle, -3.0)

# --- Peel: goo bed, sparse and dense squelch, rubbery stretch --------------

goo = shaped_noise(lambda f: f ** -1.0 * band(f, 30, 650)) * slow_envelope(3, 0.35, 1.0)
write("peel_goo_loop.wav", goo, -3.0)

write("peel_squelch_sparse_loop.wav", place_grains(squelch_grain, 3), -3.0)
write("peel_squelch_dense_loop.wav", place_grains(squelch_grain, 13), -3.0)

vibrato = 1.5 * np.sin(2 * np.pi * loop_hz(5) * t)
stretch_phase = 2 * np.pi * np.cumsum(loop_hz(120) + vibrato) / RATE
stretch_tone = sum(np.sin(k * stretch_phase) / k**1.3 for k in range(1, 9))
# Stick-slip creak: irregular soft clicks about 28 times a second.
creak = place_grains(
    lambda: np.exp(-np.arange(int(RATE * 0.006)) / (RATE * 0.0015)) * rng.uniform(0.3, 1.0),
    28,
)
write("peel_stretch_loop.wav", normalize(stretch_tone) * 0.8 + normalize(creak) * 0.5, -3.0)

# --- Peel snap: one-shot release when the monster comes off the mucus -----

SNAP_SECONDS = 0.6
snap_n = int(RATE * SNAP_SECONDS)
st = np.arange(snap_n) / RATE
click = np.zeros(snap_n)
click_n = int(RATE * 0.004)
click[:click_n] = rng.normal(size=click_n) * np.linspace(1, 0, click_n)
pop_glide = 520 * np.exp(-st * 9) + 110
pop = np.sin(2 * np.pi * np.cumsum(pop_glide) / RATE) * np.exp(-st / 0.07)
tail = shaped_noise(lambda f: band(f, 80, 900), snap_n) * np.exp(-st / 0.12)
snap = normalize(click) * 0.5 + normalize(pop) + normalize(tail) * 0.35
for delay, scale in ((0.13, 0.35), (0.24, 0.22), (0.33, 0.15)):
    drip = squelch_grain(scale)
    start = int(delay * RATE)
    end = min(snap_n, start + drip.size)
    snap[start:end] += drip[: end - start] * 2.0
write("peel_snap.wav", snap, -1.0)

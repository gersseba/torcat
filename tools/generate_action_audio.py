"""Rebuild the original, deterministic gameplay cues using only Python stdlib."""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
DESTINATION = Path(__file__).resolve().parents[1] / "resources/audio/sfx"


def cue(name, duration, level, voice):
    rng = random.Random(name)
    samples = []
    noise = 0.0
    for i in range(round(duration * RATE)):
        t = i / RATE
        raw = rng.uniform(-1, 1)
        noise = 0.78 * noise + 0.22 * raw
        envelope = min(1.0, t / 0.008, (duration - t) / 0.035)
        samples.append(voice(t, raw, noise) * envelope)
    gain = 32767 * level / max(abs(value) for value in samples)
    with wave.open(str(DESTINATION / f"sfx_{name}.wav"), "wb") as file:
        file.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        file.writeframes(b"".join(struct.pack("<h", round(value * gain)) for value in samples))


def tone(t, hz, sweep=0):
    return math.sin(math.tau * (hz * t + sweep * t * t / 2))


def decay(t, speed):
    return math.exp(-t * speed)


cue("shell_windup", .26, .25, lambda t, r, n: t * (tone(t, 190, 1250) + .4 * tone(t, 380, 2500)))
cue("shell_impact", .32, .48, lambda t, r, n: decay(t, 13) * (tone(t, 100, -205) + 1.5 * n + .28 * tone(t, 950)))
cue("pounce_launch", .17, .23, lambda t, r, n: math.sin(math.pi * t / .17) * (n + .17 * tone(t, 240, 1100)))
cue("pounce_hit", .19, .39, lambda t, r, n: decay(t, 22) * (n * 2 + tone(t, 165, -560)))
cue("pounce_land", .13, .25, lambda t, r, n: decay(t, 28) * (n + .45 * tone(t, 112, -280)))
cue("loot_wood", .2, .37, lambda t, r, n: decay(t, 28) * (.4 * r + n + tone(t, 195, -480)))
cue("loot_stone", .22, .36, lambda t, r, n: decay(t, 20) * (.4 * r + n + .4 * tone(t, 731, -450) + .3 * tone(t, 1241)))
cue("loot_rustle", .18, .24, lambda t, r, n: decay(t, 18) * (r - n) * (.6 + .4 * tone(t, 43)))
cue("shell_pack", .15, .26, lambda t, r, n: decay(t, 25) * (n + .55 * tone(t, 410, -1000)))
cue("shell_handoff", .24, .26, lambda t, r, n: decay(t, 17) * (tone(t, 620) + .46 * tone(t, 934)))
cue("step_soft", .10, .12, lambda t, r, n: decay(t, 33) * (n + .16 * r))
cue("step_grit", .12, .13, lambda t, r, n: decay(t, 28) * (.58 * n + .36 * r + .12 * tone(t, 126)))


def breeze(t, raw, noise):
    return noise * (.6 + .25 * tone(t, .5) + .15 * tone(t, .125))


def meadow(t, raw, noise):
    chirp_t = (t + .17) % 2.0
    bird = (tone(chirp_t, 1680, 3400) * math.sin(math.pi * chirp_t / .10) ** 2
            if chirp_t < .10 else 0.0)
    return breeze(t, raw, noise) * .28 + bird * .35


cue("ambience_meadow", 8.0, .13, meadow)
cue("ambience_ridge", 8.0, .11, breeze)

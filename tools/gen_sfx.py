#!/usr/bin/env python3
"""Sintetiza todos los SFX de GJ-Horror (numpy + wave). Reproducible (semilla fija).
Uso: python3 tools/gen_sfx.py [dir_salida]   (por defecto assets/audio/sfx)"""
import sys, os, wave
import numpy as np

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "sfx")
rng = np.random.default_rng(1337)


def noise(n): return rng.standard_normal(n)


def fshape(x, f):
    """Filtra con respuesta f(freqs)->ganancia via FFT (circular: apto para loops)."""
    X = np.fft.rfft(x); fr = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * f(fr), len(x))


def lp(x, fc, order=2): return fshape(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))
def hp(x, fc, order=2): return fshape(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))
def bp(x, lo, hi, order=2): return hp(lp(x, hi, order), lo, order)


def formant(x, fc, bw, g=1.0):
    return g * fshape(x, lambda f: 1 / np.sqrt(1 + ((f - fc) / (bw / 2)) ** 4))


def env_exp(n, tau): return np.exp(-np.arange(n) / SR / tau)


def ad(n, a, tau):
    e = env_exp(n, tau); k = max(1, int(a * SR)); e[:k] *= np.linspace(0, 1, k); return e


def ring(n, freqs, decays, amps=None):
    t = np.arange(n) / SR; y = np.zeros(n)
    for i, (f, d) in enumerate(zip(freqs, decays)):
        y += (amps[i] if amps else 1) * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    return y


def reverb(x, rt, wet=0.5, pre=0.012, tail_lp=3500):
    n = int(rt * 1.3 * SR); t = np.arange(n) / SR
    ir = noise(n) * np.exp(-6.9 * t / rt)
    ir = hp(lp(ir, tail_lp, 1), 120, 1) if tail_lp else hp(ir, 120, 1)
    ir = np.concatenate([np.zeros(int(pre * SR)), ir]); ir /= np.sqrt(np.sum(ir ** 2))
    L = len(x) + len(ir)
    N = 1 << (L - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(ir, N), N)[:L]
    xx = np.concatenate([x, np.zeros(L - len(x))])
    return (1 - wet) * xx + wet * y * 2.2


def trim_tail(x, thr):
    idx = np.where(np.abs(x) > thr * np.max(np.abs(x)))[0]
    return x[: idx[-1] + 1] if len(idx) else x


def save(name, x, peak=0.89, oneshot=True, fade_out=0.02):
    x = np.asarray(x, float)
    if oneshot:
        x = trim_tail(x, 2e-3).copy()
        na, nb = int(0.002 * SR), int(fade_out * SR)
        x[:na] *= np.linspace(0, 1, na); x[-nb:] *= np.linspace(1, 0, nb)
    else:
        x = x - np.mean(x)
    x = x / np.max(np.abs(x)) * peak
    pcm = np.int16(np.round(x * 32767))
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


# ---------------- relojes ----------------
def clock_click(f0, dur=0.09):
    n = int(dur * SR)
    c = bp(noise(n), 1800, 6000) * ad(n, 0.0003, 0.004)
    body = ring(n, [f0, f0 * 2.31, f0 * 3.7], [0.012, 0.008, 0.005], [1, .5, .3]) * ad(n, .0002, 1)
    return c * 0.9 + body * 0.6


def gen_clock():
    save("clock_tick.wav", clock_click(1250), 0.8)
    save("clock_tock.wav", clock_click(930) * 0.95, 0.8)
    n = int(0.22 * SR)
    hit = bp(noise(n), 1200, 7000) * ad(n, 0.0003, 0.006)
    thud = ring(n, [180, 410, 1450, 2600], [0.03, 0.02, 0.012, 0.008], [1, .6, .4, .2]) * ad(n, .0003, 1)
    clack = np.zeros(n); k = int(0.05 * SR)
    clack[k:] += bp(noise(n - k), 2500, 9000) * ad(n - k, 0.0003, 0.004) * 0.5
    save("clock_press.wav", hit + thud * 1.1 + clack, 0.85)


# ---------------- piezas ----------------
def gen_pieces():
    for i, (f, d) in enumerate([(520, 0.05), (610, 0.045), (460, 0.055)], 1):
        n = int(0.25 * SR)
        knock = ring(n, [f, f * 1.9, f * 3.1, f * 4.6], [d, d * .6, d * .4, d * .25], [1, .5, .3, .15]) * ad(n, .0002, 1)
        tap = bp(noise(n), 800, 5000) * ad(n, .0002, 0.005)
        board = ring(n, [160 + 15 * i, 240], [0.06, 0.05], [.5, .3]) * ad(n, .0005, 1)
        save(f"piece_place_{i}.wav", knock + tap * .7 + board, 0.8)


# ---------------- pluma ----------------
def gen_pen():
    n = int(2.5 * SR); t = np.arange(n) / SR
    base = bp(noise(n), 1500, 7500)
    m = np.zeros(n)
    for k, ph in [(5, 0.3), (9, 1.7), (13, 4.0)]:  # enteros por 2.5 s -> periodico
        m += np.sin(2 * np.pi * k / 2.5 * t + ph) / np.sqrt(k)
    m = np.clip(0.55 + 0.45 * m / np.max(np.abs(m)), 0.05, 1) ** 2
    grit = lp(noise(n), 60, 1); grit = np.clip(0.5 + grit / np.std(grit) * 0.35, 0.1, 1.2)
    y = base * m * grit + 0.3 * bp(noise(n), 300, 900) * m
    save("pen_write_loop.wav", y, 0.6, oneshot=False)


# ---------------- pasos ----------------
def footstep(i):
    n = int(0.45 * SR)
    heel = bp(noise(n), 1500 + 150 * i, 6000) * ad(n, .0002, 0.006)
    thump = ring(n, [95 + 7 * i, 170 + 10 * i, 330], [0.05, 0.04, 0.03], [1, .6, .3]) * ad(n, .0004, 1)
    sole = np.zeros(n); k = int((0.085 + 0.006 * (i % 3)) * SR)
    sole[k:] = bp(noise(n - k), 700, 3500) * ad(n - k, .001, 0.02) * 0.4
    return reverb(heel * .8 + thump + sole, 1.6, 0.35, pre=0.02, tail_lp=3000)


def gen_steps():
    for i in range(1, 7): save(f"footstep_{i}.wav", footstep(i), 0.75, fade_out=0.15)


# ---------------- arma ----------------
def gen_gun():
    n = int(0.6 * SR); t = np.arange(n) / SR
    crack = hp(noise(n), 800) * ad(n, .00005, 0.012)
    blast = lp(noise(n), 2500) * ad(n, .0001, 0.05)
    boom = np.sin(2 * np.pi * (45 + 110 * np.exp(-t / 0.04)) * t) * ad(n, .0003, 0.12)
    dry = np.tanh((crack + blast * 1.2 + boom * 1.6) * 1.2)
    save("gunshot.wav", reverb(dry, 1.6, 0.6, pre=0.025, tail_lp=2800), 0.92, fade_out=0.3)


def gen_cock():
    def click(f, tau, amp, delay, n=int(.4 * SR)):
        y = np.zeros(n); k = int(delay * SR); m = n - k
        y[k:] = amp * (bp(noise(m), 2000, 9000) * ad(m, .0002, tau) + ring(m, [f, f * 2.7], [tau * 3, tau * 2], [.6, .3]) * ad(m, .0002, 1))
        return y
    y = click(2200, .004, .6, 0) + click(3100, .005, .8, .12) + click(1500, .006, 1.0, .20) * 1.2
    sl = int(.1 * SR)
    y[int(.02 * SR):int(.02 * SR) + sl] += bp(noise(sl), 300, 1500) * ad(sl, .005, .03) * .25
    save("gun_cock.wav", reverb(y, .9, .2, tail_lp=4000), 0.8, fade_out=0.1)


# ---------------- cuerpos ----------------
def gen_bodies():
    n = int(1.6 * SR)
    y = ring(n, [70, 110, 190], [.12, .09, .06], [1, .7, .4]) * ad(n, .001, 1)
    y += lp(noise(n), 500) * ad(n, .002, .05) * 1.2
    y += ring(n, [140, 260, 480], [.18, .12, .08], [.5, .4, .25]) * ad(n, .001, 1)
    for _ in range(14):  # piezas dispersandose
        k = int(rng.uniform(0.04, 0.9) ** 1.3 * SR + 0.03 * SR); f = rng.uniform(500, 1100); m = int(.18 * SR)
        if k + m < n:
            y[k:k + m] += rng.uniform(.08, .3) * (ring(m, [f, f * 1.9, f * 3], [.03, .02, .01]) + bp(noise(m), 800, 4000) * ad(m, .0002, .004) * .5) * ad(m, .0002, 1)
    for _ in range(4):  # rodar
        k = int(rng.uniform(.3, .8) * SR); m = int(.3 * SR)
        if k + m < n: y[k:k + m] += bp(noise(m), 500, 2500) * ad(m, .05, .12) * .05
    save("body_slump_table.wav", reverb(y, 1.2, .25), 0.85, fade_out=.2)

    n = int(1.4 * SR)
    th = ring(n, [55, 85, 140], [.15, .1, .07], [1, .7, .35]) * ad(n, .001, 1) + lp(noise(n), 350) * ad(n, .003, .06) * 1.3
    k = int(.03 * SR); m = int(.25 * SR); th[k:k + m] += bp(noise(m), 400, 3000) * ad(m, .01, .08) * .3
    k2 = int(.17 * SR); m2 = int(.12 * SR); th[k2:k2 + m2] += ring(m2, [60, 100], [.08, .05]) * .5 * ad(m2, .001, 1)
    save("body_fall_floor.wav", reverb(th, 1.6, .4, tail_lp=2500), 0.85, fade_out=.3)


def gen_chair():
    n = int(0.9 * SR); t = np.arange(n) / SR
    e = np.sin(np.pi * np.clip(t / 0.7, 0, 1)) ** 0.6
    jit = np.abs(0.55 + 0.45 * np.clip(lp(noise(n), 40, 1) / 0.5, -1, 1))
    scr = (bp(noise(n), 500, 3500) + formant(noise(n), 1400, 500, 2.2) + formant(noise(n), 2600, 700, 1.4)) * e * jit
    stick = np.zeros(n)
    for k in np.cumsum(rng.uniform(.015, .05, 18)):
        i = int(k * SR)
        if i + 800 < n: stick[i:i + 800] += rng.uniform(.3, 1) * bp(noise(800), 600, 3000) * ad(800, .0002, .004)
    y = scr * .5 + stick * (e > 0.05) * .9
    k = int(.68 * SR); m = n - k
    y[k:] += (ring(m, [110, 220, 500], [.05, .04, .02], [1, .6, .3]) + bp(noise(m), 300, 2000) * ad(m, .0003, .01)) * ad(m, .0003, 1) * .9
    save("chair_scrape.wav", reverb(y, 1.0, .25), 0.8, fade_out=.15)


# ---------------- voz (sintetica, formantes) ----------------
VOW = {"a": [(800, 90), (1200, 110), (2600, 160)], "e": [(500, 80), (1900, 120), (2600, 160)],
       "o": [(500, 80), (900, 90), (2500, 140)], "u": [(330, 70), (800, 90), (2400, 140)]}


def voice(n, f0, vowel, breath=0.15):
    ph = np.cumsum(f0) / SR
    src = 2 * (ph % 1) - 1
    src = src - np.mean(src) + breath * noise(n)
    y = np.zeros(n)
    for (fc, bw), g in zip(VOW[vowel], [1.0, .6, .3]):
        y += formant(src, fc, bw, g)
    return y


def gen_voice():
    d = 0.9; n = int(d * SR); t = np.arange(n) / SR
    f0 = 330 - 70 * (t / d) + 14 * np.sin(2 * np.pi * 6 * t)
    wob = 1 + 0.35 * np.sin(2 * np.pi * 21 * t)
    mix = np.clip((t - 0.25) / 0.2, 0, 1)
    y = (voice(n, f0, "u", .3) * (1 - mix) + voice(n, f0, "e", .3) * mix) * wob
    e = np.sin(np.pi * t / d) ** 1.5
    y = y * e / np.max(np.abs(y))
    save("whimper.wav", y, 0.6, fade_out=.15)

    d = 4.0; n = int(d * SR)
    y = np.zeros(n)
    for c0, dur, f in [(0.5, .75, 300), (1.65, .7, 285), (2.8, .9, 270)]:
        m = int(dur * SR); tt = np.arange(m) / SR; i = int(c0 * SR)
        f0 = f * (1 - .18 * tt / dur) + 10 * np.sin(2 * np.pi * 5.5 * tt)
        v = voice(m, f0, "o", .35) * (1 + .3 * np.sin(2 * np.pi * 17 * tt)) * np.sin(np.pi * tt / dur) ** 1.4
        v = v / np.std(v) * 0.2
        y[i:i + m] += v
        k = int(.3 * SR)
        y[i - k:i] += bp(noise(k), 600, 3500) * np.sin(np.pi * np.arange(k) / k) ** 2 * .03
    y += 0.01 * lp(noise(n), 2500)
    save("sob_loop.wav", y, 0.55, oneshot=False)

    d = 2.4; n = int(d * SR); t = np.arange(n) / SR
    ph = (t % 0.8) / 0.8
    inh = np.where(ph < .42, np.sin(np.pi * ph / .42) ** 1.3, 0)
    exh = np.where((ph >= .5) & (ph < .95), np.sin(np.pi * (ph - .5) / .45) ** 1.3, 0)
    nz = noise(n)
    y = (formant(nz, 1500, 1200) + formant(nz, 3200, 1500, .6)) * inh \
        + (formant(nz, 900, 800) + formant(nz, 2400, 1400, .5)) * exh * .8 + 0.15 * lp(noise(n), 400) * exh
    save("panic_breath_loop.wav", y, 0.55, oneshot=False)


def gen_ear():
    d = 3.0; n = int(d * SR); t = np.arange(n) / SR
    e = np.exp(-t / 1.4) * np.clip(t / 0.01, 0, 1) * np.where(t > 2.2, np.clip((3.0 - t) / 0.8, 0, 1), 1)
    y = (np.sin(2 * np.pi * 7400 * t) + .5 * np.sin(2 * np.pi * 7422 * t) + .35 * np.sin(2 * np.pi * 4100 * t) + .15 * np.sin(2 * np.pi * 11100 * t)) * e
    save("ear_ring.wav", y * (1 + .05 * np.sin(2 * np.pi * 3 * t)), 0.6, fade_out=.05)


def gen_heart():
    n = int(1.6 * SR); y = np.zeros(n)

    def beat(at, amp, f):
        m = int(.28 * SR); t = np.arange(m) / SR
        b = np.sin(2 * np.pi * (f + 30 * np.exp(-t / .03)) * t) * np.exp(-t / .05) * np.clip(t / .004, 0, 1) + lp(noise(m), 200) * np.exp(-t / .02) * .3
        i = int(at * SR); y[i:i + m] += amp * b
    beat(0.05, 1.0, 48); beat(0.38, .7, 42)
    save("heartbeat_loop.wav", lp(y, 220, 2), 0.85, oneshot=False)


def gen_room():
    n = int(10.0 * SR); t = np.arange(n) / SR
    y = lp(noise(n), 260, 2) + lp(noise(n), 90, 2) * 2.5
    for f, a in [(50, 1.0), (100, .6), (150, .25), (200, .12)]:  # f entero*0.1 Hz -> periodico en 10 s
        y += a * 0.6 * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * (1 + .15 * np.sin(2 * np.pi * 0.2 * t + rng.uniform(0, 6)))
    y += 0.05 * bp(noise(n), 800, 2500) * (1 + np.sin(2 * np.pi * 0.3 * t))
    save("room_tone_loop.wav", y, 0.5, oneshot=False)


# ---------------- foco de teatro (inicio del torneo) ----------------
def stage_light(on):
    """Interruptor/relé de teatro: golpe grave, chasquido metálico y zumbido eléctrico (solo al encender
    queda una cola de ~0,6 s; al apagar el golpe es más seco y el zumbido se corta)."""
    n = int(2.4 * SR); t = np.arange(n) / SR; y = np.zeros(n)
    thump = np.sin(2 * np.pi * (58 + 90 * np.exp(-t / 0.03)) * t) * ad(n, .0004, 0.07 if on else 0.045)
    y += thump * 1.5
    clunk = bp(noise(n), 400, 5000) * ad(n, .0002, 0.012) + ring(n, [1180, 2650, 4100], [.05, .035, .02], [.7, .4, .25]) * ad(n, .0002, 1)
    y += clunk * (1.1 if on else 0.8)
    k = int((0.07 if on else 0.05) * SR)   # segundo chasquido (resorte del contacto)
    y[k:] += 0.55 * (bp(noise(n - k), 1500, 8000) * ad(n - k, .0002, 0.006) + ring(n - k, [3300, 5200], [.03, .02]) * ad(n - k, .0002, 1))
    hum_len = 0.65 if on else 0.05
    hum_env = ad(n, .004, 10.0) * np.clip((hum_len - t) / (0.18 if on else 0.03), 0, 1) * (t > 0.05)
    hum = sum(a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) for f, a in [(100, 1.0), (200, .55), (300, .3), (500, .12)])
    hum = (hum + 0.25 * bp(noise(n), 2000, 7000)) * (1 + .3 * np.sin(2 * np.pi * 9 * t))
    y += hum * hum_env * (0.35 if on else 0.25)
    y = np.tanh(y * 0.9)
    save("stage_light_%s.wav" % ("on" if on else "off"), reverb(y, 2.2, 0.38, pre=0.03, tail_lp=3000), 0.92, fade_out=0.4)


def gen_stage_light():
    stage_light(True); stage_light(False)


if __name__ == "__main__":
    for g in (gen_clock, gen_pieces, gen_pen, gen_steps, gen_gun, gen_cock, gen_bodies, gen_chair, gen_voice, gen_ear, gen_heart, gen_room, gen_stage_light):
        g()
    print("ok ->", os.path.abspath(OUT))

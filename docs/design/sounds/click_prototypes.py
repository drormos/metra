# Metra click sound prototypes (Python/numpy), chosen by ear on 2026-10-19.
# Port the two FINAL voices below into tool/generate_clicks.dart, keeping its
# existing rules: starts at full level on sample 0 (cosine phase), peak
# normalized to accent 0.9 / normal 0.7, mono 16-bit 44.1 kHz.
#
# FINAL
#   Cowbell = cowbell_d (agogo-style high metal bell): accent 1480 Hz, normal 1180 Hz, 220 ms
#   Bell    = bell_a    (small bright ding):           accent 2637 Hz, normal 2093 Hz, 500 ms
# Woodblock and Beep stay exactly as in generate_clicks.dart. Classic is removed.
import numpy as np, wave
SR = 44100

def lp(x, hz):  # one-pole low-pass, primed with the first sample
    a = np.exp(-2*np.pi*hz/SR); y = np.empty_like(x); v = x[0]
    for i, s in enumerate(x): v = (1-a)*s + a*v; y[i] = v
    return y

def hp(x, hz): return x - lp(x, hz)

rng = np.random.default_rng(1)

def modal(f0, partials, dur, noise_amt=0.0, noise_decay=0.002, noise_lp=6000, fade=0.03):
    """Sum of exponentially decaying cosines (ratio, amp, decay_s) + a short
    low-passed noise strike, with a linear fade over the last `fade` seconds."""
    t = np.arange(int(SR*dur))/SR; x = np.zeros_like(t)
    for ratio, amp, dec in partials:
        x += amp*np.exp(-t/dec)*np.cos(2*np.pi*f0*ratio*t)
    if noise_amt:
        n = lp(rng.uniform(-1, 1, len(t)), noise_lp)
        x += noise_amt*np.exp(-t/noise_decay)*n
    k = int(SR*fade); x[-k:] *= np.linspace(1, 0, k)
    return x

# FINAL Cowbell
AGOGO = [(1.0, 1.0, 0.09), (2.32, 0.35, 0.04), (4.1, 0.15, 0.015)]
def cowbell_d(f): return hp(modal(f, AGOGO, 0.22, noise_amt=0.4, noise_decay=0.0015, noise_lp=8000, fade=0.03), 400)

# FINAL Bell
BELL_A = [(1.0, 1.0, 0.35), (2.0, 0.35, 0.2), (2.76, 0.25, 0.08), (5.4, 0.12, 0.03)]
def bell_a(f): return modal(f, BELL_A, 0.5, noise_amt=0.15, noise_decay=0.001, noise_lp=9000, fade=0.08)
# Note: the high-pass in cowbell_d removes a few samples of the attack's DC;
# check the first sample is still the loudest region (zero leading silence).

def save(name, x, peak):
    x = x/np.abs(x).max()*peak
    w = wave.open(name, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x*32767).astype('<i2').tobytes()); w.close()

if __name__ == '__main__':
    save('cowbell_accent.wav', cowbell_d(1480), 0.9); save('cowbell_normal.wav', cowbell_d(1180), 0.7)
    save('bell_accent.wav', bell_a(2637), 0.9);       save('bell_normal.wav', bell_a(2093), 0.7)

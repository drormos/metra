// Generates the click samples in assets/clicks/:
// <sound>_accent.wav and <sound>_normal.wav for every ClickSound.
//
// Run with: dart run tool/generate_clicks.dart
//
// Every sound starts at its loudest on sample 0 (cosine phase), so the
// files have zero leading silence. Peaks are normalized so all sounds play
// at the same level: accent 0.9, normal 0.7 of full scale. Cowbell and Bell
// are ports of the voices chosen by ear in
// docs/design/sounds/click_prototypes.py (cowbell_d, bell_a).
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _sampleRate = 44100;

typedef _Voice = double Function(double t);

void main() {
  // Inharmonic partials (wood bars ring near 1 : 2.76) plus a short noise
  // tick for the strike.
  _pair('woodblock', (accent) {
    final f = accent ? 1250.0 : 950.0;
    final noise = Random(1);
    return (
      _ms(60),
      (t) =>
          exp(-t / 0.012) * cos(_w(f) * t) +
          0.5 * exp(-t / 0.006) * cos(_w(2.76 * f) * t) +
          0.6 * exp(-t / 0.001) * (noise.nextDouble() * 2 - 1),
    );
  });

  // Plain tone with a flat body and a 3 ms release to avoid a tail click.
  _pair('beep', (accent) {
    final f = accent ? 1760.0 : 1320.0;
    const length = 0.035, release = 0.003;
    return (_ms(35), (t) => cos(_w(f) * t) * min(1.0, (length - t) / release));
  });

  // Agogo-style high metal bell: three inharmonic partials and a short
  // noise strike, then a 400 Hz high-pass for a thin, cutting tone.
  _write('cowbell', (accent) {
    final x = _modal(
      accent ? 1480 : 1180,
      const [(1.0, 1.0, 0.09), (2.32, 0.35, 0.04), (4.1, 0.15, 0.015)],
      0.22,
      noiseAmount: 0.4,
      noiseDecay: 0.0015,
      noiseLowPassHz: 8000,
      fade: 0.03,
    );
    return _highPass(x, 400);
  });

  // Small bright ding: a long fundamental with an octave and two
  // inharmonic partials, a faint strike, and an 80 ms fade at the end.
  _write(
    'bell',
    (accent) => _modal(
      accent ? 2637 : 2093,
      const [
        (1.0, 1.0, 0.35),
        (2.0, 0.35, 0.2),
        (2.76, 0.25, 0.08),
        (5.4, 0.12, 0.03),
      ],
      0.5,
      noiseAmount: 0.15,
      noiseDecay: 0.001,
      noiseLowPassHz: 9000,
      fade: 0.08,
    ),
  );
}

/// Exponentially decaying cosines (ratio, amplitude, decay in s) at
/// [f0], plus a short low-passed noise strike, with a linear fade to zero
/// over the last [fade] seconds.
List<double> _modal(
  double f0,
  List<(double, double, double)> partials,
  double seconds, {
  double noiseAmount = 0,
  double noiseDecay = 0.002,
  double noiseLowPassHz = 6000,
  double fade = 0.03,
}) {
  final frames = (_sampleRate * seconds).round();
  final random = Random(1);
  final noise = _lowPass([
    for (var i = 0; i < frames; i++) random.nextDouble() * 2 - 1,
  ], noiseLowPassHz);
  final x = [
    for (var i = 0; i < frames; i++)
      () {
        final t = i / _sampleRate;
        var v = noiseAmount * exp(-t / noiseDecay) * noise[i];
        for (final (ratio, amp, decay) in partials) {
          v += amp * exp(-t / decay) * cos(_w(f0 * ratio) * t);
        }
        return v;
      }(),
  ];
  final k = (_sampleRate * fade).round();
  for (var j = 0; j < k; j++) {
    x[frames - k + j] *= 1 - j / (k - 1);
  }
  return x;
}

/// Writes `<name>_accent.wav` and `<name>_normal.wav` from a voice given
/// as a time function (see [_write] for whole sample lists).
void _pair(String name, (int, _Voice) Function(bool accent) voice) =>
    _write(name, (accent) {
      final (frames, fn) = voice(accent);
      return [for (var i = 0; i < frames; i++) fn(i / _sampleRate)];
    });

/// Writes `<name>_accent.wav` and `<name>_normal.wav`, peak-normalized.
void _write(String name, List<double> Function(bool accent) voice) {
  for (final accent in [true, false]) {
    final shaped = voice(accent);
    final peak = shaped.map((x) => x.abs()).reduce(max);
    final target = accent ? 0.9 : 0.7;
    final samples = Int16List.fromList([
      for (final x in shaped) (x / peak * target * 32767).round(),
    ]);
    File('assets/clicks/${name}_${accent ? 'accent' : 'normal'}.wav')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_wav(samples));
  }
}

/// One-pole low-pass, primed with the first sample so the attack (and the
/// zero-leading-silence guarantee) survives.
List<double> _lowPass(List<double> x, double hz) {
  final a = exp(-2 * pi * hz / _sampleRate);
  var y = x.first;
  return [for (final v in x) y = (1 - a) * v + a * y];
}

/// One-pole high-pass (the input minus its low-pass). The low-pass starts
/// from 0, not primed: primed with the first sample, the output's first
/// sample would be exactly 0 and the attack would be lost.
List<double> _highPass(List<double> x, double hz) {
  final a = exp(-2 * pi * hz / _sampleRate);
  var y = 0.0;
  return [for (final v in x) v - (y = (1 - a) * v + a * y)];
}

double _w(double hz) => 2 * pi * hz;
int _ms(int ms) => _sampleRate * ms ~/ 1000;

Uint8List _wav(Int16List samples) {
  final dataBytes = samples.lengthInBytes;
  final header = ByteData(44)
    ..setUint32(0, 0x52494646) // RIFF
    ..setUint32(4, 36 + dataBytes, Endian.little)
    ..setUint32(8, 0x57415645) // WAVE
    ..setUint32(12, 0x666d7420) // fmt
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, _sampleRate, Endian.little)
    ..setUint32(28, _sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461) // data
    ..setUint32(40, dataBytes, Endian.little);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...samples.buffer.asUint8List(),
  ]);
}

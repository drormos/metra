// Generates the click samples in assets/clicks/:
// <sound>_accent.wav and <sound>_normal.wav for every ClickSound.
//
// Run with: dart run tool/generate_clicks.dart
//
// Every sound starts at its loudest on sample 0 (cosine phase, squares at
// +1), so the files have zero leading silence. Peaks are normalized so all
// sounds play at the same level: accent 0.9, normal 0.7 of full scale.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _sampleRate = 44100;

typedef _Voice = double Function(double t);

void main() {
  _pair('classic', (accent) {
    final f = accent ? 1800.0 : 1200.0;
    final decay = accent ? 0.006 : 0.005;
    return (
      _ms(30),
      (t) => exp(-t / decay) * (cos(_w(f) * t) + 0.3 * cos(_w(2 * f) * t)),
    );
  });

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

  // Two detuned squares (the classic drum-machine cowbell), quick drop then
  // a ringing tail, softened by a low-pass.
  _pair('cowbell', (accent) {
    final f = accent ? 680.0 : 540.0;
    return (
      _ms(250),
      (t) =>
          (0.7 * exp(-t / 0.015) + 0.3 * exp(-t / 0.12)) *
          (_square(f, t) + _square(f * 1.48, t)),
    );
  }, lowPassHz: 4000);
}

/// Writes `<name>_accent.wav` and `<name>_normal.wav`.
void _pair(
  String name,
  (int, _Voice) Function(bool accent) voice, {
  double? lowPassHz,
}) {
  for (final accent in [true, false]) {
    final (frames, fn) = voice(accent);
    final raw = [for (var i = 0; i < frames; i++) fn(i / _sampleRate)];
    final shaped = lowPassHz == null ? raw : _lowPass(raw, lowPassHz);
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

double _w(double hz) => 2 * pi * hz;
int _ms(int ms) => _sampleRate * ms ~/ 1000;
double _square(double hz, double t) => (t * hz) % 1 < 0.5 ? 1 : -1;

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

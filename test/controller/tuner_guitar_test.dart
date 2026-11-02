import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/mic_input.dart';
import 'package:metra/src/controller/tuner_controller.dart';

import '../audio/fake_mic_input.dart';

/// [seconds] of a plucked string at [hz] (Karplus-Strong: a noise burst in
/// a delay line, averaged each pass; a first-order allpass tunes the
/// fractional part of the period), plus mains hum and background noise.
Float32List pluck(
  double hz,
  double seconds, {
  int rate = 48000,
  double noise = 0.004,
  double hum = 0.003,
  int seed = 1,
}) {
  final random = math.Random(seed);
  // The averaging filter delays half a sample.
  final period = rate / hz - 0.5;
  final n = period.floor();
  final d = period - n;
  final c = (1 - d) / (1 + d);
  final line = Float64List.fromList([
    for (var i = 0; i < n; i++) random.nextDouble() * 2 - 1,
  ]);
  final out = Float32List((rate * seconds).round());
  var pos = 0;
  var prev = 0.0;
  var apIn = 0.0;
  var apOut = 0.0;
  for (var i = 0; i < out.length; i++) {
    final x = line[pos];
    // 0.996 per pass: a low E still rings after a few seconds.
    final averaged = 0.996 * 0.5 * (x + prev);
    prev = x;
    apOut = c * averaged + apIn - c * apOut;
    apIn = averaged;
    line[pos] = apOut;
    pos = (pos + 1) % n;
    out[i] =
        0.3 * x +
        hum * math.sin(2 * math.pi * 50 * i / rate) +
        noise * (random.nextDouble() * 2 - 1);
  }
  return out;
}

void main() {
  late FakeMicInput mic;
  late TunerController tuner;

  setUp(() async {
    mic = FakeMicInput(state: MicPermission.granted);
    tuner = TunerController(mic, referenceA4: () => 440);
    await tuner.open();
  });

  tearDown(() => tuner.dispose());

  var heard = 0;
  setUp(() => heard = 0);

  void play(Float32List samples) {
    for (var i = 0; i < samples.length; i += 1024) {
      final end = (i + 1024).clamp(0, samples.length);
      mic.push(Float32List.sublistView(samples, i, end));
    }
  }

  const strings = {
    'E2': 82.41,
    'A2': 110.0,
    'D3': 146.83,
    'G3': 196.0,
    'B3': 246.94,
    'E4': 329.63,
  };

  for (final MapEntry(key: name, value: hz) in strings.entries) {
    for (final offset in [0, -15, 8, 30]) {
      test('$name plucked ${offset == 0 ? 'in tune' : '$offset cents'}, '
          'with hum and noise', () {
        // Just after the attack the string is ~40 dB above the noise; by
        // 1 s it has faded to ~15 dB above (E4) and the reading wobbles a
        // little; by 2 s it may fade into the noise, where the tuner
        // shows nothing rather than a wrong note.
        final samples = pluck(
          hz * math.pow(2, offset / 1200),
          2,
          seed: name.hashCode,
        );
        for (final (at, end, tolerance) in [
          ('0.3 s', 14400, 1.0),
          ('1 s', 48000, 2.0),
          ('2 s', samples.length, null),
        ]) {
          play(Float32List.sublistView(samples, heard, end));
          heard = end;
          final note = tuner.note;
          if (tolerance == null && note == null) continue;
          expect(note, isNotNull, reason: at);
          expect(
            '${note!.name}${note.sharp ? '#' : ''}${note.octave}',
            name,
            reason: at,
          );
          expect(note.cents, closeTo(offset, tolerance ?? 3), reason: at);
        }
      });
    }
  }
}

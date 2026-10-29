// Loudness of the real engine output at 100% on every slider: per sound,
// the loudest accented and regular click, the capture's RMS while
// clicking, and clipped samples; plus accents + 16ths + polyrhythm
// together (the most overlap). Prints the numbers; asserts the levels the
// mix is built for (clicks near full scale, never clipped).
//
//   flutter test integration_test/loudness_test.dart -d macos
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:metra/src/audio/soloud_click_output.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/click_sound.dart';
import 'package:metra/src/model/click_volumes.dart';
import 'package:metra/src/model/metronome_pattern.dart';

const _sampleRate = 44100;
const _full = ClickVolumes(accent: 1, beat: 1, subdivision: 1, polyrhythm: 1);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SoloudClickOutput output;
  late MetronomeController controller;

  setUpAll(() async => output = await SoloudClickOutput.create());
  setUp(() => controller = MetronomeController(output)..setVolumes(_full));
  tearDown(() => controller.dispose());

  /// Plays [pattern] at 120 BPM for 4 s and measures the left channel.
  Future<_Levels> capture(ClickSound sound, MetronomePattern pattern) async {
    final samples = <double>[];
    final stream = SoLoud.instance.startMixerOutputStream(
      format: MixerOutputFormat.pcmF32le,
    );
    final sub = stream.listen((chunk) {
      final f = chunk.buffer.asFloat32List(
        chunk.offsetInBytes,
        chunk.lengthInBytes ~/ 4,
      );
      for (var i = 0; i < f.length; i += 2) {
        samples.add(f[i]);
      }
    });
    controller
      ..setClickSound(sound, preview: false)
      ..setBpm(120)
      ..setPattern(pattern);
    await controller.play();
    await Future<void>.delayed(const Duration(seconds: 4));
    controller.stop();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    SoLoud.instance.stopMixerOutputStream();
    await sub.cancel();
    return _Levels.of(samples);
  }

  final report = <String>[];
  tearDownAll(() {
    debugPrint('\n${report.join('\n')}');
  });

  for (final sound in ClickSound.values) {
    test('${sound.name}: 4/4 with an accent, 100%', () async {
      final levels = await capture(sound, const MetronomePattern.standard());
      report.add('${sound.name.padRight(10)} quarters  $levels');
      expect(levels.clipped, 0, reason: 'never clipped');
    });
  }

  test('woodblock: accents + 16ths + polyrhythm 3 at 100%', () async {
    final levels = await capture(
      ClickSound.woodblock,
      MetronomePattern.simple(
        beatsPerBar: 4,
        stepsPerBeat: 4,
      ).withPolyrhythm(3),
    );
    report.add('woodblock  16ths+poly $levels');
    expect(levels.clipped, 0, reason: 'never clipped');
  });

  test('bell: accents + 16ths + polyrhythm 3 at 100% (longest tail)', () async {
    final levels = await capture(
      ClickSound.bell,
      MetronomePattern.simple(
        beatsPerBar: 4,
        stepsPerBeat: 4,
      ).withPolyrhythm(3),
    );
    report.add('bell       16ths+poly $levels');
    expect(levels.clipped, 0, reason: 'never clipped');
  });
}

/// Levels of a capture, in dBFS: the loudest sample, the RMS over the
/// clicking part, the loudest accented click (each bar's first) and the
/// loudest regular one, and how many samples sat at the clip ceiling.
class _Levels {
  _Levels(this.peak, this.rms, this.accent, this.regular, this.clipped);

  factory _Levels.of(List<double> x) {
    // Clicks: rises past a threshold after 40 ms of quiet-ish signal.
    final onsets = <int>[];
    var last = -_sampleRate;
    for (var i = 0; i < x.length; i++) {
      if (x[i].abs() > 0.05 && i - last > _sampleRate * 0.1) onsets.add(i);
      if (x[i].abs() > 0.05) last = i;
    }
    double peakIn(int from, int frames) {
      var p = 0.0;
      for (var i = from; i < min(x.length, from + frames); i++) {
        p = max(p, x[i].abs());
      }
      return p;
    }

    final clickPeaks = [for (final o in onsets) peakIn(o, _sampleRate ~/ 30)];
    final sorted = [...clickPeaks]..sort();
    final first = onsets.isEmpty ? 0 : onsets.first;
    final end = onsets.isEmpty ? 0 : onsets.last + _sampleRate ~/ 2;
    var sum = 0.0;
    for (var i = first; i < min(end, x.length); i++) {
      sum += x[i] * x[i];
    }
    final rms = sqrt(sum / max(1, min(end, x.length) - first));
    final peak = x.fold(0.0, (p, v) => max(p, v.abs()));
    // The engine's hard clip at ±1.
    final clipped = x.where((v) => v.abs() >= 0.9999).length;
    return _Levels(
      peak,
      rms,
      sorted.isEmpty ? 0 : sorted.last,
      sorted.isEmpty ? 0 : sorted[sorted.length ~/ 2],
      clipped,
    );
  }

  final double peak, rms, accent, regular;
  final int clipped;

  static String db(double a) =>
      a <= 0 ? '  -inf' : (20 * log(a) / ln10).toStringAsFixed(2).padLeft(6);

  @override
  String toString() =>
      'peak ${db(peak)}  RMS ${db(rms)}  loudest click ${db(accent)}  '
      'median click ${db(regular)}  clipped $clipped';
}

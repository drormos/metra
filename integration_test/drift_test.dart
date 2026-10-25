// Acceptance test (PLAN.md Phase 1 step 7): runs the real engine, captures
// the mixer output, and checks every click against the ideal grid.
//
//   flutter test integration_test/drift_test.dart -d macos
//   flutter test integration_test/drift_test.dart -d macos \
//       --dart-define=DRIFT_SECONDS=300   # full 5-minute runs
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:metra/src/audio/soloud_click_output.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';
import 'package:metra/src/model/song_part.dart';

const _seconds = int.fromEnvironment('DRIFT_SECONDS', defaultValue: 20);
const _sampleRate = 44100; // engine default
// Step times are rounded to microseconds, then to samples by the engine.
const _toleranceFrames = 2;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SoloudClickOutput output;
  late MetronomeController controller;

  setUpAll(() async => output = await SoloudClickOutput.create());
  setUp(() => controller = MetronomeController(output));
  tearDown(() => controller.dispose());

  int framesPerBeat(int bpm) => _sampleRate * 60 ~/ bpm;

  for (final bpm in [30, 60, 120, 300]) {
    test('$bpm BPM for $_seconds s stays on the grid', () async {
      final recorder = _OnsetRecorder()..start();
      controller.setBpm(bpm);
      await controller.play();
      await _wait(Duration(seconds: _seconds));
      controller.stop();
      await recorder.stop();

      final onsets = recorder.onsets;
      final expected = _seconds * bpm ~/ 60;
      expect(onsets.length, inInclusiveRange(expected - 1, expected + 1));
      _expectOnGrid(onsets, framesPerBeat(bpm), allowGaps: false);
      _expectAccentsEvery(4, recorder);
    }, timeout: Timeout(Duration(seconds: _seconds + 60)));
  }

  test('triplet subdivisions stay on the grid', () async {
    final recorder = _OnsetRecorder()..start();
    controller.setBpm(120);
    controller.setPattern(
      MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 3),
    );
    await controller.play();
    await _wait(const Duration(seconds: 5));
    controller.stop();
    await recorder.stop();

    // 3 per beat at 120 BPM: 7350 frames apart, every one present.
    _expectOnGrid(recorder.onsets, framesPerBeat(120) ~/ 3, allowGaps: false);
    expect(recorder.onsets.length, inInclusiveRange(29, 31)); // 6 per second
  });

  test('tempo change mid-bar switches interval and keeps the bar', () async {
    final recorder = _OnsetRecorder()..start();
    controller.setBpm(120);
    await controller.play();
    await _wait(const Duration(milliseconds: 2300)); // between beats 5 and 6
    controller.setBpm(90);
    await _wait(const Duration(seconds: 4));
    controller.stop();
    await recorder.stop();

    final intervals = recorder.intervals;
    final fast = framesPerBeat(120), slow = framesPerBeat(90);
    final switchAt = intervals.indexWhere((d) => (d - fast).abs() > 2);
    expect(switchAt, greaterThan(2));
    for (var i = 0; i < intervals.length; i++) {
      expect(
        intervals[i],
        closeTo(i < switchAt ? fast : slow, _toleranceFrames),
        reason: 'interval $i',
      );
    }
    _expectAccentsEvery(4, recorder);
  });

  test('a song switch restarts on beat 1 at the new tempo', () async {
    final recorder = _OnsetRecorder()..start();
    controller.setBpm(120);
    await controller.play();
    await _waitForOnsets(recorder, 3);
    final before = recorder.onsets.length;
    controller.loadSong(bpm: 90, pattern: const MetronomePattern.standard());
    await _waitForOnsets(recorder, before + 6);
    controller.stop();
    await recorder.stop();

    // Find the first click of the new song: everything after it is on a
    // 90 BPM grid starting with an accent.
    final switchAt = recorder.intervals.indexWhere(
      (d) => (d - framesPerBeat(120)).abs() > _toleranceFrames,
    );
    expect(switchAt, greaterThan(0));
    final after = recorder.onsets.sublist(switchAt + 1);
    _expectOnGrid(after, framesPerBeat(90), allowGaps: false);
    final peaks = recorder.peaks.sublist(switchAt + 1);
    expect(peaks[0], greaterThan(peaks[1]), reason: 'beat 1 accented');
  });

  test('a count-in leads into the song on the same grid, beat 1 '
      'accented both times', () async {
    final recorder = _OnsetRecorder()..start();
    controller
      ..setBpm(120)
      ..setOnStart(const OnStart(countInOn: true));
    await controller.play();
    await _waitForOnsets(recorder, 10);
    controller.stop();
    await recorder.stop();

    // 4 count-in beats then the song, with no gap between them.
    _expectOnGrid(recorder.onsets, framesPerBeat(120), allowGaps: false);
    _expectAccentsEvery(4, recorder);
  });

  test('speed up keeps the old interval up to the bar line and the new '
      'one from beat 1', () async {
    final recorder = _OnsetRecorder()..start();
    controller
      ..setBpm(120)
      ..setOnStart(const OnStart(speedUp: true, changeBy: 60, every: 1));
    await controller.play();
    await _waitForOnsets(recorder, 9);
    controller.stop();
    await recorder.stop();

    final intervals = recorder.intervals;
    // Bar 1 at 120 (beat 4 → beat 1 included), bar 2 at 180.
    for (var i = 0; i < 4; i++) {
      expect(intervals[i], closeTo(framesPerBeat(120), _toleranceFrames));
    }
    for (var i = 4; i < 8; i++) {
      expect(intervals[i], closeTo(framesPerBeat(180), _toleranceFrames));
    }
    expect(controller.bpm, 120, reason: 'Stop returns to where it started');
  });

  test('song parts: a part change on a bar line, a one-bar 2/4 part, a '
      'gradual ramp, then an open part', () async {
    SongPart part(String id, int? bars, int from, int to, int beats) =>
        SongPart(
          id: id,
          name: id,
          bars: bars,
          tempoStart: from,
          tempoEnd: to,
          pattern: MetronomePattern.simple(beatsPerBar: beats, stepsPerBeat: 1),
        );
    final recorder = _OnsetRecorder()..start();
    controller.loadSong(
      bpm: 120,
      pattern: const MetronomePattern.standard(),
      parts: [
        part('a', 1, 120, 120, 4),
        part('b', 1, 120, 120, 2), // the odd bar
        part('c', 1, 60, 120, 4), // 60, 80, 100, 120 a beat
        part('d', null, 90, 90, 4),
      ],
    );
    await controller.play();
    await _wait(const Duration(seconds: 7));
    await _waitForOnsets(recorder, 15);
    controller.stop();
    await recorder.stop();

    final f120 = framesPerBeat(120), f90 = framesPerBeat(90);
    final expected = [
      f120, f120, f120, f120, // a, then into b
      f120, f120, // b, then into c
      framesPerBeat(60), framesPerBeat(80), framesPerBeat(100), f120, // c
      f90, f90, f90, f90, // d
    ];
    final intervals = recorder.intervals;
    for (var i = 0; i < expected.length; i++) {
      expect(
        intervals[i],
        closeTo(expected[i], _toleranceFrames),
        reason: 'interval $i',
      );
    }
    // Every part starts on its own beat 1; d accents every 4 beats.
    final peaks = recorder.peaks;
    for (var i = 0; i < 15; i++) {
      expect(
        peaks[i] > 0.9 * peaks[0],
        {0, 4, 6, 10, 14}.contains(i),
        reason: 'click $i accent',
      );
    }
  });

  test('a 1 s stall skips beats but never plays off the grid', () async {
    final recorder = _OnsetRecorder()..start();
    controller.setBpm(120);
    await controller.play();
    await _wait(const Duration(seconds: 2));
    // Block the isolate, like a throttled timer (macOS App Nap).
    final block = Stopwatch()..start();
    while (block.elapsed < const Duration(seconds: 1)) {}
    await _wait(const Duration(seconds: 2));
    controller.stop();
    await recorder.stop();

    final missing = _expectOnGrid(
      recorder.onsets,
      framesPerBeat(120),
      allowGaps: true,
    );
    expect(missing, greaterThan(0), reason: 'the stall should skip beats');
  });

  test('stop silences and play restarts on the downbeat', () async {
    final recorder = _OnsetRecorder()..start();
    controller.setBpm(120);
    await controller.play();
    // Wait for clicks, not wall time: after an idle stop the device can
    // take a moment to start, so the engine clock starts late.
    await _waitForOnsets(recorder, 3);
    controller.stop();
    await _wait(const Duration(seconds: 1));
    await controller.play();
    await _waitForOnsets(recorder, 6);
    controller.stop();
    await recorder.stop();

    // The capture only runs while the device does, and the device idles
    // off 0.5 s after stop, so find the session break by the grid instead
    // of by a long gap.
    final gapAt = recorder.intervals.indexWhere(
      (d) => (d - framesPerBeat(120)).abs() > _toleranceFrames,
    );
    expect(gapAt, greaterThan(0), reason: 'a break while stopped');
    final first = recorder.onsets.sublist(0, gapAt + 1);
    final second = recorder.onsets.sublist(gapAt + 1);
    _expectOnGrid(first, framesPerBeat(120), allowGaps: false);
    _expectOnGrid(second, framesPerBeat(120), allowGaps: false);
    // Both sessions start on an accent.
    expect(recorder.peaks[0], greaterThan(recorder.peaks[1]));
    expect(recorder.peaks[gapAt + 1], greaterThan(recorder.peaks[gapAt + 2]));
  });
}

Future<void> _wait(Duration d) => Future<void>.delayed(d);

Future<void> _waitForOnsets(_OnsetRecorder recorder, int count) async {
  final timeout = Stopwatch()..start();
  while (recorder.onsets.length < count) {
    expect(timeout.elapsed, lessThan(const Duration(seconds: 5)));
    await _wait(const Duration(milliseconds: 20));
  }
}

/// Asserts every onset sits on `first + k * interval`; returns how many
/// grid positions had no click.
int _expectOnGrid(List<int> onsets, int interval, {required bool allowGaps}) {
  expect(onsets.length, greaterThan(1));
  var lastK = 0;
  var missing = 0;
  for (var i = 1; i < onsets.length; i++) {
    final offset = onsets[i] - onsets[0];
    final k = (offset / interval).round();
    expect(
      (offset - k * interval).abs(),
      lessThanOrEqualTo(_toleranceFrames),
      reason: 'click $i is ${offset - k * interval} frames off the grid',
    );
    if (!allowGaps) expect(k, i, reason: 'click $i: missing beat before it');
    missing += k - lastK - 1;
    lastK = k;
  }
  return missing;
}

void _expectAccentsEvery(int n, _OnsetRecorder recorder) {
  final peaks = recorder.peaks;
  for (var i = 0; i < peaks.length; i++) {
    final isAccent = i % n == 0;
    // Default volumes: accents peak at 0.9, beats at 0.8 of that.
    expect(peaks[i] > 0.9 * peaks[0], isAccent, reason: 'click $i accent');
  }
}

/// Finds click onsets in the captured mixer output. Clicks start at full
/// amplitude on their first sample, so an onset is the first sample above a
/// threshold after a quiet gap.
class _OnsetRecorder {
  // Soft subdivision clicks peak near 0.4; a click's tail is far below this
  // within the 50 ms gap.
  static const _threshold = 0.1;
  static const _minGapFrames = _sampleRate ~/ 20; // 50 ms > click length

  final onsets = <int>[];
  final peaks = <double>[];
  int _frame = 0;
  int _lastLoud = -_minGapFrames;
  late StreamSubscription<Uint8List> _sub;

  List<int> get intervals => [
    for (var i = 1; i < onsets.length; i++) onsets[i] - onsets[i - 1],
  ];

  void start() {
    _sub = SoLoud.instance
        .startMixerOutputStream(
          format: MixerOutputFormat.pcmF32le,
          // Must match the engine's channel count (stereo): capture does not
          // convert channels. ~47 s of stereo float absorbs isolate stalls.
          bufferSizeBytes: 16 << 20,
          chunkPCMFrames: 2048,
        )
        .listen(_onChunk);
  }

  Future<void> stop() async {
    // Let the last click's tail reach the capture before stopping.
    await _wait(const Duration(milliseconds: 300));
    SoLoud.instance.stopMixerOutputStream();
    await _sub.cancel();
  }

  void _onChunk(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    // Interleaved stereo; the click is centred, so the left channel is enough.
    for (var i = 0; i + 8 <= bytes.length; i += 8) {
      final x = data.getFloat32(i, Endian.little).abs();
      if (x > _threshold) {
        if (_frame - _lastLoud >= _minGapFrames) {
          onsets.add(_frame);
          peaks.add(x);
        }
        _lastLoud = _frame;
      }
      _frame++;
    }
  }
}

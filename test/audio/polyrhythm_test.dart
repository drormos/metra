import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/click_scheduler.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';

import 'fake_click_output.dart';

const _ms = Duration(milliseconds: 1);

void main() {
  late FakeClickOutput output;
  late ClickScheduler scheduler;

  setUp(() {
    output = FakeClickOutput()..time = _ms * 1000;
    scheduler = ClickScheduler(
      output,
      lookahead: _ms * 150,
      guard: _ms * 60,
      startLead: _ms * 120,
    );
  });
  tearDown(() => scheduler.stop());

  void runFor(Duration span) {
    final end = output.time + span;
    while (output.time < end) {
      output.time += _ms * 25;
      scheduler.refill();
    }
  }

  /// Pulse k of n at k × beats ÷ n beats into each bar, from the first
  /// beat (now + lead = 1120 ms).
  List<int> expected(double bpm, int beats, int n, {int bars = 2}) => [
    for (var bar = 0; bar < bars; bar++)
      for (var k = 0; k < n; k++)
        1120000 + ((bar * beats + k * beats / n) * 60e6 / bpm).round(),
  ];

  List<int> pulsesMicros(int count) => [
    for (final p in output.livePulses.take(count)) p.at.inMicroseconds,
  ];

  void expectTimes(List<int> actual, List<int> want) {
    expect(actual, hasLength(want.length));
    for (final (i, t) in actual.indexed) {
      expect((t - want[i]).abs(), lessThanOrEqualTo(1), reason: 'pulse $i');
    }
  }

  MetronomePattern poly(
    int beats,
    int n, {
    int beatUnit = 4,
    int stepsPerBeat = 1,
  }) => MetronomePattern.simple(
    beatsPerBar: beats,
    stepsPerBeat: stepsPerBeat,
    beatUnit: beatUnit,
  ).withPolyrhythm(n);

  group('pulse timing', () {
    for (final (name, beats, n, unit) in [
      ('3 against 4', 4, 3, 4),
      ('2 against 3', 3, 2, 4),
      ('5 against 4', 4, 5, 4),
      ('3 against 6/8', 6, 3, 8),
    ]) {
      test(name, () async {
        await scheduler.start(
          bpm: 120,
          pattern: poly(beats, n, beatUnit: unit),
        );
        runFor(_ms * 500 * beats * 2 + _ms * 200); // two bars
        expectTimes(pulsesMicros(2 * n), expected(120, beats, n));
        expect(
          output.livePulses.first.at,
          output.liveTimes.first,
          reason: 'pulse 1 lands with beat 1',
        );
      });
    }

    test('subdivisions do not move the pulses', () async {
      await scheduler.start(bpm: 90, pattern: poly(4, 3, stepsPerBeat: 3));
      runFor(_ms * 6000);
      expectTimes(pulsesMicros(6), expected(90, 4, 3));
    });

    test('tempo changes carry the pulses along', () async {
      await scheduler.start(bpm: 120, pattern: poly(4, 3));
      runFor(_ms * 300); // into beat 1 of bar 1
      scheduler.setTempo(60);
      runFor(_ms * 9000);
      final times = [for (final p in output.livePulses) p.at];
      // From the second pulse on, all at the new tempo: 4/3 beat at 60.
      for (var i = 2; i < times.length; i++) {
        expect(
          (times[i] - times[i - 1] - _ms * 1333).inMicroseconds.abs(),
          lessThanOrEqualTo(1000),
        );
      }
    });

    test('muted pulses stay silent; accented ones are accents', () async {
      await scheduler.start(
        bpm: 120,
        pattern: poly(4, 3).cyclePulse(0).cyclePulse(1).cyclePulse(1),
      );
      runFor(_ms * 2100);
      expect(
        [for (final p in output.livePulses) p.level],
        [StepLevel.accent, StepLevel.normal, StepLevel.accent],
        reason: 'pulse 2 of bar 1 is muted; bar 2 starts',
      );
      // Now (3100 ms) pulse 3 (from 2453) sounds until bar 2 at 3120.
      expect(scheduler.pulseAt(output.time)?.pulse, 2);
      expect(scheduler.pulseAt(_ms * 3119)?.pulse, 2);
    });
  });

  group('on / off while playing', () {
    late MetronomeController controller;
    setUp(() => controller = MetronomeController(output));
    tearDown(() => controller.dispose());

    void play(Duration span) {
      final end = output.time + span;
      while (output.time < end) {
        output.time += _ms * 25;
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      }
    }

    test('turning it on starts at the next beat 1', () async {
      await controller.play(); // beat 1 at 1120, bar 2 at 3120
      play(_ms * 600);
      controller.setPolyrhythm(3);
      play(_ms * 3000);
      expect(output.livePulses.first.at, _ms * 3120);
    });

    test('Off stops the pulses at once', () async {
      controller.setPolyrhythm(3);
      await controller.play();
      play(_ms * 700);
      controller.setPolyrhythm(0);
      play(_ms * 3000);
      expect(
        output.livePulses.where((p) => p.at > _ms * 1760), // now + guard
        isEmpty,
      );
      expect(output.livePulses, isNotEmpty, reason: 'pulse 1 played');
    });

    test('beats changed to equal the pulse count turn it off', () {
      controller.setPolyrhythm(3);
      controller.setMeter(3, 4);
      expect(controller.pattern.polyrhythm, 0);
      controller.setPolyrhythm(5);
      controller.setMeter(7, 8);
      expect(controller.pattern.polyrhythm, 5, reason: 'not equal: kept');
    });
  });
}

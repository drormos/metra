import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/click_scheduler.dart';
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

  /// Advance the engine clock in refill-sized steps, refilling each time.
  void runFor(
    Duration span, {
    Duration step = const Duration(milliseconds: 25),
  }) {
    final end = output.time + span;
    while (output.time < end) {
      output.time += step;
      scheduler.refill();
    }
  }

  Future<void> start({double bpm = 120, MetronomePattern? pattern}) => scheduler
      .start(bpm: bpm, pattern: pattern ?? const MetronomePattern.standard());

  test('start prepares the output and anchors at now + lead', () async {
    await start();
    expect(output.prepared, isTrue);
    expect(scheduler.isRunning, isTrue);
    expect(output.liveTimes.first, _ms * 1120);
  });

  test('schedules steps on the grid within the lookahead only', () async {
    await start();
    expect(output.liveTimes, [_ms * 1120]);
    runFor(_ms * 1000); // now 2000, horizon 2150
    expect(output.liveTimes, [_ms * 1120, _ms * 1620, _ms * 2120]);
    // Nothing beyond now + lookahead.
    expect(output.liveTimes.last, lessThanOrEqualTo(output.time + _ms * 150));
  });

  test('uses pattern levels and skips silent steps', () async {
    await start(
      pattern: MetronomePattern(
        beatsPerBar: 3,
        stepsPerBeat: 1,
        steps: const [StepLevel.accent, StepLevel.silent, StepLevel.normal],
      ),
    );
    runFor(_ms * 2600);
    expect(output.live.map((c) => c.level).take(4), [
      StepLevel.accent,
      StepLevel.normal,
      StepLevel.accent,
      StepLevel.normal,
    ]);
    expect(output.liveTimes.take(4), [
      _ms * 1120,
      _ms * 2120,
      _ms * 2620,
      _ms * 3620,
    ]);
  });

  test(
    'a late refill skips past steps instead of playing them off-grid',
    () async {
      await start(bpm: 300); // 200 ms steps
      output.time += _ms * 1000; // timer stalled for a second
      scheduler.refill();
      for (final click in output.live) {
        // Every scheduled click is on the grid ...
        final offset = (click.at - _ms * 1120).inMicroseconds;
        expect(offset % 200000, 0);
      }
      // ... and nothing after the first one is in the past or inside the guard.
      expect(
        output.liveTimes.skip(1),
        everyElement(greaterThanOrEqualTo(output.time + _ms * 60)),
      );
    },
  );

  test('stop cancels pending clicks and releases the output', () async {
    await start();
    runFor(_ms * 100);
    final pending = output.live.where((c) => c.at > output.time).toList();
    expect(pending, isNotEmpty);
    scheduler.stop();
    expect(pending.every((c) => c.cancelled), isTrue);
    expect(scheduler.isRunning, isFalse);
    expect(output.releaseCount, 1);
    final count = output.clicks.length;
    runFor(_ms * 1000);
    expect(output.clicks.length, count);
  });

  test('stop leaves an already sounding click alone', () async {
    await start();
    output.time = _ms * 1130; // first click started 10 ms ago
    scheduler.stop();
    expect(output.clicks.first.cancelled, isFalse);
  });

  test('restart after stop re-anchors from the current engine time', () async {
    await start();
    runFor(_ms * 1000);
    scheduler.stop();
    output.time = _ms * 9000;
    await start();
    expect(output.live.last.at, _ms * 9120);
    expect(output.live.last.level, StepLevel.accent);
  });

  group('setTempo', () {
    test('applies from the last committed step and keeps the bar', () async {
      await start(bpm: 60); // 1000 ms steps: 1120, 2120, 3120 ...
      runFor(_ms * 1050); // now 2050: 1120 sounded, 2120 pending
      expect(output.liveTimes, [_ms * 1120, _ms * 2120]);

      scheduler.setTempo(120);
      // 2120 is beyond now + guard, so it is cancelled. On the new grid
      // the next step (1120 + 500) is already past, so it is re-anchored
      // at now + guard instead.
      runFor(_ms * 2000);
      final times = output.liveTimes;
      expect(times.first, _ms * 1120);
      // Steps after the change are 500 ms apart.
      for (var i = 2; i < times.length; i++) {
        expect(times[i] - times[i - 1], _ms * 500);
      }
      // Bar position carries over: step indices 0, 1, 2, ... -> accent
      // returns on the 5th click.
      expect(output.live[4].level, StepLevel.accent);
    });

    test('keeps the pivot step time when it is still ahead', () async {
      await start(bpm: 120); // 1120, 1620, 2120 ...
      runFor(_ms * 500); // now 1500: 1120 sounded, 1620 pending
      scheduler.setTempo(60);
      runFor(_ms * 3000);
      // 1620 cancelled; new grid from 1120 at 1000 ms -> 2120, 3120, ...
      expect(output.liveTimes.take(3), [_ms * 1120, _ms * 2120, _ms * 3120]);
      expect(output.clicks[1].cancelled, isTrue);
    });

    test('does not cancel a click inside the guard', () async {
      await start(bpm: 120);
      runFor(_ms * 575); // now 1575: 1620 is 45 ms away (< 60 guard)
      scheduler.setTempo(60);
      expect(output.clicks[1].at, _ms * 1620);
      expect(output.clicks[1].cancelled, isFalse);
      runFor(_ms * 2000);
      // Next click 1000 ms after the committed 1620.
      expect(output.liveTimes[2], _ms * 2620);
    });

    test('before the first click keeps the start time', () async {
      await start(bpm: 120);
      scheduler.setTempo(60);
      runFor(_ms * 2000);
      expect(output.liveTimes.take(2), [_ms * 1120, _ms * 2120]);
    });

    test('when stopped does nothing', () async {
      scheduler.setTempo(60);
      expect(output.clicks, isEmpty);
      await scheduler.start(
        bpm: 60,
        pattern: const MetronomePattern.standard(),
      );
      runFor(_ms * 1200);
      expect(output.liveTimes.take(2), [_ms * 1120, _ms * 2120]);
    });
  });

  test('a larger lookahead schedules further ahead', () async {
    await start();
    scheduler.lookahead = _ms * 2000;
    scheduler.refill();
    expect(output.liveTimes.last, greaterThan(output.time + _ms * 1500));
  });

  test('the timer drives refills while running', () {
    fakeAsync((async) {
      scheduler.start(bpm: 120, pattern: const MetronomePattern.standard());
      async.flushMicrotasks();
      final before = output.clicks.length;
      output.time += _ms * 1000;
      async.elapse(_ms * 30);
      expect(output.clicks.length, greaterThan(before));

      scheduler.stop();
      final after = output.clicks.length;
      output.time += _ms * 1000;
      async.elapse(_ms * 100);
      expect(output.clicks.length, after);
    });
  });

  test('stop during start prevents scheduling', () {
    fakeAsync((async) {
      scheduler.start(bpm: 120, pattern: const MetronomePattern.standard());
      scheduler.stop();
      async.flushMicrotasks();
      async.elapse(_ms * 100);
      expect(output.clicks, isEmpty);
      expect(scheduler.isRunning, isFalse);
    });
  });

  group('stepAt', () {
    test('returns the latest step at or before a time', () async {
      await start(); // 1120, 1620, ...
      runFor(_ms * 700); // now 1700
      expect(scheduler.stepAt(_ms * 1100), isNull);
      expect(scheduler.stepAt(_ms * 1120)?.index, 0);
      expect(scheduler.stepAt(_ms * 1619)?.index, 0);
      expect(scheduler.stepAt(_ms * 1650)?.index, 1);
      expect(scheduler.stepAt(_ms * 1650)?.level, StepLevel.normal);
    });

    test('keeps started steps for the retention window', () async {
      await start();
      runFor(_ms * 1050); // now 2050: step 0 (1120) is ~0.9 s old
      expect(scheduler.stepAt(_ms * 1200)?.index, 0);
      runFor(_ms * 200); // now 2250: step 0 is older than 1 s
      expect(scheduler.stepAt(_ms * 1200), isNull);
      expect(scheduler.stepAt(_ms * 1700)?.index, 1);
    });

    test('forgets cancelled steps and everything on stop', () async {
      await start(bpm: 60); // 1120, 2120
      runFor(_ms * 1050); // 2120 pending
      scheduler.setTempo(120);
      expect(scheduler.stepAt(_ms * 2120)?.time, isNot(_ms * 2120));
      scheduler.stop();
      expect(scheduler.stepAt(_ms * 99999), isNull);
    });
  });

  group('switchAtNextBar', () {
    final waltz = MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 1);

    test('finishes the bar, then switches tempo and pattern', () async {
      await start(bpm: 120); // 4/4: 1120, 1620, 2120, 2620 | 3120 ...
      runFor(_ms * 650); // now 1650: steps 0, 1 committed
      scheduler.switchAtNextBar(bpm: 60, pattern: waltz);
      runFor(_ms * 5000);
      expect(output.liveTimes.take(7), [
        _ms * 1120, _ms * 1620, _ms * 2120, _ms * 2620, // old bar, 120 BPM
        _ms * 3120, _ms * 4120, _ms * 5120, // new bar, 60 BPM
      ]);
      expect(output.live.map((c) => c.level).take(8), [
        StepLevel.accent, StepLevel.normal, StepLevel.normal, StepLevel.normal,
        StepLevel.accent, StepLevel.normal, StepLevel.normal, // 3/4
        StepLevel.accent,
      ]);
    });

    test('cancels already scheduled steps of the next bar', () async {
      await start(bpm: 120);
      runFor(_ms * 650);
      scheduler.lookahead = _ms * 3000; // next bar already handed over
      scheduler.refill();
      scheduler.switchAtNextBar(bpm: 60, pattern: waltz);
      scheduler.lookahead = _ms * 150;
      runFor(_ms * 3000);
      final times = output.liveTimes;
      expect(times.take(5), [
        _ms * 1120,
        _ms * 1620,
        _ms * 2120,
        _ms * 2620,
        _ms * 3120,
      ]);
      expect(times[5], _ms * 4120);
    });

    test('before the first click switches from the start', () async {
      await start(bpm: 120);
      scheduler.switchAtNextBar(bpm: 60, pattern: waltz);
      runFor(_ms * 2500);
      expect(output.liveTimes.take(3), [_ms * 1120, _ms * 2120, _ms * 3120]);
    });

    test(
      'a tempo change while a switch is pending applies to the new bar',
      () async {
        await start(bpm: 120);
        runFor(_ms * 650);
        scheduler.switchAtNextBar(bpm: 60, pattern: waltz);
        scheduler.setTempo(30);
        runFor(_ms * 5000);
        final times = output.liveTimes;
        expect(times.take(5), [
          _ms * 1120,
          _ms * 1620,
          _ms * 2120,
          _ms * 2620,
          _ms * 3120,
        ]);
        expect(times[5], _ms * 5120); // 30 BPM = 2 s
      },
    );

    test('a second switch before the bar replaces the first', () async {
      await start(bpm: 120);
      runFor(_ms * 650);
      scheduler.switchAtNextBar(bpm: 60, pattern: waltz);
      scheduler.switchAtNextBar(
        bpm: 240,
        pattern: const MetronomePattern.standard(),
      );
      runFor(_ms * 3000);
      expect(output.liveTimes.skip(4).take(3), [
        _ms * 3120,
        _ms * 3370,
        _ms * 3620,
      ]);
    });

    test('steps report their pattern and bar position', () async {
      await start(bpm: 120);
      runFor(_ms * 650);
      scheduler.switchAtNextBar(bpm: 60, pattern: waltz);
      runFor(_ms * 1500); // now 3150
      final step = scheduler.stepAt(_ms * 3500)!; // first step of new bar
      expect(step.barPosition, 0);
      expect(step.pattern, waltz);
      expect(scheduler.stepAt(_ms * 2700)!.barPosition, 3);
    });
  });
}

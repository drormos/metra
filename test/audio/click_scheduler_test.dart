import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/click_scheduler.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';

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

  group('faster pattern changes', () {
    List<StepLevel> levels() => output.live.map((c) => c.level).toList();

    test('replaceLevels applies from the next open step', () async {
      await start(bpm: 120); // 1120, 1620, 2120, 2620
      runFor(_ms * 1000); // now 2000: 2120 scheduled but beyond the guard
      expect(output.liveTimes.last, _ms * 2120);
      scheduler.replaceLevels(
        MetronomePattern.fromBeats(const [
          StepLevel.accent,
          StepLevel.normal,
          StepLevel.accent, // beat 3 now accented
          StepLevel.normal,
        ], stepsPerBeat: 1),
      );
      runFor(_ms * 1000);
      expect(output.liveTimes.take(4), [
        _ms * 1120,
        _ms * 1620,
        _ms * 2120,
        _ms * 2620,
      ]);
      expect(levels().take(4), [
        StepLevel.accent,
        StepLevel.normal,
        StepLevel.accent,
        StepLevel.normal,
      ]);
    });

    test(
      'a subdivision change starts on the next beat, bar continues',
      () async {
        await start(bpm: 120);
        runFor(_ms * 650); // now 1650: beats 1, 2 committed
        scheduler.switchAtNextBeat(
          bpm: 120,
          pattern: MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 2),
          restartBar: false,
        );
        runFor(_ms * 2000);
        expect(output.liveTimes.take(7), [
          _ms * 1120, _ms * 1620, // quarters
          _ms * 2120, _ms * 2370, _ms * 2620, _ms * 2870, // eighths, beats 3-4
          _ms * 3120, // next bar
        ]);
        expect(levels().take(7), [
          StepLevel.accent, StepLevel.normal,
          StepLevel.normal, StepLevel.soft, StepLevel.normal, StepLevel.soft,
          StepLevel.accent, // bar position kept: downbeat on time
        ]);
      },
    );

    test('a meter change starts a new bar on the next beat', () async {
      await start(bpm: 120);
      runFor(_ms * 650);
      scheduler.switchAtNextBeat(
        bpm: 120,
        pattern: MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 1),
        restartBar: true,
      );
      runFor(_ms * 2500);
      expect(output.liveTimes.take(6), [
        _ms * 1120,
        _ms * 1620,
        _ms * 2120,
        _ms * 2620,
        _ms * 3120,
        _ms * 3620,
      ]);
      expect(levels().take(6), [
        StepLevel.accent, StepLevel.normal,
        StepLevel.accent, StepLevel.normal, StepLevel.normal, // 3/4 bar
        StepLevel.accent,
      ]);
    });

    test('next beat from inside a subdivided beat', () async {
      await start(
        bpm: 120,
        pattern: MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 2),
      ); // 1120, 1370, 1620 ...
      runFor(_ms * 300); // now 1300: 1120 committed, 1370 open
      scheduler.switchAtNextBeat(
        bpm: 120,
        pattern: const MetronomePattern.standard(),
        restartBar: false,
      );
      runFor(_ms * 1500);
      expect(output.liveTimes.take(4), [
        _ms * 1120, _ms * 1370, // beat 1 finishes its eighths
        _ms * 1620, _ms * 2120, // quarters from beat 2
      ]);
    });
  });

  group('restartNow', () {
    final waltz = MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 1);

    test('starts beat 1 of the new song one guard after now', () async {
      await start(bpm: 60); // 1120, 2120, ...
      runFor(_ms * 1500); // now 2500: mid-beat 2
      scheduler.restartNow(bpm: 120, pattern: waltz);
      runFor(_ms * 1600);
      final times = output.liveTimes;
      expect(times.take(2), [_ms * 1120, _ms * 2120], reason: 'already heard');
      // New bar at 2500 + 60, then 500 ms apart.
      expect(times.skip(2).take(4), [
        _ms * 2560,
        _ms * 3060,
        _ms * 3560,
        _ms * 4060,
      ]);
      expect(output.live.map((c) => c.level).skip(2).take(4), [
        StepLevel.accent,
        StepLevel.normal,
        StepLevel.normal,
        StepLevel.accent,
      ]);
    });

    test('cancels clicks already handed over, keeps committed ones', () async {
      await start(bpm: 120);
      scheduler.lookahead = _ms * 2000;
      scheduler.refill(); // 1120 .. 2620 scheduled
      output.time = _ms * 1100; // 1120 is inside the guard: committed
      scheduler.restartNow(bpm: 60, pattern: waltz);
      expect(output.clicks.first.cancelled, isFalse);
      expect(output.clicks.skip(1).take(3).every((c) => c.cancelled), isTrue);
      expect(output.live.map((c) => c.at).skip(1).first, _ms * 1160);
    });

    test('replaces a pending bar switch', () async {
      await start(bpm: 120);
      runFor(_ms * 650);
      scheduler.switchAtNextBar(bpm: 30, pattern: waltz);
      scheduler.restartNow(bpm: 60, pattern: const MetronomePattern.standard());
      runFor(_ms * 3000);
      final times = output.liveTimes;
      expect(times[2], _ms * 1710, reason: 'restart, not the bar switch');
      expect(times[3], _ms * 2710);
    });

    test('no-op while stopped', () {
      scheduler.restartNow(bpm: 60, pattern: waltz);
      expect(output.clicks, isEmpty);
    });
  });

  group('count-in', () {
    final eighths = MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 2);

    test('beats only, beat 1 accented; then the song starts on beat 1 '
        'exactly on time', () async {
      await scheduler.start(
        bpm: 120,
        pattern: eighths.withPolyrhythm(3),
        countInBars: 1,
      );
      expect(scheduler.countingIn, isTrue);
      runFor(_ms * 2500); // now 3500
      final clicks = output.live;
      expect(
        [for (final c in clicks.take(5)) (c.at.inMilliseconds, c.level)],
        [
          (1120, StepLevel.accent),
          (1620, StepLevel.normal),
          (2120, StepLevel.normal),
          (2620, StepLevel.normal),
          (3120, StepLevel.accent), // the song's beat 1, on the grid
        ],
      );
      expect(clicks[5].at, _ms * 3370);
      expect(clicks[5].level, StepLevel.soft);
      expect(
        output.livePulses.first.at,
        _ms * 3120,
        reason: 'no polyrhythm during the count-in',
      );
      expect(scheduler.countingIn, isFalse);
      expect(scheduler.stepAt(_ms * 2620)!.countIn, (bar: 1, bars: 1));
      expect(scheduler.stepAt(_ms * 2620)!.barPosition, 3);
      expect(scheduler.stepAt(_ms * 3120)!.countIn, isNull);
    });

    test('2 bars, in the song\'s time signature', () async {
      await scheduler.start(
        bpm: 120,
        pattern: MetronomePattern.simple(
          beatsPerBar: 3,
          stepsPerBeat: 1,
          beatUnit: 8,
        ),
        countInBars: 2,
      );
      runFor(_ms * 3200); // now 4200
      expect(output.live.map((c) => c.at.inMilliseconds).take(7), [
        1120,
        1620,
        2120,
        2620,
        3120,
        3620,
        4120,
      ]);
      expect(scheduler.stepAt(_ms * 3620)!.countIn, (bar: 2, bars: 2));
      expect(scheduler.stepAt(_ms * 4120)!.countIn, isNull);
      expect(output.live[3].level, StepLevel.accent, reason: 'bar 2, beat 1');
    });

    test(
      'a subdivision change during it lands with the song, not before',
      () async {
        await scheduler.start(bpm: 120, pattern: eighths, countInBars: 1);
        runFor(_ms * 700); // now 1700
        scheduler.switchAtNextBeat(
          bpm: 120,
          pattern: eighths.withSubdivision(4),
          restartBar: false,
        );
        runFor(_ms * 1800); // now 3500
        final times = output.liveTimes.map((t) => t.inMilliseconds).toList();
        expect(times.take(6), [1120, 1620, 2120, 2620, 3120, 3245]);
      },
    );

    test('restartNow (a song loaded while playing) counts in first', () async {
      await start();
      runFor(_ms * 400); // now 1400
      scheduler.restartNow(bpm: 60, pattern: eighths, countInBars: 1);
      runFor(_ms * 5000);
      final after = [
        for (final c in output.live)
          if (c.at > _ms * 1400) (c.at.inMilliseconds, c.level),
      ];
      expect(after.take(6), [
        (1460, StepLevel.accent),
        (2460, StepLevel.normal),
        (3460, StepLevel.normal),
        (4460, StepLevel.normal),
        (5460, StepLevel.accent),
        (5960, StepLevel.soft),
      ]);
    });

    test('stop during it cancels the rest', () async {
      await scheduler.start(bpm: 120, pattern: eighths, countInBars: 1);
      runFor(_ms * 600);
      scheduler.stop();
      expect(scheduler.countingIn, isFalse);
      expect(output.liveTimes.last, lessThanOrEqualTo(output.time));
    });
  });

  group('runs', () {
    List<int> times() => [for (final t in output.liveTimes) t.inMilliseconds];

    test('speed up changes tempo exactly on bar lines; beat 1 of each bar '
        'stays on the grid', () async {
      final tempos = <double>[];
      scheduler.onRunTempo = tempos.add;
      await scheduler.start(
        bpm: 120,
        pattern: const MetronomePattern.standard(),
        run: const OnStart(speedUp: true, changeBy: 10, every: 2),
      );
      runFor(_ms * 9000);
      // Bars 0–1 at 500 ms, from bar 2 (step 8, 5120) at 130 bpm.
      expect(times().take(10), [
        1120, 1620, 2120, 2620, 3120, 3620, 4120, 4620, //
        5120, 5581,
      ]);
      expect(times()[16], 5120 + 3692, reason: 'bar 4 at 140 from here');
      expect(tempos, [130, 140]);
    });

    test('the last beat keeps the old tempo up to the bar line; the new '
        'tempo starts at beat 1 (subdivisions too)', () async {
      await scheduler.start(
        bpm: 120,
        pattern: MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 2),
        run: const OnStart(speedUp: true, changeBy: 60, every: 1),
      );
      runFor(_ms * 3000);
      final t = output.liveTimes;
      // Bar 1 starts at step 8: 1120 + 8 × 250.
      expect(t[8], _ms * 3120);
      expect(t[8] - t[7], _ms * 250, reason: 'last eighth → beat 1: old');
      expect(t[7] - t[6], _ms * 250);
      expect(
        (t[9] - t[8]).inMicroseconds,
        closeTo(166667, 1),
        reason: 'beat 1 → its next click: the first new interval',
      );
    });

    test('the new tempo is reported when the bar line plays, not when it '
        'is scheduled', () async {
      final reported = <(int, double)>[];
      scheduler.onRunTempo = (bpm) =>
          reported.add((output.time.inMilliseconds, bpm));
      await scheduler.start(
        bpm: 120,
        pattern: const MetronomePattern.standard(),
        run: const OnStart(speedUp: true, changeBy: 10, every: 1),
      );
      runFor(_ms * 2100); // bar 1's line (3120) is scheduled by now
      expect(output.liveTimes, contains(_ms * 3120));
      expect(reported, isEmpty);
      runFor(_ms * 50);
      expect(reported, [(3125, 130.0)]);
    });

    test('Until: climbs to it and holds', () async {
      await scheduler.start(
        bpm: 120,
        pattern: const MetronomePattern.standard(),
        run: const OnStart(speedUp: true, changeBy: 20, every: 1, upTo: 150),
      );
      runFor(_ms * 6000);
      final gaps = [
        for (var i = 1; i < output.live.length; i++)
          (output.live[i].at - output.live[i - 1].at).inMilliseconds,
      ];
      // Bar 0 at 120, bar 1 at 140, then 150 forever.
      expect(gaps.sublist(0, 4), [500, 500, 500, 500]);
      expect(gaps.sublist(4, 8), everyElement(closeTo(429, 1)));
      expect(gaps.sublist(8), everyElement(closeTo(400, 1)));
    });

    test(
      'a tempo change by hand mid-run: the next step adds to it, once',
      () async {
        await scheduler.start(
          bpm: 100,
          pattern: const MetronomePattern.standard(),
          run: const OnStart(speedUp: true, changeBy: 10, every: 2),
        );
        runFor(_ms * 2000); // in bar 1
        scheduler.setTempo(60);
        runFor(_ms * 6000);
        final gaps = [
          for (var i = 1; i < output.live.length; i++)
            (output.live[i].at - output.live[i - 1].at).inMilliseconds,
        ];
        // Bar 2 (step 8) and on at 70 = 60 + 10.
        expect(gaps.last, closeTo(857, 1));
        // Re-placing the bar line's step (a beat tap) doesn't add again.
        scheduler.replaceLevels(const MetronomePattern.standard().cycleBeat(2));
        runFor(_ms * 1000);
        expect(
          (output.live.last.at - output.live[output.live.length - 2].at)
              .inMilliseconds,
          closeTo(857, 1),
        );
      },
    );

    test('stop after bars: the last bar plays, the next bar line is '
        'silent, then it ends; count-in bars don\'t count', () async {
      var ended = 0;
      scheduler.onRunEnd = () => ended++;
      await scheduler.start(
        bpm: 120,
        pattern: const MetronomePattern.standard(),
        countInBars: 1,
        run: const OnStart(stopOn: true, stopBy: StopBy.bars, stopBars: 2),
      );
      runFor(_ms * 5600); // song beat 1 at 3120; its bar 2 line at 7120
      expect(times().last, 6620, reason: 'count-in 4 + 2 bars × 4 beats');
      expect(output.live.length, 12);
      expect(ended, 0);
      runFor(_ms * 600); // past 7120
      expect(ended, greaterThanOrEqualTo(1));
      expect(times().last, 6620);
    });

    test('stop after time: at the first bar line past the limit', () async {
      var ended = false;
      scheduler.onRunEnd = () => ended = true;
      await scheduler.start(
        bpm: 120,
        pattern: const MetronomePattern.standard(),
        run: const OnStart(stopOn: true, stopTime: Duration(seconds: 3)),
      );
      runFor(_ms * 6000);
      // Bar lines every 2 s from 1120; 3 s after → the line at 5120.
      expect(times().last, 4620);
      expect(ended, isTrue);
    });

    test(
      'a plan may change tempo on any beat (groundwork for ramps)',
      () async {
        await scheduler.start(
          bpm: 120,
          pattern: const MetronomePattern.standard(),
          run: _OnBeat(bar: 0, beat: 2, bpm: 60),
        );
        runFor(_ms * 3000);
        expect(times().take(4), [1120, 1620, 2120, 3120]);
      },
    );
  });
}

class _OnBeat implements RunPlan {
  _OnBeat({required this.bar, required this.beat, required this.bpm});

  final int bar, beat;
  final double bpm;

  @override
  double? tempoAt(int bar, int beat, double bpm) =>
      bar == this.bar && beat == this.beat ? this.bpm : null;

  @override
  bool endsAt(int bar, Duration elapsed) => false;
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/click_output.dart';
import 'package:metra/src/audio/click_scheduler.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';

import 'fake_click_output.dart';

const _ms = Duration(milliseconds: 1);

/// Records when each click was handed over, to check none came too late.
class _Recording extends FakeClickOutput {
  final late = <String>[];
  Duration guard = Duration.zero;

  void _check(String kind, Duration at) {
    if (at < time + guard - _ms) {
      late.add('$kind at $at handed over at $time (guard $guard)');
    }
  }

  @override
  ClickHandle schedule(StepLevel level, Duration at) {
    _check('click', at);
    return super.schedule(level, at);
  }

  @override
  ClickHandle schedulePulse(StepLevel level, Duration at) {
    _check('pulse', at);
    return super.schedulePulse(level, at);
  }
}

/// Random sequences of everything the scheduler can be asked to do, on the
/// fake clock. Whatever happens: no click is handed to the engine inside
/// the guard (it would play late, off the grid), the clicks that still
/// play are in time order, and nothing throws.
void main() {
  MetronomePattern randomPattern(Random r) {
    final beats = 1 + r.nextInt(12);
    var p = MetronomePattern.simple(
      beatsPerBar: beats,
      stepsPerBeat: 1 + r.nextInt(4),
      beatUnit: r.nextBool() ? 4 : 8,
    );
    if (r.nextInt(3) == 0) {
      final n = 2 + r.nextInt(6);
      if (n != beats) p = p.withPolyrhythm(n);
    }
    return p;
  }

  OnStart? randomRun(Random r) => switch (r.nextInt(4)) {
    0 => null,
    1 => OnStart(
      speedUp: true,
      changeBy: r.nextBool() ? 1 + r.nextInt(20) : -(1 + r.nextInt(20)),
      every: 1 + r.nextInt(4),
      upTo: r.nextBool() ? null : 30 + r.nextInt(271),
    ),
    2 => OnStart(stopOn: true, stopBy: StopBy.bars, stopBars: 1 + r.nextInt(6)),
    _ => OnStart(
      speedUp: true,
      every: 1,
      stopOn: true,
      stopTime: Duration(seconds: 15 + r.nextInt(20)),
    ),
  };

  // More: `flutter test test/audio/scheduler_fuzz_test.dart
  // --dart-define=FUZZ_SESSIONS=5000`.
  const sessions = int.fromEnvironment('FUZZ_SESSIONS', defaultValue: 300);
  for (var seed = 0; seed < sessions; seed++) {
    test('random session $seed', () async {
      final r = Random(seed);
      final output = _Recording()..time = _ms * 1000;
      final scheduler = ClickScheduler(output);
      output.guard = scheduler.guard;
      var ended = 0;
      scheduler.onRunEnd = () {
        ended++;
        scheduler.stop();
      };
      var pattern = randomPattern(r);
      // What was asked and when, for the failure message.
      final log = <String>[];
      void note(String what) =>
          log.add('${output.time.inMilliseconds} ms: $what');

      Future<void> start() {
        final bpm = 30.0 + r.nextInt(271);
        final countIn = r.nextInt(3);
        final run = randomRun(r);
        note(
          'start $bpm ${pattern.timeSignature}x${pattern.stepsPerBeat} '
          'count-in $countIn run ${run != null}',
        );
        return scheduler.start(
          bpm: bpm,
          pattern: pattern,
          countInBars: countIn,
          run: run,
        );
      }

      await start();
      for (var op = 0; op < 120; op++) {
        // Time passes in refill-sized steps, sometimes with a stall.
        final stall = r.nextInt(20) == 0;
        final span = stall ? 300 + r.nextInt(900) : 5 + r.nextInt(400);
        if (stall) {
          note('stall ${span}ms');
          output.time += _ms * span;
          scheduler.refill();
        } else {
          for (var t = 0; t < span; t += 25) {
            output.time += _ms * 25;
            scheduler.refill();
          }
        }
        if (!scheduler.isRunning) {
          if (r.nextBool()) await start();
          continue;
        }
        final bpm = 30.0 + r.nextInt(271);
        switch (r.nextInt(9)) {
          case 0 || 1:
            note('setTempo $bpm');
            scheduler.setTempo(bpm);
          case 2:
            pattern = randomPattern(r);
            note(
              'switchAtNextBeat $bpm ${pattern.timeSignature}x${pattern.stepsPerBeat}',
            );
            scheduler.switchAtNextBeat(
              bpm: bpm,
              pattern: pattern,
              restartBar: r.nextBool(),
            );
          case 3:
            pattern = randomPattern(r);
            note(
              'switchAtNextBar $bpm ${pattern.timeSignature}x${pattern.stepsPerBeat}',
            );
            scheduler.switchAtNextBar(bpm: bpm, pattern: pattern);
          case 4:
            pattern = pattern.cycleBeat(r.nextInt(pattern.beatsPerBar));
            note('replaceLevels');
            scheduler.replaceLevels(pattern);
          case 5:
            pattern = randomPattern(r);
            note(
              'restartNow $bpm ${pattern.timeSignature}x${pattern.stepsPerBeat}',
            );
            scheduler.restartNow(
              bpm: bpm,
              pattern: pattern,
              countInBars: r.nextInt(3),
              run: randomRun(r),
            );
          case 6:
            note('run =');
            scheduler.run = randomRun(r);
          case 7:
            if (pattern.polyrhythm > 0) {
              pattern = pattern.cyclePulse(r.nextInt(pattern.polyrhythm));
              scheduler.replaceLevels(pattern);
            }
          case _:
            note('stop');
            scheduler.stop();
        }
      }
      scheduler.stop();

      String around(Duration t) => log
          .where((l) {
            final at = int.parse(l.split(' ').first);
            return (at - t.inMilliseconds).abs() < 1500;
          })
          .join('\n');
      expect(output.late, isEmpty, reason: 'handed over too late');
      final live = output.live;
      for (var i = 1; i < live.length; i++) {
        expect(
          live[i].at,
          greaterThanOrEqualTo(live[i - 1].at),
          reason:
              'click ${live[i].id} (${live[i].at}) plays before click '
              '${live[i - 1].id} (${live[i - 1].at}), asked:\n'
              '${around(live[i].at)}',
        );
      }
      expect(ended, greaterThanOrEqualTo(0));
    });
  }
}

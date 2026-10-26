import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/click_output.dart';
import 'package:metra/src/audio/click_scheduler.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';
import 'package:metra/src/model/song_part.dart';
import 'package:metra/src/model/song_plan.dart';

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

/// Like scheduler_fuzz_test.dart, for songs with parts: random parts
/// (odd bars, Gradual tempos, polyrhythms, open or not, stop or loop) with
/// jumps, tempo and accent changes, run changes and restarts mixed in. No
/// click is handed over inside the guard, live clicks stay in time order,
/// a part always starts on beat 1 of its own pattern, nothing throws.
void main() {
  MetronomePattern randomPattern(Random r) {
    final beats = 1 + r.nextInt(9);
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

  SongPlan randomPlan(Random r) {
    final count = 2 + r.nextInt(4);
    final parts = [
      for (var i = 0; i < count; i++)
        SongPart(
          id: 'p$i',
          name: 'Part $i',
          bars: 1 + r.nextInt(3),
          tempoStart: 30 + r.nextInt(271),
          tempoEnd: 30 + r.nextInt(271),
          pattern: randomPattern(r),
        ),
    ];
    return SongPlan(
      parts: parts,
      end: SongEnd.values[r.nextInt(SongEnd.values.length)],
      onStart: r.nextInt(4) == 0
          ? OnStart(
              stopOn: true,
              stopBy: StopBy.bars,
              stopBars: 1 + r.nextInt(8),
            )
          : OnStart.off,
      startPart: r.nextInt(count),
    );
  }

  const sessions = int.fromEnvironment('FUZZ_SESSIONS', defaultValue: 200);
  for (var seed = 0; seed < sessions; seed++) {
    test('random parts session $seed', () async {
      final r = Random(seed);
      final output = _Recording()..time = _ms * 1000;
      final scheduler = ClickScheduler(output);
      output.guard = scheduler.guard;
      scheduler.onRunEnd = scheduler.stop;
      var plan = randomPlan(r);
      final log = <String>[];
      void note(String what) =>
          log.add('${output.time.inMilliseconds} ms: $what');

      // Every song bar line handed over: beat 1 of the part's pattern.
      final steps = <ScheduledStep>[];
      void collect() {
        for (var t = output.time; ; t -= _ms * 50) {
          final s = scheduler.stepAt(t);
          if (s == null || steps.any((x) => x.index == s.index)) break;
          steps.add(s);
          if (t < output.time - _ms * 1000) break;
        }
      }

      Future<void> start() {
        plan = randomPlan(r);
        final first = plan.parts[plan.locate(0)!.part];
        note('start ${plan.parts}');
        return scheduler.start(
          bpm: first.tempoStart.toDouble(),
          pattern: first.pattern,
          countInBars: r.nextInt(3),
          run: plan,
        );
      }

      await start();
      for (var op = 0; op < 100; op++) {
        final span = 5 + r.nextInt(400);
        for (var t = 0; t < span; t += 25) {
          output.time += _ms * 25;
          scheduler.refill();
          collect();
        }
        if (!scheduler.isRunning) {
          if (r.nextBool()) await start();
          continue;
        }
        switch (r.nextInt(6)) {
          case 0:
            final part = r.nextInt(plan.parts.length);
            note('jump to $part');
            scheduler.replan((bar) => plan.jump(bar, part));
          case 1:
            final bpm = 30.0 + r.nextInt(271);
            note('setTempo $bpm');
            scheduler.setTempo(bpm);
          case 2:
            // As the controller does: only while the first step that can
            // still change is in the part playing now.
            final step = scheduler.stepAt(output.time);
            final open = scheduler.openBar;
            final samePart =
                step?.bar == null ||
                open == null ||
                plan.locate(step!.bar!)?.part == plan.locate(open)?.part;
            if (step != null && samePart) {
              note('replaceLevels');
              scheduler.replaceLevels(
                step.pattern.cycleBeat(r.nextInt(step.pattern.beatsPerBar)),
              );
            }
          case 3:
            note('restartNow');
            plan = randomPlan(r);
            final first = plan.parts[plan.locate(0)!.part];
            scheduler.restartNow(
              bpm: first.tempoStart.toDouble(),
              pattern: first.pattern,
              countInBars: r.nextInt(3),
              run: plan,
            );
          case 4:
            note('run = same plan');
            scheduler.run = plan;
          case _:
            note('stop');
            scheduler.stop();
        }
      }
      scheduler.stop();

      expect(output.late, isEmpty, reason: 'handed over too late\n$log');
      final live = output.live;
      for (var i = 1; i < live.length; i++) {
        expect(
          live[i].at,
          greaterThanOrEqualTo(live[i - 1].at),
          reason: 'clicks out of order\n${log.join('\n')}',
        );
      }
      for (final s in steps) {
        expect(s.barPosition, lessThan(s.pattern.stepsPerBar));
      }
    });
  }
}

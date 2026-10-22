import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../model/metronome_pattern.dart';
import '../timing/beat_grid.dart';
import 'click_output.dart';

/// One step that has been handed to the engine.
@immutable
class ScheduledStep {
  const ScheduledStep(
    this.index,
    this.time,
    this.level,
    this.handle, {
    required this.pattern,
    required this.barPosition,
    this.countIn,
    this.bar,
  });

  /// Absolute step index.
  final int index;

  /// The pattern this step belongs to, and its position in that bar.
  final MetronomePattern pattern;
  final int barPosition;

  /// Engine time the step plays at.
  final Duration time;

  final StepLevel level;

  /// Null for silent steps.
  final ClickHandle? handle;

  /// For a count-in beat: its bar (1-based) of [bars]; null for the song.
  final ({int bar, int bars})? countIn;

  /// The song bar this step is in, from 0 at the song's beat 1 (count-in
  /// bars don't count); null in a count-in.
  final int? bar;
}

/// What a run does over time (speed up, stop after), asked as the song's
/// beats are scheduled: [tempoAt] at every beat (any beat may change the
/// tempo, from that beat on), [endsAt] at every bar line after the first.
abstract interface class RunPlan {
  /// The tempo from beat [beat] of song bar [bar] (both from 0) on, given
  /// the tempo so far, or null to keep it.
  double? tempoAt(int bar, int beat, double bpm);

  /// Whether the run ends at the line starting song bar [bar], [elapsed]
  /// after the song's beat 1.
  bool endsAt(int bar, Duration elapsed);
}

/// One polyrhythm pulse that has been handed to the engine.
@immutable
class ScheduledPulse {
  const ScheduledPulse({
    required this.pulse,
    required this.count,
    required this.step,
    required this.time,
    required this.end,
    required this.level,
    required this.handle,
  });

  /// Pulse [pulse] (0-based) of [count] in its bar.
  final int pulse;
  final int count;

  /// The step the pulse falls in (it plays at or after that step).
  final int step;

  /// Engine time the pulse plays at, and when the next pulse would start
  /// (the length the lane lights it for).
  final Duration time;
  final Duration end;

  final StepLevel level;

  /// Null for silent (muted) pulses.
  final ClickHandle? handle;
}

/// Lookahead scheduler: a Dart timer tops up the engine with every step
/// inside the next [lookahead] of engine time. Click timing comes only from
/// the engine clock; timer jitter just changes how early a step is handed
/// over.
class ClickScheduler {
  ClickScheduler(
    this._output, {
    this.lookahead = const Duration(milliseconds: 150),
    this.guard = const Duration(milliseconds: 60),
    this.startLead = const Duration(milliseconds: 120),
    this.refillInterval = const Duration(milliseconds: 25),
  }) : assert(startLead > guard, 'the first step must clear the guard');

  final ClickOutput _output;

  /// How far ahead of the engine clock steps are scheduled.
  Duration lookahead;

  /// Steps closer than this to the engine clock are treated as committed:
  /// never cancelled, and skipped if not yet scheduled. Must cover at least
  /// one mix buffer, since the engine clock jumps a buffer at a time.
  final Duration guard;

  /// Delay from start to the first step.
  final Duration startLead;

  final Duration refillInterval;

  /// How long started steps stay queryable through [stepAt].
  static const retention = Duration(seconds: 1);

  final List<ScheduledStep> _steps = [];
  final List<ScheduledPulse> _pulses = [];
  MetronomePattern _pattern = const MetronomePattern.standard();
  BeatGrid? _grid;
  // Step where the current pattern's bar 1 starts.
  int _barStart = 0;
  // A pending switch: from step [_switchAt], use [_nextGrid]/[_nextPattern].
  int? _switchAt;
  BeatGrid? _nextGrid;
  MetronomePattern? _nextPattern;
  int _nextBarStart = 0;
  int _nextStep = 0;
  // Steps before this one are a count-in (null: none in progress), of
  // [_countInBars] bars.
  int? _countInEnd;
  int _countInBars = 0;
  // The run (null: none), its first step, the song bar the last scheduled
  // step is in (−1 before beat 1), and when beat 1 plays.
  RunPlan? _run;
  int _runBegin = 0;
  int _bar = -1;
  Duration? _runStart;
  // Where the run ends (the bar line not scheduled), once decided.
  Duration? _endAt;
  // The step whose tempo the run last changed, and the tempo before it,
  // so scheduling that step again (after a cancel) doesn't add twice.
  int? _planStep;
  double _planFrom = 0;
  // The run's tempo changes not yet reached by the engine clock, by step:
  // (when it plays, the new tempo).
  final Map<int, (Duration, double)> _tempoChanges = {};
  Timer? _timer;
  bool _prepared = false;

  // Bumped by start/stop so a stop during start's await wins.
  int _session = 0;

  bool get isRunning => _timer != null;

  /// Whether a count-in is playing, or about to (the song hasn't been
  /// handed to the engine yet).
  bool get countingIn => _countInEnd != null;

  /// Called when the engine clock reaches a step where the run changed the
  /// tempo (so the shown tempo changes on the bar line, not when the bar
  /// was scheduled), and when it reaches the bar line where the run ends.
  void Function(double bpm)? onRunTempo;
  void Function()? onRunEnd;

  /// When the song's beat 1 plays in this run, or null before it's known.
  Duration? get runStart => _runStart;

  /// Changes to the run apply from the next beat not yet scheduled.
  set run(RunPlan? run) {
    _run = run;
    _endAt = null;
    refill();
  }

  /// The bar a count-in plays: [song]'s beats and time signature, beats
  /// only (no subdivisions, no polyrhythm), beat 1 accented.
  static MetronomePattern countInPattern(MetronomePattern song) =>
      MetronomePattern.simple(
        beatsPerBar: song.beatsPerBar,
        stepsPerBeat: 1,
        beatUnit: song.beatUnit,
      );

  /// The latest step at or before engine time [time], or null. Covers
  /// steps up to [retention] old, so visuals can trail the engine clock.
  ScheduledStep? stepAt(Duration time) {
    for (final step in _steps.reversed) {
      if (step.time <= time) return step;
    }
    return null;
  }

  /// The time from [step] to the next step (or from the one before, when
  /// the next isn't scheduled yet), or null with nothing to compare.
  Duration? stepInterval(ScheduledStep step) {
    final i = _steps.indexWhere((s) => s.index == step.index);
    if (i < 0) return null;
    if (i + 1 < _steps.length) return _steps[i + 1].time - step.time;
    if (i > 0) return step.time - _steps[i - 1].time;
    return null;
  }

  /// The latest polyrhythm pulse at or before engine time [time] that is
  /// still sounding (before the next pulse's start), or null.
  ScheduledPulse? pulseAt(Duration time) {
    for (final pulse in _pulses.reversed) {
      if (pulse.time <= time) return time < pulse.end ? pulse : null;
    }
    return null;
  }

  /// Start a new session: step 0 plays [startLead] after now. With
  /// [countInBars], that many bars of count-in come first, and [pattern]
  /// starts on beat 1 right after them.
  Future<void> start({
    required double bpm,
    required MetronomePattern pattern,
    int countInBars = 0,
    RunPlan? run,
  }) async {
    stop();
    final session = ++_session;
    _pattern = pattern;
    _prepared = true;
    await _output.prepare();
    if (session != _session) return;

    _timer = Timer.periodic(refillInterval, (_) => refill());
    _begin(
      0,
      _output.now() + startLead,
      bpm: bpm,
      pattern: pattern,
      countInBars: countInBars,
      run: run,
    );
  }

  /// A fresh bar 1 at [step], playing at [at]: the count-in's if there is
  /// one (with the switch to [pattern] waiting at its end), else
  /// [pattern]'s.
  void _begin(
    int step,
    Duration at, {
    required double bpm,
    required MetronomePattern pattern,
    required int countInBars,
    RunPlan? run,
  }) {
    final first = countInBars > 0 ? countInPattern(pattern) : pattern;
    _run = run;
    _runBegin = step;
    _runStart = null;
    _planStep = null;
    _tempoChanges.clear();
    _switchAt = null;
    _nextGrid = null;
    _nextPattern = null;
    _countInEnd = null;
    _pattern = first;
    _barStart = step;
    _rewindTo(step);
    _grid = BeatGrid(
      anchor: at,
      anchorStep: step,
      bpm: bpm,
      stepsPerBeat: first.stepsPerBeat,
    );
    if (countInBars > 0) {
      final end = step + countInBars * first.stepsPerBar;
      _countInEnd = end;
      _countInBars = countInBars;
      _scheduleSwitch(_grid!, end, bpm: bpm, pattern: pattern, barStart: end);
    } else {
      refill();
    }
  }

  /// Cancel every step that has not started and stop refilling. A click
  /// that is already sounding rings out.
  void stop() {
    _session++;
    _timer?.cancel();
    _timer = null;
    _grid = null;
    _countInEnd = null;
    _run = null;
    _endAt = null;
    _tempoChanges.clear();
    if (_steps.isNotEmpty || _pulses.isNotEmpty) {
      final now = _output.now();
      for (final step in _steps) {
        if (step.time > now) _cancel(step);
      }
      _steps.clear();
      _cancelPulses((p) => p.time > now);
      _pulses.clear();
    }
    if (_prepared) {
      _prepared = false;
      _output.release();
    }
  }

  /// Change tempo at the next step that is not committed yet. Steps beyond
  /// the guard are cancelled and re-placed; step numbering, and so the bar
  /// position, carries over.
  /// No-op while stopped; [start] takes the tempo.
  void setTempo(double bpm) {
    final grid = _grid;
    if (grid == null) return;
    final switchAt = _switchAt;
    if (switchAt != null) {
      // The current bar keeps its tempo; the pending one takes the change.
      _nextGrid = grid.retempo(
        pivotStep: switchAt,
        bpm: bpm,
        stepsPerBeat: _nextPattern!.stepsPerBeat,
      );
      return;
    }

    final cutoff = _output.now() + guard;
    final lastCommitted = min(_nextStep - 1, grid.lastStepAtOrBefore(cutoff));
    _steps.removeWhere((step) {
      if (step.index <= lastCommitted) return false;
      _cancel(step);
      return true;
    });
    _cancelPulses((p) => p.time > cutoff);

    // Before anything is committed in this segment, its anchor step keeps
    // its time; otherwise the last committed step does.
    final pivot = max(lastCommitted, grid.anchorStep);
    var next = grid.retempo(pivotStep: pivot, bpm: bpm);
    _rewindTo(lastCommitted + 1);
    if (next.stepTime(_nextStep) < cutoff) {
      // Speeding up past steps that are already gone: start the new
      // segment as soon as safely possible.
      next = next.reanchor(step: _nextStep, at: cutoff);
    }
    _grid = next;
    // Pulses between the last committed step and the next one follow the
    // new tempo too.
    _reemitTail(lastCommitted, after: cutoff);
    refill();
  }

  /// Finish the current bar, then continue with [bpm] and [pattern] from
  /// the next bar line (a song change). Steps of the next bar that were
  /// already scheduled are cancelled and re-placed. No-op while stopped.
  void switchAtNextBar({
    required double bpm,
    required MetronomePattern pattern,
  }) {
    final grid = _grid;
    if (grid == null) return;

    var at = _switchAt;
    if (at == null) {
      final firstOpen = _firstOpenStep(grid);
      final intoBar = (firstOpen - _barStart) % _pattern.stepsPerBar;
      at = intoBar == 0
          ? firstOpen
          : firstOpen + _pattern.stepsPerBar - intoBar;
    }
    _scheduleSwitch(grid, at, bpm: bpm, pattern: pattern, barStart: at);
  }

  /// Continue with [pattern] from the next beat (a subdivision or
  /// time-signature change): at most one beat away, and on the pulse. With
  /// [restartBar] that beat becomes beat 1; otherwise the bar position
  /// carries over. Replaces any pending switch. No-op while stopped.
  void switchAtNextBeat({
    required double bpm,
    required MetronomePattern pattern,
    required bool restartBar,
  }) {
    final grid = _grid;
    if (grid == null) return;
    // A count-in plays out; the song starts with the change.
    if (_countInEnd case final end?) {
      return _scheduleSwitch(
        grid,
        end,
        bpm: bpm,
        pattern: pattern,
        barStart: end,
      );
    }

    final firstOpen = _firstOpenStep(grid);
    final perBeat = _pattern.stepsPerBeat;
    final intoBeat = (firstOpen - _barStart) % perBeat;
    final at = intoBeat == 0 ? firstOpen : firstOpen + perBeat - intoBeat;
    final beat = ((at - _barStart) ~/ perBeat) % _pattern.beatsPerBar;
    _scheduleSwitch(
      grid,
      at,
      bpm: bpm,
      pattern: pattern,
      barStart: restartBar ? at : at - beat * pattern.stepsPerBeat,
    );
  }

  /// Restart on beat 1 with [bpm] and [pattern] as soon as safely possible
  /// (a song switch): every step not yet committed is cancelled and the new
  /// bar starts [guard] from now, after [countInBars] of count-in. Replaces
  /// any pending switch. No-op while stopped.
  void restartNow({
    required double bpm,
    required MetronomePattern pattern,
    int countInBars = 0,
    RunPlan? run,
  }) {
    final grid = _grid;
    if (grid == null) return;
    final firstOpen = _firstOpenStep(grid);
    _cancelFrom(firstOpen);
    _cancelPulses((p) => p.time > _output.now() + guard); // the old bar's
    _begin(
      firstOpen,
      _output.now() + guard,
      bpm: bpm,
      pattern: pattern,
      countInBars: countInBars,
      run: run,
    );
  }

  /// Same shape, new levels (accents): applies from the next step that is
  /// not committed yet. With a switch pending, it updates the pending
  /// pattern instead. No-op while stopped.
  void replaceLevels(MetronomePattern pattern) {
    final grid = _grid;
    if (grid == null) return;
    if (_switchAt != null) {
      _nextPattern = pattern;
      return;
    }
    assert(
      pattern.stepsPerBar == _pattern.stepsPerBar &&
          pattern.stepsPerBeat == _pattern.stepsPerBeat,
      'replaceLevels keeps the pattern shape',
    );
    final firstOpen = _firstOpenStep(grid);
    _cancelFrom(firstOpen);
    final cutoff = _output.now() + guard;
    _cancelPulses((p) => p.time > cutoff);
    _pattern = pattern;
    _rewindTo(firstOpen);
    // Pulse states (and a polyrhythm turned off) apply from the next pulse.
    _reemitTail(firstOpen - 1, after: cutoff, pattern: pattern);
    refill();
  }

  /// The first step that can still be changed: not yet within the guard.
  int _firstOpenStep(BeatGrid grid) =>
      min(_nextStep - 1, grid.lastStepAtOrBefore(_output.now() + guard)) + 1;

  void _cancelFrom(int step) => _steps.removeWhere((s) {
    if (s.index < step) return false;
    _cancel(s);
    return true;
  });

  void _cancelPulses(bool Function(ScheduledPulse) test) =>
      _pulses.removeWhere((p) {
        if (!test(p)) return false;
        final handle = p.handle;
        if (handle != null) _output.cancel(handle);
        return true;
      });

  /// Hands over the polyrhythm pulses that fall within [step] (bar
  /// position [barPosition] of [pattern]), on [grid]: pulse k sits at
  /// k × stepsPerBar ÷ n steps into the bar. With [after], only those
  /// later than it.
  void _emitPulses(
    int step,
    int barPosition,
    MetronomePattern pattern,
    BeatGrid grid, {
    Duration? after,
  }) {
    final n = pattern.polyrhythm;
    if (n == 0) return;
    final perBar = pattern.stepsPerBar;
    final barStart = step - barPosition;
    // Pulses k with barPosition <= k * perBar / n < barPosition + 1.
    final first = (barPosition * n + perBar - 1) ~/ perBar;
    final last = ((barPosition + 1) * n + perBar - 1) ~/ perBar - 1;
    for (var k = first; k <= last; k++) {
      final time = grid.timeAt(barStart + pattern.pulseOffset(k));
      if (after != null && time <= after) continue;
      final level = pattern.polyStates[k];
      _pulses.add(
        ScheduledPulse(
          pulse: k,
          count: n,
          step: step,
          time: time,
          end: grid.timeAt(barStart + pattern.pulseOffset(k + 1)),
          level: level,
          handle: level == StepLevel.silent
              ? null
              : _output.schedulePulse(level, time),
        ),
      );
    }
  }

  /// Re-places the pulses of the committed [step] that are still ahead
  /// (after [after]) on the current grid, with [pattern] if given.
  void _reemitTail(
    int step, {
    required Duration after,
    MetronomePattern? pattern,
  }) {
    for (final s in _steps.reversed) {
      if (s.index != step) continue;
      _emitPulses(
        step,
        s.barPosition,
        pattern ?? s.pattern,
        _grid!,
        after: after,
      );
      return;
    }
  }

  void _scheduleSwitch(
    BeatGrid grid,
    int at, {
    required double bpm,
    required MetronomePattern pattern,
    required int barStart,
  }) {
    _cancelFrom(at);
    _cancelPulses((p) => p.step >= at);
    _rewindTo(min(_nextStep, at));
    _switchAt = at;
    _nextPattern = pattern;
    _nextBarStart = barStart;
    _nextGrid = grid.retempo(
      pivotStep: at,
      bpm: bpm,
      stepsPerBeat: pattern.stepsPerBeat,
    );
    refill();
  }

  void _applySwitch() {
    _grid = _nextGrid;
    _pattern = _nextPattern!;
    _barStart = _nextBarStart;
    if (_switchAt == _countInEnd) _countInEnd = null;
    _switchAt = null;
    _nextGrid = null;
    _nextPattern = null;
  }

  /// Hand every step up to now + [lookahead] to the engine. Runs on the
  /// timer; call directly to apply a larger [lookahead] right away.
  void refill() {
    if (_grid == null) return;

    final now = _output.now();
    _reportTempo(now);
    if (_endAt case final end? when now >= end) return onRunEnd?.call();
    // The latest step stays: it carries the bar count on.
    while (_steps.length > 1 && _steps.first.time <= now - retention) {
      _steps.removeAt(0);
    }
    _pulses.removeWhere((pulse) => pulse.end <= now - retention);

    // A stalled timer must not play steps late (they would be off-grid):
    // skip to the first step that can still be placed exactly.
    final cutoff = now + guard;
    final switchAt = _switchAt;
    if (switchAt != null && _grid!.stepTime(switchAt) <= cutoff) {
      _nextStep = max(_nextStep, switchAt);
      _applySwitch();
    }
    // shortcut: bar lines skipped here aren't counted by a run; only a
    // stalled timer skips, which would also break the click itself.
    _nextStep = max(_nextStep, _grid!.firstStepAtOrAfter(cutoff));

    final horizon = now + lookahead;
    while (_endAt == null) {
      if (_nextStep == _switchAt) _applySwitch();
      final barPosition = (_nextStep - _barStart) % _pattern.stepsPerBar;
      final song = _countInEnd == null;
      final bar = song && barPosition == 0 ? _bar + 1 : _bar;
      final run = _run;
      if (song && run != null && barPosition % _pattern.stepsPerBeat == 0) {
        final at = _grid!.stepTime(_nextStep);
        if (barPosition == 0 &&
            bar > 0 &&
            run.endsAt(bar, at - (_runStart ?? at))) {
          _endAt = at; // this bar line is silence
          break;
        }
        _plan(run, bar, barPosition ~/ _pattern.stepsPerBeat);
      }
      final time = _grid!.stepTime(_nextStep);
      if (time > horizon) break;
      if (song && bar == 0 && barPosition == 0) _runStart = time;
      final level = _pattern.steps[barPosition];
      final handle = level == StepLevel.silent
          ? null
          : _output.schedule(level, time);
      _steps.add(
        ScheduledStep(
          _nextStep,
          time,
          level,
          handle,
          pattern: _pattern,
          barPosition: barPosition,
          countIn: _countInEnd == null
              ? null
              : (
                  bar: (_nextStep - _barStart) ~/ _pattern.stepsPerBar + 1,
                  bars: _countInBars,
                ),
          bar: song ? bar : null,
        ),
      );
      _bar = bar;
      _emitPulses(_nextStep, barPosition, _pattern, _grid!);
      _nextStep++;
    }
  }

  /// [run]'s tempo from the next step (a beat of song bar [bar]): placed
  /// with that step kept where it is, and only once per step.
  void _plan(RunPlan run, int bar, int beat) {
    final grid = _grid!;
    final step = _nextStep;
    final again = _planStep == step && grid.anchorStep == step;
    final before = again ? _planFrom : grid.bpm;
    final bpm = run.tempoAt(bar, beat, before) ?? before;
    if (bpm != before) _tempoChanges[step] = (grid.stepTime(step), bpm);
    if (bpm == grid.bpm) return;
    _planStep = step;
    _planFrom = before;
    _grid = grid.retempo(pivotStep: step, bpm: bpm);
  }

  void _reportTempo(Duration now) {
    final due = [
      for (final MapEntry(key: step, value: (at, _)) in _tempoChanges.entries)
        if (at <= now) step,
    ]..sort();
    for (final step in due) {
      onRunTempo?.call(_tempoChanges.remove(step)!.$2);
    }
  }

  /// Steps from [step] on will be (re)scheduled: the bar count and the end
  /// go back to just before it.
  void _rewindTo(int step) {
    _nextStep = step;
    _endAt = null;
    _tempoChanges.removeWhere((at, _) => at >= step);
    _bar = -1;
    for (final s in _steps.reversed) {
      if (s.index >= step) continue;
      if (s.index >= _runBegin) _bar = s.bar ?? -1;
      break;
    }
  }

  void _cancel(ScheduledStep step) {
    final handle = step.handle;
    if (handle != null) _output.cancel(handle);
  }
}

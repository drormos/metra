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

/// A run that also changes the bar's shape (a song's parts): asked at
/// every song bar line, before [RunPlan.tempoAt].
abstract interface class PatternPlan implements RunPlan {
  /// The pattern from song bar [bar] (from 0) on, or null to keep it.
  MetronomePattern? patternAt(int bar);
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
  // Where the run ends (the bar line not scheduled) and that bar, once
  // decided.
  Duration? _endAt;
  int? _endBar;
  // The state before each change applied at a step (a switch, a run's
  // tempo change), newest last: when steps from there are cancelled to be
  // placed again, the state that was in force for them comes back.
  final List<_Before> _undo = [];
  // The run's tempo changes not yet reached by the engine clock, by step:
  // (when it plays, the new tempo).
  final Map<int, (Duration, double)> _tempoChanges = {};
  // Likewise its pattern changes (a song's next part).
  final Map<int, (Duration, MetronomePattern)> _patternChanges = {};
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

  /// Called when the engine clock reaches a bar line where the run changed
  /// the pattern.
  void Function(MetronomePattern pattern)? onRunPattern;

  /// The song bar (from 0) of the first step that can still change; null
  /// in a count-in or while stopped.
  int? get openBar {
    if (_grid == null) return null;
    final cutoff = _output.now() + guard;
    for (final s in _steps) {
      if (s.time > cutoff) return s.bar;
    }
    if (_countInEnd case final end? when _nextStep < end) return null;
    final position = (_nextStep - _barStart) % _pattern.stepsPerBar;
    return position == 0 ? _bar + 1 : _bar;
  }

  /// The song bar whose line ended the run (from 0), once decided.
  int? get endBar => _endAt == null ? null : _endBar;

  /// When the song's beat 1 plays in this run, or null before it's known.
  Duration? get runStart => _runStart;

  /// Changes to the run apply from the next beat not yet scheduled.
  set run(RunPlan? run) {
    _run = run;
    _endAt = null;
    refill();
  }

  /// The run changes from the next bar line not yet committed: steps from
  /// the first open one are taken back, [change] gets that bar (the song
  /// bar it starts, from 0) and they're placed again under the changed
  /// run. No-op while stopped.
  /// With [run], that run takes over there.
  void replan(void Function(int nextBar) change, {RunPlan? run}) {
    if (_grid == null) return;
    _undoFrom(_firstOpenStep());
    if (run != null) {
      _run = run;
      _endAt = null;
    }
    change(_bar + 1);
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
    _undo.clear();
    _tempoChanges.clear();
    _patternChanges.clear();
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
      _scheduleSwitch(end, bpm: bpm, pattern: pattern, barStart: end);
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
    _undo.clear();
    _tempoChanges.clear();
    _patternChanges.clear();
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
    if (_grid == null) return;
    final firstOpen = _firstOpenStep();
    _undoFrom(firstOpen);
    if (_switchAt case final at?) {
      // The current bar keeps its tempo; the pending one takes the change.
      _nextGrid = _grid!.retempo(
        pivotStep: at,
        bpm: bpm,
        stepsPerBeat: _nextPattern!.stepsPerBeat,
      );
      return refill();
    }

    final cutoff = _output.now() + guard;
    final grid = _grid!;
    final lastCommitted = firstOpen - 1;
    // Before anything is committed in this segment, its anchor step keeps
    // its time; otherwise the last committed step does.
    final pivot = max(lastCommitted, grid.anchorStep);
    var next = grid.retempo(pivotStep: pivot, bpm: bpm);
    if (next.stepTime(firstOpen) < cutoff) {
      // Speeding up past steps that are already gone: start the new
      // segment as soon as safely possible.
      next = next.reanchor(step: firstOpen, at: cutoff);
    }
    // Pulses between the last committed step and the next one follow the
    // new tempo too, when the new grid covers that step; otherwise they
    // stay where they are.
    final reemit = _canReemit(lastCommitted, next, null);
    if (reemit) {
      _cancelPulses((p) => p.step == lastCommitted && p.time > cutoff);
    }
    _grid = next;
    if (reemit) _reemitTail(lastCommitted, after: cutoff);
    refill();
  }

  /// Finish the current bar, then continue with [bpm] and [pattern] from
  /// the next bar line (a song change). Steps of the next bar that were
  /// already scheduled are cancelled and re-placed. No-op while stopped.
  void switchAtNextBar({
    required double bpm,
    required MetronomePattern pattern,
  }) {
    if (_grid == null) return;
    final firstOpen = _firstOpenStep();
    _undoFrom(firstOpen);

    var at = _switchAt;
    if (at == null) {
      final intoBar = (firstOpen - _barStart) % _pattern.stepsPerBar;
      at = intoBar == 0
          ? firstOpen
          : firstOpen + _pattern.stepsPerBar - intoBar;
    }
    _scheduleSwitch(at, bpm: bpm, pattern: pattern, barStart: at);
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
    if (_grid == null) return;
    final firstOpen = _firstOpenStep();
    _undoFrom(firstOpen);
    // A count-in plays out; the song starts with the change.
    if (_countInEnd case final end?) {
      return _scheduleSwitch(end, bpm: bpm, pattern: pattern, barStart: end);
    }

    final perBeat = _pattern.stepsPerBeat;
    final intoBeat = (firstOpen - _barStart) % perBeat;
    final at = intoBeat == 0 ? firstOpen : firstOpen + perBeat - intoBeat;
    final beat = ((at - _barStart) ~/ perBeat) % _pattern.beatsPerBar;
    _scheduleSwitch(
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
    if (_grid == null) return;
    final firstOpen = _firstOpenStep();
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
    if (_grid == null) return;
    final firstOpen = _firstOpenStep();
    _undoFrom(firstOpen);
    if (_switchAt != null) {
      _nextPattern = pattern;
      return refill();
    }
    // A song's next part may already be in force there, in another
    // shape: the change was for the part before it, which has no step
    // left to change.
    if (pattern.stepsPerBar != _pattern.stepsPerBar ||
        pattern.stepsPerBeat != _pattern.stepsPerBeat) {
      return refill();
    }
    final cutoff = _output.now() + guard;
    // Pulse states (and a polyrhythm turned off) apply from the next pulse:
    // the last committed step's remaining pulses are placed again when
    // they're from a bar of this shape on this grid.
    final reemit = _canReemit(firstOpen - 1, _grid!, pattern);
    if (reemit) {
      _cancelPulses((p) => p.step == firstOpen - 1 && p.time > cutoff);
    }
    _pattern = pattern;
    if (reemit) _reemitTail(firstOpen - 1, after: cutoff, pattern: pattern);
    refill();
  }

  /// The first step that can still be changed: the first one handed over
  /// that plays after the guard, else the next to hand over. From the
  /// scheduled times, never from grid math: a grid anchored at a later
  /// change doesn't know when the steps before it play.
  int _firstOpenStep() {
    final cutoff = _output.now() + guard;
    for (final s in _steps) {
      if (s.time > cutoff) return s.index;
    }
    return _nextStep;
  }

  /// Takes back every step from [step] on (and its pulses): they'll be
  /// placed again, under the state that was in force for them.
  void _undoFrom(int step) {
    _cancelFrom(step);
    _cancelPulses((p) => p.step >= step);
    _rewindTo(step);
  }

  void _save(int at) => _undo.add((
    at: at,
    grid: _grid!,
    pattern: _pattern,
    barStart: _barStart,
    switchAt: _switchAt,
    nextGrid: _nextGrid,
    nextPattern: _nextPattern,
    nextBarStart: _nextBarStart,
    countInEnd: _countInEnd,
  ));

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
  /// Whether the committed [step]'s remaining pulses can be placed again
  /// on [grid] with [pattern] (null: the step's own): the grid covers the
  /// step, and the step's bar has the pattern's shape.
  bool _canReemit(int step, BeatGrid grid, MetronomePattern? pattern) {
    if (grid.anchorStep > step) return false;
    final s = _steps.where((x) => x.index == step).lastOrNull;
    if (s == null) return false;
    final p = pattern ?? s.pattern;
    return s.pattern.stepsPerBar == p.stepsPerBar &&
        s.barPosition < p.stepsPerBar;
  }

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
    int at, {
    required double bpm,
    required MetronomePattern pattern,
    required int barStart,
  }) {
    _undoFrom(min(_nextStep, at));
    _switchAt = at;
    _nextPattern = pattern;
    _nextBarStart = barStart;
    _nextGrid = _grid!.retempo(
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
      _save(switchAt);
      _applySwitch();
    }
    // shortcut: bar lines skipped here aren't counted by a run; only a
    // stalled timer skips, which would also break the click itself.
    _nextStep = max(_nextStep, _grid!.firstStepAtOrAfter(cutoff));

    final horizon = now + lookahead;
    while (_endAt == null) {
      // A switch or a run's tempo change keeps its step's time, so the grid
      // in force says when the next step plays; changes apply only to steps
      // about to be handed over.
      if (_grid!.stepTime(_nextStep) > horizon) break;
      if (_nextStep == _switchAt) {
        _save(_nextStep);
        _applySwitch();
      }
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
          _endBar = bar;
          break;
        }
        if (barPosition == 0) _planPattern(run, bar);
        _plan(run, bar, barPosition ~/ _pattern.stepsPerBeat);
      }
      final time = _grid!.stepTime(_nextStep);
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
    // Changes at committed steps can't be taken back any more.
    final open = _firstOpenStep();
    _undo.removeWhere((before) => before.at < open);
  }

  /// [run]'s tempo from the next step (a beat of song bar [bar]), placed
  /// with that step kept where it is. Taking the step back restores the
  /// tempo before it, so placing it again never adds twice.
  void _plan(RunPlan run, int bar, int beat) {
    final grid = _grid!;
    final step = _nextStep;
    final bpm = run.tempoAt(bar, beat, grid.bpm);
    if (bpm == null || bpm == grid.bpm) return;
    _save(step);
    _tempoChanges[step] = (grid.stepTime(step), bpm);
    _grid = grid.retempo(pivotStep: step, bpm: bpm);
    // A switch waiting further on starts where this tempo puts it.
    if (_switchAt case final at? when at > step) {
      _nextGrid = _grid!.retempo(
        pivotStep: at,
        bpm: _nextGrid!.bpm,
        stepsPerBeat: _nextGrid!.stepsPerBeat,
      );
    }
  }

  /// [run]'s pattern from the next step (song bar [bar]'s line): a new bar
  /// starts there in it, at the tempo in force. Undone like [_plan].
  void _planPattern(RunPlan run, int bar) {
    if (run is! PatternPlan) return;
    final pattern = run.patternAt(bar);
    if (pattern == null || pattern == _pattern) return;
    final grid = _grid!;
    final step = _nextStep;
    _save(step);
    _patternChanges[step] = (grid.stepTime(step), pattern);
    _pattern = pattern;
    _barStart = step;
    _grid = grid.retempo(
      pivotStep: step,
      bpm: grid.bpm,
      stepsPerBeat: pattern.stepsPerBeat,
    );
  }

  void _reportTempo(Duration now) {
    final patterns = [
      for (final MapEntry(key: step, value: (at, _)) in _patternChanges.entries)
        if (at <= now) step,
    ]..sort();
    for (final step in patterns) {
      onRunPattern?.call(_patternChanges.remove(step)!.$2);
    }
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
    while (_undo.isNotEmpty && _undo.last.at >= step) {
      final before = _undo.removeLast();
      _grid = before.grid;
      _pattern = before.pattern;
      _barStart = before.barStart;
      _switchAt = before.switchAt;
      _nextGrid = before.nextGrid;
      _nextPattern = before.nextPattern;
      _nextBarStart = before.nextBarStart;
      _countInEnd = before.countInEnd;
    }
    _nextStep = step;
    _endAt = null;
    _tempoChanges.removeWhere((at, _) => at >= step);
    _patternChanges.removeWhere((at, _) => at >= step);
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

/// The scheduler's state just before a change applied at step [at].
typedef _Before = ({
  int at,
  BeatGrid grid,
  MetronomePattern pattern,
  int barStart,
  int? switchAt,
  BeatGrid? nextGrid,
  MetronomePattern? nextPattern,
  int nextBarStart,
  int? countInEnd,
});

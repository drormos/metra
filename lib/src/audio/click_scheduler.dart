import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../model/metronome_pattern.dart';
import '../timing/beat_grid.dart';
import 'click_output.dart';

/// One step that has been handed to the engine.
@immutable
class ScheduledStep {
  const ScheduledStep(this.index, this.time, this.level, this.handle);

  /// Absolute step index (bar position is `index % stepsPerBar`).
  final int index;

  /// Engine time the step plays at.
  final Duration time;

  final StepLevel level;

  /// Null for silent steps.
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
  MetronomePattern _pattern = const MetronomePattern.standard();
  BeatGrid? _grid;
  int _nextStep = 0;
  Timer? _timer;
  bool _prepared = false;

  // Bumped by start/stop so a stop during start's await wins.
  int _session = 0;

  bool get isRunning => _timer != null;

  /// The latest step at or before engine time [time], or null. Covers
  /// steps up to [retention] old, so visuals can trail the engine clock.
  ScheduledStep? stepAt(Duration time) {
    for (final step in _steps.reversed) {
      if (step.time <= time) return step;
    }
    return null;
  }

  /// Start a new session: step 0 plays [startLead] after now.
  Future<void> start({
    required double bpm,
    required MetronomePattern pattern,
  }) async {
    stop();
    final session = ++_session;
    _pattern = pattern;
    _prepared = true;
    await _output.prepare();
    if (session != _session) return;

    _grid = BeatGrid(
      anchor: _output.now() + startLead,
      bpm: bpm,
      stepsPerBeat: pattern.stepsPerBeat,
    );
    _nextStep = 0;
    _timer = Timer.periodic(refillInterval, (_) => refill());
    refill();
  }

  /// Cancel every step that has not started and stop refilling. A click
  /// that is already sounding rings out.
  void stop() {
    _session++;
    _timer?.cancel();
    _timer = null;
    _grid = null;
    if (_steps.isNotEmpty) {
      final now = _output.now();
      for (final step in _steps) {
        if (step.time > now) _cancel(step);
      }
      _steps.clear();
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

    final cutoff = _output.now() + guard;
    final lastCommitted = min(_nextStep - 1, grid.lastStepAtOrBefore(cutoff));
    _steps.removeWhere((step) {
      if (step.index <= lastCommitted) return false;
      _cancel(step);
      return true;
    });

    // Before anything is committed in this segment, its anchor step keeps
    // its time; otherwise the last committed step does.
    final pivot = max(lastCommitted, grid.anchorStep);
    var next = grid.retempo(pivotStep: pivot, bpm: bpm);
    _nextStep = lastCommitted + 1;
    if (next.stepTime(_nextStep) < cutoff) {
      // Speeding up past steps that are already gone: start the new
      // segment as soon as safely possible.
      next = next.reanchor(step: _nextStep, at: cutoff);
    }
    _grid = next;
    refill();
  }

  /// Hand every step up to now + [lookahead] to the engine. Runs on the
  /// timer; call directly to apply a larger [lookahead] right away.
  void refill() {
    final grid = _grid;
    if (grid == null) return;

    final now = _output.now();
    _steps.removeWhere((step) => step.time <= now - retention);

    // A stalled timer must not play steps late (they would be off-grid):
    // skip to the first step that can still be placed exactly.
    _nextStep = max(_nextStep, grid.firstStepAtOrAfter(now + guard));

    final horizon = now + lookahead;
    while (true) {
      final time = grid.stepTime(_nextStep);
      if (time > horizon) break;
      final level = _pattern.levelAt(_nextStep);
      final handle = level == StepLevel.silent
          ? null
          : _output.schedule(level, time);
      _steps.add(ScheduledStep(_nextStep, time, level, handle));
      _nextStep++;
    }
  }

  void _cancel(ScheduledStep step) {
    final handle = step.handle;
    if (handle != null) _output.cancel(handle);
  }
}

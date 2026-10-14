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
  // Step where the current pattern's bar 1 starts.
  int _barStart = 0;
  // A pending switch: from step [_switchAt], use [_nextGrid]/[_nextPattern].
  int? _switchAt;
  BeatGrid? _nextGrid;
  MetronomePattern? _nextPattern;
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
    _barStart = 0;
    _switchAt = null;
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

  /// Finish the current bar, then continue with [bpm] and [pattern] from
  /// the next bar line (a song or time-signature change). Steps of the next
  /// bar that were already scheduled are cancelled and re-placed.
  /// No-op while stopped.
  void switchAtNextBar({
    required double bpm,
    required MetronomePattern pattern,
  }) {
    final grid = _grid;
    if (grid == null) return;

    var at = _switchAt;
    if (at == null) {
      final cutoff = _output.now() + guard;
      final firstOpen = min(_nextStep - 1, grid.lastStepAtOrBefore(cutoff)) + 1;
      final intoBar = (firstOpen - _barStart) % _pattern.stepsPerBar;
      at = intoBar == 0
          ? firstOpen
          : firstOpen + _pattern.stepsPerBar - intoBar;
    }
    final switchAt = at;
    _steps.removeWhere((step) {
      if (step.index < switchAt) return false;
      _cancel(step);
      return true;
    });
    _nextStep = min(_nextStep, switchAt);
    _switchAt = switchAt;
    _nextPattern = pattern;
    _nextGrid = grid.retempo(
      pivotStep: switchAt,
      bpm: bpm,
      stepsPerBeat: pattern.stepsPerBeat,
    );
    refill();
  }

  void _applySwitch() {
    _grid = _nextGrid;
    _pattern = _nextPattern!;
    _barStart = _switchAt!;
    _switchAt = null;
    _nextGrid = null;
    _nextPattern = null;
  }

  /// Hand every step up to now + [lookahead] to the engine. Runs on the
  /// timer; call directly to apply a larger [lookahead] right away.
  void refill() {
    if (_grid == null) return;

    final now = _output.now();
    _steps.removeWhere((step) => step.time <= now - retention);

    // A stalled timer must not play steps late (they would be off-grid):
    // skip to the first step that can still be placed exactly.
    final cutoff = now + guard;
    final switchAt = _switchAt;
    if (switchAt != null && _grid!.stepTime(switchAt) <= cutoff) {
      _nextStep = max(_nextStep, switchAt);
      _applySwitch();
    }
    _nextStep = max(_nextStep, _grid!.firstStepAtOrAfter(cutoff));

    final horizon = now + lookahead;
    while (true) {
      if (_nextStep == _switchAt) _applySwitch();
      final time = _grid!.stepTime(_nextStep);
      if (time > horizon) break;
      final barPosition = (_nextStep - _barStart) % _pattern.stepsPerBar;
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
        ),
      );
      _nextStep++;
    }
  }

  void _cancel(ScheduledStep step) {
    final handle = step.handle;
    if (handle != null) _output.cancel(handle);
  }
}

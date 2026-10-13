import 'package:flutter/foundation.dart';

/// Maps absolute step indices to engine times for one tempo segment.
///
/// Step `n` plays at `anchor + (n - anchorStep) * stepInterval`, computed in
/// doubles and rounded once, so long runs never accumulate rounding error.
/// A tempo change starts a new segment via [retempo] instead of mutating the
/// old one, so step numbering (and therefore bar position) carries over.
@immutable
class BeatGrid {
  BeatGrid({
    required this.anchor,
    required this.bpm,
    this.anchorStep = 0,
    this.stepsPerBeat = 1,
  }) {
    if (bpm <= 0) throw ArgumentError.value(bpm, 'bpm', 'must be > 0');
    if (stepsPerBeat < 1) {
      throw ArgumentError.value(stepsPerBeat, 'stepsPerBeat', 'must be >= 1');
    }
  }

  /// Engine time of [anchorStep].
  final Duration anchor;

  /// Absolute index of the step that plays at [anchor].
  final int anchorStep;

  final double bpm;
  final int stepsPerBeat;

  double get _stepMicros =>
      Duration.microsecondsPerMinute / (bpm * stepsPerBeat);

  Duration get stepInterval => Duration(microseconds: _stepMicros.round());

  Duration stepTime(int step) {
    final offset =
        (step - anchorStep) *
        Duration.microsecondsPerMinute /
        (bpm * stepsPerBeat);
    return anchor + Duration(microseconds: offset.round());
  }

  /// Smallest step `>= anchorStep` whose time is at or after [time].
  int firstStepAtOrAfter(Duration time) {
    final steps = (time - anchor).inMicroseconds / _stepMicros;
    final n = anchorStep + (steps - _epsilon).ceil();
    return n < anchorStep ? anchorStep : n;
  }

  /// Largest step whose time is at or before [time] (may be before
  /// [anchorStep]).
  int lastStepAtOrBefore(Duration time) {
    final steps = (time - anchor).inMicroseconds / _stepMicros;
    return anchorStep + (steps + _epsilon).floor();
  }

  /// New segment at [bpm] (and optionally [stepsPerBeat]) where [pivotStep]
  /// keeps its current time and later steps follow the new interval.
  BeatGrid retempo({
    required int pivotStep,
    required double bpm,
    int? stepsPerBeat,
  }) => BeatGrid(
    anchor: stepTime(pivotStep),
    anchorStep: pivotStep,
    bpm: bpm,
    stepsPerBeat: stepsPerBeat ?? this.stepsPerBeat,
  );

  /// Same tempo, with [step] moved to [at].
  BeatGrid reanchor({required int step, required Duration at}) => BeatGrid(
    anchor: at,
    anchorStep: step,
    bpm: bpm,
    stepsPerBeat: stepsPerBeat,
  );

  // Tolerance in steps for float noise at exact grid times.
  static const _epsilon = 1e-9;
}

import 'package:flutter/foundation.dart';

/// How a single step of a pattern sounds.
enum StepLevel { accent, normal, silent }

/// One bar of a metronome pattern: [beatsPerBar] beats, each split into
/// [stepsPerBeat] equal steps, with one [StepLevel] per step.
///
/// Steps are addressed by an absolute, ever-increasing step index; the bar
/// position is that index modulo [stepsPerBar].
@immutable
class MetronomePattern {
  MetronomePattern({
    required this.beatsPerBar,
    required this.stepsPerBeat,
    required List<StepLevel> steps,
  }) : steps = List.unmodifiable(steps) {
    _validateSizes(beatsPerBar, stepsPerBeat);
    if (steps.length != beatsPerBar * stepsPerBeat) {
      throw ArgumentError.value(
        steps.length,
        'steps',
        'must have beatsPerBar * stepsPerBeat '
            '(${beatsPerBar * stepsPerBeat}) entries',
      );
    }
  }

  /// Accent on the downbeat, every other step normal.
  factory MetronomePattern.simple({
    required int beatsPerBar,
    required int stepsPerBeat,
  }) {
    _validateSizes(beatsPerBar, stepsPerBeat);
    return MetronomePattern(
      beatsPerBar: beatsPerBar,
      stepsPerBeat: stepsPerBeat,
      steps: [
        StepLevel.accent,
        for (var i = 1; i < beatsPerBar * stepsPerBeat; i++) StepLevel.normal,
      ],
    );
  }

  /// 4/4 quarters, accent on beat 1.
  const MetronomePattern.standard()
    : beatsPerBar = 4,
      stepsPerBeat = 1,
      steps = const [
        StepLevel.accent,
        StepLevel.normal,
        StepLevel.normal,
        StepLevel.normal,
      ];

  final int beatsPerBar;
  final int stepsPerBeat;
  final List<StepLevel> steps;

  int get stepsPerBar => beatsPerBar * stepsPerBeat;

  /// Level of the absolute step [stepIndex] (wraps into the bar).
  StepLevel levelAt(int stepIndex) => steps[stepIndex % stepsPerBar];

  /// Whether the absolute step [stepIndex] is the first step of a beat.
  bool isBeatStart(int stepIndex) => stepIndex % stepsPerBeat == 0;

  static void _validateSizes(int beatsPerBar, int stepsPerBeat) {
    if (beatsPerBar < 1) {
      throw ArgumentError.value(beatsPerBar, 'beatsPerBar', 'must be >= 1');
    }
    if (stepsPerBeat < 1) {
      throw ArgumentError.value(stepsPerBeat, 'stepsPerBeat', 'must be >= 1');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MetronomePattern &&
      other.beatsPerBar == beatsPerBar &&
      other.stepsPerBeat == stepsPerBeat &&
      listEquals(other.steps, steps);

  @override
  int get hashCode =>
      Object.hash(beatsPerBar, stepsPerBeat, Object.hashAll(steps));
}

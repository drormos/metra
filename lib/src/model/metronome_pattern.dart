import 'package:flutter/foundation.dart';

/// How a single step of a pattern sounds. [soft] is for subdivisions:
/// quieter than a beat so the pulse stays clear.
enum StepLevel { accent, normal, silent, soft }

/// One bar of a metronome pattern: [beatsPerBar] beats, each split into
/// [stepsPerBeat] equal steps, with one [StepLevel] per step. [beatUnit]
/// (4 or 8) is only the time signature's denominator for display: in x/8
/// every eighth note is a beat and the tempo counts eighths.
///
/// Steps are addressed by an absolute, ever-increasing step index; the bar
/// position is that index modulo [stepsPerBar].
@immutable
class MetronomePattern {
  MetronomePattern({
    required this.beatsPerBar,
    required this.stepsPerBeat,
    required List<StepLevel> steps,
    this.beatUnit = 4,
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

  /// Accent on the downbeat, other beats normal, subdivisions soft.
  factory MetronomePattern.simple({
    required int beatsPerBar,
    required int stepsPerBeat,
    int beatUnit = 4,
  }) {
    _validateSizes(beatsPerBar, stepsPerBeat);
    return MetronomePattern.fromBeats(
      [
        StepLevel.accent,
        for (var i = 1; i < beatsPerBar; i++) StepLevel.normal,
      ],
      stepsPerBeat: stepsPerBeat,
      beatUnit: beatUnit,
    );
  }

  /// One level per beat; each beat's subdivisions are soft.
  factory MetronomePattern.fromBeats(
    List<StepLevel> beatLevels, {
    required int stepsPerBeat,
    int beatUnit = 4,
  }) => MetronomePattern(
    beatsPerBar: beatLevels.length,
    stepsPerBeat: stepsPerBeat,
    beatUnit: beatUnit,
    steps: [
      for (final level in beatLevels) ...[
        level,
        for (var i = 1; i < stepsPerBeat; i++) StepLevel.soft,
      ],
    ],
  );

  /// 4/4 quarters, accent on beat 1.
  const MetronomePattern.standard()
    : beatsPerBar = 4,
      stepsPerBeat = 1,
      beatUnit = 4,
      steps = const [
        StepLevel.accent,
        StepLevel.normal,
        StepLevel.normal,
        StepLevel.normal,
      ];

  final int beatsPerBar;
  final int stepsPerBeat;
  final int beatUnit;
  final List<StepLevel> steps;

  int get stepsPerBar => beatsPerBar * stepsPerBeat;

  /// E.g. "7/8".
  String get timeSignature => '$beatsPerBar/$beatUnit';

  /// The level of each beat's first step.
  List<StepLevel> get beatLevels => [
    for (var beat = 0; beat < beatsPerBar; beat++) steps[beat * stepsPerBeat],
  ];

  /// Level of the absolute step [stepIndex] (wraps into the bar).
  StepLevel levelAt(int stepIndex) => steps[stepIndex % stepsPerBar];

  /// Whether the absolute step [stepIndex] is the first step of a beat.
  bool isBeatStart(int stepIndex) => stepIndex % stepsPerBeat == 0;

  /// Same beat levels, new subdivision.
  MetronomePattern withSubdivision(int stepsPerBeat) =>
      MetronomePattern.fromBeats(
        beatLevels,
        stepsPerBeat: stepsPerBeat,
        beatUnit: beatUnit,
      );

  /// Beat [beat] goes normal → accent → silent → normal (first tap on a
  /// plain beat accents it: the common case, e.g. 7/8 as 2+2+3).
  MetronomePattern cycleBeat(int beat) {
    final levels = beatLevels;
    levels[beat] = switch (levels[beat]) {
      StepLevel.normal => StepLevel.accent,
      StepLevel.accent => StepLevel.silent,
      _ => StepLevel.normal,
    };
    return MetronomePattern.fromBeats(
      levels,
      stepsPerBeat: stepsPerBeat,
      beatUnit: beatUnit,
    );
  }

  Map<String, Object?> toJson() => {
    'beatsPerBar': beatsPerBar,
    'stepsPerBeat': stepsPerBeat,
    'beatUnit': beatUnit,
    'steps': [for (final step in steps) step.name],
  };

  /// Throws on malformed data (unknown step names, wrong step count).
  factory MetronomePattern.fromJson(Map<String, Object?> json) =>
      MetronomePattern(
        beatsPerBar: json['beatsPerBar'] as int,
        stepsPerBeat: json['stepsPerBeat'] as int,
        // Absent in files saved before time signatures existed.
        beatUnit: json['beatUnit'] as int? ?? 4,
        steps: [
          for (final name in json['steps'] as List)
            StepLevel.values.byName(name as String),
        ],
      );

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
      other.beatUnit == beatUnit &&
      listEquals(other.steps, steps);

  @override
  int get hashCode =>
      Object.hash(beatsPerBar, stepsPerBeat, beatUnit, Object.hashAll(steps));
}

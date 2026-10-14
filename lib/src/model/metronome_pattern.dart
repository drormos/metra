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

  /// Same beat levels, new subdivision; the new subdivision cells all
  /// start on (soft). An unchanged subdivision returns this pattern.
  MetronomePattern withSubdivision(int stepsPerBeat) =>
      stepsPerBeat == this.stepsPerBeat
      ? this
      : MetronomePattern.fromBeats(
          beatLevels,
          stepsPerBeat: stepsPerBeat,
          beatUnit: beatUnit,
        );

  /// [beatsPerBar] beats in [beatUnit]: existing beats keep their levels
  /// and cells, new beats are regular with their cells on.
  MetronomePattern withBeats(int beatsPerBar, {int? beatUnit}) {
    _validateSizes(beatsPerBar, stepsPerBeat);
    return MetronomePattern(
      beatsPerBar: beatsPerBar,
      stepsPerBeat: stepsPerBeat,
      beatUnit: beatUnit ?? this.beatUnit,
      steps: [
        for (var beat = 0; beat < beatsPerBar; beat++)
          for (var cell = 0; cell < stepsPerBeat; cell++)
            beat < this.beatsPerBar
                ? steps[beat * stepsPerBeat + cell]
                : (cell == 0 ? StepLevel.normal : StepLevel.soft),
      ],
    );
  }

  /// Beat [beat] goes normal → accent → silent → normal (first tap on a
  /// plain beat accents it: the common case, e.g. 7/8 as 2+2+3). Only the
  /// beat's own step changes; its subdivision cells keep their states.
  MetronomePattern cycleBeat(int beat) {
    final i = beat * stepsPerBeat;
    return _withStep(i, switch (steps[i]) {
      StepLevel.normal => StepLevel.accent,
      StepLevel.accent => StepLevel.silent,
      _ => StepLevel.normal,
    });
  }

  /// Subdivision [cell] (1 … stepsPerBeat − 1) of [beat] toggles on (soft)
  /// ↔ off (silent): how gallops and similar patterns are built.
  MetronomePattern toggleCell(int beat, int cell) {
    RangeError.checkValueInInterval(cell, 1, stepsPerBeat - 1, 'cell');
    final i = beat * stepsPerBeat + cell;
    return _withStep(
      i,
      steps[i] == StepLevel.silent ? StepLevel.soft : StepLevel.silent,
    );
  }

  /// Whether this is the plain pattern for its shape: accent on 1, other
  /// beats regular, every subdivision on.
  bool get isDefault =>
      this ==
      MetronomePattern.simple(
        beatsPerBar: beatsPerBar,
        stepsPerBeat: stepsPerBeat,
        beatUnit: beatUnit,
      );

  MetronomePattern _withStep(int index, StepLevel level) => MetronomePattern(
    beatsPerBar: beatsPerBar,
    stepsPerBeat: stepsPerBeat,
    beatUnit: beatUnit,
    steps: [...steps]..[index] = level,
  );

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

import 'package:flutter/foundation.dart';

import 'metronome_pattern.dart';

/// Per-level click volumes (Settings > Volume), each 0–1.
@immutable
class ClickVolumes {
  const ClickVolumes({
    this.accent = 1,
    this.beat = 0.8,
    this.subdivision = 0.45,
    this.polyrhythm = 0.7,
  });

  /// Accent 100%, Beat 80%, Subdivision 45%, Polyrhythm 70% (ui-spec.md);
  /// "Reset" restores these.
  static const defaults = ClickVolumes();

  final double accent;
  final double beat;
  final double subdivision;

  /// The polyrhythm pulses (accented ones louder).
  final double polyrhythm;

  double forLevel(StepLevel level) => switch (level) {
    StepLevel.accent => accent,
    StepLevel.normal => beat,
    StepLevel.soft => subdivision,
    StepLevel.silent => 0,
  };

  ClickVolumes copyWith({
    double? accent,
    double? beat,
    double? subdivision,
    double? polyrhythm,
  }) => ClickVolumes(
    accent: accent ?? this.accent,
    beat: beat ?? this.beat,
    subdivision: subdivision ?? this.subdivision,
    polyrhythm: polyrhythm ?? this.polyrhythm,
  );

  Map<String, Object?> toJson() => {
    'accent': accent,
    'beat': beat,
    'subdivision': subdivision,
    'polyrhythm': polyrhythm,
  };

  /// Missing or out-of-range values fall back or clamp rather than fail.
  factory ClickVolumes.fromJson(Map<String, Object?> json) {
    double read(String key, double fallback) =>
        ((json[key] as num?)?.toDouble() ?? fallback).clamp(0.0, 1.0);
    return ClickVolumes(
      accent: read('accent', defaults.accent),
      beat: read('beat', defaults.beat),
      subdivision: read('subdivision', defaults.subdivision),
      polyrhythm: read('polyrhythm', defaults.polyrhythm),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClickVolumes &&
      other.accent == accent &&
      other.beat == beat &&
      other.subdivision == subdivision &&
      other.polyrhythm == polyrhythm;

  @override
  int get hashCode => Object.hash(accent, beat, subdivision, polyrhythm);
}

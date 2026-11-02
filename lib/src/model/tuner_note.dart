import 'dart:math' as math;

/// The nearest note to a frequency and how far off it is (ui-spec.md
/// "Tuner"), against a Reference A4 in Hz.
class TunerNote {
  const TunerNote({
    required this.name,
    required this.sharp,
    required this.octave,
    required this.cents,
    required this.hz,
  });

  factory TunerNote.fromHz(double hz, {double a4 = 440}) {
    final midi = 69 + 12 * math.log(hz / a4) / math.ln2;
    final nearest = midi.round();
    return TunerNote(
      name: names[nearest % 12],
      sharp: const {1, 3, 6, 8, 10}.contains(nearest % 12),
      octave: nearest ~/ 12 - 1,
      cents: (midi - nearest) * 100,
      hz: hz,
    );
  }

  /// The letter of each pitch class; the black keys are [sharp].
  static const names = [
    'C', 'C', 'D', 'D', 'E', 'F', 'F', 'G', 'G', 'A', 'A', 'B', //
  ];

  /// Within this many cents reads "In tune".
  static const inTuneCents = 3.0;

  /// The letter ("A"); a sharp is drawn after it (a vector, not a glyph).
  final String name;
  final bool sharp;
  final int octave;

  /// −50 to +50: above the note is sharp.
  final double cents;
  final double hz;

  bool get inTune => cents.abs() <= inTuneCents;

  /// "+12 cents · 111.2 Hz", or "In tune".
  String get line {
    if (inTune) return 'In tune';
    final c = cents.round();
    return '${c > 0 ? '+' : '−'}${c.abs()} ${c.abs() == 1 ? 'cent' : 'cents'}'
        ' · ${hz.toStringAsFixed(1)} Hz';
  }

  /// What TalkBack says: "A, 12 cents sharp", "A, in tune".
  String get spoken {
    final note = sharp ? '$name sharp' : name;
    if (inTune) return '$note, in tune';
    final c = cents.round().abs();
    return '$note, $c ${c == 1 ? 'cent' : 'cents'} '
        '${cents > 0 ? 'sharp' : 'flat'}';
  }
}

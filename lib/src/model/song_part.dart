import 'package:flutter/foundation.dart' show immutable;

import 'metronome_pattern.dart';

/// "When the song ends" (ui-spec.md "Song parts").
enum SongEnd { stop, loop }

/// One part of a song (ui-spec.md "Song parts"): a "little song" with its
/// own length, tempo and rhythm.
@immutable
class SongPart {
  const SongPart({
    required this.id,
    required this.name,
    required this.bars,
    required this.tempoStart,
    required this.tempoEnd,
    required this.pattern,
  });

  /// A steady part of [bpm] and [pattern]; [bars] null runs until Stop.
  const SongPart.steady({
    required this.id,
    required this.name,
    required this.bars,
    required int bpm,
    required this.pattern,
  }) : tempoStart = bpm,
       tempoEnd = bpm;

  final String id;
  final String name;

  /// 1–999 bars, or null: "Until you stop" (only the last part).
  final int? bars;

  /// Equal when Steady. Gradual: the tempo changes on every beat, linear
  /// from [tempoStart] to [tempoEnd], which it reaches on the last beat.
  final int tempoStart;
  final int tempoEnd;

  final MetronomePattern pattern;

  bool get open => bars == null;

  /// An open part is always steady.
  bool get gradual => !open && tempoStart != tempoEnd;

  /// The tempo of beat [beat] (from 0) of the part.
  double tempoAtBeat(int beat) {
    if (!gradual) return tempoStart.toDouble();
    final last = bars! * pattern.beatsPerBar - 1;
    if (last <= 0) return tempoEnd.toDouble();
    return tempoStart + (tempoEnd - tempoStart) * beat / last;
  }

  static const _keep = Object();

  SongPart copyWith({
    String? name,
    Object? bars = _keep,
    int? tempoStart,
    int? tempoEnd,
    MetronomePattern? pattern,
  }) => SongPart(
    id: id,
    name: name ?? this.name,
    bars: identical(bars, _keep) ? this.bars : bars as int?,
    tempoStart: tempoStart ?? this.tempoStart,
    tempoEnd: tempoEnd ?? this.tempoEnd,
    pattern: pattern ?? this.pattern,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'bars': bars,
    'tempoStart': tempoStart,
    'tempoEnd': tempoEnd,
    'pattern': pattern.toJson(),
  };

  factory SongPart.fromJson(Map<String, Object?> json) => SongPart(
    id: json['id'] as String,
    name: json['name'] as String,
    bars: json['bars'] as int?,
    tempoStart: json['tempoStart'] as int,
    tempoEnd: json['tempoEnd'] as int,
    // A broken pattern doesn't cost the part (its length and tempo).
    pattern: _patternOr(json['pattern']),
  );

  static MetronomePattern _patternOr(Object? json) {
    try {
      return MetronomePattern.fromJson(json! as Map<String, Object?>);
    } catch (_) {
      return const MetronomePattern.standard();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SongPart &&
      other.id == id &&
      other.name == name &&
      other.bars == bars &&
      other.tempoStart == tempoStart &&
      other.tempoEnd == tempoEnd &&
      other.pattern == pattern;

  @override
  int get hashCode =>
      Object.hash(id, name, bars, tempoStart, tempoEnd, pattern);

  @override
  String toString() =>
      'SongPart($name, ${bars ?? 'open'} bars, $tempoStart→$tempoEnd, '
      '${pattern.timeSignature})';
}

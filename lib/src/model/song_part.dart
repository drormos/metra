import 'package:flutter/foundation.dart' show immutable;

import 'metronome_pattern.dart';

/// "When the song ends" (ui-spec.md "Song parts"): stop, loop the whole
/// song, or loop the last part, each until Stop. ("Loop" is until you
/// stop; "repeat" is kept for a counted repeat.)
enum SongEnd { stop, loopSong, loopLastPart }

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

  /// A steady part of [bpm] and [pattern].
  const SongPart.steady({
    required this.id,
    required this.name,
    required this.bars,
    required int bpm,
    required this.pattern,
  }) : tempoStart = bpm,
       tempoEnd = bpm;

  /// A one-part song's part (and every migrated song's).
  static const firstId = 'part-1';
  static const firstName = 'Part 1';

  /// Bars a part can have.
  static const minBars = 1;
  static const maxBars = 999;

  final String id;
  final String name;

  /// 1–999.
  final int bars;

  /// Equal when Steady. Gradual: the tempo changes on every beat, linear
  /// from [tempoStart] to [tempoEnd], which it reaches on the last beat.
  final int tempoStart;
  final int tempoEnd;

  final MetronomePattern pattern;

  bool get gradual => tempoStart != tempoEnd;

  /// The tempo of beat [beat] (from 0) of the part.
  double tempoAtBeat(int beat) {
    if (!gradual) return tempoStart.toDouble();
    final last = bars * pattern.beatsPerBar - 1;
    if (last <= 0) return tempoEnd.toDouble();
    // Held at its ends: a beat past the last (a longer bar in force than
    // the part's own) plays To, never a tempo beyond it.
    final t = (beat / last).clamp(0.0, 1.0);
    return tempoStart + (tempoEnd - tempoStart) * t;
  }

  SongPart copyWith({
    String? name,
    int? bars,
    int? tempoStart,
    int? tempoEnd,
    MetronomePattern? pattern,
  }) => SongPart(
    id: id,
    name: name ?? this.name,
    bars: bars ?? this.bars,
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
    bars: json['bars'] as int,
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
      'SongPart($name, $bars bars, $tempoStart→$tempoEnd, '
      '${pattern.timeSignature})';
}

/// Whether [parts] ending as [end] need the parts engine: 2 or more, a
/// Gradual one, or an end other than looping it (one steady part looping
/// plays as before, speed up included).
bool partsPlay(List<SongPart> parts, SongEnd end) =>
    parts.length > 1 || parts.first.gradual || end != SongEnd.loopLastPart;

/// Whether [parts] ending as [end] is a plain one-part song: one steady
/// bar of the default name, looping; nothing to remember beyond its tempo
/// and pattern.
bool partsPlain(List<SongPart> parts, SongEnd end) =>
    !partsPlay(parts, end) &&
    parts.first.bars == 1 &&
    parts.first.name == SongPart.firstName;

/// How long a part takes, beat by beat ("≈ 0:26").
Duration partDuration(SongPart part) {
  var seconds = 0.0;
  for (var beat = 0; beat < part.bars * part.pattern.beatsPerBar; beat++) {
    seconds += 60 / part.tempoAtBeat(beat);
  }
  return Duration(milliseconds: (seconds * 1000).round());
}

/// "≈ 1:38".
String durationLabel(Duration d) {
  final s = (d.inMilliseconds / 1000).round();
  return '≈ ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// The parts page's summary: "6 parts · 45 bars · ≈ 1:38", and with the
/// last part looping ", then loops Outro" (ui-spec.md "The parts page").
String partsSummary(List<SongPart> parts, SongEnd end) {
  final count = parts.length == 1 ? '1 part' : '${parts.length} parts';
  final total = parts.fold(0, (sum, p) => sum + p.bars);
  final bars = total == 1 ? '1 bar' : '$total bars';
  final time = parts.fold(Duration.zero, (sum, p) => sum + partDuration(p));
  final summary = '$count · $bars · ${durationLabel(time)}';
  return end == SongEnd.loopLastPart
      ? '$summary, then loops ${parts.last.name}'
      : summary;
}

/// A card's line: "8 bars · 7/8 · ≈ 0:26".
String partLine(SongPart part) =>
    '${part.bars == 1 ? '1 bar' : '${part.bars} bars'} · '
    '${part.pattern.timeSignature} · ${durationLabel(partDuration(part))}';

/// The common part names, in song order (the name dropdown).
const partNames = [
  'Intro',
  'Verse',
  'Pre-chorus',
  'Chorus',
  'Bridge',
  'Break',
  'Solo',
  'Outro',
];

/// The name for a part added after [parts]: the common name after the
/// last part's, else "Part N" (its number), skipping one in use.
String nextPartName(List<SongPart> parts) {
  final at = partNames.indexOf(parts.last.name);
  if (at >= 0 && at + 1 < partNames.length) return partNames[at + 1];
  final taken = {for (final p in parts) p.name};
  var n = parts.length + 1;
  while (taken.contains('Part $n')) {
    n++;
  }
  return 'Part $n';
}

/// Where the song is, for the line under the BPM: "Chorus · bar 3 of 8 ·
/// next: Break"; the last part has no "next" (nor any part with [next]
/// off), and looping it, "Outro · bar 3 of 8 · looping". [bar] counts
/// from 0.
String partPositionLabel(
  List<SongPart> parts,
  int part,
  int bar, {
  SongEnd end = SongEnd.stop,
  bool next = true,
}) {
  final p = parts[part];
  final last = part + 1 == parts.length;
  return [
    p.name,
    'bar ${bar + 1} of ${p.bars}',
    if (last && end == SongEnd.loopLastPart)
      'looping'
    else if (next && !last)
      'next: ${parts[part + 1].name}',
  ].join(' · ');
}

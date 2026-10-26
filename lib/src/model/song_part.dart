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

  /// A one-part song's part (and every migrated song's).
  static const firstId = 'part-1';
  static const firstName = 'Part 1';

  /// Bars a part can have.
  static const minBars = 1;
  static const maxBars = 999;

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
    // Held at its ends: a beat past the last (a longer bar in force than
    // the part's own) plays To, never a tempo beyond it.
    final t = (beat / last).clamp(0.0, 1.0);
    return tempoStart + (tempoEnd - tempoStart) * t;
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

/// Whether [parts] need the parts engine: 2 or more, or a length (a song
/// of one open part plays as before, speed up included).
bool partsPlay(List<SongPart> parts) => parts.length > 1 || !parts.first.open;

/// Whether [parts] is a plain one-part song: one open part with the
/// default name, nothing to remember beyond its tempo and pattern.
bool partsPlain(List<SongPart> parts) =>
    parts.length == 1 &&
    parts.first.open &&
    parts.first.name == SongPart.firstName;

/// How long a part takes, beat by beat ("≈ 0:26"); null when open.
Duration? partDuration(SongPart part) {
  final bars = part.bars;
  if (bars == null) return null;
  var seconds = 0.0;
  for (var beat = 0; beat < bars * part.pattern.beatsPerBar; beat++) {
    seconds += 60 / part.tempoAtBeat(beat);
  }
  return Duration(milliseconds: (seconds * 1000).round());
}

/// "≈ 1:38".
String durationLabel(Duration d) {
  final s = (d.inMilliseconds / 1000).round();
  return '≈ ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// The parts page's summary: "6 parts · 45 bars · ≈ 1:38", or "6 parts ·
/// 37 bars, then until you stop" (ui-spec.md "The parts page").
String partsSummary(List<SongPart> parts) {
  final count = parts.length == 1 ? '1 part' : '${parts.length} parts';
  final closed = [for (final p in parts) ?p.bars].fold(0, (a, b) => a + b);
  final bars = closed == 1 ? '1 bar' : '$closed bars';
  if (parts.last.open) {
    return closed == 0
        ? '$count · until you stop'
        : '$count · $bars, then until you stop';
  }
  final total = parts.fold(Duration.zero, (sum, p) => sum + partDuration(p)!);
  return '$count · $bars · ${durationLabel(total)}';
}

/// A card's line: "8 bars · 7/8 · ≈ 0:26", or "4/4 · until you stop".
String partLine(SongPart part) {
  final bars = part.bars;
  final meter = part.pattern.timeSignature;
  if (bars == null) return '$meter · until you stop';
  return '${bars == 1 ? '1 bar' : '$bars bars'} · $meter · '
      '${durationLabel(partDuration(part)!)}';
}

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
/// next: Break"; the last part (or with [next] off) has no "next"; an open
/// part "Outro · bar 12". [bar] counts from 0.
String partPositionLabel(
  List<SongPart> parts,
  int part,
  int bar, {
  bool next = true,
}) {
  final p = parts[part];
  if (p.bars == null) return '${p.name} · bar ${bar + 1}';
  return [
    p.name,
    'bar ${bar + 1} of ${p.bars}',
    if (next && part + 1 < parts.length) 'next: ${parts[part + 1].name}',
  ].join(' · ');
}

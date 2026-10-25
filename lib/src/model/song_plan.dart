import '../audio/click_scheduler.dart';
import 'metronome_pattern.dart';
import 'on_start.dart';
import 'song_part.dart';

/// A song's parts as the scheduler plays them (ui-spec.md "Song parts"):
/// each part starts on a bar line in its own pattern; a Gradual part
/// changes tempo on every beat; the song stops or loops at its end; an
/// open last part repeats until Stop. Stop after still applies; speed up
/// doesn't (the parts decide the tempo).
class SongPlan implements PatternPlan {
  SongPlan({
    required this.parts,
    required this.end,
    required this.onStart,
    int startPart = 0,
  }) : _jumps = [(bar: 0, part: startPart)];

  /// The parts, in order; replaced as they're edited while playing.
  List<SongPart> parts;
  SongEnd end;
  OnStart onStart;

  // Where the song plays from: from song bar `bar` on, part `part`'s first
  // bar (the start, then each jump), oldest first.
  final List<({int bar, int part})> _jumps;

  /// From song bar [bar] on (a bar line not yet played), part [part]
  /// starts over; later jumps already planned are dropped.
  void jump(int bar, int part) {
    _jumps
      ..removeWhere((j) => j.bar >= bar)
      ..add((bar: bar, part: part));
  }

  /// The part song bar [bar] (from 0) is in, and the bar within it (from
  /// 0); null past the end of a song that stops.
  ({int part, int bar})? locate(int bar) {
    final from = _jumps.lastWhere(
      (j) => j.bar <= bar,
      orElse: () => _jumps.first,
    );
    var part = from.part.clamp(0, parts.length - 1);
    var into = bar - from.bar;
    // Looping, whole passes of the song are skipped at once.
    final total = parts.every((p) => !p.open)
        ? parts.fold(0, (sum, p) => sum + p.bars!)
        : null;
    while (true) {
      final bars = parts[part].bars;
      if (bars == null || into < bars) return (part: part, bar: into);
      into -= bars;
      if (++part < parts.length) continue;
      if (end == SongEnd.stop) return null;
      part = 0;
      into %= total!;
    }
  }

  @override
  MetronomePattern? patternAt(int bar) {
    final at = locate(bar);
    return at == null || at.bar != 0 ? null : parts[at.part].pattern;
  }

  /// A Gradual part sets every beat; a steady one its first beat only, so
  /// a change to the tempo while it plays holds until the next part.
  @override
  double? tempoAt(int bar, int beat, double bpm) {
    final at = locate(bar);
    if (at == null) return null;
    final part = parts[at.part];
    if (part.gradual) {
      return part.tempoAtBeat(at.bar * part.pattern.beatsPerBar + beat);
    }
    return at.bar == 0 && beat == 0 ? part.tempoStart.toDouble() : null;
  }

  /// At the song's end (Stop) or Stop after's limit.
  @override
  bool endsAt(int bar, Duration elapsed) =>
      locate(bar) == null || onStart.endsAt(bar, elapsed);
}
